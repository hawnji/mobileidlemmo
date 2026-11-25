extends WbTestCase
## Town: construction projects, building effects, gating, worker capacity,
## tavern tokens, NPC selling.

const S := CharacterStates.State


func _world_with(items: Dictionary, gold := 0) -> SimulationWorld:
	var w := new_world()
	for it in items:
		w.storage.add(it, int(items[it]))
		w.record_source(it, int(items[it]), "test")
	if gold > 0:
		w.wallet.earn("gold", gold, "test")
	return w


func test_start_construction_charges_cost() -> void:
	var w := _world_with({"oak_plank": 20})
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.start_construction("bank"), "")
	assert_eq(w.wallet.get_balance("gold"), gold - 100)
	assert_eq(w.storage.get_quantity("oak_plank"), 10)
	assert_eq(w.town.project.building, "bank")
	assert_ne(w.start_construction("tavern"), "", "one project at a time")
	assert_eq(w.held_totals(), w.ledger_totals(), "building materials are a sink")


func test_cannot_start_without_materials_and_nothing_is_charged() -> void:
	var w := _world_with({"oak_plank": 5})
	var gold := w.wallet.get_balance("gold")
	assert_ne(w.start_construction("bank"), "")
	assert_eq(w.wallet.get_balance("gold"), gold)
	assert_eq(w.storage.get_quantity("oak_plank"), 5)
	assert_true(w.town.project.is_empty())


func test_town_hall_gates_other_buildings() -> void:
	var w := _world_with({"oak_plank": 500, "bronze_bar": 500}, 100000)
	w.town.levels["bank"] = 2
	w.town.recompute(w.registry)
	assert_ne(w.town.can_start(w.registry, "bank"), "", "bank 3 needs town hall 2")
	w.town.levels["town_hall"] = 2
	assert_eq(w.town.can_start(w.registry, "bank"), "")


func test_construct_activity_completes_project_and_applies_effects() -> void:
	var w := _world_with({"oak_plank": 10})
	var slots := w.storage.max_distinct
	assert_ne(w.assign_activity("tamsin_reed", make_assignment(w, "tamsin_reed", "construct")), "", "no project yet")
	assert_eq(w.start_construction("bank"), "")
	assert_eq(w.assign_activity("tamsin_reed", make_assignment(w, "tamsin_reed", "construct")), "")
	assert_eq(w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "construct")), "")
	var done := {"v": false}
	w.event_emitted.connect(func(ev): if ev.type == "building_completed": done.v = true)
	w.advance(200.0, 0.1)
	assert_true(done.v)
	assert_eq(w.town.level_of("bank"), 1)
	assert_eq(w.storage.max_distinct, slots + 16)
	assert_gt(w.characters["tamsin_reed"].skills.get_xp("construction"), 0.0)
	assert_eq(w.characters["tamsin_reed"].state, S.WAITING, "waits for the next project")


func test_worker_capacity_limits_assignments() -> void:
	var w := new_world()
	w.wallet.earn("recruitment_tokens", 100, "t")
	while w.character_order.size() < 6:
		w.recruit("standard", 1)
	var ok := 0
	for cid in w.character_order:
		if w.assign_activity(cid, make_assignment(w, cid, "fish_minnow")).is_empty():
			ok += 1
	assert_eq(ok, 4, "base capacity is 4")
	w.town.levels["housing"] = 1
	w.town.recompute(w.registry)
	assert_eq(w.worker_capacity(), 6)
	var last := w.character_order[w.character_order.size() - 1]
	assert_eq(w.assign_activity(last, make_assignment(w, last, "fish_minnow")), "")
	assert_eq(w.assign_activity(w.character_order[0], make_assignment(w, w.character_order[0], "chop_oak")), "", "reassigning a worker does not need a new slot")


func test_tavern_generates_tokens() -> void:
	var w := new_world()
	var before := w.wallet.get_balance("recruitment_tokens")
	w.town.levels["tavern"] = 1  # 0.125 tokens per hour
	w.town.recompute(w.registry)
	w.advance(8.0 * 3600.0, 10.0)
	assert_eq(w.wallet.get_balance("recruitment_tokens"), before + 1)


func test_sell_items_for_gold_respects_lock() -> void:
	var w := _world_with({"copper_ore": 10, "river_pearl": 1})
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.sell_item("copper_ore", 4), "")
	assert_eq(w.wallet.get_balance("gold"), gold + 12)
	assert_eq(w.storage.get_quantity("copper_ore"), 6)
	w.set_item_locked("river_pearl", true)
	assert_ne(w.sell_item("river_pearl", 1), "")
	assert_ne(w.sell_item("copper_ore", 7), "", "cannot sell more than held")
	assert_eq(w.held_totals(), w.ledger_totals(), "sold items are a sink")
	w.town.levels["marketplace"] = 1
	w.town.recompute(w.registry)
	assert_eq(w.sell_price("river_pearl"), 63, "marketplace +5%")


func test_town_survives_save() -> void:
	var w := _world_with({"oak_plank": 10})
	w.start_construction("bank")
	w.town.add_work(20.0)
	w.set_item_locked("oak_plank", true)
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.town.project.building, "bank")
	assert_almost(float(w2.town.project.work_done), 20.0)
	assert_true(w2.locked_items.has("oak_plank"))
	assert_eq(w2.town.level_of("town_hall"), 1)
