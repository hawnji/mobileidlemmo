class_name LocalGameBackend
extends GameBackend
## Offline, single-device backend used by the Phase 1 prototype.

var save_service: SaveService
var time_source: TimeSource
var offline_provider: OfflineProgressionProvider


func _init(registry: DataRegistry, p_save_path := "", p_time: TimeSource = null) -> void:
	var path := p_save_path if not p_save_path.is_empty() else String(registry.get_config("save.file_path", "user://worldbound_save.json"))
	save_service = SaveService.new(path)
	time_source = p_time if p_time else TimeSource.new()
	offline_provider = LocalOfflineSimulator.new(registry)


func load_world(registry: DataRegistry) -> Dictionary:
	var data := save_service.load_data()
	if data.is_empty() or not (data.get("world") is Dictionary):
		return {}
	var world := SimulationWorld.from_dict(registry, data.world)
	return {"world": world, "saved_at_unix": float(data.get("saved_at_unix", now_unix()))}


func save_world(world: SimulationWorld) -> bool:
	return save_service.save(world, now_unix())


func delete_save() -> void:
	save_service.delete()


func now_unix() -> float:
	return time_source.now_unix()


func get_offline_provider() -> OfflineProgressionProvider:
	return offline_provider


func backend_name() -> String:
	return "local"
