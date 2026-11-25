class_name OnlineService
extends Node
## The online session: sign-in, cloud save sync, server recruitment,
## market, guild, chat, world boss, world events and region presence.
##
## HTTP calls run on WorkerThreadPool (NakamaClient is blocking) and their
## callbacks run back on the main thread, so the UI never freezes. All
## changes to the world go through OnlineSync on the main thread.

signal status_changed(status: String)
signal synced(result: Dictionary)
signal social_changed
signal chat_received(msg: Dictionary)
signal presence_changed(players: Dictionary)

const SETTINGS_PATH := "user://online.cfg"
const OP_POS := 1
const OP_STATE := 2

var client: NakamaClient
var socket := NakamaSocket.new()
var world: SimulationWorld
var effects: OnlineSync.Effects

var status := "offline"  # offline | connecting | online | error
var status_message := ""
var cloud_version := ""
var last_sync_unix := 0.0
var last_sync_text := "Not synced yet"
var events: Array = []
var guild: Dictionary = {}
var pending_deliveries := 0
var chat_channel_id := ""
var chat_log: Array = []  # [{username, text}]
var region_match_id := ""
var region_match_region := ""
var region_players := {}  # user_id -> {name, heroes:[{id,x,y}]}

var upload_interval := 60.0
var refresh_interval := 120.0
var presence_interval := 2.0
## Tests: run requests inline instead of on worker threads.
var synchronous := false

var _tasks := []  # WorkerThreadPool task ids
var _since_upload := 0.0
var _since_refresh := 0.0
var _since_presence := 0.0
var _upload_in_flight := false
var _upload_wanted := false
var _socket_started := false


## Reads the saved server address. Returns {} when the player has not
## turned online play on.
static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return {}
	var url := String(cfg.get_value("server", "url", ""))
	if url.is_empty():
		return {}
	return {"url": url, "server_key": String(cfg.get_value("server", "server_key", "defaultkey")),
		"username": String(cfg.get_value("account", "username", ""))}


static func save_settings(url: String, server_key: String, username: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("server", "url", url)
	cfg.set_value("server", "server_key", server_key)
	cfg.set_value("account", "username", username)
	cfg.save(SETTINGS_PATH)


static func clear_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("server", "url", "")
	cfg.save(SETTINGS_PATH)


## A random id kept per install (OS ids are missing or restricted on some
## platforms). It is the account's device credential.
static func device_id() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var id := String(cfg.get_value("account", "device_id", ""))
	if id.length() < 10:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		id = "wb-%08x%08x%08x" % [rng.randi(), rng.randi(), rng.randi()]
		cfg.set_value("account", "device_id", id)
		cfg.save(SETTINGS_PATH)
	return id


func _init(url := "", server_key := "defaultkey") -> void:
	name = "OnlineService"
	client = NakamaClient.new(url, server_key)
	socket.event.connect(_on_socket_event)
	socket.closed.connect(_on_socket_closed)
	socket.connected.connect(func() -> void:
		if world:
			refresh_social())


func is_online() -> bool:
	return status == "online"


func _set_status(s: String, message := "") -> void:
	status = s
	status_message = message
	status_changed.emit(s)


## Blocking sign-in + bootstrap, used once at start-up (before the world
## exists). Returns the bootstrap data or {} on failure.
func connect_blocking(p_device_id: String, username := "") -> Dictionary:
	_set_status("connecting")
	var r := client.authenticate_device(p_device_id, username)
	if not r.ok and r.status == 409 and not username.is_empty():
		r = client.authenticate_device(p_device_id, "")  # name taken
	if not r.ok:
		_set_status("error", r.message)
		return {}
	var boot := client.call_rpc("wb_bootstrap")
	if not boot.ok:
		_set_status("error", boot.message)
		return {}
	_apply_bootstrap(boot.data)
	_set_status("online")
	return boot.data


func _apply_bootstrap(data: Dictionary) -> void:
	events = data.get("events", [])
	pending_deliveries = int(data.get("pending_deliveries", 0))


## Called once the session's world exists.
func attach_world(p_world: SimulationWorld) -> void:
	world = p_world
	effects = OnlineSync.Effects.new(world.registry)
	world.account.extra_sources.append(effects)
	_update_effects()
	if is_online():
		if not _socket_started:
			_socket_started = true
			socket.open(client)
		refresh_social()
		claim_deliveries()


func _update_effects() -> void:
	if effects and world:
		effects.set_sources(world.registry, guild.get("perks", {}) if guild.get("in_guild", false) else {}, events)


# ---------------------------------------------------------------- plumbing

## Runs `job` (returns a Dictionary) on a worker thread, then `done` with
## its result on the main thread.
func run(job: Callable, done: Callable = Callable()) -> void:
	if synchronous:
		_finish(done, job.call())
		return
	var id := WorkerThreadPool.add_task(func() -> void:
		var r: Dictionary = job.call()
		_finish.call_deferred(done, r))
	_tasks.append(id)


func call_rpc(rpc_id: String, payload: Dictionary, done: Callable = Callable()) -> void:
	run(func() -> Dictionary: return client.call_rpc(rpc_id, payload), done)


func _finish(done: Callable, r: Dictionary) -> void:
	if not r.ok and r.status == 0 and is_online():
		_set_status("error", r.message)
	elif r.ok and status == "error":
		_set_status("online")
	_reply(done, r)


## Panels can close while a request is in flight; their callbacks are then
## invalid and skipped.
static func _reply(done: Callable, r: Dictionary) -> void:
	if done.is_valid():
		done.call(r)


func _process(delta: float) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	if not client.is_authenticated() or world == null:
		return
	socket.poll()
	_since_upload += delta
	_since_refresh += delta
	_since_presence += delta
	if _upload_wanted and _since_upload >= upload_interval:
		upload_now()
	if _since_refresh >= refresh_interval:
		_since_refresh = 0.0
		if not _socket_started:
			_socket_started = true
			socket.open(client)
		refresh_social()
		if pending_deliveries > 0:
			claim_deliveries()
	if _since_presence >= presence_interval:
		_since_presence = 0.0
		_update_presence()


func _exit_tree() -> void:
	socket.close()
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


# ---------------------------------------------------------------- saves

## Called on every local save; uploads at most once per upload_interval.
func queue_upload(force := false) -> void:
	_upload_wanted = true
	if force or _since_upload >= upload_interval:
		upload_now()


func upload_now() -> void:
	if world == null or _upload_in_flight or not client.is_authenticated():
		return
	_upload_in_flight = true
	_upload_wanted = false
	_since_upload = 0.0
	var save := {"save_version": 1, "world": world.to_dict()}
	var sent := OnlineSync.premium_snapshot(world)
	var payload := {"save": save}
	if not cloud_version.is_empty():
		payload["expected_version"] = cloud_version
	call_rpc("wb_save_upload", payload, func(r: Dictionary) -> void:
		_upload_in_flight = false
		var result := {"ok": r.ok, "message": r.message}
		if r.ok and r.data.get("accepted", false):
			cloud_version = String(r.data.get("version", ""))
			OnlineSync.apply_server_wallet(world, r.data.get("wallet", {}), sent)
			last_sync_unix = Time.get_unix_time_from_system()
			last_sync_text = "Synced at %s" % Time.get_time_string_from_system().left(5)
		elif r.ok:
			result.ok = false
			result.message = "The server did not accept this save: %s" % String(r.data.get("reason", ""))
			last_sync_text = result.message
		else:
			last_sync_text = "Sync failed: %s" % r.message
		synced.emit(result))


## Replaces the local world with the cloud copy (after a conflict).
func download_cloud(done: Callable) -> void:
	call_rpc("wb_save_download", {}, func(r: Dictionary) -> void:
		if r.ok and r.data.get("found", false):
			cloud_version = String(r.data.get("version", ""))
		_reply(done, r))


# ---------------------------------------------------------------- economy

func recruit(banner_id: String, count: int, done: Callable) -> void:
	call_rpc("wb_recruit", {"banner": banner_id, "count": count}, func(r: Dictionary) -> void:
		if r.ok:
			var results := OnlineSync.apply_recruit(world, r.data)
			_reply(done, {"error": "", "results": results})
			queue_upload(true)
		else:
			_reply(done, {"error": r.message, "results": []}))


func claim_deliveries(done: Callable = Callable()) -> void:
	call_rpc("wb_claim_deliveries", {}, func(r: Dictionary) -> void:
		var got := {}
		if r.ok:
			got = OnlineSync.apply_deliveries(world, r.data)
			pending_deliveries = 0
			if not got.is_empty():
				queue_upload(true)
		_reply(done, {"ok": r.ok, "message": r.message, "items": got, "notes": r.data.get("notes", [])}))


## Lists `qty` of `item` from storage. `buyer` = a friend's user id for a
## private trade.
func market_list(item: String, qty: int, price: int, buyer: String, done: Callable) -> void:
	if world.storage.get_quantity(item) < qty:
		_reply(done, {"ok": false, "message": "Not enough in storage"})
		return
	var payload := {"item": item, "qty": qty, "price": price}
	if not buyer.is_empty():
		payload["buyer"] = buyer
	call_rpc("wb_market_list", payload, func(r: Dictionary) -> void:
		if r.ok:
			var e := OnlineSync.apply_debit(world, item, qty, int(r.data.get("ledger_seq", 0)), "market_list")
			if not e.is_empty():
				r = {"ok": false, "message": e}
			queue_upload(true)
		_reply(done, r))


func market_buy(listing_id: String, done: Callable) -> void:
	call_rpc("wb_market_buy", {"listing_id": listing_id}, func(r: Dictionary) -> void:
		if r.ok:
			var l: Dictionary = r.data.get("bought", {})
			OnlineSync.apply_debit(world, "gold", int(l.get("price", 0)), int(r.data.get("ledger_seq", 0)), "market_buy")
			claim_deliveries()
		_reply(done, r))


func guild_donate(gold: int, done: Callable) -> void:
	if world.wallet.get_balance("gold") < gold:
		_reply(done, {"ok": false, "message": "Not enough gold"})
		return
	call_rpc("wb_guild_donate", {"gold": gold}, func(r: Dictionary) -> void:
		if r.ok:
			OnlineSync.apply_debit(world, "gold", gold, int(r.data.get("ledger_seq", 0)), "guild_donation")
			var gname: String = guild.get("name", "")
			guild = r.data
			guild["in_guild"] = true
			guild["name"] = gname
			_update_effects()
			social_changed.emit()
			queue_upload(true)
		_reply(done, r))


# ---------------------------------------------------------------- social

## Refreshes guild info and world events; joins the guild chat.
func refresh_social() -> void:
	call_rpc("wb_guild_info", {}, func(r: Dictionary) -> void:
		if not r.ok:
			return
		guild = r.data
		_update_effects()
		if guild.get("in_guild", false) and socket.is_open() and chat_channel_id.is_empty():
			_join_chat(String(guild.get("group_id", "")))
		social_changed.emit())
	call_rpc("wb_world_events", {}, func(r: Dictionary) -> void:
		if r.ok:
			events = r.data.get("events", [])
			_update_effects()
			social_changed.emit())


func _join_chat(group_id: String) -> void:
	if group_id.is_empty():
		return
	socket.join_group_chat(group_id, func(msg: Dictionary) -> void:
		var ch: Dictionary = msg.get("channel", {})
		chat_channel_id = String(ch.get("id", ""))
		if chat_channel_id.is_empty():
			return
		var cid := chat_channel_id
		run(func() -> Dictionary: return client.channel_messages(cid), func(r: Dictionary) -> void:
			if not r.ok:
				return
			chat_log.clear()
			var msgs: Array = r.data.get("messages", [])
			msgs.reverse()
			for m in msgs:
				if int(m.get("code", 0)) == 0:  # skip join / leave notices
					chat_log.append(_chat_entry(m))
			social_changed.emit()))


func send_chat(text: String) -> void:
	if not chat_channel_id.is_empty() and not text.strip_edges().is_empty():
		socket.send_chat(chat_channel_id, text.strip_edges())


static func _chat_entry(m: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(String(m.get("content", "{}")))
	var text := String(parsed.get("text", "")) if parsed is Dictionary else ""
	return {"username": String(m.get("username", "?")), "text": text}


## Rejoined on the next refresh.
func _on_socket_closed() -> void:
	_socket_started = false
	chat_channel_id = ""
	region_match_id = ""
	region_match_region = ""


func _on_socket_event(msg: Dictionary) -> void:
	if msg.has("channel_message"):
		var m: Dictionary = msg.channel_message
		if String(m.get("channel_id", "")) == chat_channel_id and int(m.get("code", 0)) == 0:
			var e := _chat_entry(m)
			chat_log.append(e)
			if chat_log.size() > 100:
				chat_log.remove_at(0)
			chat_received.emit(e)
	elif msg.has("match_data"):
		if String(msg.match_data.get("match_id", "")) != region_match_id:
			return
		if int(msg.match_data.get("op_code", 0)) == OP_STATE:
			var st := NakamaSocket.decode_match_data(msg)
			var players: Dictionary = st.get("players", {})
			players.erase(client.user_id)
			region_players = players
			presence_changed.emit(region_players)


## Joins the shared match of the region where most heroes are, and sends
## their positions so other players there see them.
func _update_presence() -> void:
	if not socket.is_open():
		return
	var counts := {}
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		if ch.state == CharacterStates.State.AWAY:
			continue
		var rid := world.region_at(ch.tile)
		counts[rid] = int(counts.get(rid, 0)) + 1
	var best := ""
	for rid in counts:
		if best.is_empty() or int(counts[rid]) > int(counts[best]):
			best = rid
	if best.is_empty():
		return
	if best != region_match_region:
		if not region_match_id.is_empty():
			socket.leave_match(region_match_id)
		region_match_id = ""
		region_match_region = best
		region_players = {}
		presence_changed.emit(region_players)
		call_rpc("wb_region_match", {"region": best}, func(r: Dictionary) -> void:
			if r.ok and region_match_region == best:
				var mid := String(r.data.get("match_id", ""))
				socket.join_match(mid, func(_m: Dictionary) -> void: region_match_id = mid))
		return
	if region_match_id.is_empty():
		return
	var heroes := []
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		if ch.state != CharacterStates.State.AWAY and world.region_at(ch.tile) == best and heroes.size() < 12:
			heroes.append({"id": cid, "x": ch.tile.x, "y": ch.tile.y})
	socket.send_match_data(region_match_id, OP_POS, {"heroes": heroes})
