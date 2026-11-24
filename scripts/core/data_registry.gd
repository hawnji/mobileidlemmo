class_name DataRegistry
extends RefCounted
## Loads every data-driven definition (skills, items, resource nodes,
## activities, characters, terrain, regions, config) from res://data and
## validates cross references. Gameplay code only ever reads definitions
## through this registry, so balance changes never require code changes.

const DEFAULT_ROOT := "res://data"

var root := DEFAULT_ROOT
var config := {}
var skills := {}  # id -> def
var skill_order: Array[String] = []
var items := {}
var node_types := {}
var activities := {}
var activity_order: Array[String] = []
var characters := {}
var character_order: Array[String] = []
var terrain_by_symbol := {}
var terrain_list: Array = []
var regions := {}
var skill_xp_table: XpTable
var character_xp_table: XpTable
var load_errors := PackedStringArray()

static var _default: DataRegistry


## Shared, lazily loaded registry for the default data folder. Definitions are
## read-only at runtime so sharing is safe.
static func get_default() -> DataRegistry:
	if _default == null:
		_default = DataRegistry.new()
		_default.load_from(DEFAULT_ROOT)
	return _default


func load_from(p_root: String) -> bool:
	root = p_root
	load_errors.clear()
	config = _load_dict("config/game_config.json")
	var curves := _load_dict("skills/xp_curve.json")
	skill_xp_table = XpTable.from_curve(curves.get("skill_curve", {}))
	character_xp_table = XpTable.from_curve(curves.get("character_curve", {}))
	skill_order.clear()
	for s in _load_list("skills/skills.json", "skills"):
		skills[s.id] = s
		skill_order.append(String(s.id))
	for it in _load_list("items/items.json", "items"):
		items[it.id] = it
	for nt in _load_list("resources/resource_nodes.json", "node_types"):
		node_types[nt.id] = nt
	activity_order.clear()
	for a in _load_list("activities/activities.json", "activities"):
		activities[a.id] = a
		activity_order.append(String(a.id))
	character_order.clear()
	for c in _load_list("characters/characters.json", "characters"):
		characters[c.id] = c
		character_order.append(String(c.id))
	terrain_list = _load_list("regions/terrain.json", "terrain")
	for t in terrain_list:
		terrain_by_symbol[t.symbol] = t
	var start_region := String(get_config("world.start_region", "greenvale_start"))
	var region := _load_dict("regions/%s.json" % start_region)
	if not region.is_empty():
		regions[region.id] = region
	return load_errors.is_empty()


func _load_dict(rel: String) -> Dictionary:
	var data: Variant = JsonData.load_file(root.path_join(rel))
	if data is Dictionary:
		return data
	load_errors.append("Could not load %s" % rel)
	return {}


func _load_list(rel: String, key: String) -> Array:
	var d := _load_dict(rel)
	var list: Variant = d.get(key, [])
	if list is Array:
		return list
	load_errors.append("%s: '%s' is not an array" % [rel, key])
	return []


## Dotted lookup into game_config.json, e.g. "offline.base_cap_hours".
func get_config(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = config
	for part in path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return fallback
	return node


func get_item_name(item_id: String) -> String:
	return String(items.get(item_id, {}).get("name", item_id))


## Returns a list of human-readable problems. Empty means the data is sound.
func validate() -> PackedStringArray:
	var errors := PackedStringArray(load_errors)
	if skill_order.size() != 24:
		errors.append("Expected 24 skills, found %d" % skill_order.size())
	for nt_id in node_types:
		var nt: Dictionary = node_types[nt_id]
		if not skills.has(nt.get("skill", "")):
			errors.append("Node type %s references unknown skill %s" % [nt_id, nt.get("skill")])
		var item_id := String(nt.get("yield", {}).get("item", ""))
		if not items.has(item_id):
			errors.append("Node type %s yields unknown item %s" % [nt_id, item_id])
		for rd in nt.get("rare_drops", []):
			if not items.has(rd.get("item", "")):
				errors.append("Node type %s rare drop unknown item %s" % [nt_id, rd.get("item")])
		if float(nt.get("gather_seconds", 0)) <= 0.0:
			errors.append("Node type %s needs gather_seconds > 0" % nt_id)
		if int(nt.get("charges", 0)) <= 0:
			errors.append("Node type %s needs charges > 0" % nt_id)
	for a_id in activities:
		var a: Dictionary = activities[a_id]
		if not node_types.has(a.get("node_type", "")):
			errors.append("Activity %s references unknown node type %s" % [a_id, a.get("node_type")])
		if not skills.has(a.get("skill", "")):
			errors.append("Activity %s references unknown skill %s" % [a_id, a.get("skill")])
	for c_id in characters:
		var c: Dictionary = characters[c_id]
		for s in c.get("starting_skills", {}):
			if not skills.has(s):
				errors.append("Character %s has unknown starting skill %s" % [c_id, s])
		for s in c.get("affinities", {}):
			if not skills.has(s):
				errors.append("Character %s has unknown affinity skill %s" % [c_id, s])
		if int(c.get("base_stats", {}).get("carry_capacity", 0)) <= 0:
			errors.append("Character %s needs carry_capacity > 0" % c_id)
	for r_id in regions:
		errors.append_array(_validate_region(regions[r_id]))
	return errors


func _validate_region(region: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var rows: Array = region.get("rows", [])
	var w := int(region.get("width", 0))
	if rows.size() != int(region.get("height", -1)):
		errors.append("Region %s height mismatch" % region.get("id"))
	for y in rows.size():
		var row := String(rows[y])
		if row.length() != w:
			errors.append("Region %s row %d has width %d (expected %d)" % [region.get("id"), y, row.length(), w])
		for ch in row:
			if not terrain_by_symbol.has(ch):
				errors.append("Region %s row %d uses unknown terrain '%s'" % [region.get("id"), y, ch])
				break
	var location_ids := {}
	for loc in region.get("locations", []):
		location_ids[loc.id] = true
	for a_id in activities:
		var dest := String(activities[a_id].get("default_destination", ""))
		if not dest.is_empty() and not location_ids.has(dest):
			errors.append("Activity %s destination %s not in region %s" % [a_id, dest, region.get("id")])
	for n in region.get("resource_nodes", []):
		if not node_types.has(n.get("type", "")):
			errors.append("Region node %s has unknown type %s" % [n.get("id"), n.get("type")])
	return errors
