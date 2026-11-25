class_name NakamaSocket
extends RefCounted
## Nakama realtime socket (JSON protocol) on WebSocketPeer. Call poll()
## every frame. send() takes an optional callback for the server's reply
## (matched by `cid`); everything else arrives through `event`.

signal event(msg: Dictionary)
signal connected
signal closed

var _ws := WebSocketPeer.new()
var _cid := 1
var _pending := {}  # cid -> Callable
var _was_open := false
var _opening := false


func open(client: NakamaClient) -> int:
	var url := client.base_url.replace("https://", "wss://").replace("http://", "ws://")
	_ws = WebSocketPeer.new()
	_was_open = false
	_opening = true
	return _ws.connect_to_url("%s/ws?token=%s&format=json" % [url, client.token])


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func close() -> void:
	_ws.close()


func poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		_opening = false
		connected.emit()
	elif state == WebSocketPeer.STATE_CLOSED and (_was_open or _opening):
		_was_open = false
		_opening = false
		_pending.clear()
		closed.emit()
	while _ws.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		var msg: Dictionary = parsed
		var cid := String(msg.get("cid", ""))
		if not cid.is_empty() and _pending.has(cid):
			var cb: Callable = _pending[cid]
			_pending.erase(cid)
			if cb.is_valid():
				cb.call(msg)
			continue
		event.emit(msg)


func send(body: Dictionary, on_reply := Callable()) -> void:
	var msg := body.duplicate()
	if on_reply.is_valid():
		var cid := str(_cid)
		_cid += 1
		msg["cid"] = cid
		_pending[cid] = on_reply
	_ws.send_text(JSON.stringify(msg))


func join_group_chat(group_id: String, on_reply := Callable()) -> void:
	send({"channel_join": {"target": group_id, "type": 3, "persistence": true, "hidden": false}}, on_reply)


func send_chat(channel_id: String, text: String) -> void:
	send({"channel_message_send": {"channel_id": channel_id, "content": JSON.stringify({"text": text.left(300)})}})


func join_match(match_id: String, on_reply := Callable()) -> void:
	send({"match_join": {"match_id": match_id}}, on_reply)


func leave_match(match_id: String) -> void:
	send({"match_leave": {"match_id": match_id}})


func send_match_data(match_id: String, op_code: int, data: Dictionary) -> void:
	send({"match_data_send": {"match_id": match_id, "op_code": str(op_code),
		"data": Marshalls.utf8_to_base64(JSON.stringify(data))}})


static func decode_match_data(msg: Dictionary) -> Dictionary:
	var md: Dictionary = msg.get("match_data", {})
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_utf8(String(md.get("data", ""))))
	return parsed if parsed is Dictionary else {}
