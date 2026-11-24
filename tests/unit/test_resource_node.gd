extends WbTestCase


func _node() -> ResourceNodeState:
	return ResourceNodeState.create("rock", {"id": "copper_rock", "charges": 2, "respawn_seconds": 5.0}, Vector2i(1, 1))


func test_charges_deplete_and_respawn() -> void:
	var n := _node()
	assert_true(n.consume())
	assert_true(n.consume())
	assert_true(n.is_depleted())
	assert_false(n.consume(), "cannot gather from a depleted node")
	assert_false(n.tick(4.9))
	assert_true(n.tick(0.2))
	assert_eq(n.charges, 2)


func test_reservation_is_exclusive() -> void:
	var n := _node()
	assert_true(n.reserve("a"))
	assert_false(n.reserve("b"))
	assert_true(n.is_available_for("a"))
	n.release("b")
	assert_eq(n.reserved_by, "a", "only the holder can release")
	n.release("a")
	assert_true(n.reserve("b"))


func test_load_clamps_tampered_values() -> void:
	var n := _node()
	n.load_dict({"charges": 999, "respawn_remaining": -3})
	assert_eq(n.charges, 2)
	n.load_dict({"charges": 0, "respawn_remaining": 0})
	assert_gt(n.respawn_remaining, 0.0, "depleted node always has a respawn timer")
