extends WbTestCase
## Phase 5: endgame regions, relics, pets, mounts, mastery, mythic dungeon
## tiers, seasons and World Ascension.

const S := CharacterStates.State


func _first(w: SimulationWorld) -> Adventurer:
	return w.characters[w.character_order[0]]


func _team(w: SimulationWorld, n: int) -> Array:
	var out := []
	for cid in w.character_order:
		if out.size() < n:
			out.append(cid)
	return out


func _buff(ch: Adventurer, level := 80) -> void:
	for s in ["attack", "strength", "defense", "ranged", "magic", "exploration", "mining"]:
		ch.skills.set_level(s, level)
	ch.character_xp = float(ch.registry.character_xp_table.xp_for_level(mini(level, 99)))
	ch.invalidate_stats()
	ch.health = ch.max_health()


func _give(w: SimulationWorld, item: String, qty := 1) -> void:
	w.storage.add(item, qty)
	w.record_source(item, qty, "test")


func _open_all(w: SimulationWorld) -> void:
	for rid in w.registry.map_region_order:
		if not w.is_region_unlocked(rid):
			w._set_region_unlocked(rid)


func _unix(date: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(date + "T12:00:00"))


func _roundtrip(w: SimulationWorld) -> SimulationWorld:
	return SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))


# --- Regions ----------------------------------------------------------------------

func test_endgame_regions_are_on_the_map_behind_gates() -> void:
	var w := new_world()
	for rid in ["shadowlands", "celestial_isles"]:
		assert_has(w.registry.map_regions, rid)
		assert_false(w.is_region_unlocked(rid))
	assert_eq(w.grid.height, 144)
	_open_all(w)
	var route: Array = w.nav.region_route("greenvale", "celestial_isles")
	assert_eq(route.size(), 3, "Greenvale > Whisperwood > Shadowlands > Celestial Isles")
	assert_eq(route[2].region_to, "celestial_isles")
	assert_eq(w.location_region("void_rift"), "shadowlands")
	assert_eq(w.location_region("sentinel_terrace"), "celestial_isles")


func test_celestial_isles_need_a_flying_mount() -> void:
	var w := new_world()
	w.quests.completed["mq_11_the_sky_road"] = 1
	assert_true(w.region_unlock_gap("celestial_isles").contains("flying"), w.region_unlock_gap("celestial_isles"))
	_give(w, "mount_pack_pony")
	w.use_item("mount_pack_pony")
	assert_true(w.region_unlock_gap("celestial_isles").contains("flying"), "a pony cannot fly")
	_give(w, "mount_griffin")
	assert_eq(w.use_item("mount_griffin").error, "")
	assert_true(w.region_unlock_gap("celestial_isles").contains("level"), w.region_unlock_gap("celestial_isles"))


func test_heroes_gather_voidstone_in_the_shadowlands() -> void:
	var w := new_world()
	_open_all(w)
	var ch := _first(w)
	_buff(ch, 85)
	ch.tile = w.free_tile_near(w.locations["voidstone_pits"].rect.get_center())
	assert_eq(w.assign_activity(ch.id, make_assignment(w, ch.id, "mine_voidstone")), "")
	w.advance(180.0, 0.5)
	assert_gt(int(ch.stats.gathered.get("voidstone_ore", 0)), 0, "mined voidstone")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_old_fog_survives_the_taller_map() -> void:
	var w := new_world()
	var old := PackedByteArray()
	old.resize(128 * 96)
	for x in 128:
		old[x] = 1
	var d := {"fog": Marshalls.raw_to_base64(old.compress(FileAccess.COMPRESSION_DEFLATE)), "fog_size": old.size(), "discovered": {}}
	w.exploration.load_dict(d)
	assert_eq(w.exploration.revealed.size(), 128 * 144)
	assert_true(w.exploration.is_revealed(Vector2i(5, 0)))
	assert_false(w.exploration.is_revealed(Vector2i(5, 120)))


# --- Collectibles -------------------------------------------------------------------

func test_pet_egg_hatches_and_duplicates_become_relic_dust() -> void:
	var w := new_world()
	_give(w, "pet_egg_rock_crab", 2)
	var r := w.use_item("pet_egg_rock_crab")
	assert_eq(r.error, "")
	assert_has(w.endgame.pets, "rock_crab")
	var dust := w.wallet.get_balance("relic_dust")
	w.use_item("pet_egg_rock_crab")
	assert_eq(w.wallet.get_balance("relic_dust"), dust + 20, "uncommon duplicate")
	assert_eq(w.storage.get_quantity("pet_egg_rock_crab"), 0)
	assert_ne(w.use_item("iron_ore").error, "", "ordinary items cannot be used")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_pet_levels_from_its_owners_xp_and_helps_only_its_owner() -> void:
	var w := new_world()
	_give(w, "pet_egg_rock_crab")
	w.use_item("pet_egg_rock_crab")
	var a := _first(w)
	var b: Adventurer = w.characters[w.character_order[1]]
	var a_speed := a.stat("gather_speed", "mining")
	var b_speed := b.stat("gather_speed", "mining")
	assert_eq(w.assign_pet(a.id, "rock_crab"), "")
	assert_almost(a.stat("gather_speed", "mining"), a_speed * 1.012, 0.0001)
	w.engine.grant_xp(a, "mining", 60000.0 / a.xp_multiplier("mining"))
	assert_eq(int(w.endgame.pets.rock_crab.level), 2, "5% of 60k XP passes 2,000")
	var with_pet := a.stat("gather_speed", "mining")
	assert_almost(b.stat("gather_speed", "mining"), b_speed, 0.0001)
	assert_eq(w.assign_pet(b.id, "rock_crab"), "")
	assert_false(w.endgame.pet_assign.has(a.id), "a pet follows one hero")
	assert_almost(with_pet / a.stat("gather_speed", "mining"), pow(1.012, 2), 0.0001, "level 2 pet bonus")


func test_mount_speeds_up_one_hero() -> void:
	var w := new_world()
	_give(w, "mount_pack_pony")
	w.use_item("mount_pack_pony")
	var a := _first(w)
	var b: Adventurer = w.characters[w.character_order[1]]
	var speed := a.move_speed_tiles()
	var cap := a.inventory.max_units
	assert_eq(w.assign_mount(a.id, "pack_pony"), "")
	assert_almost(a.move_speed_tiles(), speed * 1.15, 0.001)
	assert_eq(a.inventory.max_units, cap + 4)
	assert_eq(w.assign_mount(b.id, "pack_pony"), "")
	assert_almost(a.move_speed_tiles(), speed, 0.001, "the pony moved to the other hero")
	assert_ne(w.assign_mount(a.id, "griffin"), "", "not owned")


func test_relics_equip_upgrade_and_respect_slots() -> void:
	var w := new_world()
	var ch := _first(w)
	var base := ch.stat("gather_speed", "mining")
	_give(w, "relic_miners_lantern", 2)
	w.use_item("relic_miners_lantern")
	assert_has(w.endgame.equipped_relics, "miners_lantern", "auto-equipped into a free slot")
	assert_almost(ch.stat("gather_speed", "mining"), base * 1.04, 0.0001)
	w.use_item("relic_miners_lantern")
	assert_eq(w.wallet.get_balance("relic_dust"), 40, "rare duplicate")
	assert_ne(w.upgrade_relic("miners_lantern"), "", "60 dust needed")
	w.wallet.earn("relic_dust", 20, "test")
	assert_eq(w.upgrade_relic("miners_lantern"), "")
	assert_almost(ch.stat("gather_speed", "mining"), base * 1.04 * 1.04, 0.0001)
	for rid in ["woodsmans_charm", "anglers_pearl", "scholars_tome"]:
		_give(w, "relic_" + rid)
		w.use_item("relic_" + rid)
	assert_eq(w.endgame.equipped_relics.size(), 3)
	assert_ne(w.equip_relic("scholars_tome"), "", "three slots")
	assert_eq(w.unequip_relic("miners_lantern"), "")
	assert_almost(ch.stat("gather_speed", "mining"), base, 0.0001)
	assert_eq(w.equip_relic("scholars_tome"), "")


func test_celestial_hourglass_extends_offline_progress() -> void:
	var w := new_world()
	var sim := LocalOfflineSimulator.new(registry())
	sim.step_seconds = 60.0
	assert_almost(sim.apply_offline_progress(w, 3600.0 * 20).cap_seconds, 8 * 3600.0, 0.5)
	_give(w, "relic_celestial_hourglass")
	w.use_item("relic_celestial_hourglass")
	var report := sim.apply_offline_progress(w, 3600.0 * 20)
	assert_almost(report.cap_seconds, 10 * 3600.0, 0.5)


func test_sigil_brings_a_mythic_hero() -> void:
	var w := new_world()
	_give(w, "sigil_nyx_voidwalker")
	assert_false(w.characters.has("nyx_voidwalker"))
	assert_eq(w.use_item("sigil_nyx_voidwalker").error, "")
	assert_true(w.characters.has("nyx_voidwalker"))
	assert_eq(w.registry.characters.nyx_voidwalker.rarity, "mythic")


# --- Mastery ------------------------------------------------------------------------

func test_mastery_grows_past_level_99() -> void:
	var w := new_world()
	var ch := _first(w)
	ch.skills.set_level("mining", 98)
	w.engine.grant_xp(ch, "mining", 1000.0)
	assert_true(ch.mastery_xp.is_empty(), "no mastery below the cap")
	ch.skills.set_level("mining", 99)
	var dust := w.wallet.get_balance("relic_dust")
	w.engine.grant_xp(ch, "mining", 5200000.0 / ch.xp_multiplier("mining"))
	assert_eq(w.endgame.mastery_level(ch, "mining"), 5)
	var with_mastery := ch.stat("gather_speed", "mining")
	var saved: Dictionary = ch.mastery_xp.duplicate()
	ch.mastery_xp.clear()
	ch.invalidate_stats()
	assert_almost(with_mastery / ch.stat("gather_speed", "mining"), pow(1.01, 5), 0.0001)
	ch.mastery_xp = saved
	ch.invalidate_stats()
	assert_eq(w.wallet.get_balance("relic_dust"), dust + 50, "level 5 milestone")
	assert_true(Objectives.is_met(w, {"type": "mastery", "skill": "mining", "level": 5}))
	var w2 := _roundtrip(w)
	assert_eq(w2.endgame.mastery_level(w2.characters[ch.id], "mining"), 5)


# --- Mythic dungeons ------------------------------------------------------------------

func test_mythic_tiers_open_one_at_a_time() -> void:
	var w := new_world()
	var team := _team(w, 3)
	assert_eq(w.endgame.max_unlocked_tier(w, "goblin_warren"), 0)
	assert_ne(w.start_dungeon("goblin_warren", team, 1), "", "clear it normally first")
	w.dungeon_records["goblin_warren"] = {"clears": 1, "best_time": 100.0}
	assert_eq(w.endgame.max_unlocked_tier(w, "goblin_warren"), 1)
	assert_ne(w.start_dungeon("goblin_warren", team, 2), "")
	w.endgame.mythic_records["goblin_warren"] = 4
	assert_eq(w.endgame.max_unlocked_tier(w, "goblin_warren"), 5)


func test_mythic_tier_scales_enemies_and_adds_affixes() -> void:
	var w := new_world()
	var team := _team(w, 3)
	var run := DungeonRun.create(w, "goblin_warren", team, 4)
	assert_has(run.affix_names(), "Fortified")
	assert_has(run.affix_names(), "Tyrannical")
	assert_eq(run.affix_names().size(), 2)
	while run.floor_index < 0:
		run.tick(w, 0.5)
	var f: Dictionary = run.foes[0]
	var base: float = float(w.registry.enemies[f.enemy.enemy_id].health) * f.enemy.stat_multiplier()
	assert_almost(f.enemy.max_health, base * 1.6 * 1.2, 0.01, "tier 4: +60% health, fortified +20%")
	var saved := DungeonRun.from_dict(w, JSON.parse_string(JSON.stringify(run.to_dict())))
	assert_eq(saved.tier, 4)
	assert_almost(saved.foes[0].enemy.max_health, f.enemy.max_health, 0.01)


func test_mythic_clear_pays_dust_and_records_the_tier() -> void:
	var w := new_world()
	var team := _team(w, 3)
	for cid in team:
		_buff(w.characters[cid], 90)
	_give(w, "cooked_trout", 60)
	w.dungeon_records["goblin_warren"] = {"clears": 1, "best_time": 100.0}
	var dust := w.wallet.get_balance("relic_dust")
	assert_eq(w.start_dungeon("goblin_warren", team, 1), "")
	var result := {}
	w.event_emitted.connect(func(e): if e.type == "dungeon_completed": result.merge(e))
	w.advance(900.0, 0.5)
	assert_eq(String(result.get("result", "")), "cleared", str(result.get("log", [])))
	assert_eq(int(result.tier), 1)
	assert_eq(int(w.endgame.mythic_records.get("goblin_warren", 0)), 1)
	assert_gte(w.wallet.get_balance("relic_dust"), dust + 15)
	assert_eq(w.endgame.max_unlocked_tier(w, "goblin_warren"), 2)
	assert_true(Objectives.is_met(w, {"type": "mythic_tier", "tier": 1}))
	assert_eq(w.held_totals(), w.ledger_totals())


# --- Seasons ------------------------------------------------------------------------

func test_season_follows_the_calendar_and_gives_its_bonus() -> void:
	var w := new_world()
	var ch := _first(w)
	w.endgame.set_calendar(_unix("2026-07-10"))
	assert_eq(w.endgame.current_season(), "sunfire_regatta")
	var summer := ch.stat("gather_speed", "fishing")
	w.endgame.set_calendar(_unix("2026-01-10"))
	assert_eq(w.endgame.current_season(), "frostfall")
	assert_almost(summer, ch.stat("gather_speed", "fishing") * 1.1, 0.0001)
	assert_true(Objectives.is_met(w, {"type": "season", "season": "frostfall"}))


func test_seasonal_quests_and_stock_come_and_go() -> void:
	var w := new_world()
	w.endgame.set_calendar(_unix("2026-04-10"))
	w.quests.refresh(w)
	assert_true(w.quests.active.has("sq_bloomtide_1"))
	assert_false(w.quests.active.has("sq_frostfall_1"))
	w.wallet.earn("event_tokens", 600, "test")
	assert_eq(w.buy_from_vendor("festival_merchant", "pet_egg_sapling", 1), "")
	assert_ne(w.buy_from_vendor("festival_merchant", "mount_frost_elk", 1), "", "winter stock")
	w.endgame.set_calendar(_unix("2026-12-10"))
	w.quests.refresh(w)
	assert_false(w.quests.active.has("sq_bloomtide_1"), "spring contracts expire")
	assert_true(w.quests.active.has("sq_frostfall_1"))
	assert_eq(w.buy_from_vendor("festival_merchant", "mount_frost_elk", 1), "")


# --- Ascension ----------------------------------------------------------------------

func test_ascension_requires_the_last_main_quest() -> void:
	var w := new_world()
	assert_ne(w.ascension_gap(), "")
	assert_ne(String(w.ascend().error), "")
	w.quests.completed["mq_12_starfall"] = 1
	assert_eq(w.ascension_gap(), "")


func test_ascension_resets_the_world_and_keeps_the_legacy() -> void:
	var w := new_world()
	w.quests.completed["mq_12_starfall"] = 1
	var ch := _first(w)
	ch.skills.set_level("mining", 60)
	_give(w, "iron_ore", 500)
	_give(w, "pet_egg_rock_crab")
	w.use_item("pet_egg_rock_crab")
	w.assign_pet(ch.id, "rock_crab")
	w.wallet.earn("gold", 9000, "test")
	var gems := w.wallet.get_balance("gems")
	w._set_region_unlocked("irondeep")
	w.exploration.discovered["old_watchtower"] = {"time": 1.0, "by": ch.id}
	var roster := w.character_order.duplicate()
	var res := w.ascend()
	assert_eq(String(res.error), "")
	var nw: SimulationWorld = res.world
	assert_gt(int(res.points), 0)
	assert_eq(nw.wallet.get_balance("ascension_points"), int(res.points))
	assert_eq(nw.character_order, roster)
	assert_eq(nw.characters[ch.id].skills.get_level("mining"), 60, "skills are kept")
	assert_eq(nw.wallet.get_balance("gems"), gems, "premium currency is kept")
	assert_eq(nw.wallet.get_balance("gold"), 200, "gold resets")
	assert_eq(nw.storage.get_quantity("iron_ore"), 0, "storage resets")
	assert_false(nw.is_region_unlocked("irondeep"), "regions reset")
	assert_false(nw.quests.has_completed("mq_12_starfall"), "quests reset")
	assert_true(nw.exploration.discovered.is_empty())
	assert_eq(String(nw.endgame.pet_assign.get(ch.id, "")), "rock_crab", "pets stay")
	assert_eq(nw.endgame.ascensions, 1)
	assert_eq(nw.storage.get_quantity("sigil_astraea_skyborn"), 1, "first ascension reward")
	assert_eq(nw.storage.get_quantity("mount_celestial_drake"), 1)
	assert_eq(nw.held_totals(), nw.ledger_totals())
	assert_true(Objectives.is_met(nw, {"type": "ascension", "count": 1}))
	nw.advance(30.0, 0.5)
	var again := _roundtrip(nw)
	assert_eq(again.endgame.ascensions, 1)
	assert_eq(again.held_totals(), again.ledger_totals())


func test_repeat_ascension_without_growth_pays_the_minimum() -> void:
	var w := new_world()
	w.quests.completed["mq_12_starfall"] = 1
	var first: SimulationWorld = w.ascend().world
	first.quests.completed["mq_12_starfall"] = 1
	var res := first.ascend()
	assert_eq(int(res.points), 5)
	assert_eq(res.world.storage.get_quantity("sigil_astraea_skyborn"), 0, "first-ascension rewards once")


func test_perks_spend_points_and_apply_effects() -> void:
	var w := new_world()
	var ch := _first(w)
	var xp := ch.xp_multiplier("mining")
	assert_ne(w.buy_perk("insight"), "", "no points yet")
	w.wallet.earn("ascension_points", 100, "test")
	assert_eq(w.buy_perk("insight"), "")
	assert_almost(ch.xp_multiplier("mining"), xp * 1.05, 0.0001)
	assert_eq(w.wallet.get_balance("ascension_points"), 90)
	assert_eq(w.buy_perk("attunement"), "")
	assert_eq(w.endgame.relic_slots(), 4)
	w.wallet.earn("ascension_points", 100, "test")
	assert_eq(w.buy_perk("head_start"), "")
	assert_eq(w.endgame.head_start_gold(), 5000)


func test_endgame_state_survives_save_and_load() -> void:
	var w := new_world()
	for it in ["relic_warlords_banner", "pet_egg_study_owl", "mount_griffin"]:
		_give(w, it)
		w.use_item(it)
	var ch := _first(w)
	w.assign_pet(ch.id, "study_owl")
	w.assign_mount(ch.id, "griffin")
	w.endgame.mythic_records["goblin_warren"] = 3
	w.wallet.earn("ascension_points", 10, "test")
	w.buy_perk("insight")
	var dmg := ch.stat("damage")
	var speed := ch.move_speed_tiles()
	var w2 := _roundtrip(w)
	var ch2: Adventurer = w2.characters[ch.id]
	assert_eq(w2.endgame.to_dict(), w.endgame.to_dict())
	assert_almost(ch2.stat("damage"), dmg, 0.0001)
	assert_almost(ch2.move_speed_tiles(), speed, 0.0001)
	assert_eq(w2.held_totals(), w2.ledger_totals())
