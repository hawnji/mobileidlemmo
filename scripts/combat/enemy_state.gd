class_name EnemyState
extends RefCounted
## One enemy spawn point in the world. Enemies stand on a fixed tile (they
## block movement like resource nodes) and respawn after being killed. A
## spawn can roll a variant (Champion, Elite, ... Legendary) that multiplies
## its stats, XP, gold and loot rolls.

var id := ""
var enemy_id := ""
var def := {}
var tile := Vector2i.ZERO
var variant := ""  # "" = normal
var variant_def := {}
var health := 0.0
var max_health := 1.0
var respawn_remaining := 0.0
var engaged_by := ""
var attack_timer := 0.0


static func create(p_id: String, p_def: Dictionary, p_tile: Vector2i) -> EnemyState:
	var e := EnemyState.new()
	e.id = p_id
	e.enemy_id = String(p_def.get("id", ""))
	e.def = p_def
	e.tile = p_tile
	e.max_health = float(p_def.get("health", 1))
	e.health = e.max_health
	return e


func is_alive() -> bool:
	return respawn_remaining <= 0.0 and health > 0.0


func is_available_for(character_id: String) -> bool:
	return is_alive() and (engaged_by.is_empty() or engaged_by == character_id)


func stat_multiplier() -> float:
	return float(variant_def.get("stat_multiplier", 1.0))


func level() -> int:
	return int(round(int(def.get("level", 1)) * stat_multiplier()))


func display_name() -> String:
	var n := String(def.get("name", enemy_id))
	return n if variant.is_empty() else "%s %s" % [variant_def.get("name", variant), n]


## (Re)spawns at full health, rolling a variant from the data table.
func spawn(rng: RandomNumberGenerator, variants: Array) -> void:
	variant = ""
	variant_def = {}
	var r := rng.randf()
	var acc := 0.0
	for v in variants:
		acc += float(v.get("chance", 0.0))
		if r < acc:
			variant = String(v.id)
			variant_def = v
			break
	max_health = float(def.get("health", 1)) * stat_multiplier()
	health = max_health
	respawn_remaining = 0.0
	attack_timer = 0.0


func kill() -> void:
	health = 0.0
	engaged_by = ""
	respawn_remaining = maxf(float(def.get("respawn_seconds", 20)), 0.1)


func disengage(character_id: String) -> void:
	if engaged_by == character_id:
		engaged_by = ""
		attack_timer = 0.0
		if is_alive():
			health = max_health  # enemies recover once left alone


## Returns true when the enemy finishes respawning this tick.
func tick(dt: float) -> bool:
	if respawn_remaining <= 0.0:
		return false
	respawn_remaining -= dt
	return respawn_remaining <= 0.0


func to_dict() -> Dictionary:
	return {"variant": variant, "health": health, "respawn_remaining": respawn_remaining,
		"engaged_by": engaged_by, "attack_timer": attack_timer}


func load_dict(d: Dictionary, variants: Array) -> void:
	variant = String(d.get("variant", ""))
	variant_def = {}
	for v in variants:
		if String(v.id) == variant:
			variant_def = v
	if variant_def.is_empty():
		variant = ""
	max_health = float(def.get("health", 1)) * stat_multiplier()
	health = clampf(float(d.get("health", max_health)), 0.0, max_health)
	respawn_remaining = maxf(float(d.get("respawn_remaining", 0.0)), 0.0)
	engaged_by = String(d.get("engaged_by", ""))
	attack_timer = maxf(float(d.get("attack_timer", 0.0)), 0.0)
	if respawn_remaining <= 0.0 and health <= 0.0:
		health = max_health
