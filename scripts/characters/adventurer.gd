class_name Adventurer
extends RefCounted
## Runtime state of one recruited character. Persistent fields are
## serialised by to_dict(); everything about presentation (sprites,
## animation) lives in CharacterView and is derived from this state.

const S := CharacterStates.State

enum TravelPurpose { NONE, TO_NODE, TO_STORAGE }

var id := ""
var definition := {}
var display_name := ""
var rarity := "common"

var tile := Vector2i.ZERO
var facing := Vector2i.DOWN
var skills: SkillSet
var character_xp := 0.0
var inventory: Inventory

# --- Activity state -------------------------------------------------------
var state: int = S.IDLE
var assignment: Assignment
var travel_purpose := TravelPurpose.NONE
var path: Array[Vector2i] = []
var path_index := 0
## Progress (0..1) of the step from `tile` towards path[path_index].
var move_progress := 0.0
var action_elapsed := 0.0
var target_node_id := ""
var wait_remaining := 0.0
var path_failures := 0
var unreachable_until := {}  # node_id -> sim_time
var status_message := ""

## Lifetime counters (also used to build offline reports).
var stats := {"gathered": {}, "deposited": {}, "trips": 0, "actions": 0, "interruptions": 0}


static func create(def: Dictionary, registry: DataRegistry) -> Adventurer:
	var a := Adventurer.new()
	a.id = String(def.get("id", ""))
	a.definition = def
	a.display_name = String(def.get("name", a.id))
	a.rarity = String(def.get("rarity", "common"))
	a.skills = SkillSet.new(registry.skill_xp_table)
	for skill_id in def.get("starting_skills", {}):
		a.skills.set_level(skill_id, int(def.starting_skills[skill_id]))
	var cap := int(def.get("base_stats", {}).get("carry_capacity", 28))
	a.inventory = Inventory.new(cap)
	return a


# --- Derived stats --------------------------------------------------------

func move_speed_tiles() -> float:
	return maxf(float(definition.get("base_stats", {}).get("move_speed_tiles", 3.0)), 0.5)


func _affinity(skill_id: String, key: String) -> float:
	var aff: Dictionary = definition.get("affinities", {}).get(skill_id, {})
	return float(aff.get(key, 1.0))


func _passive_effect(key: String) -> float:
	var effects: Dictionary = definition.get("passive", {}).get("effects", {})
	return float(effects.get(key, 1.0))


## Multiplier on gathering speed: affinity * (0.5% per level above the
## requirement, max +40%). Tunables live in docs/BALANCE.md.
const LEVEL_SPEED_PER_LEVEL := 0.005
const LEVEL_SPEED_CAP := 0.4


func gather_speed_multiplier(skill_id: String, required_level: int) -> float:
	var over := maxi(skills.get_level(skill_id) - required_level, 0)
	return _affinity(skill_id, "speed") * (1.0 + minf(over * LEVEL_SPEED_PER_LEVEL, LEVEL_SPEED_CAP))


func xp_multiplier(skill_id: String) -> float:
	return _affinity(skill_id, "xp") * _passive_effect("xp_multiplier.all") * _passive_effect("xp_multiplier." + skill_id)


func rare_drop_multiplier(skill_id: String) -> float:
	return _passive_effect("rare_drop_multiplier." + skill_id)


func character_level(registry: DataRegistry) -> int:
	return registry.character_xp_table.level_for_xp(character_xp)


## Interpolated world position in tile units (for rendering only).
func visual_tile_position() -> Vector2:
	var base := Vector2(tile)
	if (state == S.TRAVELING or state == S.RETURNING) and path_index < path.size():
		return base.lerp(Vector2(path[path_index]), move_progress)
	return base


func is_busy() -> bool:
	return state != S.IDLE and state != S.COMPLETED


func record(stat_key: String, item_id: String, qty: int) -> void:
	var d: Dictionary = stats[stat_key]
	d[item_id] = int(d.get(item_id, 0)) + qty


# --- Persistence ----------------------------------------------------------

func to_dict() -> Dictionary:
	var p := []
	for c in path:
		p.append([c.x, c.y])
	return {
		"id": id,
		"tile": [tile.x, tile.y],
		"facing": [facing.x, facing.y],
		"skills": skills.to_dict(),
		"character_xp": character_xp,
		"inventory": inventory.to_dict(),
		"state": CharacterStates.name_of(state),
		"assignment": assignment.to_dict() if assignment else null,
		"travel_purpose": TravelPurpose.keys()[travel_purpose],
		"path": p,
		"path_index": path_index,
		"move_progress": move_progress,
		"action_elapsed": action_elapsed,
		"target_node_id": target_node_id,
		"wait_remaining": wait_remaining,
		"path_failures": path_failures,
		"status_message": status_message,
		"stats": stats.duplicate(true),
	}


func load_dict(d: Dictionary) -> void:
	tile = JsonData.to_vec2i(d.get("tile"), tile)
	facing = JsonData.to_vec2i(d.get("facing"), Vector2i.DOWN)
	skills.load_dict(d.get("skills", {}))
	character_xp = maxf(float(d.get("character_xp", 0.0)), 0.0)
	var cap := inventory.max_units
	inventory.load_dict(d.get("inventory", {}))
	inventory.max_units = cap  # capacity comes from data, not from the save
	state = CharacterStates.from_name(String(d.get("state", "IDLE")))
	var asg: Variant = d.get("assignment")
	assignment = Assignment.from_dict(asg) if asg is Dictionary else null
	var tp := TravelPurpose.keys().find(String(d.get("travel_purpose", "NONE")))
	travel_purpose = tp if tp >= 0 else TravelPurpose.NONE
	path.clear()
	for c in d.get("path", []):
		path.append(JsonData.to_vec2i(c))
	path_index = int(d.get("path_index", 0))
	move_progress = clampf(float(d.get("move_progress", 0.0)), 0.0, 0.999)
	action_elapsed = maxf(float(d.get("action_elapsed", 0.0)), 0.0)
	target_node_id = String(d.get("target_node_id", ""))
	wait_remaining = float(d.get("wait_remaining", 0.0))
	path_failures = int(d.get("path_failures", 0))
	status_message = String(d.get("status_message", ""))
	var st: Variant = d.get("stats")
	if st is Dictionary:
		stats.merge(st, true)
	for k in ["gathered", "deposited"]:
		if not (stats[k] is Dictionary):
			stats[k] = {}
	if assignment == null and is_busy():
		state = S.IDLE
