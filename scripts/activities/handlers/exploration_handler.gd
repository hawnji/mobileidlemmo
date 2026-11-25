class_name ExplorationHandler
extends ActivityHandler
## "Explore <region>": walk to the nearest hidden part of the region, lifting
## the fog of war as you go, and investigate any discovery the character is
## able to make. Fog and discoveries are resolved by the world whenever any
## character moves (SimulationWorld.on_character_moved); this handler only
## chooses where to walk.
##
## UNTIL_QUANTITY counts discoveries made during the assignment. The
## assignment completes when the region is explored (exploration.explore_complete_pct)
## or nothing reachable is left hidden.


func validate(e: ActivityEngine, _ch: Adventurer, _asg: Assignment, act: Dictionary) -> String:
	var region := String(act.get("region", ""))
	if not e.world.is_region_unlocked(region):
		return "Unlock %s first" % e.registry.region_name(region)
	return ""


func counts_deposits() -> bool:
	return false


func decide(e: ActivityEngine, ch: Adventurer, asg: Assignment, act: Dictionary) -> void:
	var world: SimulationWorld = e.world
	var region := String(act.get("region", ""))
	if asg.is_quantity_reached() or world.exploration.explored_pct(region) >= float(e.registry.get_config("exploration.explore_complete_pct", 0.98)):
		_finish(e, ch)
		return
	e.release_targets(ch)
	# 1. A revealed discovery this character can make: go and look.
	for did in world.exploration.discovery_order:
		var d: Dictionary = world.exploration.discoveries[did]
		if world.exploration.is_discovered(did) or String(d.get("region", "")) != region:
			continue
		var t := JsonData.to_vec2i(d.tile)
		var key := "disc:%s" % did
		if not world.exploration.is_revealed(t) or float(ch.unreachable_until.get(key, -1.0)) > world.sim_time:
			continue
		if not ExplorationState.requirement_gap(e.registry, ch, d).is_empty():
			continue
		ch.target_key = key
		e.travel_to(ch, t, true, "Investigating something interesting")
		return
	# 2. The nearest hidden tile in the region.
	var skip := {}
	for k in ch.unreachable_until:
		if String(k).begins_with("fog:") and float(ch.unreachable_until[k]) > world.sim_time:
			var parts := String(k).substr(4).split(",")
			skip[Vector2i(int(parts[0]), int(parts[1]))] = true
	var target := world.exploration.nearest_hidden(region, ch.tile, skip, world.grid)
	if target.x < 0:
		_finish(e, ch)
		return
	ch.target_key = "fog:%d,%d" % [target.x, target.y]
	e.travel_to(ch, target, false, "Exploring %s" % e.registry.region_name(region))


func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	if ch.target_key.begins_with("disc:"):
		var did := ch.target_key.substr(5)
		if e.world.try_discover(ch, did) and ch.assignment:
			ch.assignment.deposited_primary += 1
		else:
			# Already found (or not by us): do not walk back here.
			ch.unreachable_until[ch.target_key] = e.world.sim_time + 3600.0
	e.set_state(ch, S.CHECKING_CONDITIONS)


func _finish(e: ActivityEngine, ch: Adventurer) -> void:
	if ch.inventory.is_empty():
		e.complete(ch)
	else:
		e.begin_return(ch, "Exploration done, returning")
