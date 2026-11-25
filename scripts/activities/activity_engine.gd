class_name ActivityEngine
extends RefCounted
## Drives every character's autonomous behaviour.
##
## tick() consumes a time budget by running state handlers until the budget
## is spent. Each handler returns the time it did NOT use, so a single large
## step (1 s during offline simulation) produces the same outcome as many
## small ones (0.1 s while playing). That property is what lets online play
## and offline simulation share one implementation.
##
## The engine owns the shared parts of every loop: travel, pathfinding,
## depositing, restocking, waiting, resting and injury. What a character
## does at its work site is delegated to an ActivityHandler chosen by the
## activity's "type" (gathering, crafting, combat, construction).
##
## Gathering:    CHECK -> PATHFINDING -> TRAVELING -> PERFORMING -> CHECK ... -> RETURNING -> DEPOSITING
## Crafting:     CHECK -> (RETURNING -> DEPOSITING -> RESTOCKING) -> TRAVELING to station -> PERFORMING ...
## Combat:       CHECK -> TRAVELING to enemy -> COMBAT -> CHECK ... (INJURED -> RESTING) (RETURNING -> DEPOSITING -> RESTING -> RESTOCKING)
## Construction: CHECK -> TRAVELING to the building plot -> PERFORMING ... until the project completes

const S := CharacterStates.State
const TP := Adventurer.TravelPurpose
const EPS := 0.000001

## The owning SimulationWorld. Held weakly: the world owns the engine, so a
## strong back-reference would form a RefCounted cycle and leak.
var world:
	get:
		return _world_ref.get_ref()
var _world_ref: WeakRef
var registry: DataRegistry
var handlers := {}  # activity type -> ActivityHandler
var max_steps_per_tick := 32
var waiting_retry_seconds := 2.0
var materials_retry_seconds := 10.0
var unreachable_cooldown := 30.0
var max_path_failures := 5
var deposit_seconds := 1.0
var restock_seconds := 1.0
var character_xp_share := 0.25
var regen_per_second := 0.01
var rest_regen_per_second := 0.08


func _init(p_world, p_registry: DataRegistry) -> void:
	_world_ref = weakref(p_world)
	registry = p_registry
	max_steps_per_tick = int(registry.get_config("simulation.max_state_steps_per_tick", 32))
	waiting_retry_seconds = float(registry.get_config("simulation.waiting_retry_seconds", 2.0))
	materials_retry_seconds = float(registry.get_config("simulation.materials_retry_seconds", 10.0))
	unreachable_cooldown = float(registry.get_config("simulation.unreachable_node_cooldown_seconds", 30.0))
	max_path_failures = int(registry.get_config("simulation.max_consecutive_path_failures", 5))
	deposit_seconds = float(registry.get_config("simulation.deposit_seconds", 1.0))
	restock_seconds = float(registry.get_config("simulation.restock_seconds", 1.0))
	character_xp_share = float(registry.get_config("character_progression.character_xp_share", 0.25))
	regen_per_second = float(registry.get_config("combat.regen_per_second", 0.01))
	rest_regen_per_second = float(registry.get_config("combat.rest_regen_per_second", 0.08))
	handlers = {
		"gathering": GatheringHandler.new(),
		"crafting": CraftingHandler.new(),
		"combat": CombatHandler.new(),
		"construction": ConstructionHandler.new(),
	}


func handler_for(activity_id: String) -> ActivityHandler:
	var act: Dictionary = registry.activities.get(activity_id, {})
	return handlers.get(String(act.get("type", "gathering")))


# ==========================================================================
# Public API
# ==========================================================================

## Validates and starts an assignment. Returns "" on success or a reason.
func assign(ch: Adventurer, asg: Assignment) -> String:
	var err := validate_assignment(ch, asg)
	if not err.is_empty():
		return err
	if ch.state == S.INJURED:
		return "%s is recovering from an injury" % ch.display_name
	cancel(ch, "")
	asg.character_id = ch.id
	asg.started_at_sim_time = world.sim_time
	ch.assignment = asg
	ch.path_failures = 0
	ch.unreachable_until.clear()
	_set_state(ch, S.ASSIGNED, "Assigned: %s" % registry.activities[asg.activity_id].get("name", asg.activity_id))
	world.emit_event("assignment_started", {"character_id": ch.id, "activity_id": asg.activity_id})
	return ""


func validate_assignment(ch: Adventurer, asg: Assignment) -> String:
	if asg == null:
		return "No assignment"
	var act: Dictionary = registry.activities.get(asg.activity_id, {})
	if act.is_empty():
		return "Unknown activity '%s'" % asg.activity_id
	var skill := String(act.get("skill", ""))
	var req := int(act.get("required_level", 1))
	if not skill.is_empty() and ch.skills.get_level(skill) < req:
		return "%s needs %s level %d" % [ch.display_name, registry.skills.get(skill, {}).get("name", skill), req]
	if not asg.destination_id.is_empty() and not world.locations.has(asg.destination_id):
		return "Unknown destination '%s'" % asg.destination_id
	var h := handler_for(asg.activity_id)
	if h == null:
		return "Activity type '%s' is not supported" % act.get("type", "")
	return h.validate(self, ch, asg, act)


## Stops the current assignment. The character keeps its bag contents.
## An injured character keeps recovering.
func cancel(ch: Adventurer, message := "Stopped") -> void:
	release_targets(ch)
	ch.path.clear()
	ch.path_index = 0
	ch.move_progress = 0.0
	ch.action_elapsed = 0.0
	ch.travel_purpose = TP.NONE
	ch.assignment = null
	if ch.state == S.INJURED or ch.state == S.RESTING:
		return
	if ch.state != S.IDLE:
		_set_state(ch, S.IDLE, message)


func tick(ch: Adventurer, dt: float) -> void:
	if ch.state != S.COMBAT and ch.state != S.INJURED and ch.state != S.RESTING:
		var mh := ch.max_health()
		if ch.health < mh:
			ch.health = minf(ch.health + regen_per_second * mh * dt, mh)
	var remaining := dt
	var steps := 0
	while remaining > EPS and steps < max_steps_per_tick:
		steps += 1
		var before_state := ch.state
		var left := _run_state(ch, remaining)
		# A handler that neither used time nor changed state is blocked
		# (e.g. waiting for a pathfinding slot): stop for this tick.
		if is_equal_approx(left, remaining) and before_state == ch.state:
			break
		remaining = left


# ==========================================================================
# State handlers. Each returns unused time.
# ==========================================================================

func _run_state(ch: Adventurer, t: float) -> float:
	match ch.state:
		S.IDLE, S.COMPLETED:
			return 0.0
		S.ASSIGNED:
			set_state(ch, S.CHECKING_CONDITIONS)
			return t
		S.CHECKING_CONDITIONS:
			_check_conditions(ch)
			return t
		S.PATHFINDING:
			return _pathfind(ch, t)
		S.TRAVELING, S.RETURNING:
			return _move(ch, t)
		S.PERFORMING_ACTIVITY, S.COMBAT:
			var h := _handler(ch)
			if h == null:
				interrupt(ch, "Activity no longer exists")
				return t
			return h.perform(self, ch, t)
		S.DEPOSITING:
			return _deposit(ch, t)
		S.RESTOCKING:
			return _restock(ch, t)
		S.RESTING:
			return _rest(ch, t)
		S.INJURED:
			ch.injured_remaining -= t
			if ch.injured_remaining > 0.0:
				return 0.0
			var left := -ch.injured_remaining
			ch.injured_remaining = 0.0
			set_state(ch, S.RESTING, "Resting after injury")
			return left
		S.WAITING:
			ch.wait_remaining -= t
			if ch.wait_remaining > 0.0:
				return 0.0
			var left := -ch.wait_remaining
			ch.wait_remaining = 0.0
			set_state(ch, S.CHECKING_CONDITIONS)
			return left
	set_state(ch, S.CHECKING_CONDITIONS)
	return t


func _handler(ch: Adventurer) -> ActivityHandler:
	if ch.assignment == null:
		return null
	return handler_for(ch.assignment.activity_id)


## The decision point of every loop.
func _check_conditions(ch: Adventurer) -> void:
	var asg := ch.assignment
	if asg == null:
		set_state(ch, S.IDLE, "No assignment")
		return
	var act: Dictionary = registry.activities.get(asg.activity_id, {})
	if act.is_empty():
		interrupt(ch, "Activity no longer exists")
		return
	var skill := String(act.get("skill", ""))
	if not skill.is_empty() and ch.skills.get_level(skill) < int(act.get("required_level", 1)):
		interrupt(ch, "Skill level too low for %s" % act.get("name", ""))
		return
	_handler(ch).decide(self, ch, asg, act)


func _pathfind(ch: Adventurer, t: float) -> float:
	if not world.take_path_budget():
		return t  # no budget this tick; tick() will stop and retry next tick
	var result: PathResult
	var target_id := ""
	match ch.travel_purpose:
		TP.TO_STORAGE:
			result = world.pathfinder.find_path_to_adjacent(ch.tile, world.storage_tile)
		TP.TO_NODE:
			var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
			if node == null:
				set_state(ch, S.CHECKING_CONDITIONS)
				return t
			target_id = node.id
			result = world.pathfinder.find_path_to_adjacent(ch.tile, node.tile)
		_:
			target_id = ch.target_enemy_id if not ch.target_enemy_id.is_empty() else ch.target_station_id
			if ch.target_adjacent:
				result = world.pathfinder.find_path_to_adjacent(ch.tile, ch.target_tile)
			else:
				result = world.pathfinder.find_path(ch.tile, ch.target_tile)
	if not result.reachable:
		ch.path_failures += 1
		if ch.path_failures >= max_path_failures:
			interrupt(ch, "Stuck: no route found")
			return t
		if ch.travel_purpose == TP.TO_STORAGE:
			ch.wait_remaining = waiting_retry_seconds
			set_state(ch, S.WAITING, "Cannot reach storage, retrying")
		else:
			if not target_id.is_empty():
				ch.unreachable_until[target_id] = world.sim_time + unreachable_cooldown
			release_targets(ch)
			set_state(ch, S.CHECKING_CONDITIONS, "Route blocked, trying another spot")
		return t
	ch.path_failures = 0
	ch.path = result.path
	ch.path_index = 0
	ch.move_progress = 0.0
	if ch.path.is_empty():
		_arrive(ch)
	elif ch.travel_purpose == TP.TO_STORAGE:
		set_state(ch, S.RETURNING)
	else:
		set_state(ch, S.TRAVELING)
	return t


func _move(ch: Adventurer, t: float) -> float:
	var speed := ch.move_speed_tiles()
	while t > EPS and ch.path_index < ch.path.size():
		var next: Vector2i = ch.path[ch.path_index]
		if not world.grid.is_walkable(next):
			# Terrain changed under us: re-plan from the current tile.
			ch.move_progress = 0.0
			set_state(ch, S.PATHFINDING)
			return t
		var step_len := 1.41421356 if (next.x != ch.tile.x and next.y != ch.tile.y) else 1.0
		var full_time: float = step_len * world.grid.move_cost(next) / speed
		var need: float = (1.0 - ch.move_progress) * full_time
		ch.facing = (next - ch.tile).sign()
		if t >= need:
			t -= need
			ch.tile = next
			ch.move_progress = 0.0
			ch.path_index += 1
		else:
			ch.move_progress += t / full_time
			return 0.0
	if ch.path_index >= ch.path.size():
		_arrive(ch)
	return t


func _arrive(ch: Adventurer) -> void:
	ch.path.clear()
	ch.path_index = 0
	ch.move_progress = 0.0
	if ch.travel_purpose == TP.TO_STORAGE:
		ch.action_elapsed = 0.0
		ch.facing = (world.storage_tile - ch.tile).sign()
		set_state(ch, S.DEPOSITING, "Depositing")
		return
	var h := _handler(ch)
	if h == null:
		set_state(ch, S.CHECKING_CONDITIONS)
		return
	h.on_arrive(self, ch)


func _deposit(ch: Adventurer, t: float) -> float:
	var need := deposit_seconds - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	var asg := ch.assignment
	var h := _handler(ch)
	var keep: Dictionary = h.keep_on_deposit(self, ch, asg) if h and asg else {}
	var primary := h.primary_item(self, asg) if h and asg else ""
	var moved := {}
	for item_id in ch.inventory.items():
		var qty := ch.inventory.get_quantity(item_id) - int(keep.get(item_id, 0))
		if qty <= 0:
			continue
		var fit: int = world.storage.can_add(item_id, qty)
		if fit > 0:
			ch.inventory.remove(item_id, fit)
			world.storage.add(item_id, fit)
			moved[item_id] = fit
	var total := 0
	for item_id in moved:
		total += int(moved[item_id])
		ch.record("deposited", item_id, int(moved[item_id]))
		if item_id == primary and asg and h.counts_deposits():
			asg.deposited_primary += int(moved[item_id])
	if total > 0:
		ch.stats.trips = int(ch.stats.trips) + 1
		if asg:
			asg.trips_completed += 1
		world.emit_event("deposited", {"character_id": ch.id, "items": moved, "total": total})
	if asg and asg.auto_repair:
		var spent := EquipmentService.repair_all(world, ch)
		if spent > 0:
			ch.status_message = "Repaired equipment (%d gold)" % spent
	var leftover := 0
	for item_id in ch.inventory.items():
		leftover += ch.inventory.get_quantity(item_id) - int(keep.get(item_id, 0))
	if leftover > 0:
		# Storage is full. Never drop or duplicate items: wait and retry.
		ch.wait_remaining = waiting_retry_seconds * 5.0
		set_state(ch, S.WAITING, "Storage full")
		world.emit_event("interrupted", {"character_id": ch.id, "reason": "Storage full"})
		ch.stats.interruptions = int(ch.stats.interruptions) + 1
		return t
	if asg == null:
		complete(ch)
		return t
	if asg.is_quantity_reached() or (asg.continue_mode == Assignment.ContinueMode.SINGLE_TRIP and h.single_trip_done(self, ch, asg)):
		complete(ch)
		return t
	h.after_deposit(self, ch, asg)
	return t


func _restock(ch: Adventurer, t: float) -> float:
	var need := restock_seconds - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	var h := _handler(ch)
	if h == null or ch.assignment == null:
		set_state(ch, S.IDLE, "No assignment")
		return t
	h.restock(self, ch, ch.assignment)
	return t


func _rest(ch: Adventurer, t: float) -> float:
	var mh := ch.max_health()
	var rate := rest_regen_per_second * mh * ch.stat("healing")
	var missing := mh - ch.health
	if missing <= EPS:
		ch.health = mh
		_after_rest(ch)
		return t
	var need := missing / maxf(rate, 0.0001)
	if t < need:
		ch.health += rate * t
		return 0.0
	ch.health = mh
	_after_rest(ch)
	return t - need


func _after_rest(ch: Adventurer) -> void:
	if ch.assignment == null:
		set_state(ch, S.IDLE, "Rested")
		return
	var h := _handler(ch)
	if h and h.wants_restock(self, ch, ch.assignment) and WorldGrid.chebyshev(ch.tile, world.storage_tile) == 1:
		ch.action_elapsed = 0.0
		set_state(ch, S.RESTOCKING, "Restocking")
	else:
		set_state(ch, S.CHECKING_CONDITIONS, "Rested")


# ==========================================================================
# Helpers shared by handlers
# ==========================================================================

## Grants skill XP (with the character's multipliers) plus character XP,
## and fires level-up, milestone and trait hooks.
func grant_xp(ch: Adventurer, skill: String, base_xp: float) -> float:
	if base_xp <= 0.0 or skill.is_empty():
		return 0.0
	var xp := base_xp * ch.xp_multiplier(skill)
	var before := ch.skills.get_level(skill)
	var levels := ch.skills.add_xp(skill, xp)
	var char_before := ch.character_level()
	ch.character_xp = minf(ch.character_xp + xp * character_xp_share, registry.character_xp_table.max_xp)
	if world.wants_event("xp_gained"):
		world.emit_event("xp_gained", {"character_id": ch.id, "skill": skill, "xp": xp})
	if levels > 0:
		var after := ch.skills.get_level(skill)
		world.emit_event("level_up", {"character_id": ch.id, "skill": skill, "level": after})
		world.on_skill_level_up(ch, skill, before, after)
	var char_after := ch.character_level()
	if char_after > char_before:
		world.emit_event("character_level_up", {"character_id": ch.id, "level": char_after})
		world.on_character_level_up(ch)
	return xp


func begin_return(ch: Adventurer, message: String) -> void:
	release_targets(ch)
	ch.travel_purpose = TP.TO_STORAGE
	# PATHFINDING resolves "already next to storage" instantly with an empty path.
	set_state(ch, S.PATHFINDING, message)


## Sends the character to a tile (adjacent to it when `adjacent`).
func travel_to(ch: Adventurer, tile: Vector2i, adjacent: bool, message: String) -> void:
	ch.travel_purpose = TP.TO_TARGET
	ch.target_tile = tile
	ch.target_adjacent = adjacent
	set_state(ch, S.PATHFINDING, message)


func wait(ch: Adventurer, seconds: float, message: String) -> void:
	ch.wait_remaining = seconds
	set_state(ch, S.WAITING, message)


func complete(ch: Adventurer) -> void:
	release_targets(ch)
	ch.travel_purpose = TP.NONE
	set_state(ch, S.COMPLETED, "Assignment complete")
	world.emit_event("assignment_completed", {"character_id": ch.id})
	var asg := ch.assignment
	if asg and not asg.route.is_empty():
		_advance_route(ch, asg)


## Route builder: start the next step of the character's route.
func _advance_route(ch: Adventurer, asg: Assignment) -> void:
	var next := asg.route_index + 1
	if next >= asg.route.size():
		if not asg.route_loop:
			ch.status_message = "Route complete"
			world.emit_event("route_completed", {"character_id": ch.id})
			return
		next = 0
	var step := Assignment.from_dict(asg.route[next])
	step.route = asg.route
	step.route_index = next
	step.route_loop = asg.route_loop
	step.route_name = asg.route_name
	var err := assign(ch, step)
	if not err.is_empty():
		interrupt(ch, "Route step %d: %s" % [next + 1, err])
		return
	world.emit_event("route_step", {"character_id": ch.id, "step": next})


func interrupt(ch: Adventurer, reason: String) -> void:
	ch.stats.interruptions = int(ch.stats.interruptions) + 1
	world.emit_event("interrupted", {"character_id": ch.id, "reason": reason})
	release_targets(ch)
	ch.path.clear()
	ch.travel_purpose = TP.NONE
	set_state(ch, S.IDLE, reason)


func release_targets(ch: Adventurer) -> void:
	if not ch.target_node_id.is_empty():
		var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
		if node:
			node.release(ch.id)
		ch.target_node_id = ""
	if not ch.target_enemy_id.is_empty():
		var e: EnemyState = world.enemies.get(ch.target_enemy_id)
		if e:
			e.disengage(ch.id)
		ch.target_enemy_id = ""
	ch.target_station_id = ""


## Kept for Phase 1 callers and tests.
func _release_node(ch: Adventurer) -> void:
	release_targets(ch)


func set_state(ch: Adventurer, new_state: int, message := "") -> void:
	if not message.is_empty():
		ch.status_message = message
	if new_state == ch.state:
		return
	if not CharacterStates.can_transition(ch.state, new_state):
		push_error("ActivityEngine: illegal transition %s -> %s for %s" % [
			CharacterStates.name_of(ch.state), CharacterStates.name_of(new_state), ch.id])
		new_state = S.IDLE
	var old := ch.state
	ch.state = new_state
	var w = world
	if w.wants_event("state_changed"):
		w.emit_event("state_changed", {"character_id": ch.id, "from": old, "to": new_state})


func _set_state(ch: Adventurer, new_state: int, message := "") -> void:
	set_state(ch, new_state, message)
