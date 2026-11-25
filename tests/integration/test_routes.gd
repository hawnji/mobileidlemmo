extends WbTestCase
## Route builder: multi-step routes run in order, loop, survive save/load,
## and templates persist.

const S := CharacterStates.State


func _step(w: SimulationWorld, cid: String, activity: String, qty: int, recipe := "") -> Assignment:
	var a := make_assignment(w, cid, activity)
	a.continue_mode = Assignment.ContinueMode.UNTIL_QUANTITY
	a.target_quantity = qty
	a.recipe_id = recipe
	return a


func test_route_runs_steps_in_order() -> void:
	var w := new_world()
	var steps := [_step(w, "brom_stonefist", "mine_copper", 10), _step(w, "brom_stonefist", "mine_tin", 10),
		_step(w, "brom_stonefist", "smelt", 10, "smelt_bronze")]
	assert_eq(w.start_route("brom_stonefist", steps, false, "Bronze run"), "")
	var seen := []
	w.event_emitted.connect(func(ev): if ev.type == "route_step": seen.append(ev.step))
	w.advance(1800.0, 0.2)
	assert_eq(seen, [1, 2])
	assert_gte(w.storage.get_quantity("bronze_bar"), 10)
	assert_eq(w.characters["brom_stonefist"].state, S.COMPLETED)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_looping_route_wraps() -> void:
	var w := new_world()
	var steps := [_step(w, "tamsin_reed", "fish_minnow", 5), _step(w, "tamsin_reed", "chop_oak", 5)]
	assert_eq(w.start_route("tamsin_reed", steps, true), "")
	var wraps := []
	w.event_emitted.connect(func(ev): if ev.type == "route_step" and ev.step == 0: wraps.append(1))
	w.advance(1500.0, 0.5)
	assert_gt(wraps.size(), 0, "returned to step 1")
	assert_true(w.characters["tamsin_reed"].is_busy())


func test_repeat_steps_rejected() -> void:
	var w := new_world()
	var a := make_assignment(w, "tamsin_reed", "fish_minnow")
	assert_ne(w.start_route("tamsin_reed", [a, _step(w, "tamsin_reed", "chop_oak", 5)]), "")


func test_invalid_step_interrupts() -> void:
	var w := new_world()
	var bad := _step(w, "tamsin_reed", "mine_iron", 5)  # needs mining 15
	assert_eq(w.start_route("tamsin_reed", [_step(w, "tamsin_reed", "mine_copper", 3), bad]), "")
	w.advance(600.0, 0.5)
	assert_eq(w.characters["tamsin_reed"].state, S.IDLE)
	assert_true(w.characters["tamsin_reed"].status_message.begins_with("Route step 2"))


func test_route_and_templates_survive_save() -> void:
	var w := new_world()
	var steps := [_step(w, "brom_stonefist", "mine_copper", 10), _step(w, "brom_stonefist", "mine_tin", 10)]
	w.start_route("brom_stonefist", steps, true, "Ores")
	assert_eq(w.save_route_template("Ores", steps, true), "")
	w.advance(300.0, 0.2)
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	var a: Assignment = w2.characters["brom_stonefist"].assignment
	assert_eq(a.route.size(), 2)
	assert_eq(a.route_index, w.characters["brom_stonefist"].assignment.route_index)
	assert_true(a.route_loop)
	assert_true(w2.route_templates.has("Ores"))
	w2.advance(900.0, 0.5)
	assert_true(w2.characters["brom_stonefist"].is_busy())
