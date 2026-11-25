class_name LocalNotifier
extends RefCounted
## Bridge to operating-system notifications.
##
## Godot 4 has no built-in API for mobile local or push notifications; they
## need an Android plugin (e.g. a LocalNotification singleton) and an iOS
## plugin plus Apple/Google push credentials for remote push. This class is
## the single place that will call them:
##   * if an engine singleton named "LocalNotification" exists, post() and
##     schedule() forward to it;
##   * otherwise calls are recorded in `pending` (used by tests and shown in
##     the debug log) and nothing reaches the OS.
## What is NOT done yet is listed in docs/DEVELOPMENT_ROADMAP.md (Phase 3 gaps).

const SINGLETON := "LocalNotification"

static var enabled := false  # only true while the app is in the background
static var pending: Array[Dictionary] = []


static func post(title: String, body: String) -> void:
	if not enabled:
		return
	if Engine.has_singleton(SINGLETON):
		Engine.get_singleton(SINGLETON).call("show", title, body)
	else:
		_record({"title": title, "body": body, "delay": 0.0})


## Schedules a notification `delay_seconds` from now (e.g. an expedition
## finishing while the app is closed).
static func schedule(key: String, title: String, body: String, delay_seconds: float) -> void:
	if Engine.has_singleton(SINGLETON):
		Engine.get_singleton(SINGLETON).call("schedule", key, title, body, int(delay_seconds))
	else:
		_record({"key": key, "title": title, "body": body, "delay": delay_seconds})


static func cancel_all() -> void:
	if Engine.has_singleton(SINGLETON):
		Engine.get_singleton(SINGLETON).call("cancel_all")
	pending.clear()


static func _record(entry: Dictionary) -> void:
	pending.append(entry)
	if pending.size() > 50:
		pending.remove_at(0)
