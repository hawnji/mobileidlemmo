class_name NotificationCenter
extends RefCounted
## In-game notification inbox with per-category settings
## (data/config/notifications.json). Only important events become
## notifications; ordinary gathering never does. Repeats of one category
## inside the cooldown are merged into the previous entry instead of
## stacking up ("+2 more").
##
## Mobile push: the same entries are handed to LocalNotifier while the app is
## in the background. See LocalNotifier for what is and is not implemented.

var enabled := {}  # category -> bool
var items: Array[Dictionary] = []  # newest first: {id, category, title, body, time, read, count}
var _category_of := {}  # event type -> category
var _last := {}  # category -> sim_time of the last new entry
var _cooldown := 60.0
var _max_kept := 60
var _next_id := 1
var registry: DataRegistry


func setup(p_registry: DataRegistry) -> void:
	registry = p_registry
	var cfg := registry.notification_config
	_cooldown = float(cfg.get("cooldown_seconds", 60.0))
	_max_kept = int(cfg.get("max_kept", 60))
	for c in cfg.get("categories", []):
		enabled[String(c.id)] = bool(c.get("default_enabled", true))
		for ev in c.get("events", []):
			_category_of[String(ev)] = String(c.id)


func categories() -> Array:
	return registry.notification_config.get("categories", [])


func set_enabled(category: String, on: bool) -> void:
	enabled[category] = on


func unread_count() -> int:
	var n := 0
	for it in items:
		if not it.read:
			n += 1
	return n


func mark_all_read() -> void:
	for it in items:
		it.read = true


func on_event(world, ev: Dictionary) -> void:
	var cat := String(_category_of.get(ev.get("type", ""), ""))
	if cat.is_empty() or not bool(enabled.get(cat, false)):
		return
	var text := _format(world, ev)
	if text.is_empty():
		return
	var now := float(ev.get("time", 0.0))
	if not items.is_empty() and items[0].category == cat and not items[0].read and now - float(_last.get(cat, -INF)) < _cooldown:
		items[0].count = int(items[0].count) + 1
		items[0].time = now
		return
	_last[cat] = now
	items.push_front({"id": _next_id, "category": cat, "title": text[0], "body": text[1], "time": now, "read": false, "count": 1})
	_next_id += 1
	if items.size() > _max_kept:
		items.resize(_max_kept)
	LocalNotifier.post(text[0], text[1])


## [title, body] or [] to skip.
func _format(world, ev: Dictionary) -> Array:
	var reg := registry
	var who := ""
	if ev.has("character_id") and world.characters.has(ev.character_id):
		who = world.characters[ev.character_id].display_name
	match String(ev.type):
		"discovery":
			return ["Discovery: %s" % ev.get("name", ""), "%s found %s in %s." % [who, ev.get("name", ""), reg.region_name(String(ev.get("region", "")))]]
		"rare_drop":
			return ["Rare find!", "%s found %s." % [who, reg.get_item_name(String(ev.get("item_id", "")))]]
		"rare_enemy":
			return ["Rare enemy", "%s has appeared." % ev.get("name", "")]
		"secret_revealed":
			return ["Secret passage", "A hidden way opened in %s." % reg.region_name(String(ev.get("region", "")))]
		"expedition_completed":
			return ["Expedition %s" % ("complete" if ev.get("success", false) else "failed"), "%s has returned." % ev.get("name", "")]
		"dungeon_completed":
			var res := String(ev.get("result", ""))
			return ["%s %s" % [ev.get("name", ""), "cleared!" if res == "cleared" else "failed"], "The party is back from %s." % ev.get("name", "")]
		"crafting_finished":
			return ["Crafting complete", "%s finished crafting." % who]
		"storage_full":
			return ["Storage full", "%s cannot deposit. Sell items or upgrade the Bank." % who]
		"encounter_started":
			return [String(ev.get("name", "World event")), String(ev.get("message", ""))]
		"region_unlocked":
			return ["New region", "%s is now open." % ev.get("name", "")]
		"quest_ready":
			return ["Quest complete", "\"%s\" is ready to claim." % ev.get("name", "")]
		"tokens_ready":
			return ["Recruitment", "You have enough tokens for a 10x recruit."]
		"character_joined":
			return ["New adventurer", "%s joined your settlement." % ev.get("name", "")]
		"character_injured":
			return ["Character injured", "%s was knocked out." % who]
	return []


func to_dict() -> Dictionary:
	return {"enabled": enabled.duplicate(), "items": items.duplicate(true), "next_id": _next_id}


func load_dict(d: Dictionary) -> void:
	var en: Variant = d.get("enabled", {})
	if en is Dictionary:
		for k in en:
			if enabled.has(k):
				enabled[k] = bool(en[k])
	items.clear()
	for it in d.get("items", []):
		if it is Dictionary:
			items.append({"id": int(it.get("id", 0)), "category": String(it.get("category", "")), "title": String(it.get("title", "")),
				"body": String(it.get("body", "")), "time": float(it.get("time", 0.0)), "read": bool(it.get("read", true)), "count": int(it.get("count", 1))})
	_next_id = maxi(int(d.get("next_id", 1)), 1)
