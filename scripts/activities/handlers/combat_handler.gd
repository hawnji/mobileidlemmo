class_name CombatHandler
extends ActivityHandler
## Hunting grounds: pick an enemy, walk next to it, fight, loot, repeat.
##
## Fights are resolved event by event (the next player swing or the next
## enemy swing, whichever comes first), so the result does not depend on the
## simulation step size. The character eats food from its bag when health
## falls below the assignment's heal threshold, and retreats to storage to
## rest when it is below the retreat threshold with no food left. Reaching
## 0 health means INJURED: the character is carried back to the village,
## recovers for injury_seconds, then rests to full. Nothing is lost.
##
## UNTIL_QUANTITY counts enemies defeated.


func validate(e: ActivityEngine, ch: Adventurer, asg: Assignment, _act: Dictionary) -> String:
	if e.world.enemies_in(asg.destination_id).is_empty():
		return "No enemies at that destination"
	if ch.health <= 0.0:
		return "%s is too hurt to fight" % ch.display_name
	return ""


func counts_deposits() -> bool:
	return false


func primary_item(_e: ActivityEngine, _asg: Assignment) -> String:
	return ""


static func is_food(registry: DataRegistry, item_id: String) -> bool:
	return float(registry.items.get(item_id, {}).get("heal", 0)) > 0.0


func food_in_bag(e: ActivityEngine, ch: Adventurer) -> int:
	var n := 0
	for it in ch.inventory.items():
		if is_food(e.registry, it):
			n += ch.inventory.get_quantity(it)
	return n


func keep_on_deposit(e: ActivityEngine, ch: Adventurer, _asg: Assignment) -> Dictionary:
	var keep := {}
	for it in ch.inventory.items():
		if is_food(e.registry, it):
			keep[it] = ch.inventory.get_quantity(it)
	return keep


func single_trip_done(_e: ActivityEngine, _ch: Adventurer, asg: Assignment) -> bool:
	return asg.deposited_primary > 0


func decide(e: ActivityEngine, ch: Adventurer, asg: Assignment, _act: Dictionary) -> void:
	var world: SimulationWorld = e.world
	var ratio := ch.health / ch.max_health()
	var food := food_in_bag(e, ch)
	if asg.is_quantity_reached() or (asg.continue_mode == Assignment.ContinueMode.SINGLE_TRIP and asg.deposited_primary > 0):
		if ch.inventory.total_units() - food > 0:
			e.begin_return(ch, "Done, returning with loot")
		else:
			e.complete(ch)
		return
	if ratio < asg.heal_threshold and food > 0:
		eat(e, ch, asg)
		ratio = ch.health / ch.max_health()
		food = food_in_bag(e, ch)
	if ratio < asg.retreat_threshold() and food == 0:
		e.begin_return(ch, "Retreating to rest")
		return
	if ch.inventory.free_units() < 2 or ch.inventory.fill_ratio() >= asg.return_fill_ratio - EPS:
		e.begin_return(ch, "Bag full, returning")
		return
	# Stock up before the first fight, and whenever food ran out while hurt.
	if asg.food_supply > 0 and food == 0 and ratio < asg.heal_threshold and _storage_food(e, asg) > 0:
		e.begin_return(ch, "Fetching food")
		return
	var target: EnemyState = world.enemies.get(ch.target_enemy_id)
	if target == null or not target.is_available_for(ch.id):
		e.release_targets(ch)
		target = world.find_best_enemy(ch, asg.destination_id, asg.enemy_priority, asg.max_enemy_level())
	if target == null:
		e.wait(ch, e.waiting_retry_seconds, "Waiting for enemies")
		return
	target.engaged_by = ch.id
	ch.target_enemy_id = target.id
	if WorldGrid.chebyshev(ch.tile, target.tile) == 1:
		_engage(e, ch, target)
	else:
		e.travel_to(ch, target.tile, true, "Hunting %s" % target.display_name())


func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	var target: EnemyState = e.world.enemies.get(ch.target_enemy_id)
	if target and target.is_available_for(ch.id) and WorldGrid.chebyshev(ch.tile, target.tile) == 1:
		_engage(e, ch, target)
	else:
		e.set_state(ch, S.CHECKING_CONDITIONS)


func _engage(e: ActivityEngine, ch: Adventurer, target: EnemyState) -> void:
	ch.travel_purpose = TP.NONE
	ch.facing = (target.tile - ch.tile).sign()
	ch.attack_timer = 0.0
	target.attack_timer = 0.0
	e.set_state(ch, S.COMBAT, "Fighting %s" % target.display_name())


func perform(e: ActivityEngine, ch: Adventurer, t: float) -> float:
	var world: SimulationWorld = e.world
	var reg := e.registry
	var target: EnemyState = world.enemies.get(ch.target_enemy_id)
	var asg := ch.assignment
	if target == null or not target.is_available_for(ch.id) or asg == null:
		e.set_state(ch, S.CHECKING_CONDITIONS)
		return t
	var p_int := CombatRules.attack_interval(ch, reg)
	var e_int := CombatRules.enemy_attack_interval(target)
	while t > EPS:
		var to_player := maxf(p_int - ch.attack_timer, 0.0)
		var to_enemy := maxf(e_int - target.attack_timer, 0.0)
		var dt := minf(minf(to_player, to_enemy), t)
		ch.attack_timer += dt
		target.attack_timer += dt
		t -= dt
		if ch.attack_timer >= p_int - EPS:
			ch.attack_timer = 0.0
			_player_attack(e, ch, target)
			if not target.is_alive():
				_on_kill(e, ch, target, asg)
				e.set_state(ch, S.CHECKING_CONDITIONS)
				return t
		if target.attack_timer >= e_int - EPS:
			target.attack_timer = 0.0
			_enemy_attack(e, ch, target)
			if ch.health <= 0.0:
				_injure(e, ch, target)
				return t
			var ratio := ch.health / ch.max_health()
			if ratio < asg.heal_threshold and food_in_bag(e, ch) > 0:
				eat(e, ch, asg)
			elif ratio < asg.retreat_threshold() and food_in_bag(e, ch) == 0:
				e.release_targets(ch)
				e.set_state(ch, S.CHECKING_CONDITIONS, "Disengaging")
				return t
	return 0.0


func _player_attack(e: ActivityEngine, ch: Adventurer, target: EnemyState) -> void:
	var world: SimulationWorld = e.world
	var reg := e.registry
	EquipmentService.wear(world, ch, "weapon", int(reg.get_config("equipment.durability_per_attack", 1)))
	var dmg := 0
	if world.rng.randf() < CombatRules.player_hit_chance(ch, target, reg):
		dmg = world.rng.randi_range(1, CombatRules.player_max_hit(ch, target, reg))
		dmg = mini(dmg, int(ceil(target.health)))
		target.health -= dmg
	if world.wants_event("combat_hit"):
		world.emit_event("combat_hit", {"character_id": ch.id, "spawn_id": target.id, "damage": dmg, "by": "player"})
	if dmg > 0:
		ch.stats.damage_dealt = int(ch.stats.damage_dealt) + dmg
		var xp := dmg * float(reg.get_config("combat.xp_per_damage", 4.0))
		match ch.combat_style():
			"ranged":
				e.grant_xp(ch, "ranged", xp)
			"magic":
				e.grant_xp(ch, "magic", xp)
			_:
				e.grant_xp(ch, "attack", xp * 0.5)
				e.grant_xp(ch, "strength", xp * 0.5)


func _enemy_attack(e: ActivityEngine, ch: Adventurer, target: EnemyState) -> void:
	var world: SimulationWorld = e.world
	var reg := e.registry
	var dmg := 0
	if world.rng.randf() < CombatRules.enemy_hit_chance(ch, target, reg):
		dmg = maxi(world.rng.randi_range(0, CombatRules.enemy_max_hit(target)) - CombatRules.damage_reduction(ch, reg), 0)
	if dmg > 0:
		ch.health = maxf(ch.health - dmg, 0.0)
		EquipmentService.wear_random_armor(world, ch, int(reg.get_config("equipment.durability_per_hit_taken", 1)))
		e.grant_xp(ch, "defense", dmg * float(reg.get_config("combat.defense_xp_per_damage_taken", 1.5)))
	if world.wants_event("combat_hit"):
		world.emit_event("combat_hit", {"character_id": ch.id, "spawn_id": target.id, "damage": dmg, "by": "enemy"})


## Eats the best (or chosen) food in the bag. Food is a sink in the ledger.
func eat(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> bool:
	var world: SimulationWorld = e.world
	var best := ""
	var best_heal := 0.0
	for it in ch.inventory.items():
		var h := float(e.registry.items.get(it, {}).get("heal", 0))
		if h <= 0.0:
			continue
		if it == asg.food_item:
			best = it
			best_heal = h
			break
		if h > best_heal:
			best = it
			best_heal = h
	if best.is_empty():
		return false
	var saved := world.rng.randf() < ch.stat("supply_saving_chance")
	if not saved:
		ch.inventory.remove(best, 1)
		world.record_sink(best, 1, "eaten")
	var mh := ch.max_health()
	ch.health = minf(ch.health + best_heal * ch.stat("healing"), mh)
	if world.wants_event("food_eaten"):
		world.emit_event("food_eaten", {"character_id": ch.id, "item_id": best, "heal": best_heal})
	return true


func _on_kill(e: ActivityEngine, ch: Adventurer, target: EnemyState, asg: Assignment) -> void:
	var world: SimulationWorld = e.world
	var reg := e.registry
	var vdef := target.variant_def
	var rolls := int(vdef.get("loot_rolls", 1))
	var loot := {}
	for r in rolls:
		for drop in target.def.get("loot", []):
			var chance := float(drop.get("chance", 0.0)) * (ch.rare_drop_multiplier("hunting") if float(drop.get("chance", 0.0)) < 0.5 else 1.0)
			if world.rng.randf() < chance:
				var it := String(drop.item)
				var q := world.rng.randi_range(int(drop.get("min", 1)), int(drop.get("max", 1)))
				var added := ch.inventory.add(it, q)  # loot that does not fit is left behind
				if added > 0:
					world.record_source(it, added, "loot")
					ch.record("gathered", it, added)
					loot[it] = int(loot.get(it, 0)) + added
	var g: Array = target.def.get("gold", [0, 0])
	var gold := int(round(world.rng.randi_range(int(g[0]), int(g[1])) * float(vdef.get("gold_multiplier", 1.0)) * world.encounters.gold_multiplier_at(target.tile)))
	if gold > 0:
		world.wallet.earn("gold", gold, "loot")
	var cur: Dictionary = target.def.get("currencies", {})
	for c in cur:
		var amt := world.rng.randi_range(int(cur[c][0]), int(cur[c][1]))
		if amt > 0:
			world.wallet.earn(String(c), amt, "loot")
	var hxp := float(reg.get_config("combat.hunting_xp_per_enemy_level", 2.0)) * int(target.def.get("level", 1)) * float(vdef.get("xp_multiplier", 1.0))
	e.grant_xp(ch, "hunting", hxp)
	ch.record("kills", target.enemy_id, 1)
	ch.stats.actions = int(ch.stats.actions) + 1
	asg.deposited_primary += 1
	world.emit_event("enemy_killed", {"character_id": ch.id, "spawn_id": target.id, "enemy_id": target.enemy_id,
		"variant": target.variant, "name": target.display_name(), "loot": loot, "gold": gold})
	ch.target_enemy_id = ""
	world.mark_enemy_dead(target)


func _injure(e: ActivityEngine, ch: Adventurer, target: EnemyState) -> void:
	var world: SimulationWorld = e.world
	e.release_targets(ch)
	ch.health = 0.0
	ch.stats.deaths = int(ch.stats.deaths) + 1
	ch.tile = world.free_tile_near(world.storage_tile, world.character_order.find(ch.id))
	ch.path.clear()
	ch.travel_purpose = TP.NONE
	ch.injured_remaining = float(e.registry.get_config("combat.injury_seconds", 60.0))
	e.set_state(ch, S.INJURED, "Defeated by %s" % target.display_name())
	world.emit_event("character_injured", {"character_id": ch.id, "enemy": target.display_name()})
	world.emit_event("interrupted", {"character_id": ch.id, "reason": "Defeated by %s" % target.display_name()})


func _storage_food(e: ActivityEngine, asg: Assignment) -> int:
	var n := 0
	for it in e.world.storage.items():
		if is_food(e.registry, it) and not e.world.locked_items.has(it) and (asg.food_item.is_empty() or asg.food_item == it):
			n += e.world.storage.get_quantity(it)
	return n


func after_deposit(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> void:
	if ch.health < ch.max_health() * 0.95:
		e.set_state(ch, S.RESTING, "Resting")
	elif wants_restock(e, ch, asg):
		ch.action_elapsed = 0.0
		e.set_state(ch, S.RESTOCKING, "Packing food")
	else:
		super.after_deposit(e, ch, asg)


func wants_restock(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> bool:
	return asg.food_supply > food_in_bag(e, ch) and _storage_food(e, asg) > 0


## Takes the best food from storage up to the assignment's food supply.
func restock(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> void:
	var world: SimulationWorld = e.world
	var want := asg.food_supply - food_in_bag(e, ch)
	var options: Array = []
	for it in world.storage.items():
		if is_food(e.registry, it) and not world.locked_items.has(it) and (asg.food_item.is_empty() or asg.food_item == it):
			options.append(it)
	options.sort_custom(func(a, b): return float(e.registry.items[a].heal) > float(e.registry.items[b].heal))
	for it in options:
		if want <= 0:
			break
		var q := mini(mini(want, world.storage.get_quantity(it)), ch.inventory.can_add(it, want))
		if q > 0:
			world.storage.remove(it, q)
			ch.inventory.add(it, q)
			want -= q
	e.set_state(ch, S.CHECKING_CONDITIONS, "Heading out")
