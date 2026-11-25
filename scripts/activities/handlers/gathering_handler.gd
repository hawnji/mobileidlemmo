class_name GatheringHandler
extends ActivityHandler
## Mining, woodcutting, fishing, foraging, farming: work resource nodes until
## the bag rule says "go home", deposit, repeat.


func validate(e: ActivityEngine, _ch: Adventurer, asg: Assignment, act: Dictionary) -> String:
	var ntype := String(act.get("node_type", ""))
	if not e.registry.node_types.has(ntype):
		return "Unknown resource type"
	if e.world.nodes_of_type(ntype, asg.destination_id).is_empty():
		return "No %s at that destination" % e.registry.node_types[ntype].get("name", ntype)
	return ""


func primary_item(e: ActivityEngine, asg: Assignment) -> String:
	var act: Dictionary = e.registry.activities.get(asg.activity_id, {})
	return String(e.registry.node_types.get(act.get("node_type", ""), {}).get("yield", {}).get("item", ""))


func decide(e: ActivityEngine, ch: Adventurer, asg: Assignment, act: Dictionary) -> void:
	var world: SimulationWorld = e.world
	var ntype: Dictionary = e.registry.node_types[act.node_type]
	var yield_max := int(ntype.get("yield", {}).get("max", 1)) + (1 if ch.stat("yield_bonus_chance", String(ntype.skill)) > 0.0 else 0)

	# 1. Finished? Deposit what we carry first, then complete.
	if asg.is_quantity_reached():
		if ch.inventory.is_empty():
			e.complete(ch)
		else:
			e.begin_return(ch, "Target reached, returning")
		return

	# 2. Bag rule: return at the configured fill ratio, or when the next
	#    gather could not fit.
	var carrying_primary := ch.inventory.get_quantity(String(ntype.yield.item))
	var quantity_in_bag_reached := asg.continue_mode == Assignment.ContinueMode.UNTIL_QUANTITY \
		and asg.target_quantity > 0 and asg.deposited_primary + carrying_primary >= asg.target_quantity
	if ch.inventory.fill_ratio() >= asg.return_fill_ratio - EPS \
			or ch.inventory.free_units() < yield_max or quantity_in_bag_reached:
		e.begin_return(ch, "Bag full, returning" if ch.inventory.is_full() else "Returning to deposit")
		return

	# 3. Keep working the current node if still ours and available.
	var current: ResourceNodeState = world.nodes.get(ch.target_node_id)
	if current and current.is_available_for(ch.id) and current.type_id == String(act.node_type):
		current.reserve(ch.id)
		if WorldGrid.chebyshev(ch.tile, current.tile) == 1:
			_start(e, ch)
		else:
			ch.travel_purpose = TP.TO_NODE
			e.set_state(ch, S.PATHFINDING)
		return

	# 4. Pick a new node.
	e.release_targets(ch)
	var node: ResourceNodeState = world.find_best_node(ch, String(act.node_type), asg.destination_id, asg.preferred_node_ids)
	if node == null:
		e.wait(ch, e.waiting_retry_seconds, "Waiting for a free %s" % ntype.get("name", "node"))
		return
	node.reserve(ch.id)
	ch.target_node_id = node.id
	if WorldGrid.chebyshev(ch.tile, node.tile) == 1:
		_start(e, ch)
	else:
		ch.travel_purpose = TP.TO_NODE
		e.set_state(ch, S.PATHFINDING, "Heading to %s" % ntype.get("name", "node"))


func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	var node: ResourceNodeState = e.world.nodes.get(ch.target_node_id)
	if node and node.is_available_for(ch.id) and WorldGrid.chebyshev(ch.tile, node.tile) == 1:
		_start(e, ch)
	else:
		e.set_state(ch, S.CHECKING_CONDITIONS)


func _start(e: ActivityEngine, ch: Adventurer) -> void:
	var node: ResourceNodeState = e.world.nodes.get(ch.target_node_id)
	ch.action_elapsed = 0.0
	ch.travel_purpose = TP.NONE
	if node:
		ch.facing = (node.tile - ch.tile).sign()
	var act: Dictionary = e.registry.activities[ch.assignment.activity_id]
	e.set_state(ch, S.PERFORMING_ACTIVITY, String(act.get("name", "Working")))


func perform(e: ActivityEngine, ch: Adventurer, t: float) -> float:
	var node: ResourceNodeState = e.world.nodes.get(ch.target_node_id)
	if node == null or node.reserved_by != ch.id or node.is_depleted():
		e.set_state(ch, S.CHECKING_CONDITIONS, "Resource depleted")
		return t
	var ntype: Dictionary = e.registry.node_types[node.type_id]
	var skill := String(ntype.skill)
	var duration: float = float(ntype.gather_seconds) / ch.gather_speed_multiplier(skill, int(ntype.get("required_level", 1)), e.world.is_night()) \
		/ e.world.local_multiplier(node.tile, "gather_speed")
	var need: float = duration - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	complete_gather(e, ch, node, ntype)
	e.set_state(ch, S.CHECKING_CONDITIONS)
	return t


## Resolves one successful gather. Order matters for exploit safety: the node
## charge is consumed first, and the item is only granted if the charge was
## real. Items that cannot fit are never created.
func complete_gather(e: ActivityEngine, ch: Adventurer, node: ResourceNodeState, ntype: Dictionary) -> void:
	var world: SimulationWorld = e.world
	var skill := String(ntype.skill)
	var y: Dictionary = ntype.get("yield", {})
	var item_id := String(y.get("item", ""))
	var qty: int = world.rng.randi_range(int(y.get("min", 1)), int(y.get("max", 1)))
	var bonus := ch.stat("yield_bonus_chance", skill)
	if bonus > 0.0 and world.rng.randf() < bonus:
		qty += 1
	qty = int(floor(qty * world.encounters.yield_multiplier_at(node.tile)))
	qty = mini(qty, ch.inventory.can_add(item_id, qty))
	if qty <= 0:
		return  # no room: nothing consumed, nothing granted
	if not node.consume():
		return
	if node.is_depleted():
		world.mark_depleted(node)
	var added := ch.inventory.add(item_id, qty)
	world.record_source(item_id, added, "gathered")
	ch.record("gathered", item_id, added)
	ch.stats.actions = int(ch.stats.actions) + 1
	if node.is_depleted():
		world.emit_event("node_depleted", {"node_id": node.id})
	if world.wants_event("item_gathered"):
		world.emit_event("item_gathered", {"character_id": ch.id, "item_id": item_id, "qty": added, "node_id": node.id})
	var tool: Dictionary = ch.equipment.get("tool", {})
	if not tool.is_empty() and String(e.registry.items.get(tool.item_id, {}).get("tool_skill", "")) == skill:
		EquipmentService.wear(world, ch, "tool", int(e.registry.get_config("equipment.durability_per_gather", 1)))
	e.grant_xp(ch, skill, float(ntype.get("xp", 0.0)) * world.local_multiplier(node.tile, "xp"))
	for rd in ntype.get("rare_drops", []):
		var chance := float(rd.get("chance", 0.0)) * ch.rare_drop_multiplier(skill)
		if world.rng.randf() < chance:
			var rid := String(rd.item)
			var got := ch.inventory.add(rid, 1)
			if got > 0:
				world.record_source(rid, got, "rare_drop")
				ch.record("gathered", rid, got)
				world.emit_event("rare_drop", {"character_id": ch.id, "item_id": rid})
