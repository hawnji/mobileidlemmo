class_name WbServerData
extends RefCounted
## Client-side read of data/server/server_config.json, so the Social screen
## shows the same guild levels, perks and market fee the server uses.

const PATH := "res://data/server/server_config.json"
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"_": true}
	return _data


static func guild_levels() -> Array:
	return data().get("guild", {}).get("level_xp", [0])


static func market_fee() -> float:
	return float(data().get("market", {}).get("fee", 0.05))


static func is_tradeable(reg: DataRegistry, item_id: String) -> bool:
	return reg.items.has(item_id) and not bool(reg.items[item_id].get("untradeable", false))


## "+3% XP, +2% gathering speed" for multiplier effects.
static func describe_effects(effects: Dictionary) -> String:
	var names := {"xp": "XP", "gather_speed": "gathering speed", "craft_speed": "crafting speed", "damage": "damage"}
	var parts := []
	for k in effects:
		var fam := String(k).get_slice(".", 0)
		var pct := roundi((float(effects[k]) - 1.0) * 100.0)
		parts.append("+%d%% %s" % [pct, names.get(fam, fam)])
	return ", ".join(parts)
