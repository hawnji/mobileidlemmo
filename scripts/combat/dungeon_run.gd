class_name DungeonRun
extends RefCounted
## One party inside a dungeon: floors of enemies, then a boss.
##
## The party leaves the map (state AWAY) and the run is simulated here in
## fixed 0.1 s sub-steps, so online play (0.1 s ticks) and offline catch-up
## (1 s ticks) give identical results. All randomness uses the world RNG.
##
## Mechanics:
##   * every member attacks with the overworld combat formulas (CombatRules);
##   * members use their active ability (data/characters/abilities.json) on
##     cooldown: guard/taunt, strike, multi strike, strike all, party heal,
##     party damage buff;
##   * enemies attack a random standing member, or a taunting tank;
##   * bosses (enemy "boss" block) have hp-threshold phases, special attacks,
##     area attacks, summoned adds, self-heals, elemental weaknesses (from
##     "weaknesses") and an enrage timer;
##   * members eat from a shared food pool taken from storage at the start;
##     a member at 0 health is knocked out for the rest of the run;
##   * the run fails if every member is knocked out or the time limit passes.
##
## Phase 5 mythic tiers (dungeons.json "mythic"): tier N scales enemy health
## and damage, adds affixes from tier 2 up (fortified, tyrannical, frenzied,
## famished) and scales the clear rewards (SimulationWorld._mythic_rewards).
##
## Loot is only created when the run ends (SimulationWorld._finish_dungeon),
## so a save made mid-run cannot duplicate items.

const STEP := 0.1
const EPS := 0.000001

var dungeon_id := ""
var def := {}
var party: Array[Dictionary] = []  # {id, hp, attack_timer, ability_timer, guard, buff, down}
var foes: Array[Dictionary] = []  # {enemy: EnemyState, attack_timer, boss, ability_timers, phase, special_ready}
var floor_index := -1  # -1 entering; floors.size() = boss floor
var entry_remaining := 0.0
var elapsed := 0.0
var boss_elapsed := 0.0
var enraged := false
var food := {}  # item_id -> qty (taken from storage)
var loot := {}
var gold := 0
var result := ""  # "", "cleared", "failed", "timeout"
var log_lines: Array[String] = []
var _acc := 0.0
var _foe_seq := 0
## Mythic tier (0 = normal) and the affix multipliers it brings.
var tier := 0
var _mods := {}


static func create(world, p_dungeon_id: String, team: Array, p_tier := 0) -> DungeonRun:
	var run := DungeonRun.new()
	run.dungeon_id = p_dungeon_id
	run.def = world.registry.dungeons[p_dungeon_id]
	run._set_tier(world, p_tier)
	run.entry_remaining = float(run.def.get("entry_seconds", 10.0))
	for cid in team:
		var ch: Adventurer = world.characters[cid]
		var ab := ch.active_ability()
		run.party.append({"id": String(cid), "hp": ch.health, "attack_timer": 0.0,
			"ability_timer": float(ab.get("cooldown", 15.0)) * 0.5, "guard": 0.0, "buff": 0.0, "down": ch.health <= 0.0})
	run._take_food(world, int(team.size() * int(run.def.get("food_per_member", 10)) * float(run._mods.food_mult)))
	if run.tier > 0:
		run._log("The party enters %s at mythic tier %d." % [run.def.get("name", p_dungeon_id), run.tier])
	else:
		run._log("The party enters %s." % run.def.get("name", p_dungeon_id))
	return run


func _set_tier(world, p_tier: int) -> void:
	tier = maxi(p_tier, 0)
	var cfg: Dictionary = world.registry.dungeon_mythic
	_mods = {"health": 1.0 + float(cfg.get("enemy_health_per_tier", 0.25)) * tier,
		"damage": 1.0 + float(cfg.get("enemy_damage_per_tier", 0.12)) * tier,
		"trash_health": 1.0, "boss_health": 1.0, "boss_damage": 1.0, "enrage": 1.0, "food_mult": 1.0, "affixes": []}
	if tier <= 0:
		return
	for a in cfg.get("affixes", []):
		if tier < int(a.get("min_tier", 99)):
			continue
		_mods.affixes.append(String(a.get("name", a.get("id", ""))))
		_mods.trash_health *= float(a.get("trash_health_mult", 1.0))
		_mods.boss_health *= float(a.get("boss_health_mult", 1.0))
		_mods.boss_damage *= float(a.get("boss_damage_mult", 1.0))
		_mods.enrage *= float(a.get("enrage_mult", 1.0))
		_mods.food_mult *= float(a.get("food_mult", 1.0))


func affix_names() -> Array:
	return _mods.get("affixes", [])


func _foe_damage_mult(f: Dictionary) -> float:
	return float(_mods.damage) * (float(_mods.boss_damage) if f.boss else 1.0)


func has_member(cid: String) -> bool:
	for m in party:
		if m.id == cid:
			return true
	return false


## Food comes out of storage now and is a sink only when eaten.
func _take_food(world, wanted: int) -> void:
	var foods := []
	for it in world.storage.items():
		var heal := float(world.registry.items.get(it, {}).get("heal", 0))
		if heal > 0.0 and not world.locked_items.has(it):
			foods.append([heal, it])
	foods.sort_custom(func(a, b): return a[0] > b[0])
	for f in foods:
		if wanted <= 0:
			break
		var q := mini(world.storage.get_quantity(f[1]), wanted)
		world.storage.remove(f[1], q)
		food[f[1]] = int(food.get(f[1], 0)) + q
		wanted -= q


func boss_foe() -> Dictionary:
	for f in foes:
		if f.boss:
			return f
	return {}


func stage_label() -> String:
	var floors: Array = def.get("floors", [])
	if floor_index < 0:
		return "Entering"
	if floor_index < floors.size():
		return "Floor %d/%d" % [floor_index + 1, floors.size()]
	return "Boss"


## Advances the run. Returns true when it has ended (see `result`).
func tick(world, dt: float) -> bool:
	if not result.is_empty():
		return true
	_acc += dt
	while _acc >= STEP - EPS and result.is_empty():
		_acc -= STEP
		_step(world, STEP)
	return not result.is_empty()


func _step(world, h: float) -> void:
	elapsed += h
	if elapsed >= float(def.get("time_limit_seconds", 900.0)):
		_end("timeout", "The party ran out of time and retreated.")
		return
	if floor_index < 0:
		entry_remaining -= h
		if entry_remaining <= 0.0:
			_next_floor(world)
		return
	var reg: DataRegistry = world.registry
	var boss := boss_foe()
	if not boss.is_empty():
		boss_elapsed += h
		var bdef: Dictionary = boss.enemy.def.get("boss", {})
		if not enraged and boss_elapsed >= float(bdef.get("enrage_seconds", INF)) * float(_mods.enrage):
			enraged = true
			_log("%s becomes enraged!" % boss.enemy.display_name())
		_boss_abilities(world, boss, h)
	for m in party:
		if m.down:
			continue
		m.guard = maxf(float(m.guard) - h, 0.0)
		m.buff = maxf(float(m.buff) - h, 0.0)
		m.ability_timer = float(m.ability_timer) - h
		m.attack_timer = float(m.attack_timer) + h
		var ch: Adventurer = world.characters.get(m.id)
		if ch == null:
			m.down = true
			continue
		if float(m.ability_timer) <= 0.0 and _alive_foes() > 0:
			_use_ability(world, m, ch)
		var interval := CombatRules.attack_interval(ch, reg)
		if float(m.attack_timer) >= interval and _alive_foes() > 0:
			m.attack_timer = float(m.attack_timer) - interval
			_member_attack(world, m, ch, _first_alive(), 1.0, false)
	_check_kills(world)
	if _alive_foes() == 0:
		if floor_index >= def.get("floors", []).size():
			_end("cleared", "%s is cleared!" % def.get("name", dungeon_id))
		else:
			_next_floor(world)
		return
	for f in foes:
		if not f.enemy.is_alive():
			continue
		f.attack_timer = float(f.attack_timer) + h
		var interval := CombatRules.enemy_attack_interval(f.enemy) * _phase_value(f, "attack_speed_mult", 1.0)
		if float(f.attack_timer) >= interval:
			f.attack_timer = float(f.attack_timer) - interval
			var mult := 1.0
			if f.boss and bool(f.get("special_ready", false)):
				f.special_ready = false
				mult = float(f.special_mult)
				_log("%s uses %s!" % [f.enemy.display_name(), f.special_name])
			_foe_attack(world, f, _pick_target(world), mult)
	if _standing() == 0:
		_end("failed", "The party was defeated.")


func _next_floor(world) -> void:
	floor_index += 1
	foes.clear()
	var floors: Array = def.get("floors", [])
	if floor_index < floors.size():
		for eid in floors[floor_index].get("enemies", []):
			_spawn_foe(world, String(eid), false)
		_log("Floor %d: %d enemies." % [floor_index + 1, foes.size()])
	else:
		_spawn_foe(world, String(def.boss), true)
		boss_elapsed = 0.0
		_log("%s awakens!" % foes[0].enemy.display_name())


func _spawn_foe(world, enemy_id: String, is_boss: bool) -> Dictionary:
	var edef: Dictionary = world.registry.enemies.get(enemy_id, {})
	_foe_seq += 1
	var es := EnemyState.create("%s_%d" % [dungeon_id, _foe_seq], edef, Vector2i.ZERO)
	es.spawn(world.rng, [])
	if tier > 0:
		es.max_health *= float(_mods.health) * (float(_mods.boss_health) if is_boss else float(_mods.trash_health))
		es.health = es.max_health
	var f := {"enemy": es, "attack_timer": 0.0, "boss": is_boss, "ability_timers": {}, "phase": -1, "special_ready": false,
		"special_mult": 1.0, "special_name": "", "add": false}
	if is_boss:
		for ab in edef.get("boss", {}).get("abilities", []):
			f.ability_timers[String(ab.id)] = float(ab.get("every", 15.0))
	foes.append(f)
	return f


func _alive_foes() -> int:
	var n := 0
	for f in foes:
		if f.enemy.is_alive():
			n += 1
	return n


func _first_alive() -> Dictionary:
	# Adds first (they protect the boss), then the boss.
	for f in foes:
		if f.enemy.is_alive() and not f.boss:
			return f
	for f in foes:
		if f.enemy.is_alive():
			return f
	return {}


func _standing() -> int:
	var n := 0
	for m in party:
		if not m.down:
			n += 1
	return n


func _pick_target(world) -> Dictionary:
	var standing := []
	for m in party:
		if not m.down:
			standing.append(m)
			if float(m.guard) > 0.0 and bool(m.get("taunt", false)):
				return m
	if standing.is_empty():
		return {}
	return standing[world.rng.randi_range(0, standing.size() - 1)]


func _damage_mult(world, m: Dictionary, ch: Adventurer) -> float:
	var mult := ch.stat("dungeon_damage")
	if float(m.buff) > 0.0:
		mult *= float(m.get("buff_mult", 1.0))
	return mult


func _member_attack(world, m: Dictionary, ch: Adventurer, f: Dictionary, mult: float, always_hits: bool) -> int:
	if f.is_empty() or not f.enemy.is_alive():
		return 0
	var reg: DataRegistry = world.registry
	var dmg := 0
	if always_hits or world.rng.randf() < CombatRules.player_hit_chance(ch, f.enemy, reg):
		dmg = int(round(world.rng.randi_range(1, CombatRules.player_max_hit(ch, f.enemy, reg)) * mult * _damage_mult(world, m, ch)))
		dmg = mini(maxi(dmg, 1), int(ceil(f.enemy.health)))
		f.enemy.health -= dmg
	if dmg > 0:
		ch.stats.damage_dealt = int(ch.stats.damage_dealt) + dmg
		var xp := dmg * float(reg.get_config("combat.xp_per_damage", 4.0))
		match ch.combat_style():
			"ranged":
				world.engine.grant_xp(ch, "ranged", xp)
			"magic":
				world.engine.grant_xp(ch, "magic", xp)
			_:
				world.engine.grant_xp(ch, "attack", xp * 0.5)
				world.engine.grant_xp(ch, "strength", xp * 0.5)
	return dmg


func _use_ability(world, m: Dictionary, ch: Adventurer) -> void:
	var ab := ch.active_ability()
	if ab.is_empty():
		m.ability_timer = 9999.0
		return
	m.ability_timer = float(ab.get("cooldown", 15.0))
	var dm := float(ab.get("damage_mult", 1.0))
	match String(ab.get("kind", "")):
		"guard":
			m.guard = float(ab.get("duration", 6.0))
			m.taunt = bool(ab.get("taunt", false))
			m.guard_mult = float(ab.get("damage_taken_mult", 0.5))
		"strike":
			_member_attack(world, m, ch, _first_alive(), dm, bool(ab.get("always_hits", false)))
		"multi_strike":
			for i in int(ab.get("hits", 2)):
				_member_attack(world, m, ch, _first_alive(), dm, false)
		"strike_all":
			for f in foes:
				if f.enemy.is_alive():
					_member_attack(world, m, ch, f, dm, false)
		"heal_party":
			for o in party:
				if not o.down:
					var och: Adventurer = world.characters.get(o.id)
					if och:
						o.hp = minf(float(o.hp) + och.max_health() * float(ab.get("pct", 0.2)) * ch.stat("healing"), och.max_health())
		"buff_party":
			for o in party:
				if not o.down:
					o.buff = float(ab.get("duration", 8.0))
					o.buff_mult = dm
	if world.wants_event("dungeon_hit"):
		world.emit_event("dungeon_hit", {"dungeon": dungeon_id, "character_id": ch.id, "ability": ab.get("id", "")})


func _foe_attack(world, f: Dictionary, m: Dictionary, mult: float) -> void:
	if m.is_empty():
		return
	var ch: Adventurer = world.characters.get(m.id)
	if ch == null:
		return
	var reg: DataRegistry = world.registry
	if world.rng.randf() >= CombatRules.enemy_hit_chance(ch, f.enemy, reg):
		return
	var raw: float = world.rng.randi_range(0, CombatRules.enemy_max_hit(f.enemy)) * mult * _phase_value(f, "damage_mult", 1.0) * _foe_damage_mult(f)
	if f.boss and enraged:
		raw *= float(f.enemy.def.get("boss", {}).get("enrage_damage_mult", 2.0))
	_hurt(world, m, ch, int(round(raw)))


func _hurt(world, m: Dictionary, ch: Adventurer, raw: int) -> void:
	var dmg := maxi(raw - CombatRules.damage_reduction(ch, world.registry), 0)
	if float(m.guard) > 0.0:
		dmg = int(round(dmg * float(m.get("guard_mult", 0.5))))
	if dmg <= 0:
		return
	m.hp = float(m.hp) - dmg
	world.engine.grant_xp(ch, "defense", dmg * float(world.registry.get_config("combat.defense_xp_per_damage_taken", 1.5)))
	if float(m.hp) < ch.max_health() * 0.5:
		_eat(world, m, ch)
	if float(m.hp) <= 0.0:
		m.hp = 0.0
		m.down = true
		ch.stats.deaths = int(ch.stats.deaths) + 1
		_log("%s is knocked out." % ch.display_name)


func _eat(world, m: Dictionary, ch: Adventurer) -> void:
	var best := ""
	var best_heal := 0.0
	for it in food:
		var heal := float(world.registry.items.get(it, {}).get("heal", 0))
		if int(food[it]) > 0 and heal > best_heal:
			best = it
			best_heal = heal
	if best.is_empty():
		return
	food[best] = int(food[best]) - 1
	if int(food[best]) <= 0:
		food.erase(best)
	world.record_sink(best, 1, "eaten")
	m.hp = minf(float(m.hp) + best_heal * ch.stat("healing"), ch.max_health())


func _phase_value(f: Dictionary, key: String, fallback: float) -> float:
	if not f.boss or int(f.phase) < 0:
		return fallback
	var phases: Array = f.enemy.def.get("boss", {}).get("phases", [])
	return float(phases[int(f.phase)].get(key, fallback))


func _boss_abilities(world, f: Dictionary, h: float) -> void:
	var bdef: Dictionary = f.enemy.def.get("boss", {})
	# Phases trigger once each as health crosses their thresholds.
	var ratio: float = f.enemy.health / maxf(f.enemy.max_health, 1.0)
	var phases: Array = bdef.get("phases", [])
	for i in range(int(f.phase) + 1, phases.size()):
		if ratio < float(phases[i].get("below", 0.0)):
			f.phase = i
			_log(String(phases[i].get("message", "The boss grows stronger!")))
			world.emit_event("boss_phase", {"dungeon": dungeon_id, "boss": f.enemy.enemy_id, "phase": i})
	for ab in bdef.get("abilities", []):
		var aid := String(ab.id)
		f.ability_timers[aid] = float(f.ability_timers.get(aid, 15.0)) - h
		if float(f.ability_timers[aid]) > 0.0:
			continue
		f.ability_timers[aid] = float(ab.get("every", 15.0))
		match String(ab.get("kind", "")):
			"area":
				_log("%s uses %s!" % [f.enemy.display_name(), ab.get("name", aid)])
				var rng_dmg: Array = ab.get("damage", [5, 10])
				for m in party:
					if m.down:
						continue
					var ch: Adventurer = world.characters.get(m.id)
					if ch:
						var raw: float = world.rng.randi_range(int(rng_dmg[0]), int(rng_dmg[1])) * _phase_value(f, "damage_mult", 1.0) * _foe_damage_mult(f)
						if enraged:
							raw *= float(bdef.get("enrage_damage_mult", 2.0))
						_hurt(world, m, ch, int(round(raw)))
			"special":
				f.special_ready = true
				f.special_mult = float(ab.get("damage_mult", 2.0))
				f.special_name = String(ab.get("name", aid))
			"summon":
				var adds := 0
				for o in foes:
					if o.get("add", false) and o.enemy.is_alive():
						adds += 1
				var n := mini(int(ab.get("count", 1)), int(ab.get("max_adds", 2)) - adds)
				for i in n:
					var add := _spawn_foe(world, String(ab.enemy), false)
					add.add = true
				if n > 0:
					_log("%s uses %s!" % [f.enemy.display_name(), ab.get("name", aid)])
			"heal":
				f.enemy.health = minf(f.enemy.health + f.enemy.max_health * float(ab.get("pct", 0.05)), f.enemy.max_health)
				_log("%s uses %s." % [f.enemy.display_name(), ab.get("name", aid)])


func _check_kills(world) -> void:
	for f in foes:
		if f.get("dead", false) or f.enemy.is_alive():
			continue
		f.dead = true
		var edef: Dictionary = f.enemy.def
		# Summoned adds give XP but no loot, so they cannot be farmed.
		if not f.get("add", false):
			for drop in edef.get("loot", []):
				if world.rng.randf() < float(drop.get("chance", 0.0)):
					var q: int = world.rng.randi_range(int(drop.get("min", 1)), int(drop.get("max", 1)))
					loot[String(drop.item)] = int(loot.get(String(drop.item), 0)) + q
			var g: Array = edef.get("gold", [0, 0])
			gold += world.rng.randi_range(int(g[0]), int(g[1]))
		world.count_kill(edef)
		var hxp := float(world.registry.get_config("combat.hunting_xp_per_enemy_level", 2.0)) * int(edef.get("level", 1))
		for m in party:
			if not m.down:
				var ch: Adventurer = world.characters.get(m.id)
				if ch:
					world.engine.grant_xp(ch, "hunting", hxp / maxf(_standing(), 1))
					ch.record("kills", String(edef.get("id", "")), 1)
		if f.boss:
			_log("%s is defeated!" % f.enemy.display_name())


func _end(p_result: String, message: String) -> void:
	result = p_result
	_log(message)


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 40:
		log_lines.remove_at(0)


# --- Persistence ------------------------------------------------------------------

func to_dict() -> Dictionary:
	var fd := []
	for f in foes:
		fd.append({"enemy_id": f.enemy.enemy_id, "health": f.enemy.health, "attack_timer": f.attack_timer, "boss": f.boss,
			"ability_timers": f.ability_timers.duplicate(), "phase": f.phase, "special_ready": f.special_ready,
			"special_mult": f.special_mult, "special_name": f.special_name, "add": f.get("add", false), "dead": f.get("dead", false)})
	return {"dungeon_id": dungeon_id, "party": party.duplicate(true), "foes": fd, "floor_index": floor_index,
		"entry_remaining": entry_remaining, "elapsed": elapsed, "boss_elapsed": boss_elapsed, "enraged": enraged,
		"food": food.duplicate(), "loot": loot.duplicate(), "gold": gold, "result": result, "log": Array(log_lines), "acc": _acc, "seq": _foe_seq, "tier": tier}


static func from_dict(world, d: Dictionary) -> DungeonRun:
	var did := String(d.get("dungeon_id", ""))
	if not world.registry.dungeons.has(did):
		return null
	var run := DungeonRun.new()
	run.dungeon_id = did
	run.def = world.registry.dungeons[did]
	run._set_tier(world, clampi(int(d.get("tier", 0)), 0, int(world.registry.dungeon_mythic.get("max_tier", 10))))
	for m in d.get("party", []):
		if m is Dictionary and world.characters.has(m.get("id", "")):
			run.party.append(m.duplicate(true))
	if run.party.is_empty():
		return null
	for fd in d.get("foes", []):
		if not (fd is Dictionary) or not world.registry.enemies.has(fd.get("enemy_id", "")):
			continue
		var f := run._spawn_foe(world, String(fd.enemy_id), bool(fd.get("boss", false)))
		f.enemy.health = clampf(float(fd.get("health", f.enemy.max_health)), 0.0, f.enemy.max_health)
		f.attack_timer = float(fd.get("attack_timer", 0.0))
		f.ability_timers = fd.get("ability_timers", {}).duplicate()
		f.phase = int(fd.get("phase", -1))
		f.special_ready = bool(fd.get("special_ready", false))
		f.special_mult = float(fd.get("special_mult", 1.0))
		f.special_name = String(fd.get("special_name", ""))
		f.add = bool(fd.get("add", false))
		f.dead = bool(fd.get("dead", false))
	run.floor_index = int(d.get("floor_index", -1))
	run.entry_remaining = float(d.get("entry_remaining", 0.0))
	run.elapsed = float(d.get("elapsed", 0.0))
	run.boss_elapsed = float(d.get("boss_elapsed", 0.0))
	run.enraged = bool(d.get("enraged", false))
	for it in d.get("food", {}):
		if world.registry.items.has(it):
			run.food[String(it)] = maxi(int(d.food[it]), 0)
	for it in d.get("loot", {}):
		if world.registry.items.has(it):
			run.loot[String(it)] = maxi(int(d.loot[it]), 0)
	run.gold = maxi(int(d.get("gold", 0)), 0)
	run.result = String(d.get("result", ""))
	for l in d.get("log", []):
		run.log_lines.append(String(l))
	run._acc = float(d.get("acc", 0.0))
	run._foe_seq = int(d.get("seq", run._foe_seq))
	return run
