extends WbTestCase
## StatBlock: how effects from every source combine.


func _sb() -> StatBlock:
	return registry().new_stat_block()


func test_multiplicative_families_multiply() -> void:
	var sb := _sb()
	sb.apply({"gather_speed.mining": 1.25})
	sb.apply({"gather_speed.all": 1.08})
	sb.apply({"gather_speed.mining": 1.1})
	assert_almost(sb.get_stat("gather_speed", "mining"), 1.25 * 1.08 * 1.1)
	assert_almost(sb.get_stat("gather_speed", "fishing"), 1.08)
	assert_almost(sb.get_stat("gather_speed"), 1.08)


func test_additive_families_add() -> void:
	var sb := _sb()
	sb.apply({"carry_capacity": 6})
	sb.apply({"carry_capacity": 4})
	sb.apply({"preserve_chance.all": 0.05, "preserve_chance.smithing": 0.1})
	assert_almost(sb.get_stat("carry_capacity"), 10.0)
	assert_almost(sb.get_stat("preserve_chance", "smithing"), 0.15)
	assert_almost(sb.get_stat("preserve_chance", "cooking"), 0.05)


func test_defaults_when_absent() -> void:
	var sb := _sb()
	assert_almost(sb.get_stat("xp", "mining"), 1.0)
	assert_almost(sb.get_stat("armor"), 0.0)


func test_scale_stacks_stars() -> void:
	var sb := _sb()
	sb.apply({"xp.all": 1.04, "max_health": 5}, 3.0)
	assert_almost(sb.get_stat("xp", "x"), pow(1.04, 3.0))
	assert_almost(sb.get_stat("max_health"), 15.0)


func test_merged_with_combines_both() -> void:
	var a := _sb()
	a.apply({"xp.all": 1.1, "armor": 2})
	var b := _sb()
	b.apply({"xp.all": 1.02, "armor": 3})
	var m := a.merged_with(b)
	assert_almost(m.get_stat("xp", "mining"), 1.1 * 1.02)
	assert_almost(m.get_stat("armor"), 5.0)
	assert_almost(a.get_stat("armor"), 2.0, 0.0001, "merge does not mutate the source")


func test_character_stats_include_traits_and_stars() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["brom_stonefist"]
	var base := ch.stat("gather_speed", "mining")
	ch.traits.append("hard_worker")
	ch.invalidate_stats()
	assert_almost(ch.stat("gather_speed", "mining"), base * 1.08)
	ch.stars = 3
	ch.invalidate_stats()
	assert_almost(ch.stat("gather_speed", "mining"), base * 1.08 * pow(1.03, 2.0))


func test_building_effects_reach_characters() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var before := ch.stat("xp", "mining")
	w.town.levels["academy"] = 1
	w.town.recompute(w.registry)
	assert_almost(ch.stat("xp", "mining"), before * 1.02, 0.0001, "academy +2% xp applied through the account stat block")
