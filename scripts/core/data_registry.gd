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
var traits := {}
var specializations := {}
var specialization_config := {}
var recipes := {}
var recipe_order: Array[String] = []
var enemies := {}
var enemy_variants: Array = []
var currencies := {}
var currency_list: Array = []
var economy_config := {}
var banners := {}
var banner_order: Array[String] = []
var recruitment_config := {}
var buildings := {}
var building_order: Array[String] = []
var town_config := {}
var stat_families := {}
# --- Phase 3: world expansion -------------------------------------------
var world_map := {}  # the connected map: rows, regions, gates, locations, ...
var map_regions := {}  # region_id -> region def (rect, unlock, outpost, ...)
var map_region_order: Array[String] = []
var abilities := {}
var ability_by_specialty := {}
var quests := {}
var quest_order: Array[String] = []
var quest_config := {}
var vendors := {}
var dungeons := {}
var dungeon_order: Array[String] = []
var expeditions := {}
var expedition_order: Array[String] = []
var expedition_config := {}
var encounter_config := {}
var notification_config := {}
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
	for t in _load_list("characters/traits.json", "traits"):
		traits[t.id] = t
	specialization_config = _load_dict("characters/specializations.json")
	for sp in specialization_config.get("specializations", []):
		specializations[sp.id] = sp
	recipe_order.clear()
	for r in _load_list("recipes/recipes.json", "recipes"):
		recipes[r.id] = r
		recipe_order.append(String(r.id))
	var en := _load_dict("enemies/enemies.json")
	for e in en.get("enemies", []):
		enemies[e.id] = e
	enemy_variants = en.get("variants", [])
	economy_config = _load_dict("economy/currencies.json")
	currency_list = economy_config.get("currencies", [])
	for c in currency_list:
		currencies[c.id] = c
	recruitment_config = _load_dict("recruitment/banners.json")
	banner_order.clear()
	for b in recruitment_config.get("banners", []):
		banners[b.id] = b
		banner_order.append(String(b.id))
	town_config = _load_dict("town/buildings.json")
	building_order.clear()
	for b in town_config.get("buildings", []):
		buildings[b.id] = b
		building_order.append(String(b.id))
	stat_families = _load_dict("config/stats.json").get("families", {})
	var map_id := String(get_config("world.map", "world_map"))
	world_map = _load_dict("regions/%s.json" % map_id)
	if not world_map.is_empty():
		regions[world_map.id] = world_map
	map_region_order.clear()
	for r in world_map.get("regions", []):
		map_regions[r.id] = r
		map_region_order.append(String(r.id))
	var ab := _load_dict("characters/abilities.json")
	for a in ab.get("abilities", []):
		abilities[a.id] = a
	ability_by_specialty = ab.get("by_specialty", {})
	quest_config = _load_dict("quests/quests.json")
	quest_order.clear()
	for q in quest_config.get("quests", []):
		quests[q.id] = q
		quest_order.append(String(q.id))
	for v in _load_list("economy/vendors.json", "vendors"):
		vendors[v.id] = v
	dungeon_order.clear()
	for d in _load_list("dungeons/dungeons.json", "dungeons"):
		dungeons[d.id] = d
		dungeon_order.append(String(d.id))
	expedition_config = _load_dict("expeditions/expeditions.json")
	expedition_order.clear()
	for e in expedition_config.get("expeditions", []):
		expeditions[e.id] = e
		expedition_order.append(String(e.id))
	encounter_config = _load_dict("world/encounters.json")
	notification_config = _load_dict("config/notifications.json")
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


func new_stat_block() -> StatBlock:
	return StatBlock.new(stat_families)


func recipes_for_station(station: String) -> Array[String]:
	var out: Array[String] = []
	for rid in recipe_order:
		if String(recipes[rid].station) == station:
			out.append(rid)
	return out


func characters_by_acquisition(kind: String) -> Array[String]:
	var out: Array[String] = []
	for cid in character_order:
		if String(characters[cid].get("acquisition", "gacha")) == kind:
			out.append(cid)
	return out


## The active ability of a character: explicit in data, else by combat specialty.
func ability_for(character_def: Dictionary) -> Dictionary:
	var aid := String(character_def.get("active_ability", ""))
	if aid.is_empty():
		aid = String(ability_by_specialty.get(character_def.get("combat_specialty", "warrior"), ""))
	return abilities.get(aid, {})


func region_name(region_id: String) -> String:
	return String(map_regions.get(region_id, {}).get("name", region_id))


func reputation_tiers() -> Array:
	return quest_config.get("reputation", {}).get("tiers", [{"name": "Neutral", "points": 0}])


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
		if String(a.get("type", "gathering")) == "gathering" and not node_types.has(a.get("node_type", "")):
			errors.append("Activity %s references unknown node type %s" % [a_id, a.get("node_type")])
		if not ["combat", "construction"].has(String(a.get("type", "gathering"))) and not skills.has(a.get("skill", "")):
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
	for a_id in activities:
		var a: Dictionary = activities[a_id]
		match String(a.get("type", "gathering")):
			"crafting":
				if recipes_for_station(String(a.get("station", ""))).is_empty():
					errors.append("Crafting activity %s has no recipes for station %s" % [a_id, a.get("station")])
	for r_id in recipes:
		var r: Dictionary = recipes[r_id]
		if not skills.has(r.get("skill", "")):
			errors.append("Recipe %s unknown skill" % r_id)
		for k in r.get("inputs", {}):
			if not items.has(k):
				errors.append("Recipe %s unknown input %s" % [r_id, k])
		for k in r.get("outputs", {}):
			if not items.has(k):
				errors.append("Recipe %s unknown output %s" % [r_id, k])
		if r.has("burn") and not items.has(r.burn.get("item", "")):
			errors.append("Recipe %s unknown burn item" % r_id)
		for b in r.get("requires_building", {}):
			if not buildings.has(b):
				errors.append("Recipe %s requires unknown building %s" % [r_id, b])
	for e_id in enemies:
		for l in enemies[e_id].get("loot", []):
			if not items.has(l.get("item", "")):
				errors.append("Enemy %s loot unknown item %s" % [e_id, l.get("item")])
	for i_id in items:
		var it: Dictionary = items[i_id]
		if it.get("category") == "equipment":
			if not ["weapon", "head", "body", "legs", "gloves", "boots", "accessory", "tool"].has(it.get("equip_slot", "")):
				errors.append("Item %s has invalid equip_slot" % i_id)
			for k in it.get("stats", {}):
				if not stat_families.has(String(k).get_slice(".", 0)):
					errors.append("Item %s unknown stat family %s" % [i_id, k])
	for c_id in characters:
		var c: Dictionary = characters[c_id]
		for t in c.get("traits", []):
			if not traits.has(t):
				errors.append("Character %s unknown trait %s" % [c_id, t])
		for k in c.get("passive", {}).get("effects", {}):
			if not stat_families.has(String(k).get_slice(".", 0)):
				errors.append("Character %s passive unknown stat family %s" % [c_id, k])
		if not recruitment_config.get("rarity_order", []).has(c.get("rarity", "")):
			errors.append("Character %s invalid rarity" % c_id)
	for b_id in banners:
		var b: Dictionary = banners[b_id]
		var total := 0.0
		for r in b.get("rates", {}):
			total += float(b.rates[r])
		if absf(total - 1.0) > 0.0001:
			errors.append("Banner %s rates sum to %f" % [b_id, total])
		for c in b.get("costs", {}):
			if not currencies.has(c):
				errors.append("Banner %s unknown currency %s" % [b_id, c])
		var feat: Variant = b.get("featured")
		if feat is Dictionary and not characters.has(feat.get("character_id", "")):
			errors.append("Banner %s featured unknown character" % b_id)
	for b_id in buildings:
		for lv in buildings[b_id].get("levels", []):
			for k in lv.get("cost", {}).get("items", {}):
				if not items.has(k):
					errors.append("Building %s cost unknown item %s" % [b_id, k])
			for k in lv.get("effects", {}):
				if not stat_families.has(String(k).get_slice(".", 0)):
					errors.append("Building %s unknown effect %s" % [b_id, k])
	for r_id in regions:
		errors.append_array(_validate_region(regions[r_id]))
	errors.append_array(_validate_phase3())
	return errors


func _validate_phase3() -> PackedStringArray:
	var errors := PackedStringArray()
	for c_id in characters:
		if ability_for(characters[c_id]).is_empty():
			errors.append("Character %s has no active ability" % c_id)
	for e_id in enemies:
		var b: Variant = enemies[e_id].get("boss")
		if b is Dictionary:
			for ab in b.get("abilities", []):
				if String(ab.get("kind", "")) == "summon" and not enemies.has(ab.get("enemy", "")):
					errors.append("Boss %s summons unknown enemy %s" % [e_id, ab.get("enemy")])
	for d_id in dungeons:
		var d: Dictionary = dungeons[d_id]
		if not enemies.has(d.get("boss", "")):
			errors.append("Dungeon %s unknown boss" % d_id)
		if not map_regions.has(d.get("region", "")):
			errors.append("Dungeon %s unknown region" % d_id)
		for f in d.get("floors", []):
			for e in f.get("enemies", []):
				if not enemies.has(e):
					errors.append("Dungeon %s unknown enemy %s" % [d_id, e])
		var found := false
		for de in world_map.get("dungeon_entrances", []):
			if de.id == d_id:
				found = true
		if not found:
			errors.append("Dungeon %s has no entrance on the map" % d_id)
	for x_id in expeditions:
		var x: Dictionary = expeditions[x_id]
		if not map_regions.has(x.get("region", "")):
			errors.append("Expedition %s unknown region" % x_id)
		for it in x.get("rewards", {}).get("items", []):
			if not items.has(it.get("item", "")):
				errors.append("Expedition %s unknown reward item %s" % [x_id, it.get("item")])
		for s in x.get("rewards", {}).get("xp", {}):
			if not skills.has(s):
				errors.append("Expedition %s unknown xp skill %s" % [x_id, s])
	for q_id in quests:
		var q: Dictionary = quests[q_id]
		for o in q.get("objectives", []) + q.get("prerequisites", []):
			var t := String(o.get("type", ""))
			if not Objectives.KNOWN_TYPES.has(t):
				errors.append("Quest %s unknown objective type %s" % [q_id, t])
			if o.has("item") and not items.has(o.item):
				errors.append("Quest %s unknown item %s" % [q_id, o.item])
			if o.has("enemy") and not enemies.has(o.enemy):
				errors.append("Quest %s unknown enemy %s" % [q_id, o.enemy])
			if o.has("quest") and not quests.has(o.quest):
				errors.append("Quest %s unknown prerequisite quest %s" % [q_id, o.quest])
			if o.has("dungeon") and not dungeons.has(o.dungeon):
				errors.append("Quest %s unknown dungeon %s" % [q_id, o.dungeon])
			if o.has("building") and not buildings.has(o.building):
				errors.append("Quest %s unknown building %s" % [q_id, o.building])
		var ch := String(q.get("rewards", {}).get("character", ""))
		if not ch.is_empty() and not characters.has(ch):
			errors.append("Quest %s rewards unknown character %s" % [q_id, ch])
	for v_id in vendors:
		for s in vendors[v_id].get("stock", []):
			if not items.has(s.get("item", "")):
				errors.append("Vendor %s unknown item %s" % [v_id, s.get("item")])
	for enc in encounter_config.get("encounters", []):
		if enc.has("enemy") and not enemies.has(enc.enemy):
			errors.append("Encounter %s unknown enemy" % enc.get("id"))
		for s in enc.get("stock", []):
			if not items.has(s.get("item", "")):
				errors.append("Encounter %s unknown item %s" % [enc.get("id"), s.get("item")])
	var disc_ids := {}
	for d in world_map.get("discoveries", []):
		disc_ids[d.id] = true
		var rw: Dictionary = d.get("rewards", {})
		for it in rw.get("items", {}):
			if not items.has(it):
				errors.append("Discovery %s unknown item %s" % [d.id, it])
		if rw.has("character") and not characters.has(rw.character):
			errors.append("Discovery %s unknown character" % d.id)
	for q_id in quests:
		for o in quests[q_id].get("objectives", []):
			if o.get("type") == "discover" and not disc_ids.has(o.get("discovery", "")):
				errors.append("Quest %s unknown discovery %s" % [q_id, o.get("discovery")])
	for r_id in recipes:
		for reg in recipes[r_id].get("requires_reputation", {}):
			if not map_regions.has(reg):
				errors.append("Recipe %s requires reputation in unknown region %s" % [r_id, reg])
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
		var ar := String(activities[a_id].get("region", ""))
		if not ar.is_empty() and not map_regions.has(ar):
			errors.append("Activity %s unknown region %s" % [a_id, ar])
		var dest := String(activities[a_id].get("default_destination", ""))
		if not dest.is_empty() and not location_ids.has(dest):
			errors.append("Activity %s destination %s not in region %s" % [a_id, dest, region.get("id")])
	for n in region.get("resource_nodes", []):
		if not node_types.has(n.get("type", "")):
			errors.append("Region node %s has unknown type %s" % [n.get("id"), n.get("type")])
	for e in region.get("enemy_spawns", []):
		if not enemies.has(e.get("enemy", "")):
			errors.append("Region spawn %s unknown enemy %s" % [e.get("id"), e.get("enemy")])
	for b in region.get("building_plots", []):
		if not buildings.has(b.get("building", "")):
			errors.append("Region plot unknown building %s" % b.get("building"))
	return errors
