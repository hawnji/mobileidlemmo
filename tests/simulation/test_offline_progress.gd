extends WbTestCase


func _working_world() -> SimulationWorld:
	var w := new_world(777)
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "mine_copper"))
	w.assign_activity("sylvara_moonleaf", make_assignment(w, "sylvara_moonleaf", "chop_oak"))
	w.assign_activity("tamsin_reed", make_assignment(w, "tamsin_reed", "fish_minnow"))
	return w


func test_one_hour_offline_produces_progress_and_report() -> void:
	var w := _working_world()
	var sim := LocalOfflineSimulator.new(registry())
	var r := sim.apply_offline_progress(w, 3600.0)
	assert_almost(r.simulated_seconds, 3600.0)
	assert_false(r.capped)
	assert_gt(r.total_xp(), 0.0)
	assert_gt(r.storage_gained.get("copper_ore", 0), 0)
	assert_gt(r.storage_gained.get("oak_log", 0), 0)
	assert_gt(r.storage_gained.get("raw_minnow", 0), 0)
	assert_gt(r.characters.brom_stonefist.xp.get("mining", 0.0), 0.0)
	assert_gt(r.characters.brom_stonefist.trips, 0)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_report_matches_actual_state_change() -> void:
	var w := _working_world()
	var before := w.storage.items()
	var r := LocalOfflineSimulator.new(registry()).apply_offline_progress(w, 1800.0)
	for item in r.storage_gained:
		assert_eq(w.storage.get_quantity(item) - int(before.get(item, 0)), r.storage_gained[item])


func test_offline_time_is_capped_at_eight_hours() -> void:
	var w := _working_world()
	var t0 := w.sim_time
	var r := LocalOfflineSimulator.new(registry()).apply_offline_progress(w, 3.0 * 24 * 3600)
	assert_true(r.capped)
	assert_almost(r.simulated_seconds, 8.0 * 3600.0)
	assert_almost(w.sim_time - t0, 8.0 * 3600.0, 0.01)


func test_negative_or_tiny_elapsed_does_nothing() -> void:
	var w := _working_world()
	var snap := w.held_totals()
	var sim := LocalOfflineSimulator.new(registry())
	var r1 := sim.apply_offline_progress(w, -5000.0)
	var r2 := sim.apply_offline_progress(w, 10.0)
	assert_almost(r1.simulated_seconds, 0.0)
	assert_almost(r2.simulated_seconds, 0.0)
	assert_eq(w.held_totals(), snap)


func test_coarse_offline_steps_match_fine_live_steps() -> void:
	# The engine carries leftover time between states, so 1s offline steps
	# should give (almost) the same result as 0.1s live ticks.
	var fine := _working_world()
	var coarse := _working_world()
	fine.advance(1800.0, 0.1)
	coarse.advance(1800.0, 1.0)
	for cid in fine.character_order:
		var a: Adventurer = fine.characters[cid]
		var b: Adventurer = coarse.characters[cid]
		var ga := 0
		var gb := 0
		for k in a.stats.gathered:
			ga += int(a.stats.gathered[k])
		for k in b.stats.gathered:
			gb += int(b.stats.gathered[k])
		assert_gt(ga, 0)
		assert_lte(absf(ga - gb), maxf(3.0, ga * 0.05), "%s fine=%d coarse=%d" % [cid, ga, gb])


func test_offline_progress_does_not_duplicate_on_repeated_calls() -> void:
	# Applying the same absence twice must not grant twice: the backend saves
	# a new timestamp after every application (covered in test_backend), and
	# here we check the simulator itself only grants for time it simulates.
	var w := _working_world()
	var sim := LocalOfflineSimulator.new(registry())
	sim.apply_offline_progress(w, 600.0)
	var after_one := w.held_totals()
	sim.apply_offline_progress(w, 0.0)
	assert_eq(w.held_totals(), after_one)


func test_eight_hour_simulation_is_fast_enough() -> void:
	var w := _working_world()
	var t0 := Time.get_ticks_msec()
	LocalOfflineSimulator.new(registry()).apply_offline_progress(w, 8.0 * 3600.0)
	var ms := Time.get_ticks_msec() - t0
	assert_lte(ms, 8000, "8h offline for 3 characters took %d ms" % ms)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_report_includes_combat_crafting_and_gold() -> void:
	var w := new_world()
	w.storage.add("oak_log", 50)
	w.record_source("oak_log", 50, "test")
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "hunt_meadows"))
	var a := make_assignment(w, "sylvara_moonleaf", "craft")
	a.recipe_id = "saw_oak"
	w.assign_activity("sylvara_moonleaf", a)
	var sim := LocalOfflineSimulator.new(registry())
	var r := sim.apply_offline_progress(w, 1800.0)
	assert_false(r.characters.brom_stonefist.kills.is_empty())
	assert_gt(int(r.characters.sylvara_moonleaf.crafted.get("oak_plank", 0)), 0)
	assert_gt(int(r.currency_gained.get("gold", 0)), 0)
	assert_eq(w.held_totals(), w.ledger_totals())
