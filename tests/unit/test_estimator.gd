extends WbTestCase


func test_estimates_are_positive_and_sane() -> void:
	var w := new_world()
	for pair in [["brom_stonefist", "mine_copper"], ["sylvara_moonleaf", "chop_oak"], ["tamsin_reed", "fish_minnow"]]:
		var e := ActivityEstimator.estimate(w, w.characters[pair[0]], pair[1])
		assert_true(e.reachable, pair[1])
		assert_gt(e.xp_per_hour, 1000.0, pair[1])
		assert_lte(e.items_per_hour, 3600.0 / e.gather_seconds + 0.01, "cannot beat pure gathering speed")


func test_estimate_close_to_simulation() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters.brom_stonefist
	var e := ActivityEstimator.estimate(w, ch, "mine_copper")
	w.assign_activity(ch.id, make_assignment(w, ch.id, "mine_copper"))
	w.advance(3600.0, 1.0)
	var actual := float(ch.stats.gathered.get("copper_ore", 0))
	assert_lte(absf(actual - e.items_per_hour) / e.items_per_hour, 0.25, "estimate %.0f vs actual %.0f" % [e.items_per_hour, actual])


func test_specialist_beats_generalist() -> void:
	var w := new_world()
	var brom := ActivityEstimator.estimate(w, w.characters.brom_stonefist, "mine_copper")
	var tamsin := ActivityEstimator.estimate(w, w.characters.tamsin_reed, "mine_copper")
	assert_gt(brom.xp_per_hour, tamsin.xp_per_hour)
