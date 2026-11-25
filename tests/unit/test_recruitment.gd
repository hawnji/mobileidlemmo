extends WbTestCase
## Gacha: base rates (chi-square over 10^6 rolls), pity rules, featured share,
## costs, duplicates, fragments, star-up and persistence.


func _banner() -> Dictionary:
	return registry().banners["standard"]


func test_banner_rates_sum_to_one() -> void:
	for bid in registry().banner_order:
		var sum := 0.0
		for r in registry().banners[bid].rates:
			sum += float(registry().banners[bid].rates[r])
		assert_almost(sum, 1.0, 0.000001, bid)


## Chi-square goodness of fit of the base table (no pity) over 10^6 rolls.
## 5 degrees of freedom; the 99.9% critical value is 20.52.
func test_base_rates_chi_square_one_million_rolls() -> void:
	var st := RecruitmentState.new()
	st.rng.seed = 987654321
	var banner := _banner()
	var n := 1000000
	var counts := {}
	for i in n:
		var r := st.roll_base_rarity(banner)
		counts[r] = int(counts.get(r, 0)) + 1
	var chi := 0.0
	for r in banner.rates:
		var expected := float(banner.rates[r]) * n
		var obs := float(counts.get(r, 0))
		chi += (obs - expected) * (obs - expected) / expected
	assert_lte(chi, 20.52, "chi-square %.2f exceeds the 99.9%% critical value" % chi)


func test_rare_guaranteed_within_ten_pulls() -> void:
	var st := RecruitmentState.new()
	st.rng.seed = 1
	var reg := registry()
	var banner := _banner().duplicate(true)
	banner.rates = {"common": 1.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0, "legendary": 0.0, "mythic": 0.0}
	var results: Array[String] = []
	for i in 30:
		results.append(st.roll_rarity(reg, banner))
	# Pulls 10, 20, 30 must be rare (pity), everything else common.
	for i in 30:
		var expected := "rare" if (i + 1) % 10 == 0 else "common"
		assert_eq(results[i], expected, "pull %d" % (i + 1))


func test_higher_pity_wins_and_resets_lower_tiers() -> void:
	var st := RecruitmentState.new()
	var reg := registry()
	var banner := _banner().duplicate(true)
	banner.rates = {"common": 1.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0, "legendary": 0.0, "mythic": 0.0}
	var c := st.pity_counters("standard")
	c["rare"] = 9
	c["epic"] = 49
	c["legendary"] = 20
	assert_eq(st.roll_rarity(reg, banner), "epic", "epic pity beats rare pity on the same pull")
	assert_eq(int(c.rare), 0, "rare counter reset by an epic")
	assert_eq(int(c.epic), 0, "epic counter reset")
	assert_eq(int(c.legendary), 21, "legendary counter keeps counting")


func test_mythic_guaranteed_by_pull_200() -> void:
	var st := RecruitmentState.new()
	st.rng.seed = 42
	var reg := registry()
	var banner := _banner().duplicate(true)
	banner.rates = {"common": 1.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0, "legendary": 0.0, "mythic": 0.0}
	var first_mythic := -1
	for i in 200:
		if st.roll_rarity(reg, banner) == "mythic":
			first_mythic = i + 1
			break
	assert_eq(first_mythic, 200)


func test_natural_high_roll_resets_pity() -> void:
	var st := RecruitmentState.new()
	var reg := registry()
	var banner := _banner().duplicate(true)
	banner.rates = {"common": 0.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0, "legendary": 1.0, "mythic": 0.0}
	var c := st.pity_counters("standard")
	c["mythic"] = 10
	assert_eq(st.roll_rarity(reg, banner), "legendary")
	assert_eq(int(c.legendary), 0)
	assert_eq(int(c.rare), 0)
	assert_eq(int(c.mythic), 11)


func test_effective_rates_include_pity() -> void:
	var rates := RecruitmentState.effective_rates(registry(), _banner(), 100000)
	assert_gt(float(rates.rare), 0.17, "rare pity lifts the effective rare rate")
	assert_gte(float(rates.mythic), 0.002)
	var sum := 0.0
	for r in rates:
		sum += float(rates[r])
	assert_almost(sum, 1.0, 0.000001)


func test_featured_share() -> void:
	var st := RecruitmentState.new()
	st.rng.seed = 7
	var reg := registry()
	var banner: Dictionary = reg.banners["harvest_festival"]
	var featured := 0
	var n := 4000
	for i in n:
		if st.pick_character(reg, banner, "epic") == "morgana_ashveil":
			featured += 1
	assert_almost(float(featured) / n, 0.5, 0.03)


func test_pick_only_from_gacha_pool_of_that_rarity() -> void:
	var st := RecruitmentState.new()
	var reg := registry()
	for i in 200:
		var cid := st.pick_character(reg, _banner(), "legendary")
		assert_eq(String(reg.characters[cid].rarity), "legendary")
		assert_eq(String(reg.characters[cid].acquisition), "gacha", "starters / quest characters are not in the pool")


func test_recruit_spends_tokens_first_then_gems_with_discount() -> void:
	var w := new_world()
	assert_eq(w.recruit_cost("standard", 10), {"recruitment_tokens": 10})
	var res := w.recruit("standard", 10)
	assert_eq(String(res.error), "")
	assert_eq(res.results.size(), 10)
	assert_eq(w.wallet.get_balance("recruitment_tokens"), 0)
	assert_eq(w.recruit_cost("standard", 10), {}, "300 gems is not enough for 10 x 150 x 0.9")
	assert_eq(w.recruit_cost("standard", 1), {"gems": 150})
	w.wallet.earn("gems", 2000, "test")
	assert_eq(w.recruit_cost("standard", 10), {"gems": 1350})


func test_recruit_fails_without_currency_and_charges_nothing() -> void:
	var w := new_world()
	w.wallet.spend_many({"recruitment_tokens": 10, "gems": 300}, "test")
	var before := w.character_order.size()
	var res := w.recruit("standard", 1)
	assert_ne(String(res.error), "")
	assert_eq(w.character_order.size(), before)
	assert_eq(w.recruitment.total_pulls.get("standard", 0), 0)


func test_new_characters_join_and_duplicates_give_fragments() -> void:
	var w := new_world()
	w.wallet.earn("recruitment_tokens", 400, "test")
	var news := 0
	var dups := 0
	for i in 40:
		var res := w.recruit("standard", 10)
		for r in res.results:
			if r.new:
				news += 1
			else:
				dups += 1
	assert_eq(w.character_order.size(), 3 + news)
	assert_gt(dups, 0)
	var frag_total := 0
	for cid in w.fragments:
		frag_total += int(w.fragments[cid])
	assert_gt(frag_total, 0)
	for cid in w.character_order:
		assert_true(w.grid.is_walkable(w.characters[cid].tile), "%s spawned on a walkable tile" % cid)


func test_star_up_uses_fragments() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	assert_ne(w.star_up("tamsin_reed"), "", "no fragments yet")
	w.fragments["tamsin_reed"] = 35
	var before := ch.stat("xp", "mining")
	assert_eq(w.star_up("tamsin_reed"), "")
	assert_eq(ch.stars, 2)
	assert_eq(int(w.fragments.tamsin_reed), 25)
	assert_gt(ch.stat("xp", "mining"), before)
	assert_eq(w.star_up("tamsin_reed"), "")
	assert_eq(ch.stars, 3)
	assert_eq(int(w.fragments.tamsin_reed), 5)


func test_pity_and_history_persist_through_save() -> void:
	var w := new_world()
	w.recruit("standard", 10)
	var counters: Dictionary = w.recruitment.pity_counters("standard").duplicate()
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.recruitment.pity_counters("standard"), counters)
	assert_eq(int(w2.recruitment.total_pulls.standard), 10)
	assert_eq(w2.recruitment.history.size(), 10)
	assert_eq(w2.character_order, w.character_order)
	# Same RNG state => the next pull is identical in both worlds.
	w.wallet.earn("gems", 150, "t")
	w2.wallet.earn("gems", 150, "t")
	assert_eq(w.recruit("standard", 1).results[0].character_id, w2.recruit("standard", 1).results[0].character_id)
