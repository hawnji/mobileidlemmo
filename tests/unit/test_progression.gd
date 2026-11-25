extends WbTestCase
## Traits, specializations, milestones and character-level effects.


func test_traits_unlock_at_character_levels() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	assert_true(ch.traits.is_empty())
	ch.character_xp = w.registry.character_xp_table.xp_for_level(10)
	w.sync_traits(ch)
	assert_eq(ch.traits, ["efficient"] as Array[String])
	ch.character_xp = w.registry.character_xp_table.xp_for_level(30)
	w.sync_traits(ch)
	assert_eq(ch.traits.size(), 2)


func test_character_level_up_unlocks_trait_through_engine() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	ch.character_xp = w.registry.character_xp_table.xp_for_level(10) - 1.0
	w.engine.grant_xp(ch, "mining", 100.0)
	assert_has(ch.traits, "efficient")


func test_skill_milestones_pay_tokens_and_gold() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var tokens := w.wallet.get_balance("recruitment_tokens")
	var gold := w.wallet.get_balance("gold")
	w.engine.grant_xp(ch, "fishing", w.registry.skill_xp_table.xp_for_level(21))
	assert_eq(w.wallet.get_balance("recruitment_tokens"), tokens + 2, "levels 10 and 20")
	assert_eq(w.wallet.get_balance("gold"), gold + 100)


func test_specializations() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["brom_stonefist"]
	assert_ne(w.choose_specialization("brom_stonefist", "ore_extractor"), "", "needs mining 30")
	ch.skills.set_level("mining", 30)
	var before := ch.stat("gather_speed", "mining")
	assert_eq(w.choose_specialization("brom_stonefist", "ore_extractor"), "")
	assert_almost(ch.stat("gather_speed", "mining"), before * 1.2)
	assert_ne(w.choose_specialization("brom_stonefist", "gem_specialist"), "", "one per skill and one slot")
	assert_eq(w.respec("brom_stonefist"), "")
	assert_true(ch.specializations.is_empty())
	assert_eq(w.wallet.get_balance("gems"), 200)


func test_max_health_grows_with_defense_and_gear() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var base := ch.max_health()
	ch.skills.set_level("defense", 11)
	assert_almost(ch.max_health(), base + 10.0)


func test_only_starters_in_a_new_world() -> void:
	var w := new_world()
	assert_eq(w.character_order.size(), 3)
	for cid in w.character_order:
		assert_eq(String(w.registry.characters[cid].acquisition), "starter")
