extends WbTestCase
## Combat: hunt, kill, loot, gold, XP, eating, retreating, injury, respawn.

const S := CharacterStates.State


func _hunt(w: SimulationWorld, cid: String, activity: String) -> Assignment:
	var a := make_assignment(w, cid, activity)
	return a


func test_hunting_meadows_kills_and_loots() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["brom_stonefist"]
	var gold := w.wallet.get_balance("gold")
	assert_eq(w.assign_activity("brom_stonefist", _hunt(w, "brom_stonefist", "hunt_meadows")), "")
	var saw_combat := {"v": false}
	w.event_emitted.connect(func(ev): if ev.type == "state_changed" and ev.character_id == "brom_stonefist" and ev.to == S.COMBAT: saw_combat.v = true)
	w.advance(900.0, 0.1)
	assert_true(saw_combat.v)
	var kills := 0
	for k in ch.stats.kills:
		kills += int(ch.stats.kills[k])
	assert_gte(kills, 10)
	assert_gt(w.wallet.get_balance("gold"), gold, "gold from kills")
	assert_gt(ch.skills.get_xp("hunting"), 0.0)
	assert_gt(ch.skills.get_xp("attack") + ch.skills.get_xp("strength"), 0.0)
	assert_gt(w.storage.get_quantity("slime_gel") + w.storage.get_quantity("bones") + ch.inventory.get_quantity("bones"), 0)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_killed_enemies_respawn() -> void:
	var w := new_world()
	var e: EnemyState = w.enemies["slime_1"]
	w.mark_enemy_dead(e)
	assert_false(e.is_alive())
	w.advance(float(e.def.respawn_seconds) + 0.5, 0.5)
	assert_true(e.is_alive())
	assert_almost(e.health, e.max_health)


func test_variant_multiplies_stats() -> void:
	var w := new_world()
	var e: EnemyState = w.enemies["wolf_1"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var variants := [{"id": "elite", "name": "Elite", "chance": 1.0, "stat_multiplier": 1.8, "xp_multiplier": 2.2, "loot_rolls": 3, "gold_multiplier": 3.0}]
	e.spawn(rng, variants)
	assert_eq(e.variant, "elite")
	assert_almost(e.max_health, 22 * 1.8)
	assert_eq(e.display_name(), "Elite Wolf")
	assert_eq(CombatRules.enemy_max_hit(e), 7)


func test_eats_food_when_hurt() -> void:
	var w := new_world()
	w.storage.add("cooked_minnow", 20)
	w.record_source("cooked_minnow", 20, "test")
	var ch: Adventurer = w.characters["tamsin_reed"]
	var a := _hunt(w, "tamsin_reed", "hunt_wolves")
	a.heal_threshold = 0.9
	a.food_supply = 10
	ch.health = ch.max_health() * 0.5
	assert_eq(w.assign_activity("tamsin_reed", a), "")
	var eaten := {"v": 0}
	w.event_emitted.connect(func(ev): if ev.type == "food_eaten": eaten.v += 1)
	w.advance(300.0, 0.1)
	assert_gt(eaten.v, 0)
	_assert_conserved(w)


func _assert_conserved(w: SimulationWorld) -> void:
	assert_eq(w.held_totals(), w.ledger_totals(), "eaten food recorded as a sink")


func test_weak_character_is_injured_then_recovers() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var a := _hunt(w, "tamsin_reed", "slay_troll")
	a.food_supply = 0
	a.safety.return_below_health_ratio = 0.0  # fight to the end
	assert_eq(w.assign_activity("tamsin_reed", a), "")
	var injured := {"v": false}
	w.event_emitted.connect(func(ev): if ev.type == "character_injured": injured.v = true)
	var t := 0.0
	while t < 900.0 and not injured.v:
		w.step(0.5)
		t += 0.5
	assert_true(injured.v, "a level-1 adventurer loses to a level-25 troll")
	assert_eq(ch.state, S.INJURED)
	assert_lte(WorldGrid.chebyshev(ch.tile, w.storage_tile), 6, "carried back to the village")
	assert_true(w.enemies["forest_troll_1"].engaged_by.is_empty(), "troll released")
	w.advance(float(w.registry.get_config("combat.injury_seconds", 60.0)) + 1.0, 0.5)
	assert_eq(ch.state, S.RESTING)
	w.advance(60.0, 0.5)
	assert_ne(ch.state, S.RESTING, "rested back to full and resumed")
	assert_gte(int(ch.stats.deaths), 1)


func test_retreats_when_low_without_food() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters["tamsin_reed"]
	var a := _hunt(w, "tamsin_reed", "raid_goblins")
	a.food_supply = 0
	a.safety.return_below_health_ratio = 0.6
	assert_eq(w.assign_activity("tamsin_reed", a), "")
	var rested := {"v": false}
	var injured := {"v": false}
	w.event_emitted.connect(func(ev):
		if ev.get("character_id", "") == "tamsin_reed":
			if ev.type == "state_changed" and ev.to == S.RESTING: rested.v = true
			if ev.type == "character_injured": injured.v = true)
	w.advance(1200.0, 0.2)
	assert_true(rested.v, "went home to rest")
	assert_false(injured.v, "retreated before being defeated")


func test_combat_independent_of_step_size() -> void:
	var a := new_world(777)
	var b := new_world(777)
	for w in [a, b]:
		w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "hunt_meadows"))
	a.advance(600.0, 0.1)
	b.advance(600.0, 1.0)
	var ka: Dictionary = a.characters["brom_stonefist"].stats.kills
	var kb: Dictionary = b.characters["brom_stonefist"].stats.kills
	var na := 0
	var nb := 0
	for k in ka: na += int(ka[k])
	for k in kb: nb += int(kb[k])
	assert_almost(float(nb), float(na), maxf(2.0, na * 0.1), "kills with 1 s steps close to 0.1 s steps")


func test_avoid_enemies_above_level() -> void:
	var w := new_world()
	var a := _hunt(w, "brom_stonefist", "raid_goblins")
	a.safety.avoid_enemies_above_level = 6
	w.assign_activity("brom_stonefist", a)
	w.advance(400.0, 0.2)
	var kills: Dictionary = w.characters["brom_stonefist"].stats.kills
	assert_false(kills.has("goblin_archer"))
	assert_false(kills.has("goblin_warrior"))
	assert_true(kills.has("goblin"))


func test_combat_state_survives_save_load() -> void:
	var w := new_world()
	w.assign_activity("brom_stonefist", make_assignment(w, "brom_stonefist", "hunt_meadows"))
	w.advance(200.0, 0.1)
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var w2 := SimulationWorld.from_dict(registry(), d)
	for sid in w.enemy_order:
		assert_eq(w2.enemies[sid].engaged_by, w.enemies[sid].engaged_by, sid)
		assert_eq(w2.enemies[sid].is_alive(), w.enemies[sid].is_alive(), sid)
	w2.advance(200.0, 0.1)
	assert_eq(w2.held_totals(), w2.ledger_totals())
