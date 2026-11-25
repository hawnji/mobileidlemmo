extends WbTestCase
## Phase 3: regions and gates, fog of war and discoveries, secrets,
## navigation between regions, outposts, quests and reputation, vendors.

const S := CharacterStates.State


func _first(w: SimulationWorld) -> Adventurer:
	return w.characters[w.character_order[0]]


func _open_all(w: SimulationWorld) -> void:
	for rid in w.registry.map_region_order:
		if not w.is_region_unlocked(rid):
			w._set_region_unlocked(rid)


# --- Regions and gates --------------------------------------------------------

func test_new_world_starts_with_only_greenvale_unlocked() -> void:
	var w := new_world()
	assert_true(w.is_region_unlocked("greenvale"))
	for rid in ["irondeep", "whisperwood", "ashen_desert"]:
		assert_false(w.is_region_unlocked(rid), "%s starts locked" % rid)
	assert_eq(w.region_at(w.storage_tile), "greenvale")
	assert_eq(w.region_at(Vector2i(100, 20)), "irondeep")
	assert_eq(w.region_at(Vector2i(20, 70)), "whisperwood")
	assert_eq(w.region_at(Vector2i(100, 70)), "ashen_desert")


func test_unlock_requires_conditions_and_gold() -> void:
	var w := new_world()
	assert_ne(w.region_unlock_gap("irondeep"), "", "quest, mining level and exploration missing")
	assert_ne(w.unlock_region("irondeep"), "")
	assert_false(w.is_region_unlocked("irondeep"))
	# Meet every condition, then pay.
	w.quests.completed["mq_02_eastern_pass"] = 1
	_first(w).skills.set_level("mining", 20)
	for y in 48:
		for x in 64:
			w.exploration.reveal(Vector2i(x, y), 0)
	w.wallet.earn("gold", 1000, "test")
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.region_unlock_gap("irondeep"), "")
	assert_eq(w.unlock_region("irondeep"), "")
	assert_true(w.is_region_unlocked("irondeep"))
	assert_eq(w.wallet.get_balance("gold"), gold - 500)
	assert_eq(w.unlock_region("irondeep"), "Already unlocked")


func test_gates_open_when_both_sides_are_unlocked() -> void:
	var w := new_world()
	var a := Vector2i(63, 25)
	var b := Vector2i(64, 25)
	assert_false(w.grid.is_walkable(b), "gate closed while Irondeep is locked")
	w._set_region_unlocked("irondeep")
	assert_true(w.grid.is_walkable(a))
	assert_true(w.grid.is_walkable(b))


func test_character_walks_into_a_newly_unlocked_region() -> void:
	var w := new_world()
	var ch := _first(w)
	w._set_region_unlocked("irondeep")
	var asg := make_assignment(w, ch.id, "explore_irondeep")
	assert_eq(w.assign_activity(ch.id, asg), "")
	w.advance(400.0, 0.5)
	assert_eq(w.region_at(ch.tile), "irondeep", "crossed the gate")
	assert_gt(w.exploration.explored_pct("irondeep"), 0.0)


func test_locked_region_activities_are_rejected() -> void:
	var w := new_world()
	var ch := _first(w)
	var err := w.assign_activity(ch.id, make_assignment(w, ch.id, "explore_irondeep"))
	assert_ne(err, "", "cannot explore a locked region")


# --- Fog of war and discoveries -----------------------------------------------

func test_walking_reveals_fog_and_grants_exploration_xp() -> void:
	var w := new_world()
	var ch := _first(w)
	var before := w.exploration.explored_pct("greenvale")
	var xp := ch.skills.get_xp("exploration")
	assert_eq(w.assign_activity(ch.id, make_assignment(w, ch.id, "explore_greenvale")), "")
	w.advance(300.0, 0.5)
	assert_gt(w.exploration.explored_pct("greenvale"), before)
	assert_gt(ch.skills.get_xp("exploration"), xp)


func test_reveal_counts_only_new_walkable_tiles() -> void:
	var w := new_world()
	var c := Vector2i(30, 30)
	var first := w.exploration.reveal(c, 3)
	assert_gt(first, 0)
	assert_eq(w.exploration.reveal(c, 3), 0, "second reveal of the same circle gains nothing")
	assert_true(w.exploration.is_revealed(c))


func test_discovery_requires_its_specialty() -> void:
	var w := new_world()
	var d: Dictionary = w.exploration.discoveries["smugglers_cache"]
	var assassin: Adventurer = null
	var other: Adventurer = null
	for cid in w.registry.characters:
		var spec := String(w.registry.characters[cid].get("combat_specialty", ""))
		if spec == "assassin" and assassin == null:
			assassin = w.add_character(cid) if not w.characters.has(cid) else w.characters[cid]
		elif spec != "assassin" and other == null and w.characters.has(cid):
			other = w.characters[cid]
	assert_not_null(assassin)
	assert_not_null(other)
	other.skills.set_level("exploration", 10)
	assassin.skills.set_level("exploration", 10)
	assert_ne(ExplorationState.requirement_gap(w.registry, other, d), "")
	assert_false(w.try_discover(other, "smugglers_cache"))
	var gold := w.wallet.get_balance("gold")
	assert_true(w.try_discover(assassin, "smugglers_cache"))
	assert_true(w.exploration.is_discovered("smugglers_cache"))
	assert_gt(w.wallet.get_balance("gold"), gold, "discovery rewards paid")
	assert_false(w.try_discover(assassin, "smugglers_cache"), "only once")


func test_explorer_finds_discoveries_while_walking() -> void:
	var w := new_world()
	var ch := _first(w)
	assert_eq(w.assign_activity(ch.id, make_assignment(w, ch.id, "explore_greenvale")), "")
	w.advance(3600.0, 1.0)
	assert_gte(w.exploration.discovered_count("greenvale"), 1)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_secret_tunnel_opens_tiles() -> void:
	var w := new_world()
	var sec: Dictionary = w.secrets["irondeep_tunnel"]
	var t: Vector2i = sec.tiles[0]
	assert_false(w.grid.is_walkable(t), "hidden until revealed")
	w.reveal_secret("irondeep_tunnel")
	assert_true(w.grid.is_walkable(t))


# --- Navigation ---------------------------------------------------------------

func test_navigator_routes_through_gates() -> void:
	var w := new_world()
	_open_all(w)
	var route: Array = w.nav.region_route("greenvale", "ashen_desert")
	assert_eq(route.size(), 2, "Greenvale to the desert crosses one middle region")
	assert_eq(route[0].region_from, "greenvale")
	assert_eq(route[1].region_to, "ashen_desert")


func test_locked_region_has_no_route() -> void:
	var w := new_world()
	assert_true(w.nav.region_route("greenvale", "irondeep").is_empty())


func test_fast_travel_to_a_waystone_after_an_outpost_is_built() -> void:
	var w := new_world()
	_open_all(w)
	w.town.levels["outpost_ashen"] = 1
	w.town.recompute(w.registry)
	var ws := w.waystone_of("ashen_desert")
	assert_ne(ws, Vector2i(-1, -1))
	var ch := _first(w)
	assert_eq(w.assign_activity(ch.id, make_assignment(w, ch.id, "explore_ashen_desert")), "")
	w.advance(120.0, 0.5)
	assert_eq(w.region_at(ch.tile), "ashen_desert", "teleported instead of a long walk")


# --- Outposts -------------------------------------------------------------------

func test_outpost_depot_and_local_bonus() -> void:
	var w := new_world()
	w._set_region_unlocked("irondeep")
	var tile := Vector2i(100, 20)
	assert_almost(w.local_multiplier(tile, "gather_speed"), 1.0)
	w.town.levels["outpost_irondeep"] = 1
	w.town.recompute(w.registry)
	assert_gt(w.local_multiplier(tile, "gather_speed"), 1.0)
	assert_eq(w.deposit_tiles().size(), 2, "home storage plus the outpost depot")
	var ch := _first(w)
	ch.tile = tile
	assert_eq(w.nearest_deposit(ch), w.outpost_of("irondeep").depot_tile)


# --- Quests and reputation ----------------------------------------------------

func test_first_main_quest_activates_and_counts_from_activation() -> void:
	var w := new_world()
	w.advance(10.0, 0.5)
	assert_true(w.quests.active.has("mq_01_roots"))
	assert_false(w.quests.is_complete(w, "mq_01_roots"))
	assert_ne(w.claim_quest("mq_01_roots"), "")


func test_claiming_a_quest_pays_rewards_and_reputation() -> void:
	var w := new_world()
	w.advance(10.0, 0.5)
	w.count("gather:copper_ore", 25)
	for y in 48:
		for x in 64:
			w.exploration.reveal(Vector2i(x, y), 0)
	assert_true(w.quests.is_complete(w, "mq_01_roots"))
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.claim_quest("mq_01_roots"), "")
	assert_eq(w.wallet.get_balance("gold"), gold + 150)
	assert_eq(int(w.quests.reputation.get("greenvale", 0)), 150)
	assert_true(w.quests.has_completed("mq_01_roots"))
	assert_true(w.quests.active.has("mq_02_eastern_pass"), "next main quest follows")


func test_deliver_objective_consumes_items() -> void:
	var w := new_world()
	w.quests.completed["mq_01_roots"] = 1
	w.quests.refresh(w)
	assert_true(w.quests.active.has("mq_02_eastern_pass"))
	w.storage.add("bronze_bar", 12)
	w.record_source("bronze_bar", 12, "test")
	_first(w).skills.set_level("mining", 15)
	w.exploration.mark_discovered("old_watchtower", 0.0, "t")
	w.exploration.mark_discovered("forest_shrine", 0.0, "t")
	assert_eq(w.claim_quest("mq_02_eastern_pass"), "")
	assert_eq(w.storage.get_quantity("bronze_bar"), 2)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_reputation_tiers_unlock_vendor_stock() -> void:
	var w := new_world()
	w.wallet.earn("gold", 5000, "test")
	assert_eq(w.buy_from_vendor("greenvale_store", "cooked_trout", 2), "")
	assert_eq(w.storage.get_quantity("cooked_trout"), 2)
	assert_ne(w.buy_from_vendor("greenvale_store", "trowel", 1), "", "Friendly needed")
	w.quests.add_reputation(w, "greenvale", 500)
	assert_eq(w.quests.reputation_tier("greenvale"), 1)
	assert_eq(w.buy_from_vendor("greenvale_store", "trowel", 1), "")
	assert_eq(w.held_totals(), w.ledger_totals())


func test_reputation_character_joins_at_tier() -> void:
	var w := new_world()
	assert_false(w.characters.has("hulda_ironbraid"))
	w.quests.add_reputation(w, "irondeep", 1500)
	assert_true(w.characters.has("hulda_ironbraid"), "Honored with Irondeep recruits Hulda")


func test_repeatable_contract_has_cooldown() -> void:
	var w := new_world()
	var qid := ""
	for id in w.registry.quest_order:
		if bool(w.registry.quests[id].get("repeatable", false)) and w.registry.quests[id].get("prerequisites", []).is_empty():
			qid = id
			break
	if qid.is_empty():
		for id in w.registry.quest_order:
			if bool(w.registry.quests[id].get("repeatable", false)):
				qid = id
				break
	assert_ne(qid, "")
	w.quests.active[qid] = {"baseline": {}, "started": 0.0}
	w.quests.cooldowns.clear()
	# Force completion by marking it claimed through the internal path.
	w.quests.active.erase(qid)
	w.quests.completed[qid] = 1
	w.quests.cooldowns[qid] = w.sim_time + 100.0
	assert_false(w.quests.is_available(w, qid), "on cooldown")
	w.sim_time += 101.0
	assert_eq(w.quests.is_available(w, qid), Objectives.all_met(w, w.registry.quests[qid].get("prerequisites", [])))


# --- Mailbox --------------------------------------------------------------------

func test_rewards_overflow_into_the_mailbox() -> void:
	var w := new_world()
	w.storage.max_distinct = maxi(w.storage.distinct_count(), 1)
	if w.storage.distinct_count() == 0:
		w.storage.add("copper_ore", 1)
		w.record_source("copper_ore", 1, "test")
	w.grant_rewards({"items": {"ancient_coin": 3}}, [], "test")
	assert_eq(int(w.mailbox.get("ancient_coin", 0)), 3, "nothing destroyed")
	assert_eq(w.held_totals(), w.ledger_totals())
	w.storage.max_distinct += 5
	assert_eq(w.claim_mailbox(), 3)
	assert_eq(w.storage.get_quantity("ancient_coin"), 3)
	assert_true(w.mailbox.is_empty())


# --- Save -------------------------------------------------------------------------

func test_phase3_state_survives_save_and_load() -> void:
	var w := new_world()
	w._set_region_unlocked("irondeep")
	w.exploration.reveal(Vector2i(10, 10), 5)
	w.exploration.mark_discovered("old_watchtower", 5.0, "x")
	w.quests.add_reputation(w, "greenvale", 600)
	w.reveal_secret("irondeep_tunnel")
	w.mailbox["iron_ore"] = 4
	w.advance(30.0, 0.5)
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_true(w2.is_region_unlocked("irondeep"))
	assert_true(w2.grid.is_walkable(Vector2i(64, 25)), "gate reopened on load")
	assert_true(w2.exploration.is_revealed(Vector2i(10, 10)))
	assert_almost(w2.exploration.explored_pct("greenvale"), w.exploration.explored_pct("greenvale"))
	assert_true(w2.exploration.is_discovered("old_watchtower"))
	assert_eq(w2.quests.reputation_tier("greenvale"), 1)
	assert_true(w2.grid.is_walkable(w.secrets["irondeep_tunnel"].tiles[0]))
	assert_eq(int(w2.mailbox.get("iron_ore", 0)), 4)


func test_survey_reveals_more_than_walking_and_speeds_up_with_level() -> void:
	var w := new_world()
	var ch := _first(w)
	var a := w.exploration.nearest_hidden("greenvale", Vector2i(0, 0), {}, w.grid)
	var b := w.exploration.nearest_hidden("greenvale", Vector2i(63, 47), {}, w.grid)
	assert_true(WorldGrid.chebyshev(a, b) > 12, "two separate hidden spots")
	var walk := w.exploration.reveal(a, int(w.registry.get_config("exploration.walk_reveal_radius", 1)))
	ch.tile = b
	var survey := w.survey(ch)
	assert_gt(survey, walk * 3, "a survey lifts a much wider circle than a step")
	var slow := ExplorationHandler.survey_seconds(w, ch)
	ch.skills.set_level("exploration", 60)
	ch.invalidate_stats()
	assert_gt(slow, ExplorationHandler.survey_seconds(w, ch))
