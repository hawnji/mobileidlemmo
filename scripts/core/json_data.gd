class_name JsonData
extends RefCounted
## Small helpers for reading the JSON data files under res://data.
## JSON numbers always parse as float in Godot, so callers use the typed
## accessors below instead of casting by hand everywhere.


static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JsonData: missing file %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JsonData: parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func to_vec2i(value: Variant, fallback := Vector2i.ZERO) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Vector2i:
		return value
	return fallback


static func from_vec2i(v: Vector2i) -> Array:
	return [v.x, v.y]


static func get_int(d: Dictionary, key: String, fallback := 0) -> int:
	return int(d.get(key, fallback)) if d.get(key) != null else fallback


static func get_float(d: Dictionary, key: String, fallback := 0.0) -> float:
	return float(d.get(key, fallback)) if d.get(key) != null else fallback
