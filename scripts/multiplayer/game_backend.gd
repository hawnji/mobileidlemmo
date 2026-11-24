class_name GameBackend
extends RefCounted
## Boundary between the client and whatever owns authoritative state.
##
## Phase 1: LocalGameBackend (device save + local offline simulation).
## Phase 4: NakamaGameBackend — authenticates with Nakama, loads the profile
## from the Player/Character services, submits assignment *intents* and
## receives authoritative state + offline reports. Game code talks only to
## this interface, so swapping backends does not touch gameplay or UI.


## Returns {"world": SimulationWorld, "saved_at_unix": float} or {} if none.
func load_world(_registry: DataRegistry) -> Dictionary:
	return {}


func save_world(_world: SimulationWorld) -> bool:
	return false


func delete_save() -> void:
	pass


func now_unix() -> float:
	return Time.get_unix_time_from_system()


func get_offline_provider() -> OfflineProgressionProvider:
	return OfflineProgressionProvider.new()


func backend_name() -> String:
	return "abstract"
