class_name NakamaGameBackend
extends LocalGameBackend
## Online backend. The device save stays the working copy (the game keeps
## running offline); the Nakama server holds the cloud copy, validates each
## upload, owns premium currency and recruitment, and runs the shared
## systems (market, guilds, chat, world boss, events, region presence).
## If the server cannot be reached at start-up the session runs on the
## local save and the Social screen says so.

var service: OnlineService
var _username := ""
var _device_id := ""


func _init(registry: DataRegistry, settings: Dictionary, p_save_path := "", p_time: TimeSource = null) -> void:
	super(registry, p_save_path, p_time)
	service = OnlineService.new(String(settings.get("url", "")), String(settings.get("server_key", "defaultkey")))
	_username = String(settings.get("username", ""))
	_device_id = String(settings.get("device_id", ""))


func load_world(registry: DataRegistry) -> Dictionary:
	var local := super.load_world(registry)
	var boot := service.connect_blocking(_device_id if not _device_id.is_empty() else OnlineService.device_id(), _username)
	if boot.is_empty():
		return local
	var dl := service.client.call_rpc("wb_save_download")
	if not dl.ok:
		return local
	if dl.data.get("found", false):
		service.cloud_version = String(dl.data.get("version", ""))
	var local_world: SimulationWorld = local.get("world")
	if OnlineSync.prefer_cloud(local_world, float(local.get("saved_at_unix", 0.0)), dl.data):
		var w := SimulationWorld.from_dict(registry, dl.data.save.world)
		OnlineSync.apply_server_wallet(w, dl.data.get("wallet", {}))
		return {"world": w, "saved_at_unix": float(dl.data.get("saved_at", now_unix())), "source": "cloud"}
	# Local copy is further along (or there is no cloud save yet). Its first
	# upload becomes the server's baseline; premium balances then follow the
	# server wallet, so gems earned while never online are not carried over.
	return local


func save_world(world: SimulationWorld) -> bool:
	var ok := super.save_world(world)
	if service.client.is_authenticated():
		service.queue_upload()
	return ok


func backend_name() -> String:
	return "nakama (%s)" % service.status
