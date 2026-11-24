extends WbTestCase


func test_round_trip() -> void:
	var w := new_world()
	var a := make_assignment(w, "brom_stonefist", "mine_copper")
	a.return_fill_ratio = 0.5
	a.continue_mode = Assignment.ContinueMode.UNTIL_QUANTITY
	a.target_quantity = 40
	a.preferred_node_ids.append("copper_rock_2")
	a.deposited_primary = 12
	var b := Assignment.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(b.activity_id, "mine_copper")
	assert_eq(b.destination_id, "copper_mine")
	assert_almost(b.return_fill_ratio, 0.5)
	assert_eq(b.continue_mode, Assignment.ContinueMode.UNTIL_QUANTITY)
	assert_eq(b.target_quantity, 40)
	assert_eq(b.deposited_primary, 12)
	assert_eq(Array(b.preferred_node_ids), ["copper_rock_2"])


func test_from_dict_sanitises_values() -> void:
	var b := Assignment.from_dict({"return_fill_ratio": 7.0, "target_quantity": -5, "continue_mode": "HACK"})
	assert_almost(b.return_fill_ratio, 1.0)
	assert_eq(b.target_quantity, 0)
	assert_eq(b.continue_mode, Assignment.ContinueMode.REPEAT)


func test_engine_rejects_insufficient_level() -> void:
	var w := new_world()
	w.registry.activities["test_hard"] = {"id": "test_hard", "name": "Hard", "skill": "mining", "required_level": 60,
		"node_type": "copper_rock", "default_destination": "copper_mine"}
	var a := make_assignment(w, "tamsin_reed", "test_hard")
	var err := w.assign_activity("tamsin_reed", a)
	w.registry.activities.erase("test_hard")
	assert_true(err.contains("level 60"), err)
	assert_eq(w.characters.tamsin_reed.state, CharacterStates.State.IDLE)


func test_engine_rejects_unknown_activity_and_destination() -> void:
	var w := new_world()
	var a := Assignment.new()
	a.activity_id = "nope"
	assert_ne(w.assign_activity("brom_stonefist", a), "")
	var b := make_assignment(w, "brom_stonefist", "mine_copper")
	b.destination_id = "oakwood_forest"
	assert_ne(w.assign_activity("brom_stonefist", b), "", "no copper rocks in the forest")
