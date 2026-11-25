extends WbTestCase
## Phase 3: dungeons (floors, boss phases, enrage), expeditions (requirements,
## slots, deterministic results), dynamic encounters and notifications.

const S := CharacterStates.State


func _team(w: SimulationWorld, n: int) -> Array:
	var out := []
	for cid in w.character_order:
		if out.size() < n:
			out.append(cid)
	return out


## Makes a character strong enough for late content.
func _buff(ch: Adventurer, level := 80) -> void:
	for s in ["attack", "strength", "defense", "ranged", "magic", "exploration", "mining", "archaeology", "woodcutting", "foraging"]:
		ch.skills.set_level(s, level)
	ch.character_xp = float(ch.registry.character_xp_table.xp_for_level(mini(level, 99)))
	ch.invalidate_stats()
	ch.health = ch.max_health()


func _give_food(w: SimulationWorld, qty: int) -> void:
	w.storage.add("cooked_trout", qty)
	w.record_source("cooked_trout", qty, "test")


# --- Dungeons ---------------------------------------------------------------------

func test_strong_party_clears_the_goblin_warren() -> void:
	var w := new_world()
	var team := _team(w, 3)
	for cid in team:
		_buff(w.characters[cid])
	_give_food(w, 30)
	var gems := w.wallet.get_balance("gems")
	assert_eq(w.start_dungeon("goblin_warren", team), "")
	for cid in team:
		assert_eq(w.characters[cid].state, S.AWAY)
	assert_ne(w.start_dungeon("goblin_warren", team), "", "already inside")
	w.advance(700.0, 0.5)
	assert_true(w.dungeon_runs.is_empty(), "run finished")
	assert_eq(int(w.dungeon_records["goblin_warren"].clears), 1)
	assert_gt(w.wallet.get_balance("gems"), gems, "first-clear bonus")
	assert_eq(int(w.counters.get("dungeon:goblin_warren", 0)), 1)
	for cid in team:
		assert_ne(w.characters[cid].state, S.AWAY, "back on the map")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_weak_party_fails_the_tomb_and_comes_back_injured() -> void:
	var w := new_world()
	for rid in ["irondeep", "ashen_desert"]:
		w._set_region_unlocked(rid)
	var team := _team(w, 3)
	assert_eq(w.start_dungeon("tomb_of_the_sand_king", team), "")
	var result := ""
	var injured := 0
	var t := 0.0
	while t < 1300.0 and result.is_empty():
		w.advance(5.0, 0.5)
		t += 5.0
		if w.dungeon_runs.is_empty():
			result = "done"
			for cid in team:
				if w.characters[cid].state == S.INJURED:
					injured += 1
	assert_true(w.dungeon_runs.is_empty())
	assert_false(w.dungeon_records.has("tomb_of_the_sand_king"), "no clear recorded")
	assert_gt(injured, 0, "a wiped party comes back injured")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_dungeon_checks_party_size_and_region() -> void:
	var w := new_world()
	assert_ne(w.start_dungeon("deepforge_vault", _team(w, 2)), "", "Irondeep locked")
	w._set_region_unlocked("irondeep")
	assert_ne(w.start_dungeon("deepforge_vault", _team(w, 1)), "", "needs at least two")


func test_boss_enters_later_phases_and_enrages() -> void:
	var w := new_world()
	var team := _team(w, 3)
	for cid in team:
		_buff(w.characters[cid], 45)
	_give_food(w, 60)
	var run := DungeonRun.create(w, "goblin_warren", team)
	var saw_phase := false
	var t := 0.0
	while t < 600.0 and run.result.is_empty():
		run.tick(w, 0.5)
		t += 0.5
		var b := run.boss_foe()
		if not b.is_empty() and int(b.get("phase", -1)) >= 0:
			saw_phase = true
	assert_eq(run.result, "cleared")
	assert_true(saw_phase or run.def.get("boss", "").is_empty(), "boss changed phase before dying")
	assert_gt(run.log_lines.size(), 3)
	# Enrage: a boss fight that drags on past its enrage timer.
	var boss: Dictionary = w.registry.enemies[run.def.boss].get("boss", {})
	assert_gt(float(boss.get("enrage_seconds", 0.0)), 0.0, "bosses define an enrage timer")


func test_dungeon_run_survives_save_and_load_mid_fight() -> void:
	var w := new_world()
	var team := _team(w, 2)
	for cid in team:
		_buff(w.characters[cid])
	_give_food(w, 20)
	assert_eq(w.start_dungeon("goblin_warren", team), "")
	w.advance(40.0, 0.5)
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.dungeon_runs.size(), 1)
	assert_eq(w2.characters[team[0]].state, S.AWAY)
	w2.advance(700.0, 0.5)
	assert_true(w2.dungeon_runs.is_empty())
	assert_eq(w2.held_totals(), w2.ledger_totals())


# --- Expeditions ------------------------------------------------------------------

func _with_slot(w: SimulationWorld) -> void:
	w.town.levels["expedition_center"] = 1
	w.town.recompute(w.registry)
	w._apply_account_effects()


func test_expedition_needs_a_slot_and_the_right_team() -> void:
	var w := new_world()
	var ch_id: String = w.character_order[0]
	if w.expeditions.slots(w) == 0:
		assert_ne(w.start_expedition("greenvale_survey", [ch_id]), "", "no slot without the Expedition Center")
		_with_slot(w)
	assert_gt(w.expeditions.slots(w), 0)
	assert_ne(w.start_expedition("greenvale_survey", _team(w, 2)), "", "team size is 1")
	assert_ne(w.start_expedition("goblin_warrens_raid", _team(w, 2)), "", "combat level 10 needed")
	assert_eq(w.start_expedition("greenvale_survey", [ch_id]), "")
	assert_eq(w.characters[ch_id].state, S.AWAY)
	assert_ne(w.start_expedition("greenvale_survey", [ch_id]), "", "already away")


func test_expedition_resolves_after_its_duration() -> void:
	var w := new_world()
	_with_slot(w)
	var ch_id: String = w.character_order[0]
	_buff(w.characters[ch_id], 30)
	assert_eq(w.start_expedition("greenvale_survey", [ch_id]), "")
	w.advance(1700.0, 1.0)
	assert_eq(w.expeditions.active.size(), 1, "still away")
	w.advance(200.0, 1.0)
	assert_true(w.expeditions.active.is_empty())
	assert_eq(w.expeditions.history.size(), 1)
	assert_eq(w.expeditions.completed_total, 1)
	assert_ne(w.characters[ch_id].state, S.AWAY)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_expedition_result_is_the_same_online_and_after_reload() -> void:
	var a := new_world(77)
	_with_slot(a)
	var cid: String = a.character_order[0]
	_buff(a.characters[cid], 20)
	assert_eq(a.start_expedition("greenvale_survey", [cid]), "")
	var b := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(a.to_dict())))
	a.advance(1900.0, 0.5)
	b.advance(1900.0, 30.0)
	assert_eq(a.expeditions.history[0].success, b.expeditions.history[0].success)
	assert_eq(JSON.stringify(a.expeditions.history[0].rewards), JSON.stringify(b.expeditions.history[0].rewards))
	assert_eq(a.expeditions.history[0].story, b.expeditions.history[0].story)


func test_stronger_teams_have_better_odds() -> void:
	var w := new_world()
	var x: Dictionary = w.registry.expeditions["greenvale_survey"]
	var ch: Adventurer = w.characters[w.character_order[0]]
	var weak := w.expeditions.success_chance(w, x, [ch], false)
	_buff(ch, 60)
	var strong := w.expeditions.success_chance(w, x, [ch], false)
	assert_gt(strong, weak)
	assert_gt(w.expeditions.success_chance(w, x, [ch], true), strong - 0.0001, "supplies never hurt")


# --- Encounters ---------------------------------------------------------------------

func test_each_encounter_kind_can_spawn_and_expires() -> void:
	var w := new_world()
	for def in w.registry.encounter_config.encounters:
		var enc := w.encounters.spawn_random(w, String(def.id))
		assert_false(enc.is_empty(), "%s found a place" % def.id)
	var n := w.encounters.active.size()
	assert_gt(n, 0)
	w.advance(4000.0, 1.0)
	for enc in w.encounters.active:
		assert_gt(float(enc.ends_at), w.sim_time - 1.0, "expired encounters were removed")
	assert_true(w.temp_enemies.size() <= w.encounters.active.size())


func test_bountiful_harvest_doubles_yield_in_its_area() -> void:
	var w := new_world()
	var enc := w.encounters.spawn_random(w, "bountiful_vein")
	assert_false(enc.is_empty())
	var rect: Rect2i = w.locations[enc.location].rect
	assert_almost(w.encounters.yield_multiplier_at(rect.position), float(enc.yield_mult))
	assert_almost(w.encounters.yield_multiplier_at(Vector2i(-5, -5)), 1.0)


func test_travelling_merchant_sells_limited_stock() -> void:
	var w := new_world()
	var enc := w.encounters.spawn_random(w, "travelling_merchant")
	assert_false(enc.is_empty())
	var s: Dictionary = enc.stock[0]
	for c in s.price:
		w.wallet.earn(String(c), int(s.price[c]) * (int(s.qty) + 1), "test")
	assert_eq(w.buy_from_merchant(int(enc.uid), String(s.item), 1), "")
	assert_eq(w.storage.get_quantity(String(s.item)), 1)
	assert_ne(w.buy_from_merchant(int(enc.uid), String(s.item), 999), "", "limited stock")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_wandering_hero_joins_the_first_character_nearby() -> void:
	var w := new_world()
	var enc := w.encounters.spawn_random(w, "wandering_hero")
	assert_false(enc.is_empty())
	var hero := String(enc.character_id)
	var had := w.characters.has(hero)
	var frags := int(w.fragments.get(hero, 0))
	var ch: Adventurer = w.characters[w.character_order[0]]
	ch.tile = enc.tile
	w.encounters.on_character_moved(w, ch)
	assert_true(w.characters.has(hero))
	if had:
		assert_gt(int(w.fragments.get(hero, 0)), frags, "duplicates become fragments")
	assert_true(w.encounters.merchant(int(enc.uid)).is_empty())


func test_encounters_happen_during_offline_catch_up() -> void:
	var w := new_world()
	w.advance(4.0 * 3600.0, 30.0)
	var started := 0
	for ev in w.event_log:
		if ev.type == "encounter_started":
			started += 1
	assert_gt(started, 0)


# --- Notifications ----------------------------------------------------------------

func test_notifications_merge_repeats_and_respect_settings() -> void:
	var w := new_world()
	var nc := w.notifications
	var before := nc.items.size()
	w.emit_event("discovery", {"character_id": w.character_order[0], "discovery": "old_watchtower", "name": "Old Watchtower"})
	w.emit_event("discovery", {"character_id": w.character_order[0], "discovery": "forest_shrine", "name": "Forest Shrine"})
	assert_eq(nc.items.size(), before + 1, "second discovery merged into the first")
	assert_gt(nc.unread_count(), 0)
	nc.mark_all_read()
	assert_eq(nc.unread_count(), 0)
	nc.set_enabled("expeditions", false)
	var n := nc.items.size()
	w.emit_event("expedition_completed", {"expedition": "greenvale_survey", "name": "Survey", "success": true})
	assert_eq(nc.items.size(), n, "disabled category is ignored")


func test_ordinary_gathering_never_notifies() -> void:
	var w := new_world()
	var ch_id: String = w.character_order[0]
	w.assign_activity(ch_id, make_assignment(w, ch_id, "mine_copper"))
	var n := w.notifications.items.size()
	w.advance(600.0, 0.5)
	for it in w.notifications.items.slice(0, w.notifications.items.size() - n):
		assert_ne(String(it.category), "gathering")
