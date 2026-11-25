class_name ActivityEstimator
extends RefCounted
## Estimates hourly results for the assignment UI ("review expected
## results"). The simulation never uses estimates.
##
## Every estimate returns at least {reachable, xp_per_hour, skill,
## items_per_hour, item}. Gathering is validated against the simulation by
## test_estimate_close_to_simulation (+-25%).


static func estimate(world: SimulationWorld, ch: Adventurer, activity_id: String, return_fill_ratio := 1.0, asg: Assignment = null) -> Dictionary:
	var act: Dictionary = world.registry.activities.get(activity_id, {})
	if act.is_empty():
		return {"reachable": false}
	match String(act.get("type", "gathering")):
		"crafting":
			return _crafting(world, ch, act, asg)
		"combat":
			return _combat(world, ch, act, asg)
		"construction":
			return _construction(world, ch)
		"exploration":
			return _exploration(world, ch, act)
	return _gathering(world, ch, act, return_fill_ratio)


static func _exploration(world: SimulationWorld, ch: Adventurer, act: Dictionary) -> Dictionary:
	var region := String(act.get("region", ""))
	var pct := world.exploration.explored_pct(region)
	# Rough: one survey every survey_seconds reveals part of a circle, but
	# never more than the region has left (so XP/h falls as the map fills in).
	var ri := world.exploration.region_ids.find(region)
	var remaining := 0
	if ri >= 0:
		remaining = world.exploration.region_walkable[ri] - world.exploration.region_revealed[ri]
	var r := float(world.reveal_radius(ch))
	var per_survey := r * r * 1.6  # new tiles per survey once neighbours overlap
	var tiles_per_hour := minf(3600.0 / ExplorationHandler.survey_seconds(world, ch) * per_survey, float(remaining))
	return {"reachable": world.is_region_unlocked(region), "skill": "exploration", "item": "",
		"items_per_hour": 0.0, "explored_pct": pct,
		"xp_per_hour": tiles_per_hour * float(world.registry.get_config("exploration.xp_per_tile", 0.6)) * ch.xp_multiplier("exploration")}


static func _storage_start(world: SimulationWorld) -> Vector2i:
	var start_tiles := world.pathfinder.adjacent_walkable(world.storage_tile)
	return start_tiles[0] if not start_tiles.is_empty() else world.spawn_tile


static func _gathering(world: SimulationWorld, ch: Adventurer, act: Dictionary, return_fill_ratio: float) -> Dictionary:
	var reg := world.registry
	var ntype: Dictionary = reg.node_types[act.node_type]
	var skill := String(ntype.skill)
	var gather := float(ntype.gather_seconds) / ch.gather_speed_multiplier(skill, int(ntype.get("required_level", 1)))
	var nodes := world.nodes_of_type(String(act.node_type), String(act.get("default_destination", "")))
	if nodes.is_empty():
		return {"reachable": false}
	var depot := world.storage_tile
	if world.outpost_level(world.region_at(nodes[0].tile)) > 0:
		depot = world.outpost_of(world.region_at(nodes[0].tile)).depot_tile
	gather /= world.local_multiplier(nodes[0].tile, "gather_speed")
	var adj := world.pathfinder.adjacent_walkable(depot)
	var start: Vector2i = adj[0] if not adj.is_empty() else _storage_start(world)
	var best := INF
	for n in nodes:
		var r := world.pathfinder.find_path_to_adjacent(start, n.tile)
		if r.reachable:
			best = minf(best, r.cost)
	if best == INF:
		return {"reachable": false}
	var trip_items := maxi(int(floor(ch.inventory.max_units * clampf(return_fill_ratio, 0.1, 1.0))), 1)
	var travel := 2.0 * best / ch.move_speed_tiles()
	var cycle := trip_items * gather + travel + float(reg.get_config("simulation.deposit_seconds", 1.0))
	var items_per_hour := 3600.0 * trip_items / cycle
	return {
		"reachable": true,
		"skill": skill,
		"item": String(ntype.yield.item),
		"gather_seconds": gather,
		"round_trip_seconds": travel,
		"trip_items": trip_items,
		"items_per_hour": items_per_hour,
		"xp_per_hour": items_per_hour * float(ntype.get("xp", 0.0)) * ch.xp_multiplier(skill),
	}


static func _crafting(world: SimulationWorld, ch: Adventurer, act: Dictionary, asg: Assignment) -> Dictionary:
	var reg := world.registry
	if asg == null or not reg.recipes.has(asg.recipe_id):
		return {"reachable": false}
	var r: Dictionary = reg.recipes[asg.recipe_id]
	var skill := String(r.skill)
	var st := world.nearest_station(ch, String(r.station))
	if st.is_empty():
		return {"reachable": false}
	var path := world.pathfinder.find_path_to_adjacent(_storage_start(world), st.tile)
	if not path.reachable:
		return {"reachable": false}
	var units := 0
	for it in r.inputs:
		units += int(r.inputs[it])
	var batches := maxi(int(ch.inventory.max_units / maxi(units, 1)), 1)
	var craft := float(r.get("seconds", 3.0)) / ch.craft_speed_multiplier(skill, int(r.get("required_level", 1)))
	var travel := 2.0 * path.cost / ch.move_speed_tiles()
	var cycle := batches * craft + travel + float(reg.get_config("simulation.deposit_seconds", 1.0)) + float(reg.get_config("simulation.restock_seconds", 1.0))
	var crafts_per_hour := 3600.0 * batches / cycle
	var out := String(r.outputs.keys()[0])
	var inputs_per_hour := {}
	for it in r.inputs:
		inputs_per_hour[it] = crafts_per_hour * int(r.inputs[it])
	return {
		"reachable": true,
		"skill": skill,
		"item": out,
		"items_per_hour": crafts_per_hour * int(r.outputs[out]),
		"xp_per_hour": crafts_per_hour * float(r.get("xp", 0.0)) * ch.xp_multiplier(skill),
		"inputs_per_hour": inputs_per_hour,
		"gather_seconds": craft,
		"trip_items": batches,
		"round_trip_seconds": travel,
	}


static func _combat(world: SimulationWorld, ch: Adventurer, act: Dictionary, asg: Assignment) -> Dictionary:
	var reg := world.registry
	var dest := String(asg.destination_id if asg else act.get("default_destination", ""))
	var enemies := world.enemies_in(dest)
	if enemies.is_empty():
		return {"reachable": false}
	var e: EnemyState = enemies[0]
	if asg and not asg.enemy_priority.is_empty():
		for c in enemies:
			if c.enemy_id == asg.enemy_priority[0]:
				e = c
				break
	var rates := CombatRules.expected_rates(ch, e, reg)
	var spk: float = rates.seconds_per_kill + 2.0  # + walking between enemies
	var kills := 3600.0 / spk
	var style_skill := CombatRules.offense_skill(ch.combat_style())
	var xp := kills * (e.max_health * float(reg.get_config("combat.xp_per_damage", 4.0)) * ch.xp_multiplier(style_skill)
		+ float(reg.get_config("combat.hunting_xp_per_enemy_level", 2.0)) * int(e.def.get("level", 1)) * ch.xp_multiplier("hunting"))
	var damage_per_kill: float = rates.taken_per_second * rates.seconds_per_kill
	var risk := "Low"
	if damage_per_kill > ch.max_health() * 0.5:
		risk = "Deadly"
	elif damage_per_kill > ch.max_health() * 0.15:
		risk = "High"
	elif damage_per_kill > ch.max_health() * 0.05:
		risk = "Medium"
	var g: Array = e.def.get("gold", [0, 0])
	return {
		"reachable": true,
		"skill": "hunting",
		"item": "",
		"enemy": String(e.def.get("name", "")),
		"kills_per_hour": kills,
		"items_per_hour": kills,
		"xp_per_hour": xp,
		"gold_per_hour": kills * (float(g[0]) + float(g[1])) / 2.0,
		"damage_per_kill": damage_per_kill,
		"hit_chance": CombatRules.player_hit_chance(ch, e, reg),
		"risk": risk,
	}


static func _construction(world: SimulationWorld, ch: Adventurer) -> Dictionary:
	var reg := world.registry
	var per := float(reg.town_config.get("xp_per_work_second", 2.5))
	return {"reachable": true, "skill": "construction", "item": "",
		"items_per_hour": 0.0, "xp_per_hour": 3600.0 * per * ch.xp_multiplier("construction"),
		"work_per_hour": 3600.0 * ch.craft_speed_multiplier("construction", 1)}
