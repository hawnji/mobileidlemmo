class_name EndgameState
extends RefCounted
## Phase 5 account progression that survives World Ascension:
##
##   * relics   (data/endgame/relics.json)   owned with a level 1..max_level,
##     equipped in a limited number of slots; account-wide effects.
##   * pets     (data/endgame/pets.json)     hatched from eggs, assigned to one
##     hero each; they level from a share of their owner's XP.
##   * mounts   (data/endgame/mounts.json)   unlocked from whistles, ridden by
##     one hero each; flying mounts open the Celestial Isles.
##   * mastery  (data/endgame/mastery.json)  per hero and skill: XP earned at
##     the skill's maximum level (stored on Adventurer.mastery_xp).
##   * ascension (data/endgame/ascension.json) count, best score and the
##     permanent perks bought with ascension points.
##   * mythic dungeon records: highest tier cleared per dungeon.
##   * seasons  (data/endgame/seasons.json)  from the real calendar.
##
## The object is also an AccountEffects source: `effects` (relics, perks and
## the season bonus) and `version` change together. Per-hero effects (pet,
## mount, mastery) are applied by Adventurer.stat_block() through
## apply_character_effects().

var registry: DataRegistry
var relic_defs := {}
var pet_defs := {}
var mount_defs := {}
var perk_defs := {}
var season_defs: Array = []
var relic_cfg := {}
var pet_cfg := {}
var mastery_cfg := {}
var ascension_cfg := {}

var relics := {}  # relic_id -> level (1..max)
var equipped_relics: Array[String] = []
var pets := {}  # pet_id -> {level, xp}
var pet_assign := {}  # character_id -> pet_id
var mounts := {}  # mount_id -> true
var mount_assign := {}  # character_id -> mount_id
var perks := {}  # perk_id -> rank
var ascensions := 0
var best_score := 0
var lifetime_points := 0
var mythic_records := {}  # dungeon_id -> highest tier cleared
## Unix time used for the season. 0 = no season: the simulation never reads
## the system clock itself, so it stays deterministic. Game keeps it current.
var calendar_unix := 0.0

var effects: StatBlock
var version := 1
var _season := ""


func setup(p_registry: DataRegistry) -> void:
	registry = p_registry
	relic_cfg = registry.endgame.get("relics", {})
	pet_cfg = registry.endgame.get("pets", {})
	mastery_cfg = registry.endgame.get("mastery", {})
	ascension_cfg = registry.endgame.get("ascension", {})
	for r in relic_cfg.get("relics", []):
		relic_defs[String(r.id)] = r
	for p in pet_cfg.get("pets", []):
		pet_defs[String(p.id)] = p
	for m in registry.endgame.get("mounts", {}).get("mounts", []):
		mount_defs[String(m.id)] = m
	for p in ascension_cfg.get("perks", []):
		perk_defs[String(p.id)] = p
	season_defs = registry.endgame.get("seasons", {}).get("seasons", [])
	_rebuild()


# ==========================================================================
# Account effects
# ==========================================================================

func _rebuild() -> void:
	var sb := registry.new_stat_block()
	for rid in equipped_relics:
		var def: Dictionary = relic_defs.get(rid, {})
		sb.apply(def.get("effects_per_level", {}), float(relics.get(rid, 1)))
	for pid in perks:
		sb.apply(perk_defs.get(pid, {}).get("effects_per_rank", {}), float(perks[pid]))
	for s in season_defs:
		if String(s.id) == _season:
			sb.apply(s.get("effects", {}))
	effects = sb
	version += 1


## Call regularly (Game does it once a second): switches the season bonus
## when the month changes. Returns true when the season changed.
func set_calendar(unix: float) -> bool:
	calendar_unix = unix
	var s := season_at(unix)
	if s == _season:
		return false
	_season = s
	_rebuild()
	return true


func season_at(unix: float) -> String:
	if unix <= 0.0:
		return ""
	var month := int(Time.get_datetime_dict_from_unix_time(int(unix)).get("month", 1))
	for s in season_defs:
		for m in s.get("months", []):
			if int(m) == month:
				return String(s.id)
	return ""


func current_season() -> String:
	return _season


func season_def(season_id := "") -> Dictionary:
	var sid := season_id if not season_id.is_empty() else _season
	for s in season_defs:
		if String(s.id) == sid:
			return s
	return {}


# ==========================================================================
# Per-character effects (pet, mount, mastery)
# ==========================================================================

func apply_character_effects(ch: Adventurer, sb: StatBlock) -> void:
	var pid := String(pet_assign.get(ch.id, ""))
	if pets.has(pid):
		sb.apply(pet_defs.get(pid, {}).get("effects_per_level", {}), float(pets[pid].level))
	var mid := String(mount_assign.get(ch.id, ""))
	if mounts.has(mid):
		sb.apply(mount_defs.get(mid, {}).get("effects", {}))
	var per_level: Dictionary = mastery_cfg.get("effects_per_level", {})
	for skill in ch.mastery_xp:
		var lvl := mastery_level(ch, String(skill))
		if lvl <= 0:
			continue
		var cat := String(registry.skills.get(skill, {}).get("category", ""))
		var fx: Dictionary = per_level.get(cat, {})
		var keyed := {}
		for fam in fx:
			keyed["%s.%s" % [fam, skill]] = fx[fam]
		sb.apply(keyed, float(lvl))


func mastery_level(ch: Adventurer, skill: String) -> int:
	var per := float(mastery_cfg.get("xp_per_level", 2000000))
	return mini(int(floor(float(ch.mastery_xp.get(skill, 0.0)) / maxf(per, 1.0))), int(mastery_cfg.get("max_level", 20)))


## Called by ActivityEngine.grant_xp for every XP grant.
## `at_max` is true when the skill was already at its maximum level.
func on_xp(world, ch: Adventurer, skill: String, xp: float, at_max: bool) -> void:
	_feed_pet(world, ch, xp)
	if at_max:
		_add_mastery(world, ch, skill, xp * ch.stat("mastery_xp"))


func _add_mastery(world, ch: Adventurer, skill: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var before := mastery_level(ch, skill)
	var cap := float(mastery_cfg.get("xp_per_level", 2000000)) * int(mastery_cfg.get("max_level", 20))
	ch.mastery_xp[skill] = minf(float(ch.mastery_xp.get(skill, 0.0)) + amount, cap)
	var after := mastery_level(ch, skill)
	if after == before:
		return
	ch.invalidate_stats()
	world.emit_event("mastery_up", {"character_id": ch.id, "skill": skill, "level": after})
	for ms in mastery_cfg.get("milestones", []):
		var lv := int(ms.get("level", 0))
		if before < lv and after >= lv:
			world.grant_rewards(ms.get("reward", {}), [], "mastery:%s:%d" % [skill, lv])


func _feed_pet(world, ch: Adventurer, xp: float) -> void:
	var pid := String(pet_assign.get(ch.id, ""))
	if not pets.has(pid):
		return
	var p: Dictionary = pets[pid]
	var table: Array = pet_cfg.get("level_xp", [0])
	var max_level := mini(int(pet_cfg.get("max_level", 10)), table.size())
	if int(p.level) >= max_level:
		return
	p.xp = float(p.xp) + xp * float(pet_cfg.get("xp_share", 0.05))
	var lvl := int(p.level)
	while lvl < max_level and float(p.xp) >= float(table[lvl]):
		lvl += 1
	if lvl != int(p.level):
		p.level = lvl
		ch.invalidate_stats()
		world.emit_event("pet_level_up", {"pet": pid, "level": lvl, "character_id": ch.id,
			"name": pet_defs.get(pid, {}).get("name", pid)})


func pet_progress(pet_id: String) -> float:
	if not pets.has(pet_id):
		return 0.0
	var table: Array = pet_cfg.get("level_xp", [0])
	var lvl := int(pets[pet_id].level)
	if lvl >= table.size():
		return 1.0
	var lo := float(table[lvl - 1])
	var hi := float(table[lvl])
	return clampf((float(pets[pet_id].xp) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


# ==========================================================================
# Collectibles: eggs, whistles, relics, sigils
# ==========================================================================

## Applies the unlock of a collectible item that has already been taken out
## of storage. Returns a short description of what happened.
func unlock(world, unlock: Dictionary) -> String:
	var kind := String(unlock.get("type", ""))
	var uid := String(unlock.get("id", ""))
	match kind:
		"pet":
			if not pet_defs.has(uid):
				return ""
			if pets.has(uid):
				var dust := _dust_for(String(pet_defs[uid].get("rarity", "rare")))
				world.wallet.earn("relic_dust", dust, "duplicate_pet")
				return "%s is already in your menagerie: +%d relic dust" % [pet_defs[uid].name, dust]
			pets[uid] = {"level": 1, "xp": 0.0}
			world.emit_event("pet_hatched", {"pet": uid, "name": pet_defs[uid].name})
			return "%s hatched!" % pet_defs[uid].name
		"mount":
			if not mount_defs.has(uid):
				return ""
			if mounts.has(uid):
				var dust := _dust_for(String(mount_defs[uid].get("rarity", "rare")))
				world.wallet.earn("relic_dust", dust, "duplicate_mount")
				return "You already own a %s: +%d relic dust" % [mount_defs[uid].name, dust]
			mounts[uid] = true
			world.emit_event("mount_unlocked", {"mount": uid, "name": mount_defs[uid].name})
			return "%s joins your stables!" % mount_defs[uid].name
		"relic":
			if not relic_defs.has(uid):
				return ""
			if relics.has(uid):
				var dust := _dust_for(String(relic_defs[uid].get("rarity", "rare")))
				world.wallet.earn("relic_dust", dust, "duplicate_relic")
				return "%s is already yours: +%d relic dust" % [relic_defs[uid].name, dust]
			relics[uid] = 1
			if equipped_relics.size() < relic_slots():
				equipped_relics.append(uid)
				_rebuild()
			world.emit_event("relic_found", {"relic": uid, "name": relic_defs[uid].name})
			return "%s added to your relics." % relic_defs[uid].name
		"character":
			if not registry.characters.has(uid):
				return ""
			world.grant_character(uid, "sigil")
			return "%s answers the sigil!" % registry.characters[uid].get("name", uid)
	return ""


func _dust_for(rarity: String) -> int:
	return int(relic_cfg.get("duplicate_dust", {}).get(rarity, 20))


# ==========================================================================
# Commands
# ==========================================================================

func relic_slots() -> int:
	var extra := 0
	for pid in perks:
		extra += int(perk_defs.get(pid, {}).get("effects_per_rank", {}).get("relic_slots", 0)) * int(perks[pid])
	return mini(int(relic_cfg.get("base_slots", 3)) + extra, int(relic_cfg.get("max_slots", 6)))


func equip_relic(relic_id: String) -> String:
	if not relics.has(relic_id):
		return "You do not own that relic"
	if equipped_relics.has(relic_id):
		return "Already equipped"
	if equipped_relics.size() >= relic_slots():
		return "All %d relic slots are in use" % relic_slots()
	equipped_relics.append(relic_id)
	_rebuild()
	return ""


func unequip_relic(relic_id: String) -> String:
	if not equipped_relics.has(relic_id):
		return "Not equipped"
	equipped_relics.erase(relic_id)
	_rebuild()
	return ""


func relic_upgrade_cost(relic_id: String) -> int:
	var lvl := int(relics.get(relic_id, 0))
	var costs: Array = relic_cfg.get("upgrade_costs", [])
	if lvl <= 0 or lvl > costs.size() or lvl >= int(relic_cfg.get("max_level", 5)):
		return -1
	return int(costs[lvl - 1])


func upgrade_relic(world, relic_id: String) -> String:
	var cost := relic_upgrade_cost(relic_id)
	if cost < 0:
		return "Relic is at its maximum level" if relics.has(relic_id) else "You do not own that relic"
	if not world.wallet.spend("relic_dust", cost, "relic_upgrade:%s" % relic_id):
		return "Needs %d relic dust" % cost
	relics[relic_id] = int(relics[relic_id]) + 1
	_rebuild()
	world.emit_event("relic_upgraded", {"relic": relic_id, "level": relics[relic_id]})
	return ""


func assign_pet(world, character_id: String, pet_id: String) -> String:
	if not world.characters.has(character_id):
		return "Unknown character"
	if not pet_id.is_empty() and not pets.has(pet_id):
		return "You do not own that pet"
	for cid in pet_assign.keys():
		if pet_assign[cid] == pet_id or cid == character_id:
			pet_assign.erase(cid)
			if world.characters.has(cid):
				world.characters[cid].invalidate_stats()
	if not pet_id.is_empty():
		pet_assign[character_id] = pet_id
	world.characters[character_id].invalidate_stats()
	return ""


func assign_mount(world, character_id: String, mount_id: String) -> String:
	if not world.characters.has(character_id):
		return "Unknown character"
	if not mount_id.is_empty() and not mounts.has(mount_id):
		return "You do not own that mount"
	for cid in mount_assign.keys():
		if mount_assign[cid] == mount_id or cid == character_id:
			mount_assign.erase(cid)
			if world.characters.has(cid):
				world.characters[cid].invalidate_stats()
	if not mount_id.is_empty():
		mount_assign[character_id] = mount_id
	var ch: Adventurer = world.characters[character_id]
	ch.invalidate_stats()
	ch.refresh_capacity()
	return ""


func owns_mount_tag(tag: String) -> bool:
	for mid in mounts:
		if tag.is_empty() or (mount_defs.get(mid, {}).get("tags", []) as Array).has(tag):
			return true
	return false


func perk_cost(perk_id: String) -> int:
	var def: Dictionary = perk_defs.get(perk_id, {})
	var rank := int(perks.get(perk_id, 0))
	var costs: Array = def.get("cost", [])
	if def.is_empty() or rank >= int(def.get("max_rank", 1)) or rank >= costs.size():
		return -1
	return int(costs[rank])


func buy_perk(world, perk_id: String) -> String:
	var cost := perk_cost(perk_id)
	if cost < 0:
		return "Perk is at its maximum rank" if perk_defs.has(perk_id) else "Unknown perk"
	if not world.wallet.spend("ascension_points", cost, "perk:%s" % perk_id):
		return "Needs %d ascension points" % cost
	perks[perk_id] = int(perks.get(perk_id, 0)) + 1
	_rebuild()
	world.emit_event("perk_bought", {"perk": perk_id, "rank": perks[perk_id]})
	return ""


func head_start_gold() -> int:
	var out := 0
	for pid in perks:
		out += int(perk_defs.get(pid, {}).get("start_gold_per_rank", 0)) * int(perks[pid])
	return out


# ==========================================================================
# Mythic dungeon tiers
# ==========================================================================

func mythic_cfg() -> Dictionary:
	return registry.dungeon_mythic


## Highest tier the party may start: 1 after a normal clear, then best + 1.
func max_unlocked_tier(world, dungeon_id: String) -> int:
	if int(world.dungeon_records.get(dungeon_id, {}).get("clears", 0)) <= 0 and int(mythic_records.get(dungeon_id, 0)) <= 0:
		return 0
	return mini(int(mythic_records.get(dungeon_id, 0)) + 1, int(mythic_cfg().get("max_tier", 10)))


func affixes_for(tier: int) -> Array:
	var out := []
	for a in mythic_cfg().get("affixes", []):
		if tier >= int(a.get("min_tier", 99)):
			out.append(a)
	return out


func best_mythic_total() -> int:
	var t := 0
	for d in mythic_records:
		t += int(mythic_records[d])
	return t


# ==========================================================================
# Ascension score
# ==========================================================================

func score(world) -> int:
	var sc: Dictionary = ascension_cfg.get("score", {})
	var levels := 0
	for skill in registry.skill_order:
		levels += world.max_skill_level(skill)
	var mastery := 0
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		for skill in ch.mastery_xp:
			mastery += mastery_level(ch, String(skill))
	return int(levels * float(sc.get("per_skill_level", 1)) + mastery * float(sc.get("per_mastery_level", 5))
		+ best_mythic_total() * float(sc.get("per_mythic_tier", 40)) + world.exploration.discovered.size() * float(sc.get("per_discovery", 2)))


func _points_for(p_score: int) -> int:
	var pc: Dictionary = ascension_cfg.get("points", {})
	return int(floor(float(pc.get("scale", 30.0)) * sqrt(maxf(p_score, 0) / maxf(float(pc.get("unit", 100.0)), 1.0))))


## Points an ascension now would grant: the growth of the score curve since
## the best previous ascension, never less than the configured minimum.
func points_preview(world) -> int:
	var s := score(world)
	return maxi(int(ascension_cfg.get("points", {}).get("minimum", 5)), _points_for(s) - _points_for(best_score))


# ==========================================================================
# Persistence
# ==========================================================================

func to_dict() -> Dictionary:
	return {"relics": relics.duplicate(), "equipped_relics": Array(equipped_relics), "pets": pets.duplicate(true),
		"pet_assign": pet_assign.duplicate(), "mounts": mounts.keys(), "mount_assign": mount_assign.duplicate(),
		"perks": perks.duplicate(), "ascensions": ascensions, "best_score": best_score, "lifetime_points": lifetime_points,
		"mythic_records": mythic_records.duplicate()}


func load_dict(world, d: Dictionary) -> void:
	var max_lvl := int(relic_cfg.get("max_level", 5))
	for rid in d.get("relics", {}):
		if relic_defs.has(rid):
			relics[String(rid)] = clampi(int(d.relics[rid]), 1, max_lvl)
	equipped_relics.clear()
	for rid in d.get("equipped_relics", []):
		if relics.has(rid) and not equipped_relics.has(String(rid)):
			equipped_relics.append(String(rid))
	for pid in d.get("pets", {}):
		if pet_defs.has(pid) and d.pets[pid] is Dictionary:
			pets[String(pid)] = {"level": clampi(int(d.pets[pid].get("level", 1)), 1, int(pet_cfg.get("max_level", 10))),
				"xp": maxf(float(d.pets[pid].get("xp", 0.0)), 0.0)}
	for cid in d.get("pet_assign", {}):
		if world.characters.has(cid) and pets.has(d.pet_assign[cid]):
			pet_assign[String(cid)] = String(d.pet_assign[cid])
	for mid in d.get("mounts", []):
		if mount_defs.has(mid):
			mounts[String(mid)] = true
	for cid in d.get("mount_assign", {}):
		if world.characters.has(cid) and mounts.has(d.mount_assign[cid]):
			mount_assign[String(cid)] = String(d.mount_assign[cid])
	for pid in d.get("perks", {}):
		if perk_defs.has(pid):
			perks[String(pid)] = clampi(int(d.perks[pid]), 0, int(perk_defs[pid].get("max_rank", 1)))
	ascensions = maxi(int(d.get("ascensions", 0)), 0)
	best_score = maxi(int(d.get("best_score", 0)), 0)
	lifetime_points = maxi(int(d.get("lifetime_points", 0)), 0)
	for did in d.get("mythic_records", {}):
		if registry.dungeons.has(did):
			mythic_records[String(did)] = clampi(int(d.mythic_records[did]), 0, int(mythic_cfg().get("max_tier", 10)))
	while equipped_relics.size() > relic_slots():
		equipped_relics.pop_back()
	_rebuild()
	for cid in world.character_order:
		world.characters[cid].invalidate_stats()
		world.characters[cid].refresh_capacity()
