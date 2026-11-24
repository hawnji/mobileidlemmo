extends WbTestCase


func test_add_respects_unit_capacity() -> void:
	var inv := Inventory.new(10)
	assert_eq(inv.add("copper_ore", 6), 6)
	assert_eq(inv.add("tin_ore", 6), 4, "partial add")
	assert_eq(inv.total_units(), 10)
	assert_true(inv.is_full())
	assert_eq(inv.add("copper_ore", 1), 0)
	assert_almost(inv.fill_ratio(), 1.0)


func test_invalid_quantities_rejected() -> void:
	var inv := Inventory.new(10)
	assert_eq(inv.add("copper_ore", 0), 0)
	assert_eq(inv.add("copper_ore", -5), 0)
	assert_eq(inv.add("", 3), 0)
	assert_eq(inv.total_units(), 0)
	assert_false(inv.remove("copper_ore", -1))


func test_remove_is_all_or_nothing() -> void:
	var inv := Inventory.new()
	inv.add("oak_log", 5)
	assert_false(inv.remove("oak_log", 6))
	assert_eq(inv.get_quantity("oak_log"), 5)
	assert_true(inv.remove("oak_log", 5))
	assert_eq(inv.get_quantity("oak_log"), 0)
	assert_eq(inv.distinct_count(), 0)
	assert_true(inv.is_empty())


func test_distinct_slot_limit() -> void:
	var inv := Inventory.new(Inventory.UNLIMITED, 2)
	assert_eq(inv.add("a", 100), 100)
	assert_eq(inv.add("b", 100), 100)
	assert_eq(inv.add("c", 1), 0, "no free slot for a third item type")
	assert_eq(inv.add("a", 1000), 1000, "existing stacks still grow")


func test_transfer_moves_only_what_fits_and_conserves_items() -> void:
	var bag := Inventory.new(28)
	bag.add("copper_ore", 20)
	bag.add("uncut_quartz", 1)
	var storage := Inventory.new(Inventory.UNLIMITED, 1)
	var moved := bag.transfer_all_to(storage)
	assert_eq(moved, {"copper_ore": 20})
	assert_eq(storage.get_quantity("copper_ore"), 20)
	assert_eq(bag.get_quantity("uncut_quartz"), 1, "item that did not fit stays in the bag")
	assert_eq(bag.total_units() + storage.total_units(), 21)


func test_serialisation_round_trip() -> void:
	var inv := Inventory.new(28)
	inv.add("copper_ore", 3)
	inv.add("oak_log", 2)
	var inv2 := Inventory.new()
	inv2.load_dict(inv.to_dict())
	assert_eq(inv2.items(), inv.items())
	assert_eq(inv2.total_units(), 5)
	assert_eq(inv2.max_units, 28)


func test_unlimited_storage_never_full() -> void:
	var inv := Inventory.new()
	inv.add("copper_ore", 1000000)
	assert_false(inv.is_full())
	assert_almost(inv.fill_ratio(), 0.0)
