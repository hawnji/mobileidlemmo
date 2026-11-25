extends WbTestCase
## Crafting: restock from storage, walk to the station, craft, deposit,
## repeat; wait when materials run out; respect requirements.

const S := CharacterStates.State


func _world_with(items: Dictionary) -> SimulationWorld:
	var w := new_world()
	for it in items:
		w.storage.add(it, int(items[it]))
		w.record_source(it, int(items[it]), "test")
	return w


func _craft(w: SimulationWorld, cid: String, activity: String, recipe: String) -> Assignment:
	var a := make_assignment(w, cid, activity)
	a.recipe_id = recipe
	return a


func test_smelting_turns_ore_into_bars() -> void:
	var w := _world_with({"copper_ore": 40, "tin_ore": 40})
	var ch: Adventurer = w.characters["brom_stonefist"]
	var xp := ch.skills.get_xp("smithing")
	assert_eq(w.assign_activity("brom_stonefist", _craft(w, "brom_stonefist", "smelt", "smelt_bronze")), "")
	w.advance(900.0, 0.1)
	assert_eq(w.storage.get_quantity("bronze_bar") + ch.inventory.get_quantity("bronze_bar"), 40, "every pair of ores became a bar")
	assert_eq(w.storage.get_quantity("copper_ore"), 0)
	assert_gt(ch.skills.get_xp("smithing"), xp)
	assert_false(ch.state == S.IDLE or ch.state == S.COMPLETED, "keeps waiting for more materials")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_waits_then_resumes_when_materials_arrive() -> void:
	var w := _world_with({})
	var ch: Adventurer = w.characters["sylvara_moonleaf"]
	assert_eq(w.assign_activity("sylvara_moonleaf", _craft(w, "sylvara_moonleaf", "craft", "saw_oak")), "")
	w.advance(30.0, 0.1)
	assert_eq(ch.status_message, "Waiting for materials")
	w.storage.add("oak_log", 10)
	w.record_source("oak_log", 10, "test")
	w.advance(200.0, 0.1)
	assert_eq(w.storage.get_quantity("oak_plank"), 10)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_until_quantity_stops_at_target() -> void:
	var w := _world_with({"raw_minnow": 50})
	var a := _craft(w, "tamsin_reed", "cook", "cook_minnow")
	a.continue_mode = Assignment.ContinueMode.UNTIL_QUANTITY
	a.target_quantity = 5
	assert_eq(w.assign_activity("tamsin_reed", a), "")
	w.advance(400.0, 0.1)
	var ch: Adventurer = w.characters["tamsin_reed"]
	assert_eq(ch.state, S.COMPLETED)
	assert_gte(w.storage.get_quantity("cooked_minnow"), 5)
	assert_lte(50 - w.storage.get_quantity("raw_minnow"), 9, "did not take materials for far more than the target")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_cooking_burns_less_with_level() -> void:
	var w := new_world()
	var h := CraftingHandler.new()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var r: Dictionary = w.registry.recipes["cook_minnow"]
	ch.skills.set_level("cooking", 1)
	var low := h.burn_chance(ch, r)
	ch.skills.set_level("cooking", 8)
	var mid := h.burn_chance(ch, r)
	ch.skills.set_level("cooking", 15)
	assert_gt(low, mid)
	assert_almost(h.burn_chance(ch, r), 0.0)


func test_burnt_food_is_conserved() -> void:
	var w := _world_with({"raw_minnow": 30})
	w.assign_activity("tamsin_reed", _craft(w, "tamsin_reed", "cook", "cook_minnow"))
	w.advance(600.0, 0.1)
	var cooked := w.storage.get_quantity("cooked_minnow")
	var burnt := w.storage.get_quantity("burnt_fish")
	assert_eq(cooked + burnt, 30)
	assert_gt(burnt, 0, "a level 1 cook burns some fish")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_requirements() -> void:
	var w := _world_with({"bronze_bar": 10})
	assert_ne(w.assign_activity("brom_stonefist", _craft(w, "brom_stonefist", "forge", "forge_bronze_pickaxe")), "", "needs a blacksmith")
	w.town.levels["blacksmith"] = 1
	w.town.recompute(w.registry)
	assert_eq(w.assign_activity("brom_stonefist", _craft(w, "brom_stonefist", "forge", "forge_bronze_pickaxe")), "")
	assert_ne(w.assign_activity("tamsin_reed", _craft(w, "tamsin_reed", "smelt", "smelt_iron")), "", "smithing 15 needed")
	assert_ne(w.assign_activity("tamsin_reed", _craft(w, "tamsin_reed", "smelt", "saw_oak")), "", "wrong station")
	assert_ne(w.assign_activity("tamsin_reed", _craft(w, "tamsin_reed", "smelt", "")), "", "no recipe")


func test_preserve_chance_saves_materials() -> void:
	var w := _world_with({"oak_log": 200})
	var ch: Adventurer = w.characters["sylvara_moonleaf"]
	ch.traits.append("efficient")  # 5% preserve
	ch.specializations.append("master_woodcutter")
	ch.invalidate_stats()
	w.assign_activity("sylvara_moonleaf", _craft(w, "sylvara_moonleaf", "craft", "saw_oak"))
	w.advance(1500.0, 0.5)
	var planks := w.storage.get_quantity("oak_plank") + ch.inventory.get_quantity("oak_plank")
	var logs_used := 200 - w.storage.get_quantity("oak_log") - ch.inventory.get_quantity("oak_log")
	assert_gt(planks, logs_used, "some crafts kept their inputs")
	assert_eq(w.held_totals(), w.ledger_totals())
