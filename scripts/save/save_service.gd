class_name SaveService
extends RefCounted
## Local JSON persistence for the prototype. Writes atomically (temp file +
## rename) so a crash mid-save cannot corrupt the previous save. In the online
## build the server's PostgreSQL record is authoritative and this file is only
## a cache.

const SAVE_VERSION := 1

var path := "user://worldbound_save.json"


func _init(p_path := "") -> void:
	if not p_path.is_empty():
		path = p_path


func save(world: SimulationWorld, now_unix: float) -> bool:
	var data := {
		"save_version": SAVE_VERSION,
		"saved_at_unix": now_unix,
		"world": world.to_dict(),
	}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("SaveService: rename failed (%s)" % error_string(err))
		return false
	return true


func has_save() -> bool:
	return FileAccess.file_exists(path)


## Returns {} when there is no save or it is unreadable.
func load_data() -> Dictionary:
	if not has_save():
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("SaveService: save file unreadable, starting fresh")
		return {}
	var data: Dictionary = json.data
	if int(data.get("save_version", 0)) > SAVE_VERSION:
		push_warning("SaveService: save is from a newer version")
		return {}
	return data


func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
