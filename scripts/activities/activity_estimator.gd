class_name ActivityEstimator
extends RefCounted
## Estimates XP/hour and items/hour for a character doing a gathering
## activity, including travel to and from storage. Used by the assignment UI
## ("review expected results") — the simulation itself never uses estimates.


## Returns {items_per_hour, xp_per_hour, gather_seconds, round_trip_seconds,
##          trip_items, reachable}
static func estimate(world: SimulationWorld, ch: Adventurer, activity_id: String, return_fill_ratio := 1.0) -> Dictionary:
	var reg := world.registry
	var act: Dictionary = reg.activities.get(activity_id, {})
	if act.is_empty():
		return {"reachable": false}
	var ntype: Dictionary = reg.node_types[act.node_type]
	var skill := String(ntype.skill)
	var gather := float(ntype.gather_seconds) / ch.gather_speed_multiplier(skill, int(ntype.get("required_level", 1)))
	var nodes := world.nodes_of_type(String(act.node_type), String(act.get("default_destination", "")))
	if nodes.is_empty():
		return {"reachable": false}
	# Distance storage -> nearest node, from a tile next to storage.
	var start_tiles := world.pathfinder.adjacent_walkable(world.storage_tile)
	if start_tiles.is_empty():
		return {"reachable": false}
	var best := INF
	for n in nodes:
		var r := world.pathfinder.find_path_to_adjacent(start_tiles[0], n.tile)
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
		"gather_seconds": gather,
		"round_trip_seconds": travel,
		"trip_items": trip_items,
		"items_per_hour": items_per_hour,
		"xp_per_hour": items_per_hour * float(ntype.get("xp", 0.0)) * ch.xp_multiplier(skill),
	}
