class_name ActivityEngine
extends RefCounted
## Drives every character's autonomous behaviour.
##
## tick() consumes a time budget by running state handlers until the budget
## is spent. Each handler returns the time it did NOT use, so a single large
## step (e.g. 1 s during offline simulation) produces the same outcome as many
## small ones (0.1 s while playing). That property is what lets online play and
## offline simulation share one implementation.
##
## Gathering loop:
##   ASSIGNED -> CHECKING_CONDITIONS -> PATHFINDING -> TRAVELING
##   -> PERFORMING_ACTIVITY -> CHECKING_CONDITIONS -> ... (bag full)
##   -> PATHFINDING -> RETURNING -> DEPOSITING -> CHECKING_CONDITIONS (resume)

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
var max_steps_per_tick := 32
var waiting_retry_seconds := 2.0
var unreachable_cooldown := 30.0
var max_path_failures := 5
var deposit_seconds := 1.0
var character_xp_share := 0.25


func _init(p_world, p_registry: DataRegistry) -> void:
	_world_ref = weakref(p_world)
	registry = p_registry
	max_steps_per_tick = int(registry.get_config("simulation.max_state_steps_per_tick", 32))
	waiting_retry_seconds = float(registry.get_config("simulation.waiting_retry_seconds", 2.0))
	unreachable_cooldown = float(registry.get_config("simulation.unreachable_node_cooldown_seconds", 30.0))
	max_path_failures = int(registry.get_config("simulation.max_consecutive_path_failures", 5))
	deposit_seconds = float(registry.get_config("simulation.deposit_seconds", 1.0))
	character_xp_share = float(registry.get_config("character_progression.character_xp_share", 0.25))


# ==========================================================================
# Public API
# ==========================================================================

## Validates and starts an assignment. Returns "" on success or a reason.
func assign(ch: Adventurer, asg: Assignment) -> String:
	var err := validate_assignment(ch, asg)
	if not err.is_empty():
		return err
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
	if ch.skills.get_level(skill) < req:
		return "%s needs %s level %d" % [ch.display_name, registry.skills.get(skill, {}).get("name", skill), req]
	if not asg.destination_id.is_empty() and not world.locations.has(asg.destination_id):
		return "Unknown destination '%s'" % asg.destination_id
	if world.nodes_of_type(String(act.get("node_type", "")), asg.destination_id).is_empty():
		return "No %s at that destination" % registry.node_types.get(act.node_type, {}).get("name", act.node_type)
	return ""


## Stops the current assignment. The character keeps its bag contents.
func cancel(ch: Adventurer, message := "Stopped") -> void:
	_release_node(ch)
	ch.path.clear()
	ch.path_index = 0
	ch.move_progress = 0.0
	ch.action_elapsed = 0.0
	ch.travel_purpose = TP.NONE
	if ch.state != S.IDLE:
		_set_state(ch, S.IDLE, message)
	ch.assignment = null


func tick(ch: Adventurer, dt: float) -> void:
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
			_set_state(ch, S.CHECKING_CONDITIONS)
			return t
		S.CHECKING_CONDITIONS:
			_check_conditions(ch)
			return t
		S.PATHFINDING:
			return _pathfind(ch, t)
		S.TRAVELING, S.RETURNING:
			return _move(ch, t)
		S.PERFORMING_ACTIVITY:
			return _perform(ch, t)
		S.DEPOSITING:
			return _deposit(ch, t)
		S.WAITING:
			ch.wait_remaining -= t
			if ch.wait_remaining > 0.0:
				return 0.0
			var left := -ch.wait_remaining
			ch.wait_remaining = 0.0
			_set_state(ch, S.CHECKING_CONDITIONS)
			return left
		_:
			# Reserved Phase 2 states: hand control back to the decision step.
			_set_state(ch, S.CHECKING_CONDITIONS)
			return t


## The decision point of the loop. Decides whether to keep working, find a
## new node, go home to deposit, or finish.
func _check_conditions(ch: Adventurer) -> void:
	var asg := ch.assignment
	if asg == null:
		_set_state(ch, S.IDLE, "No assignment")
		return
	# Full validation happens in assign(); per-cycle we only re-check what can
	# change during play (data reloads, level requirements).
	var act: Dictionary = registry.activities.get(asg.activity_id, {})
	if act.is_empty():
		_interrupt(ch, "Activity no longer exists")
		return
	if ch.skills.get_level(String(act.skill)) < int(act.get("required_level", 1)):
		_interrupt(ch, "Skill level too low for %s" % act.get("name", ""))
		return
	var ntype: Dictionary = registry.node_types[act.node_type]
	var yield_max := int(ntype.get("yield", {}).get("max", 1))

	# 1. Finished? Deposit what we carry first, then complete.
	if asg.is_quantity_reached():
		if ch.inventory.is_empty():
			_complete(ch)
		else:
			_begin_return(ch, "Target reached, returning")
		return

	# 2. Bag rule: return at the configured fill ratio, or when the next
	#    gather could not fit.
	var carrying_primary := ch.inventory.get_quantity(String(ntype.yield.item))
	var quantity_in_bag_reached := asg.continue_mode == Assignment.ContinueMode.UNTIL_QUANTITY \
		and asg.target_quantity > 0 and asg.deposited_primary + carrying_primary >= asg.target_quantity
	if ch.inventory.fill_ratio() >= asg.return_fill_ratio - EPS \
			or ch.inventory.free_units() < yield_max or quantity_in_bag_reached:
		_begin_return(ch, "Bag full, returning" if ch.inventory.is_full() else "Returning to deposit")
		return

	# 3. Keep working the current node if still ours and available.
	var current: ResourceNodeState = world.nodes.get(ch.target_node_id)
	if current and current.is_available_for(ch.id) and current.type_id == String(act.node_type):
		current.reserve(ch.id)
		if WorldGrid.chebyshev(ch.tile, current.tile) == 1:
			_start_action(ch)
		else:
			ch.travel_purpose = TP.TO_NODE
			_set_state(ch, S.PATHFINDING)
		return

	# 4. Pick a new node.
	_release_node(ch)
	var node: ResourceNodeState = world.find_best_node(ch, String(act.node_type), asg.destination_id, asg.preferred_node_ids)
	if node == null:
		ch.wait_remaining = waiting_retry_seconds
		_set_state(ch, S.WAITING, "Waiting for a free %s" % ntype.get("name", "node"))
		return
	node.reserve(ch.id)
	ch.target_node_id = node.id
	if WorldGrid.chebyshev(ch.tile, node.tile) == 1:
		_start_action(ch)
	else:
		ch.travel_purpose = TP.TO_NODE
		_set_state(ch, S.PATHFINDING, "Heading to %s" % ntype.get("name", "node"))


func _pathfind(ch: Adventurer, t: float) -> float:
	if not world.take_path_budget():
		return t  # no budget this tick; tick() will stop and retry next tick
	var goal: Vector2i
	if ch.travel_purpose == TP.TO_STORAGE:
		goal = world.storage_tile
	else:
		var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
		if node == null:
			_set_state(ch, S.CHECKING_CONDITIONS)
			return t
		goal = node.tile
	var result: PathResult = world.pathfinder.find_path_to_adjacent(ch.tile, goal)
	if not result.reachable:
		ch.path_failures += 1
		if ch.path_failures >= max_path_failures:
			_interrupt(ch, "Stuck: no route found")
			return t
		if ch.travel_purpose == TP.TO_NODE:
			ch.unreachable_until[ch.target_node_id] = world.sim_time + unreachable_cooldown
			_release_node(ch)
			_set_state(ch, S.CHECKING_CONDITIONS, "Route blocked, trying another spot")
		else:
			ch.wait_remaining = waiting_retry_seconds
			_set_state(ch, S.WAITING, "Cannot reach storage, retrying")
		return t
	ch.path_failures = 0
	ch.path = result.path
	ch.path_index = 0
	ch.move_progress = 0.0
	if ch.path.is_empty():
		_arrive(ch)
	elif ch.travel_purpose == TP.TO_STORAGE:
		_set_state(ch, S.RETURNING)
	else:
		_set_state(ch, S.TRAVELING)
	return t


func _move(ch: Adventurer, t: float) -> float:
	var speed := ch.move_speed_tiles()
	while t > EPS and ch.path_index < ch.path.size():
		var next: Vector2i = ch.path[ch.path_index]
		if not world.grid.is_walkable(next):
			# Terrain changed under us: re-plan from the current tile.
			ch.move_progress = 0.0
			_set_state(ch, S.PATHFINDING)
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
		_set_state(ch, S.DEPOSITING, "Depositing")
	else:
		var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
		if node and node.is_available_for(ch.id) and WorldGrid.chebyshev(ch.tile, node.tile) == 1:
			_start_action(ch)
		else:
			_set_state(ch, S.CHECKING_CONDITIONS)


func _start_action(ch: Adventurer) -> void:
	var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
	ch.action_elapsed = 0.0
	ch.travel_purpose = TP.NONE
	if node:
		ch.facing = (node.tile - ch.tile).sign()
	var act: Dictionary = registry.activities[ch.assignment.activity_id]
	_set_state(ch, S.PERFORMING_ACTIVITY, String(act.get("name", "Working")))


func _perform(ch: Adventurer, t: float) -> float:
	var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
	if node == null or node.reserved_by != ch.id or node.is_depleted():
		_set_state(ch, S.CHECKING_CONDITIONS, "Resource depleted")
		return t
	var ntype: Dictionary = registry.node_types[node.type_id]
	var skill := String(ntype.skill)
	var duration := float(ntype.gather_seconds) / ch.gather_speed_multiplier(skill, int(ntype.get("required_level", 1)))
	var need := duration - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	_complete_gather(ch, node, ntype)
	_set_state(ch, S.CHECKING_CONDITIONS)
	return t


## Resolves one successful gather. Order matters for exploit safety: the node
## charge is consumed first, and the item is only granted if the charge was
## real. Items that cannot fit are never created.
func _complete_gather(ch: Adventurer, node: ResourceNodeState, ntype: Dictionary) -> void:
	var y: Dictionary = ntype.get("yield", {})
	var item_id := String(y.get("item", ""))
	var qty: int = world.rng.randi_range(int(y.get("min", 1)), int(y.get("max", 1)))
	qty = mini(qty, ch.inventory.can_add(item_id, qty))
	if qty <= 0:
		return  # no room: nothing consumed, nothing granted
	if not node.consume():
		return
	if node.is_depleted():
		world.mark_depleted(node)
	var added := ch.inventory.add(item_id, qty)
	world.record_production(item_id, added)
	ch.record("gathered", item_id, added)
	ch.stats.actions = int(ch.stats.actions) + 1
	if node.is_depleted():
		world.emit_event("node_depleted", {"node_id": node.id})
	if world.wants_event("item_gathered"):
		world.emit_event("item_gathered", {"character_id": ch.id, "item_id": item_id, "qty": added, "node_id": node.id})

	var skill := String(ntype.skill)
	var xp := float(ntype.get("xp", 0.0)) * ch.xp_multiplier(skill)
	var levels := ch.skills.add_xp(skill, xp)
	var char_before := ch.character_level(registry)
	ch.character_xp = minf(ch.character_xp + xp * character_xp_share, registry.character_xp_table.max_xp)
	if world.wants_event("xp_gained"):
		world.emit_event("xp_gained", {"character_id": ch.id, "skill": skill, "xp": xp})
	if levels > 0:
		world.emit_event("level_up", {"character_id": ch.id, "skill": skill, "level": ch.skills.get_level(skill)})
	if ch.character_level(registry) > char_before:
		world.emit_event("character_level_up", {"character_id": ch.id, "level": ch.character_level(registry)})

	for rd in ntype.get("rare_drops", []):
		var chance := float(rd.get("chance", 0.0)) * ch.rare_drop_multiplier(skill)
		if world.rng.randf() < chance:
			var rid := String(rd.item)
			var got := ch.inventory.add(rid, 1)
			if got > 0:
				world.record_production(rid, got)
				ch.record("gathered", rid, got)
				world.emit_event("rare_drop", {"character_id": ch.id, "item_id": rid})


func _deposit(ch: Adventurer, t: float) -> float:
	var need := deposit_seconds - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	var asg := ch.assignment
	var primary := ""
	if asg:
		var act: Dictionary = registry.activities.get(asg.activity_id, {})
		primary = String(registry.node_types.get(act.get("node_type", ""), {}).get("yield", {}).get("item", ""))
	var moved: Dictionary = ch.inventory.transfer_all_to(world.storage)
	var total := 0
	for item_id in moved:
		total += int(moved[item_id])
		ch.record("deposited", item_id, int(moved[item_id]))
		if item_id == primary and asg:
			asg.deposited_primary += int(moved[item_id])
	if total > 0:
		ch.stats.trips = int(ch.stats.trips) + 1
		if asg:
			asg.trips_completed += 1
	world.emit_event("deposited", {"character_id": ch.id, "items": moved, "total": total})
	if not ch.inventory.is_empty():
		# Storage is full. Never drop or duplicate items: wait and retry.
		ch.wait_remaining = waiting_retry_seconds * 5.0
		_set_state(ch, S.WAITING, "Storage full")
		world.emit_event("interrupted", {"character_id": ch.id, "reason": "Storage full"})
		ch.stats.interruptions = int(ch.stats.interruptions) + 1
		return t
	if asg == null or asg.continue_mode == Assignment.ContinueMode.SINGLE_TRIP or asg.is_quantity_reached():
		_complete(ch)
		return t
	_set_state(ch, S.CHECKING_CONDITIONS, "Resuming %s" % registry.activities[asg.activity_id].get("name", ""))
	return t


# ==========================================================================
# Helpers
# ==========================================================================

func _begin_return(ch: Adventurer, message: String) -> void:
	_release_node(ch)
	ch.travel_purpose = TP.TO_STORAGE
	# PATHFINDING resolves "already next to storage" instantly with an empty path.
	_set_state(ch, S.PATHFINDING, message)


func _complete(ch: Adventurer) -> void:
	_release_node(ch)
	ch.travel_purpose = TP.NONE
	_set_state(ch, S.COMPLETED, "Assignment complete")
	world.emit_event("assignment_completed", {"character_id": ch.id})


func _interrupt(ch: Adventurer, reason: String) -> void:
	ch.stats.interruptions = int(ch.stats.interruptions) + 1
	world.emit_event("interrupted", {"character_id": ch.id, "reason": reason})
	_release_node(ch)
	ch.path.clear()
	ch.travel_purpose = TP.NONE
	_set_state(ch, S.IDLE, reason)


func _release_node(ch: Adventurer) -> void:
	if ch.target_node_id.is_empty():
		return
	var node: ResourceNodeState = world.nodes.get(ch.target_node_id)
	if node:
		node.release(ch.id)
	ch.target_node_id = ""


func _set_state(ch: Adventurer, new_state: int, message := "") -> void:
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
