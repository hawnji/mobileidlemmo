class_name ConstructionHandler
extends ActivityHandler
## Work on the town's active construction project. Each work action takes
## `work_action_seconds`, adds that many (speed-scaled) work seconds to the
## project and grants Construction XP. Several characters can build at once.


func validate(e: ActivityEngine, _ch: Adventurer, _asg: Assignment, _act: Dictionary) -> String:
	if e.world.town.project.is_empty():
		return "Start a construction project in the Town first"
	return ""


func counts_deposits() -> bool:
	return false


func _required_level(e: ActivityEngine) -> int:
	var p: Dictionary = e.world.town.project
	return int(e.world.town.level_def(e.registry, String(p.building), int(p.level)).get("construction_level", 1))


func decide(e: ActivityEngine, ch: Adventurer, asg: Assignment, _act: Dictionary) -> void:
	var world: SimulationWorld = e.world
	if world.town.project.is_empty():
		if asg.continue_mode == Assignment.ContinueMode.REPEAT:
			e.wait(ch, e.materials_retry_seconds, "Waiting for a construction project")
		else:
			e.complete(ch)
		return
	if ch.skills.get_level("construction") < _required_level(e):
		e.interrupt(ch, "Needs Construction level %d" % _required_level(e))
		return
	var plot: Dictionary = world.plots.get(String(world.town.project.building), {})
	var work_tile: Vector2i = plot.get("work_tile", world.spawn_tile)
	if ch.tile == work_tile:
		ch.action_elapsed = 0.0
		ch.travel_purpose = TP.NONE
		e.set_state(ch, S.PERFORMING_ACTIVITY, "Building %s" % e.registry.buildings.get(world.town.project.building, {}).get("name", ""))
	else:
		e.travel_to(ch, work_tile, false, "Heading to the building site")


func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	e.set_state(ch, S.CHECKING_CONDITIONS)


func perform(e: ActivityEngine, ch: Adventurer, t: float) -> float:
	var world: SimulationWorld = e.world
	if world.town.project.is_empty():
		e.set_state(ch, S.CHECKING_CONDITIONS)
		return t
	var action := float(e.registry.town_config.get("work_action_seconds", 3.0))
	var need := action - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	var work := action * ch.craft_speed_multiplier("construction", _required_level(e))
	var done := world.town.add_work(work)
	ch.stats.actions = int(ch.stats.actions) + 1
	e.grant_xp(ch, "construction", float(e.registry.town_config.get("xp_per_work_second", 2.5)) * action)
	if world.wants_event("construction_progress"):
		world.emit_event("construction_progress", {"character_id": ch.id, "ratio": world.town.progress_ratio()})
	if done:
		world.complete_construction()
		if ch.assignment:
			ch.assignment.deposited_primary += 1
	e.set_state(ch, S.CHECKING_CONDITIONS)
	return t
