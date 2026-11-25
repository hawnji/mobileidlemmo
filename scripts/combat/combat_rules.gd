class_name CombatRules
extends RefCounted
## Pure combat formulas. All tunables come from game_config.json "combat"
## and from enemy / item data. Kept static and side-effect free so they can
## be unit tested and reused by the estimator and (later) the server.


static func offense_skill(style: String) -> String:
	match style:
		"ranged": return "ranged"
		"magic": return "magic"
	return "attack"


static func power_skill(style: String) -> String:
	match style:
		"ranged": return "ranged"
		"magic": return "magic"
	return "strength"


static func attack_interval(ch: Adventurer, registry: DataRegistry) -> float:
	var w: Dictionary = ch.equipment.get("weapon", {})
	if int(w.get("durability", 0)) > 0:
		var item: Dictionary = registry.items.get(w.get("item_id", ""), {})
		if item.has("attack_speed"):
			return maxf(float(item.attack_speed), 0.5)
	return float(registry.get_config("combat.default_attack_interval", 2.6))


static func player_hit_chance(ch: Adventurer, enemy: EnemyState, registry: DataRegistry) -> float:
	var style := ch.combat_style()
	var acc := ch.skills.get_level(offense_skill(style)) + ch.stat("accuracy")
	var def := float(enemy.def.get("defense", 1)) * enemy.stat_multiplier()
	var c := float(registry.get_config("combat.base_hit_chance", 0.55)) \
		+ (acc - def) * float(registry.get_config("combat.accuracy_step", 0.02))
	return clampf(c, float(registry.get_config("combat.min_hit_chance", 0.15)), float(registry.get_config("combat.max_hit_chance", 0.95)))


static func player_max_hit(ch: Adventurer, enemy: EnemyState, registry: DataRegistry) -> int:
	var style := ch.combat_style()
	var base := 1.0 + ch.skills.get_level(power_skill(style)) * float(registry.get_config("combat.strength_damage_factor", 0.18)) \
		+ ch.stat("weapon_power")
	var weak := float(enemy.def.get("weaknesses", {}).get(style, 1.0)) if enemy else 1.0
	return maxi(int(floor(base * ch.stat("damage") * weak)), 1)


static func enemy_hit_chance(ch: Adventurer, enemy: EnemyState, registry: DataRegistry) -> float:
	var acc := float(enemy.def.get("accuracy", 1)) * enemy.stat_multiplier()
	var def := ch.skills.get_level("defense") + ch.stat("armor") * 0.5
	var c := float(registry.get_config("combat.enemy_base_hit_chance", 0.5)) \
		+ (acc - def) * float(registry.get_config("combat.accuracy_step", 0.02))
	return clampf(c, float(registry.get_config("combat.enemy_min_hit_chance", 0.05)), float(registry.get_config("combat.enemy_max_hit_chance", 0.9)))


static func enemy_max_hit(enemy: EnemyState) -> int:
	return maxi(int(round(float(enemy.def.get("max_hit", 1)) * enemy.stat_multiplier())), 1)


static func damage_reduction(ch: Adventurer, registry: DataRegistry) -> int:
	return int(floor(ch.stat("armor") / maxf(float(registry.get_config("combat.armor_per_damage_point", 10.0)), 1.0)))


static func enemy_attack_interval(enemy: EnemyState) -> float:
	return maxf(float(enemy.def.get("attack_speed", 2.6)), 0.5)


## Expected damage per second the character deals and takes. Used by the
## assignment estimator and by tests to sanity-check balance.
static func expected_rates(ch: Adventurer, enemy: EnemyState, registry: DataRegistry) -> Dictionary:
	var dealt := player_hit_chance(ch, enemy, registry) * (player_max_hit(ch, enemy, registry) + 1) / 2.0 / attack_interval(ch, registry)
	var emax := enemy_max_hit(enemy)
	var red := damage_reduction(ch, registry)
	var avg_taken := 0.0
	for d in range(emax + 1):
		avg_taken += maxf(d - red, 0)
	avg_taken /= float(emax + 1)
	var taken := enemy_hit_chance(ch, enemy, registry) * avg_taken / enemy_attack_interval(enemy)
	return {"dealt_per_second": dealt, "taken_per_second": taken,
		"seconds_per_kill": enemy.max_health / maxf(dealt, 0.0001)}
