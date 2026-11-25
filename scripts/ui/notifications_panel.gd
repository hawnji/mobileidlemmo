class_name NotificationsPanel
extends ModalPanel
## Notification inbox and per-category switches. Opening it marks every
## entry as read.

var world: SimulationWorld


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("Notifications")
	refresh()
	world.notifications.mark_all_read()


func refresh() -> void:
	clear_body()
	var nc := world.notifications
	if nc.items.is_empty():
		body.add_child(UiTheme.label("Nothing yet. Discoveries, finished expeditions, dungeon clears and full storage show up here.", 17, UiTheme.TEXT_DIM))
	for it in nc.items:
		var ago := maxf(world.sim_time - float(it.time), 0.0)
		var title := String(it.title) + ("  (+%d more)" % (int(it.count) - 1) if int(it.count) > 1 else "")
		body.add_child(UiTheme.label(title, 19, UiTheme.ACCENT if not it.read else UiTheme.TEXT))
		var b := UiTheme.label("%s  -  %s ago" % [it.body, OfflineReport.format_duration(ago)], 14, UiTheme.TEXT_DIM)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(b)
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Notify me about", 20, UiTheme.ACCENT))
	for c in nc.categories():
		var cb := CheckButton.new()
		cb.text = String(c.name)
		cb.button_pressed = bool(nc.enabled.get(c.id, true))
		var cid := String(c.id)
		cb.toggled.connect(func(on: bool) -> void: nc.set_enabled(cid, on))
		body.add_child(cb)
	var note := UiTheme.label("Phone notifications while the app is closed: %s" % LocalNotifier.status_text(), 14, UiTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
