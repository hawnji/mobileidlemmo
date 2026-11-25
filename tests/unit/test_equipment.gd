extends WbTestCase
## Equipment: equip/unequip, requirements, stats, wear, breaking, repair,
## upgrade, and that none of it creates or destroys items.


func _world_with(items: Dictionary) -> SimulationWorld:
	var w := new_world()
	for it in items:
		w.storage.add(it, int(items[it]))
		w.record_source(it, int(items[it]), "test")
	return w


func test_equip_moves_item_and_applies_stats() -> void:
	var w := _world_with({"bronze_pickaxe": 1})
	var ch: Adventurer = w.characters["brom_stonefist"]
	var before := ch.stat("gather_speed", "mining")
	assert_eq(w.equip("brom_stonefist", "bronze_pickaxe"), "")
	assert_eq(w.storage.get_quantity("bronze_pickaxe"), 0)
	assert_eq(ch.equipped_item_id("tool"), "bronze_pickaxe")
	assert_almost(ch.stat("gather_speed", "mining"), before * 1.1)
	assert_eq(w.held_totals(), w.ledger_totals(), "equipping does not change totals")


func test_requirements_enforced() -> void:
	var w := _world_with({"iron_pickaxe": 1})
	assert_ne(w.equip("tamsin_reed", "iron_pickaxe"), "", "needs mining 15")
	assert_eq(w.storage.get_quantity("iron_pickaxe"), 1)
	assert_eq(w.equip("brom_stonefist", "iron_pickaxe"), "", "Brom starts at mining 15")


func test_unequip_pristine_returns_to_storage() -> void:
	var w := _world_with({"bronze_helm": 1})
	w.equip("tamsin_reed", "bronze_helm")
	assert_eq(w.unequip("tamsin_reed", "head"), "")
	assert_eq(w.storage.get_quantity("bronze_helm"), 1)
	assert_true(w.armory.is_empty())


func test_worn_item_goes_to_armory_and_can_be_re_equipped() -> void:
	var w := _world_with({"bronze_helm": 1})
	var ch: Adventurer = w.characters["tamsin_reed"]
	w.equip("tamsin_reed", "bronze_helm")
	EquipmentService.wear(w, ch, "head", 10)
	w.unequip("tamsin_reed", "head")
	assert_eq(w.storage.get_quantity("bronze_helm"), 0)
	assert_eq(w.armory.size(), 1)
	assert_eq(int(w.armory[0].durability), 390)
	assert_eq(w.held_totals(), w.ledger_totals())
	assert_eq(w.equip("brom_stonefist", "", int(w.armory[0].uid)), "")
	assert_eq(int(w.characters["brom_stonefist"].equipment.head.durability), 390, "identity kept")
	assert_true(w.armory.is_empty())


func test_swapping_returns_previous_item() -> void:
	var w := _world_with({"bronze_sword": 1, "oak_shortbow": 1})
	w.equip("tamsin_reed", "bronze_sword")
	w.equip("tamsin_reed", "oak_shortbow")
	assert_eq(w.storage.get_quantity("bronze_sword"), 1)
	assert_eq(w.characters["tamsin_reed"].combat_style(), "ranged")


func test_two_accessory_slots() -> void:
	var w := _world_with({"quartz_ring": 1, "leather_backpack": 1})
	var ch: Adventurer = w.characters["tamsin_reed"]
	var cap := ch.inventory.max_units
	w.equip("tamsin_reed", "quartz_ring")
	w.equip("tamsin_reed", "leather_backpack")
	assert_eq(ch.equipped_item_id("accessory_1"), "quartz_ring")
	assert_eq(ch.equipped_item_id("accessory_2"), "leather_backpack")
	assert_eq(ch.inventory.max_units, cap + 4, "backpack raises carry capacity")


func test_broken_items_give_no_stats_and_repair_restores() -> void:
	var w := _world_with({"bronze_pickaxe": 1})
	var ch: Adventurer = w.characters["brom_stonefist"]
	var base := ch.stat("gather_speed", "mining")
	w.equip("brom_stonefist", "bronze_pickaxe")
	EquipmentService.wear(w, ch, "tool", 1000)
	assert_eq(int(ch.equipment.tool.durability), 0)
	assert_almost(ch.stat("gather_speed", "mining"), base, 0.0001, "broken tool gives nothing")
	var cost := EquipmentService.repair_cost(w, ch.equipment.tool)
	assert_eq(cost, 75, "300 points x tier 1 x 0.25 gold")
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.repair("brom_stonefist", "tool"), "")
	assert_eq(w.wallet.get_balance("gold"), gold - cost)
	assert_almost(ch.stat("gather_speed", "mining"), base * 1.1)


func test_repair_fails_without_gold() -> void:
	var w := _world_with({"bronze_pickaxe": 1})
	var ch: Adventurer = w.characters["brom_stonefist"]
	w.equip("brom_stonefist", "bronze_pickaxe")
	EquipmentService.wear(w, ch, "tool", 300)
	w.wallet.spend("gold", w.wallet.get_balance("gold"), "test")
	assert_ne(w.repair("brom_stonefist", "tool"), "")
	assert_eq(int(ch.equipment.tool.durability), 0)


func test_upgrade_needs_blacksmith_and_consumes_bars() -> void:
	var w := _world_with({"bronze_sword": 1, "bronze_bar": 10})
	var ch: Adventurer = w.characters["brom_stonefist"]
	w.equip("brom_stonefist", "bronze_sword")
	assert_ne(w.upgrade_equipment("brom_stonefist", "weapon"), "", "no blacksmith yet")
	w.town.levels["blacksmith"] = 1
	w.town.recompute(w.registry)
	var power := ch.stat("weapon_power")
	assert_eq(w.upgrade_equipment("brom_stonefist", "weapon"), "")
	assert_eq(int(ch.equipment.weapon.upgrade), 1)
	assert_eq(w.storage.get_quantity("bronze_bar"), 8)
	assert_almost(ch.stat("weapon_power"), power * 1.1)
	assert_ne(w.upgrade_equipment("brom_stonefist", "weapon"), "", "blacksmith 1 caps at +1")
	assert_eq(w.held_totals(), w.ledger_totals(), "bars recorded as a sink")


func test_gathering_wears_the_tool() -> void:
	var w := _world_with({"bronze_pickaxe": 1})
	var ch: Adventurer = w.characters["brom_stonefist"]
	w.equip("brom_stonefist", "bronze_pickaxe")
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "mine_copper"))
	w.advance(120.0, 0.1)
	assert_lte(int(ch.equipment.tool.durability), 299)
	assert_eq(300 - int(ch.equipment.tool.durability), int(ch.stats.gathered.get("copper_ore", 0)), "one point per gather")


func test_equipment_survives_save() -> void:
	var w := _world_with({"bronze_pickaxe": 1, "bronze_helm": 1})
	w.equip("brom_stonefist", "bronze_pickaxe")
	w.equip("tamsin_reed", "bronze_helm")
	EquipmentService.wear(w, w.characters["tamsin_reed"], "head", 5)
	w.unequip("tamsin_reed", "head")
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.characters["brom_stonefist"].equipped_item_id("tool"), "bronze_pickaxe")
	assert_eq(w2.armory.size(), 1)
	assert_eq(w2.held_totals(), w2.ledger_totals())
	var uid := w2.next_item_uid()
	assert_gt(uid, int(w2.armory[0].uid), "uids keep increasing after load")
