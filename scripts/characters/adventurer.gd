class_name Adventurer
extends RefCounted
## Runtime state of one recruited character. Persistent fields are
## serialised by to_dict(); everything about presentation (sprites,
## animation) lives in CharacterView and is derived from this state.
##
## All gameplay numbers come from stat(): a StatBlock that folds together
## affinities, passive, traits, specializations, star rank, equipment and
## account-wide effects (AccountEffects: buildings, relics, pets). The block is cached and
## rebuilt only when one of those sources changes.

const S := CharacterStates.State
const SLOTS := ["weapon", "head", "body", "legs", "gloves", "boots", "accessory_1", "accessory_2", "tool"]

enum TravelPurpose { NONE, TO_NODE, TO_STORAGE, TO_TARGET }

var id := ""
var definition := {}
var display_name := ""
var rarity := "common"
var registry: DataRegistry

var tile := Vector2i.ZERO
var facing := Vector2i.DOWN
var skills: SkillSet
var character_xp := 0.0
var inventory: Inventory
var health := 100.0

# --- Progression ----------------------------------------------------------
var stars := 1
var traits: Array[String] = []
var specializations: Array[String] = []
## slot -> {uid, item_id, durability, upgrade}
var equipment := {}
## name -> {slot: item_id}
var loadouts := {}

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
var target_enemy_id := ""
var target_station_id := ""
var target_tile := Vector2i.ZERO
var target_adjacent := true
var wait_remaining := 0.0
var path_failures := 0
var unreachable_until := {}  # target id -> sim_time
var status_message := ""
var attack_timer := 0.0
var injured_remaining := 0.0

## Lifetime counters (also used to build offline reports).
var stats := {"gathered": {}, "deposited": {}, "crafted": {}, "kills": {}, "trips": 0, "actions": 0, "interruptions": 0, "damage_dealt": 0, "deaths": 0}

var _stat_cache: StatBlock
var _stat_cache_key := -1
var _own_version := 0
var account: AccountEffects
var _stat_memo := {}


static func create(def: Dictionary, p_registry: DataRegistry) -> Adventurer:
	var a := Adventurer.new()
	a.registry = p_registry
	a.id = String(def.get("id", ""))
	a.definition = def
	a.display_name = String(def.get("name", a.id))
	a.rarity = String(def.get("rarity", "common"))
	a.skills = SkillSet.new(p_registry.skill_xp_table)
	for skill_id in def.get("starting_skills", {}):
		a.skills.set_level(skill_id, int(def.starting_skills[skill_id]))
	a.inventory = Inventory.new(int(def.get("base_stats", {}).get("carry_capacity", 28)))
	a.refresh_capacity()
	a.health = a.max_health()
	return a


# ==========================================================================
# Stats
# ==========================================================================

func invalidate_stats() -> void:
	_own_version += 1


func stat_block() -> StatBlock:
	var acct: StatBlock = account.current() if account else null
	var acct_version := account.version if account else 0
	var key := _own_version * 100003 + acct_version
	if _stat_cache != null and key == _stat_cache_key:
		return _stat_cache
	_stat_memo.clear()
	var sb := registry.new_stat_block()
	for skill_id in definition.get("affinities", {}):
		var aff: Dictionary = definition.affinities[skill_id]
		sb.apply({"gather_speed." + skill_id: float(aff.get("speed", 1.0)), "xp." + skill_id: float(aff.get("xp", 1.0))})
		sb.apply({"craft_speed." + skill_id: float(aff.get("speed", 1.0))})
	sb.apply(definition.get("passive", {}).get("effects", {}))
	for t in traits:
		sb.apply(registry.traits.get(t, {}).get("effects", {}))
	for sp in specializations:
		sb.apply(registry.specializations.get(sp, {}).get("effects", {}))
	if stars > 1:
		sb.apply(registry.get_config("progression.star_effects_per_star", {}), float(stars - 1))
	var bonus_per_upgrade := float(registry.get_config("equipment.upgrade_stat_bonus_per_level", 0.1))
	for slot in equipment:
		var inst: Dictionary = equipment[slot]
		if int(inst.get("durability", 0)) <= 0:
			continue  # broken items give no stats
		var item: Dictionary = registry.items.get(inst.get("item_id", ""), {})
		var up := int(inst.get("upgrade", 0))
		for k in item.get("stats", {}):
			var v := float(item.stats[k])
			if sb.combine_of(k) == "add":
				v *= 1.0 + bonus_per_upgrade * up
			else:
				v = 1.0 + (v - 1.0) * (1.0 + bonus_per_upgrade * up)
			sb.apply({k: v})
	if acct:
		sb = sb.merged_with(acct)
	_stat_cache = sb
	_stat_cache_key = key
	return sb


func stat(family: String, skill := "") -> float:
	var sb := stat_block()
	var k := family + "|" + skill
	var v: Variant = _stat_memo.get(k)
	if v == null:
		v = sb.get_stat(family, skill)
		_stat_memo[k] = v
	return v


func refresh_capacity() -> void:
	var base := int(definition.get("base_stats", {}).get("carry_capacity", 28))
	inventory.max_units = base + int(stat("carry_capacity"))


func move_speed_tiles() -> float:
	return maxf(float(definition.get("base_stats", {}).get("move_speed_tiles", 3.0)) * stat("move_speed"), 0.5)


## Multiplier on gathering speed: stats * (0.5% per level above the
## requirement, max +40%). Tunables live in docs/BALANCE.md.
const LEVEL_SPEED_PER_LEVEL := 0.005
const LEVEL_SPEED_CAP := 0.4


func gather_speed_multiplier(skill_id: String, required_level: int, is_night := false) -> float:
	var over := maxi(skills.get_level(skill_id) - required_level, 0)
	var m := stat("gather_speed", skill_id) * (1.0 + minf(over * LEVEL_SPEED_PER_LEVEL, LEVEL_SPEED_CAP))
	if is_night:
		m *= stat("night_gather_speed")
	return m


func craft_speed_multiplier(skill_id: String, required_level: int) -> float:
	var over := maxi(skills.get_level(skill_id) - required_level, 0)
	return stat("craft_speed", skill_id) * (1.0 + minf(over * LEVEL_SPEED_PER_LEVEL, LEVEL_SPEED_CAP))


func xp_multiplier(skill_id: String) -> float:
	return stat("xp", skill_id)


func rare_drop_multiplier(skill_id: String) -> float:
	return stat("rare_drop", skill_id)


func character_level(_registry: DataRegistry = null) -> int:
	return registry.character_xp_table.level_for_xp(character_xp)


func max_health() -> float:
	var base := float(definition.get("base_stats", {}).get("health", 100))
	base += float(registry.get_config("combat.health_per_character_level", 2)) * (character_level() - 1)
	base += float(registry.get_config("combat.health_per_defense_level", 1)) * (skills.get_level("defense") - 1)
	return maxf(base + stat("max_health"), 1.0)


func combat_style() -> String:
	var w: Dictionary = equipment.get("weapon", {})
	if int(w.get("durability", 0)) > 0:
		var item: Dictionary = registry.items.get(w.get("item_id", ""), {})
		if item.has("combat_style"):
			return String(item.combat_style)
	return String(definition.get("combat_style", "melee"))


func combat_level() -> int:
	var style := combat_style()
	var off := skills.get_level("attack") + skills.get_level("strength") if style == "melee" else skills.get_level(style) * 2
	return int((off + skills.get_level("defense") * 2) / 4.0) + 1


# ==========================================================================
# Misc
# ==========================================================================

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


func equipped_item_id(slot: String) -> String:
	return String(equipment.get(slot, {}).get("item_id", ""))


# ==========================================================================
# Persistence
# ==========================================================================

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
		"health": health,
		"stars": stars,
		"traits": Array(traits),
		"specializations": Array(specializations),
		"equipment": equipment.duplicate(true),
		"loadouts": loadouts.duplicate(true),
		"state": CharacterStates.name_of(state),
		"assignment": assignment.to_dict() if assignment else null,
		"travel_purpose": TravelPurpose.keys()[travel_purpose],
		"path": p,
		"path_index": path_index,
		"move_progress": move_progress,
		"action_elapsed": action_elapsed,
		"target_node_id": target_node_id,
		"target_enemy_id": target_enemy_id,
		"target_station_id": target_station_id,
		"target_tile": [target_tile.x, target_tile.y],
		"target_adjacent": target_adjacent,
		"wait_remaining": wait_remaining,
		"path_failures": path_failures,
		"status_message": status_message,
		"attack_timer": attack_timer,
		"injured_remaining": injured_remaining,
		"stats": stats.duplicate(true),
	}


func load_dict(d: Dictionary) -> void:
	tile = JsonData.to_vec2i(d.get("tile"), tile)
	facing = JsonData.to_vec2i(d.get("facing"), Vector2i.DOWN)
	skills.load_dict(d.get("skills", {}))
	character_xp = maxf(float(d.get("character_xp", 0.0)), 0.0)
	stars = clampi(int(d.get("stars", 1)), 1, int(registry.get_config("progression.max_stars", 6)))
	traits.clear()
	for t in d.get("traits", []):
		if registry.traits.has(t) and not traits.has(String(t)):
			traits.append(String(t))
	specializations.clear()
	for sp in d.get("specializations", []):
		if registry.specializations.has(sp) and not specializations.has(String(sp)):
			specializations.append(String(sp))
	equipment.clear()
	var eq: Variant = d.get("equipment", {})
	if eq is Dictionary:
		for slot in eq:
			var inst: Variant = eq[slot]
			if SLOTS.has(slot) and inst is Dictionary and registry.items.has(inst.get("item_id", "")):
				var item: Dictionary = registry.items[inst.item_id]
				equipment[String(slot)] = {
					"uid": int(inst.get("uid", 0)), "item_id": String(inst.item_id),
					"durability": clampi(int(inst.get("durability", 0)), 0, int(item.get("max_durability", 1))),
					"upgrade": clampi(int(inst.get("upgrade", 0)), 0, 5)}
	var lo: Variant = d.get("loadouts", {})
	if lo is Dictionary:
		loadouts = lo.duplicate(true)
	invalidate_stats()
	inventory.load_dict(d.get("inventory", {}))
	refresh_capacity()  # capacity comes from data + stats, not from the save
	health = clampf(float(d.get("health", max_health())), 0.0, max_health())
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
	target_enemy_id = String(d.get("target_enemy_id", ""))
	target_station_id = String(d.get("target_station_id", ""))
	target_tile = JsonData.to_vec2i(d.get("target_tile"), Vector2i.ZERO)
	target_adjacent = bool(d.get("target_adjacent", true))
	wait_remaining = float(d.get("wait_remaining", 0.0))
	path_failures = int(d.get("path_failures", 0))
	status_message = String(d.get("status_message", ""))
	attack_timer = maxf(float(d.get("attack_timer", 0.0)), 0.0)
	injured_remaining = maxf(float(d.get("injured_remaining", 0.0)), 0.0)
	var st: Variant = d.get("stats")
	if st is Dictionary:
		stats.merge(st, true)
	for k in ["gathered", "deposited", "crafted", "kills"]:
		if not (stats.get(k) is Dictionary):
			stats[k] = {}
	if assignment == null and is_busy() and state != S.INJURED and state != S.RESTING:
		state = S.IDLE
