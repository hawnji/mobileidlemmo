extends WbTestCase
## Save/load through the local backend, including offline time measured from
## the save timestamp. Uses a fake clock and a temp save file.

const SAVE_PATH := "user://test_backend_save.json"


func after_each() -> void:
	SaveService.new(SAVE_PATH).delete()


func test_save_then_load_applies_offline_time_once() -> void:
	var clock := TimeSource.Fixed.new(1_000_000.0)
	var backend := LocalGameBackend.new(registry(), SAVE_PATH, clock)
	var w := new_world(99)
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "mine_copper"))
	w.advance(30.0, 0.1)
	assert_true(backend.save_world(w))

	clock.advance(2 * 3600.0)
	var loaded := backend.load_world(registry())
	assert_false(loaded.is_empty())
	var w2: SimulationWorld = loaded.world
	var elapsed := backend.now_unix() - float(loaded.saved_at_unix)
	assert_almost(elapsed, 7200.0)
	var report := backend.get_offline_provider().apply_offline_progress(w2, elapsed)
	assert_gt(report.storage_gained.get("copper_ore", 0), 0)
	backend.save_world(w2)

	# Re-opening immediately must not grant the same two hours again.
	var again := backend.load_world(registry())
	var elapsed2 := backend.now_unix() - float(again.saved_at_unix)
	assert_almost(elapsed2, 0.0)
	var r2 := backend.get_offline_provider().apply_offline_progress(again.world, elapsed2)
	assert_almost(r2.simulated_seconds, 0.0)
	assert_eq(again.world.held_totals(), w2.held_totals())


func test_corrupt_save_starts_fresh() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var backend := LocalGameBackend.new(registry(), SAVE_PATH, TimeSource.Fixed.new(0.0))
	assert_true(backend.load_world(registry()).is_empty())


func test_clock_rollback_grants_nothing() -> void:
	var clock := TimeSource.Fixed.new(5000.0)
	var backend := LocalGameBackend.new(registry(), SAVE_PATH, clock)
	var w := new_world()
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "mine_copper"))
	backend.save_world(w)
	clock.value = 1000.0
	var loaded := backend.load_world(registry())
	var r := backend.get_offline_provider().apply_offline_progress(loaded.world, clock.value - float(loaded.saved_at_unix))
	assert_almost(r.simulated_seconds, 0.0)
