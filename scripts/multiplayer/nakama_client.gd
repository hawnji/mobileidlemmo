class_name NakamaClient
extends RefCounted
## Minimal Nakama REST client (device auth, RPCs, friends, groups) built on
## Godot's HTTPClient. Calls are blocking, so the game runs them through
## OnlineService on a worker thread; tests and the boot sync call them
## directly. Every call returns {ok, status, data, message}.

var base_url := "http://127.0.0.1:7350"
var server_key := "defaultkey"
var timeout_seconds := 8.0
var token := ""
var refresh_token := ""
var user_id := ""
var username := ""

var _host := ""
var _port := 7350
var _tls := false


func _init(p_base_url := "", p_server_key := "") -> void:
	if not p_base_url.is_empty():
		set_url(p_base_url)
	if not p_server_key.is_empty():
		server_key = p_server_key


func set_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	_tls = base_url.begins_with("https://")
	var rest := base_url.trim_prefix("https://").trim_prefix("http://")
	_host = rest.get_slice(":", 0).get_slice("/", 0)
	_port = int(rest.get_slice(":", 1)) if rest.contains(":") else (443 if _tls else 80)


func is_authenticated() -> bool:
	return not token.is_empty()


## Signs in (creating the account the first time) with a per-install id.
func authenticate_device(device_id: String, p_username := "", create := true) -> Dictionary:
	var q := "?create=%s" % ("true" if create else "false")
	if not p_username.is_empty():
		q += "&username=" + p_username.uri_encode()
	var basic := "Basic " + Marshalls.utf8_to_base64(server_key + ":")
	var r := request(HTTPClient.METHOD_POST, "/v2/account/authenticate/device" + q, {"id": device_id}, basic)
	if r.ok:
		token = String(r.data.get("token", ""))
		refresh_token = String(r.data.get("refresh_token", ""))
		_read_token_claims()
		if username.is_empty():
			username = p_username
	return r


## Calls a server function. The payload is sent as raw JSON (?unwrap).
func call_rpc(rpc_id: String, payload: Dictionary = {}) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/rpc/%s?unwrap" % rpc_id.uri_encode(), payload)


func account() -> Dictionary:
	return request(HTTPClient.METHOD_GET, "/v2/account")


func add_friend_by_username(name: String) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/friend?usernames=" + name.uri_encode())


func add_friend_by_id(id: String) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/friend?ids=" + id.uri_encode())


func remove_friend_by_id(id: String) -> Dictionary:
	return request(HTTPClient.METHOD_DELETE, "/v2/friend?ids=" + id.uri_encode())


## Friend states: 0 mutual, 1 request sent, 2 request received, 3 blocked.
func list_friends() -> Dictionary:
	return request(HTTPClient.METHOD_GET, "/v2/friend?limit=100")


func create_group(name: String, description := "", open := true) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/group", {"name": name, "description": description, "open": open, "max_count": 50})


func list_groups(name_filter := "") -> Dictionary:
	var q := "/v2/group?limit=20"
	if not name_filter.is_empty():
		q += "&name=" + (name_filter + "%").uri_encode()
	return request(HTTPClient.METHOD_GET, q)


func join_group(group_id: String) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/group/%s/join" % group_id)


func leave_group(group_id: String) -> Dictionary:
	return request(HTTPClient.METHOD_POST, "/v2/group/%s/leave" % group_id)


func group_members(group_id: String) -> Dictionary:
	return request(HTTPClient.METHOD_GET, "/v2/group/%s/user?limit=50" % group_id)


## Recent messages of a guild channel (channel id from the socket join).
func channel_messages(channel_id: String, limit := 30) -> Dictionary:
	return request(HTTPClient.METHOD_GET, "/v2/channel/%s?limit=%d&forward=false" % [channel_id.uri_encode(), limit])


## Blocking HTTP request. `auth` overrides the Bearer session token.
func request(method: int, path: String, body: Variant = null, auth := "") -> Dictionary:
	var http := HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if _tls else null
	var err := http.connect_to_host(_host, _port, tls)
	if err != OK:
		return _fail(0, "Could not reach the server")
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return _fail(0, "Server timed out")
		OS.delay_msec(2)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return _fail(0, "Could not reach the server")
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not auth.is_empty():
		headers.append("Authorization: " + auth)
	elif not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var text := "" if body == null else JSON.stringify(body)
	err = http.request(method, path, headers, text)
	if err != OK:
		return _fail(0, "Request failed")
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return _fail(0, "Server timed out")
		OS.delay_msec(2)
	var status := http.get_response_code()
	var bytes := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			bytes.append_array(chunk)
		elif Time.get_ticks_msec() > deadline:
			return _fail(status, "Server timed out")
		else:
			OS.delay_msec(1)
	http.close()
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() > 0 else {}
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "message": ""}
	return _fail(status, String(data.get("message", "Server error %d" % status)))


func _fail(status: int, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": {}, "message": message}


## The session token is a JWT; its payload carries the user id and name.
func _read_token_claims() -> void:
	var parts := token.split(".")
	if parts.size() < 2:
		return
	var b64 := parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(b64))
	if claims is Dictionary:
		user_id = String(claims.get("uid", ""))
		username = String(claims.get("usn", username))
