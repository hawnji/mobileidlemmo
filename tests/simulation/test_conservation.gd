extends WbTestCase
## Exploit-safety: every item that exists must have been produced by exactly
## one consumed node charge, and save/load must not duplicate anything.


func _assign_all(w: SimulationWorld) -> void:
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "mine_copper"))
	w.assign_activity("sylvara_moonleaf", make_assignment(w, "sylvara_moonleaf", "chop_oak"))
	w.assign_activity("tamsin_reed", make_assignment(w, "tamsin_reed", "fish_minnow"))


func test_held_items_equal_production_ledger() -> void:
	var w := new_world()
	_assign_all(w)
	for i in 20:
		w.advance(60.0, 0.1)
		assert_eq(w.held_totals(), w.ledger_totals(), "after %d min" % (i + 1))


func test_each_gather_consumes_one_charge() -> void:
	var w := new_world()
	var consumed := {"n": 0}
	var gathered := {"n": 0}
	w.event_emitted.connect(func(ev: Dictionary) -> void:
		if ev.type == "item_gathered":
			gathered.n += int(ev.qty)
			consumed.n += 1)
	_assign_all(w)
	w.advance(1200.0, 0.1)
	assert_gt(gathered.n, 0)
	assert_eq(gathered.n, consumed.n, "1 item per charge with current data")


func test_save_load_round_trip_preserves_everything() -> void:
	var w := new_world()
	_assign_all(w)
	w.advance(437.3, 0.1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var w2 := SimulationWorld.from_dict(registry(), data)
	assert_eq(w2.held_totals(), w.held_totals())
	assert_eq(w2.ledger_totals(), w.ledger_totals())
	assert_almost(w2.sim_time, w.sim_time)
	for cid in w.character_order:
		var a: Adventurer = w.characters[cid]
		var b: Adventurer = w2.characters[cid]
		assert_eq(b.tile, a.tile)
		assert_eq(b.state, a.state, cid)
		assert_eq(b.target_node_id, a.target_node_id)
		assert_almost(b.skills.get_xp("mining"), a.skills.get_xp("mining"))
	# Both worlds continue identically (deterministic RNG + state restored).
	w.advance(300.0, 0.1)
	w2.advance(300.0, 0.1)
	assert_eq(w2.held_totals(), w.held_totals(), "deterministic after reload")


func test_repeated_save_load_does_not_duplicate() -> void:
	var w := new_world()
	_assign_all(w)
	w.advance(300.0, 0.1)
	var totals := w.held_totals()
	var cur := w
	for i in 5:
		cur = SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(cur.to_dict())))
	assert_eq(cur.held_totals(), totals)


func test_tampered_save_reservations_are_cleared() -> void:
	var w := new_world()
	var d := w.to_dict()
	d.nodes = {"copper_rock_1": {"id": "copper_rock_1", "charges": 4, "reserved_by": "ghost"}}
	var w2 := SimulationWorld.from_dict(registry(), d)
	assert_eq(w2.nodes.copper_rock_1.reserved_by, "", "reservation without an owner is dropped")


## Every Phase 2 source and sink at once: gathering, crafting, combat loot,
## eating, selling, construction costs, equipment. Totals must always match.
func test_ledger_holds_across_all_activities() -> void:
	var w := new_world(2024)
	var start := {"copper_ore": 30, "tin_ore": 30, "cooked_minnow": 20, "oak_plank": 20, "bronze_sword": 1}
	for it in start:
		var q: int = start[it]
		w.storage.add(it, q)
		w.record_source(it, q, "test")
	assert_eq(w.equip("tamsin_reed", "bronze_sword"), "")
	var a := make_assignment(w, "brom_stonefist", "smelt")
	a.recipe_id = "smelt_bronze"
	assert_eq(w.assign_activity("brom_stonefist", a), "")
	var c := make_assignment(w, "tamsin_reed", "hunt_meadows")
	c.heal_threshold = 0.8
	assert_eq(w.assign_activity("tamsin_reed", c), "")
	assert_eq(w.assign_activity("sylvara_moonleaf", make_assignment(w, "sylvara_moonleaf", "chop_oak")), "")
	assert_eq(w.start_construction("bank"), "")
	for i in 10:
		w.advance(60.0, 0.5)
		if i == 5:
			w.sell_item("copper_ore", mini(3, w.storage.get_quantity("copper_ore")))
		assert_eq(w.held_totals(), w.ledger_totals(), "after %d min" % (i + 1))
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.held_totals(), w2.ledger_totals(), "after save/load")
