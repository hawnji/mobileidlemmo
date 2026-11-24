extends WbTestCase

## The master spec lists illustrative targets. Level 10 (1,154) and level 99
## (13,034,431) match the RuneScape-style formula exactly; the spec's
## in-between values do not lie on any single exponential curve, so the
## formula's own values are used. See docs/BALANCE.md "XP curve".
const CURVE_TARGETS := {10: 1154, 20: 4470, 30: 13363, 40: 37224, 50: 101333, 60: 273742, 70: 737627, 80: 1986068, 90: 5346332, 92: 6517253, 99: 13034431}


func test_skill_curve_matches_runescape_style_targets() -> void:
	var t := registry().skill_xp_table
	for lvl in CURVE_TARGETS:
		assert_eq(t.xp_for_level(lvl), CURVE_TARGETS[lvl], "level %d" % lvl)


func test_level_one_needs_zero_and_level_two_needs_83() -> void:
	var t := registry().skill_xp_table
	assert_eq(t.xp_for_level(1), 0)
	assert_eq(t.xp_for_level(2), 83)


func test_thresholds_strictly_increase() -> void:
	var t := registry().skill_xp_table
	for lvl in range(2, t.max_level + 1):
		assert_gt(t.xp_for_level(lvl), t.xp_for_level(lvl - 1), "level %d" % lvl)


func test_level_for_xp_boundaries() -> void:
	var t := registry().skill_xp_table
	assert_eq(t.level_for_xp(0), 1)
	assert_eq(t.level_for_xp(-50), 1)
	assert_eq(t.level_for_xp(82), 1)
	assert_eq(t.level_for_xp(83), 2)
	assert_eq(t.level_for_xp(1153), 9)
	assert_eq(t.level_for_xp(1154), 10)
	assert_eq(t.level_for_xp(13034430), 98)
	assert_eq(t.level_for_xp(13034431), 99)
	assert_eq(t.level_for_xp(200000000), 99, "capped at max level")


func test_level_round_trip_for_every_level() -> void:
	var t := registry().skill_xp_table
	for lvl in range(1, t.max_level + 1):
		assert_eq(t.level_for_xp(t.xp_for_level(lvl)), lvl)


func test_progress_to_next() -> void:
	var t := registry().skill_xp_table
	assert_almost(t.progress_to_next(0), 0.0)
	assert_almost(t.progress_to_next(41.5), 0.5)
	assert_almost(t.progress_to_next(13034431), 1.0)
	assert_almost(t.xp_to_next_level(80), 3.0)


func test_character_curve_reaches_100() -> void:
	var t := registry().character_xp_table
	assert_eq(t.max_level, 100)
	assert_gt(t.xp_for_level(100), t.xp_for_level(99))
	assert_eq(t.level_for_xp(t.max_xp), 100)
