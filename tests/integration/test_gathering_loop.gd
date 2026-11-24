extends WbTestCase
## Phase 1 acceptance criteria: a character assigned to mining navigates to
## the mine, gathers ore, gains XP, returns when full, deposits and repeats
## with no further input.

const S := CharacterStates.State

var _states_seen := {}
var _deposits := 0


func _track(w: SimulationWorld, character_id: String) -> void:
	_states_seen.clear()
	_deposits = 0
	w.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev.get("character_id", "") != character_id:
			return
		if ev.type == "state_changed":
			_states_seen[ev.to] = int(_states_seen.get(ev.to, 0)) + 1
		elif ev.type == "deposited" and int(ev.total) > 0:
			_deposits += 1)


func _run_loop(character_id: String, activity_id: String, item_id: String, seconds: float) -> SimulationWorld:
	var w := new_world()
	_track(w, character_id)
	var ch: Adventurer = w.characters[character_id]
	var start_tile := ch.tile
	var xp_before := ch.skills.get_xp(String(w.registry.activities[activity_id].skill))
	assert_eq(w.assign_activity(character_id, make_assignment(w, character_id, activity_id)), "")
	var max_bag := 0
	var t := 0.0
	while t < seconds:
		w.step(0.1)
		t += 0.1
		max_bag = maxi(max_bag, ch.inventory.total_units())
		assert_true(w.grid.is_walkable(ch.tile), "character stood on a blocked tile %s" % ch.tile) if not w.grid.is_walkable(ch.tile) else null
	var skill := String(w.registry.activities[activity_id].skill)
	assert_ne(ch.tile, start_tile, "character moved")
	assert_gt(ch.skills.get_xp(skill), xp_before, "gained %s xp" % skill)
	assert_gte(_deposits, 2, "completed at least two full gather->deposit cycles")
	assert_gt(w.storage.get_quantity(item_id), 0, "storage received %s" % item_id)
	assert_lte(max_bag, ch.inventory.max_units, "bag never exceeded capacity")
	assert_eq(max_bag, ch.inventory.max_units, "bag reached capacity before returning")
	for st in [S.PATHFINDING, S.TRAVELING, S.PERFORMING_ACTIVITY, S.RETURNING, S.DEPOSITING, S.CHECKING_CONDITIONS]:
		assert_true(_states_seen.has(st), "visited %s" % CharacterStates.name_of(st))
	assert_gte(int(_states_seen.get(S.RETURNING, 0)), 2, "returned more than once (resumed after deposit)")
	assert_true(ch.is_busy(), "still working: loop continues indefinitely")
	return w


func test_mining_acceptance_loop() -> void:
	var w := _run_loop("brom_stonefist", "mine_copper", "copper_ore", 600.0)
	assert_gte(w.storage.get_quantity("copper_ore"), 56, "two full bags of copper deposited")


func test_woodcutting_loop() -> void:
	_run_loop("sylvara_moonleaf", "chop_oak", "oak_log", 600.0)


func test_fishing_loop() -> void:
	_run_loop("tamsin_reed", "fish_minnow", "raw_minnow", 900.0)


func test_return_threshold_respected() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.brom_stonefist
	var a := make_assignment(w, ch.id, "mine_copper")
	a.return_fill_ratio = 0.5
	w.assign_activity(ch.id, a)
	var max_bag := 0
	for i in 3000:
		w.step(0.1)
		max_bag = maxi(max_bag, ch.inventory.total_units())
	assert_eq(max_bag, 14, "returns at 50% of 28")
	assert_gt(w.storage.get_quantity("copper_ore"), 0)


func test_until_quantity_completes_and_stops() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.brom_stonefist
	var a := make_assignment(w, ch.id, "mine_copper")
	a.continue_mode = Assignment.ContinueMode.UNTIL_QUANTITY
	a.target_quantity = 10
	w.assign_activity(ch.id, a)
	w.advance(900.0, 0.1)
	assert_eq(ch.state, S.COMPLETED)
	assert_eq(w.storage.get_quantity("copper_ore"), 10, "stops exactly at the target")
	assert_true(ch.inventory.is_empty())
	var ore := w.storage.get_quantity("copper_ore")
	w.advance(300.0, 0.1)
	assert_eq(w.storage.get_quantity("copper_ore"), ore, "no more work after completion")


func test_single_trip_mode() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.sylvara_moonleaf
	var a := make_assignment(w, ch.id, "chop_oak")
	a.continue_mode = Assignment.ContinueMode.SINGLE_TRIP
	w.assign_activity(ch.id, a)
	w.advance(900.0, 0.1)
	assert_eq(ch.state, S.COMPLETED)
	assert_eq(w.storage.total_units(), ch.inventory.max_units, "exactly one full bag (logs + any bird nests)")
	assert_gt(w.storage.get_quantity("oak_log"), 0)


func test_cancel_keeps_items_and_frees_node() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.brom_stonefist
	w.assign_activity(ch.id, make_assignment(w, ch.id, "mine_copper"))
	while ch.inventory.total_units() < 3:
		w.step(0.1)
	var node_id := ch.target_node_id
	w.cancel_assignment(ch.id)
	assert_eq(ch.state, S.IDLE)
	assert_eq(ch.inventory.total_units(), 3, "cancelling does not delete the bag")
	assert_eq(w.nodes[node_id].reserved_by, "", "reservation released")
	w.advance(60.0, 0.1)
	assert_eq(ch.inventory.total_units(), 3, "idle characters do nothing")


func test_three_characters_work_simultaneously_without_sharing_nodes() -> void:
	var w := new_world()
	for pair in [["brom_stonefist", "mine_copper"], ["sylvara_moonleaf", "mine_copper"], ["tamsin_reed", "mine_copper"]]:
		assert_eq(w.assign_activity(pair[0], make_assignment(w, pair[0], pair[1])), "")
	for i in 4000:
		w.step(0.1)
		var working := {}
		for cid in w.character_order:
			var ch: Adventurer = w.characters[cid]
			if ch.state == S.PERFORMING_ACTIVITY:
				assert_false(working.has(ch.target_node_id), "two characters on one node") if working.has(ch.target_node_id) else null
				working[ch.target_node_id] = cid
	for cid in w.character_order:
		assert_gt(w.characters[cid].stats.deposited.get("copper_ore", 0), 0, "%s deposited ore" % cid)


func test_waits_when_all_nodes_busy_then_resumes() -> void:
	var w := new_world()
	# Deplete every tin rock and reserve none: the miner must wait, then work.
	for n in w.nodes_of_type("tin_rock"):
		while n.consume():
			pass
		w.mark_depleted(n)
	var ch: Adventurer = w.characters.brom_stonefist
	w.assign_activity(ch.id, make_assignment(w, ch.id, "mine_tin"))
	w.step(0.1)
	assert_eq(ch.state, S.WAITING)
	w.advance(30.0, 0.1)
	assert_gt(ch.stats.gathered.get("tin_ore", 0), 0, "resumed after respawn")


func test_recovers_when_path_gets_blocked() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.brom_stonefist
	w.assign_activity(ch.id, make_assignment(w, ch.id, "mine_copper"))
	while ch.state != S.TRAVELING:
		w.step(0.1)
	# Drop a boulder on the next few path tiles.
	var blocked: Array[Vector2i] = []
	for i in range(2, mini(4, ch.path.size())):
		blocked.append(ch.path[i])
		w.grid.set_object_blocked(ch.path[i], true)
	w.advance(400.0, 0.1)
	assert_gt(ch.stats.deposited.get("copper_ore", 0), 0, "re-routed and kept working")
	for c in blocked:
		w.grid.set_object_blocked(c, false)
