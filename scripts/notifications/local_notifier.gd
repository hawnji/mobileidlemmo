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


static func status_text() -> String:
	if Engine.has_singleton(SINGLETON):
		return "on (device plugin found)."
	return "not available in this build. A mobile notification plugin is needed (see the roadmap); in-game notifications work."


## Schedules OS reminders for things that finish while the app is closed.
static func schedule_for_world(world) -> void:
	cancel_all()
	for run in world.expeditions.active:
		var x: Dictionary = world.registry.expeditions.get(run.expedition_id, {})
		schedule("exp_%d" % int(run.uid), "Expedition returning", "%s is back." % x.get("name", "An expedition"),
			maxf(float(run.ends_at) - world.sim_time, 1.0))
	for qid in world.quests.cooldowns:
		var left: float = float(world.quests.cooldowns[qid]) - world.sim_time
		if left > 0.0:
			schedule("contract_%s" % qid, "Contract available", "%s can be taken again." % world.registry.quests[qid].name, left)
