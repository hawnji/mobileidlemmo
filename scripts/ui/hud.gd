class_name Hud
extends CanvasLayer
## Mobile HUD: top bar, selected-character panel, roster bar, bottom
## navigation, toasts and modal screens. Reads simulation state; the only
## writes go through SimulationWorld's command API (assign / cancel).

const NAV := [["World", "world"], ["Heroes", "heroes"], ["Skills", "skills"], ["Town", "town"], ["Market", "market"], ["Social", "social"]]

var world: SimulationWorld
var _root: Control
var _clock: Label
var _speed_btn: Button
var _cards := {}  # character_id -> CharacterCard
var _card_row: HBoxContainer
var _panel: CharacterPanel
var _toasts: VBoxContainer
var _modal_layer: Control
var _refresh_accum := 0.0
var _speeds := [1.0, 5.0, 20.0]


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)
	_build_top_bar()
	_build_bottom()
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.position = Vector2(-300, 100)
	_toasts.custom_minimum_size = Vector2(600, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_modal_layer = Control.new()
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_modal_layer)
	Game.session_started.connect(_on_session_started)
	Game.offline_report_ready.connect(_on_offline_report)
	Game.world_event.connect(_on_world_event)
	Game.selection_changed.connect(_on_selection_changed)
	if Game.world:
		_on_session_started(Game.world)


# ---------------------------------------------------------------- layout ----

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.BG, 0.92), UiTheme.BORDER, 0, 0, 10))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 80)
	_root.add_child(bar)
	var h := HBoxContainer.new()
	bar.add_child(h)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(titles)
	titles.add_child(UiTheme.label("WORLDBOUND", 26, UiTheme.ACCENT))
	_clock = UiTheme.label("Greenvale", 16, UiTheme.TEXT_DIM)
	titles.add_child(_clock)
	var storage_btn := UiTheme.button("Storage", 20)
	storage_btn.pressed.connect(open_storage)
	h.add_child(storage_btn)
	_speed_btn = UiTheme.button("x1", 20)
	_speed_btn.custom_minimum_size = Vector2(70, 56)
	_speed_btn.tooltip_text = "Simulation speed (prototype/dev)"
	_speed_btn.pressed.connect(_cycle_speed)
	h.add_child(_speed_btn)
	var dev := UiTheme.button("Dev", 20)
	dev.pressed.connect(_open_dev_menu)
	h.add_child(dev)


func _build_bottom() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_left = 10
	v.offset_right = -10
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	_panel = CharacterPanel.new()
	_panel.visible = false
	_panel.assign_requested.connect(func() -> void: open_assign(_panel.character))
	_panel.bag_requested.connect(func() -> void: open_bag(_panel.character))
	_panel.skills_requested.connect(func() -> void: open_skills(_panel.character))
	v.add_child(_panel)
	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 8)
	v.add_child(_card_row)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	v.add_child(nav)
	for spec in NAV:
		var b := UiTheme.button(spec[0], 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		var key: String = spec[1]
		b.pressed.connect(func() -> void: _on_nav(key))
		if key == "market" or key == "social":
			b.modulate = Color(1, 1, 1, 0.5)
		nav.add_child(b)


# ---------------------------------------------------------------- events ----

func _on_session_started(w: SimulationWorld) -> void:
	world = w
	for c in _card_row.get_children():
		c.queue_free()
	_cards.clear()
	for cid in world.character_order:
		var card := CharacterCard.new()
		card.setup(world.characters[cid], world.registry)
		card.pressed.connect(func() -> void:
			Game.select_character(cid if Game.selected_character_id != cid else "", true))
		_card_row.add_child(card)
		_cards[cid] = card
	_on_selection_changed(Game.selected_character_id if world.characters.has(Game.selected_character_id) else "")


func _on_selection_changed(cid: String) -> void:
	for id in _cards:
		_cards[id].set_pressed_no_signal(id == cid)
	if world and world.characters.has(cid):
		_panel.visible = true
		_panel.show_character(world, world.characters[cid])
	else:
		_panel.visible = false


func _on_offline_report(report: OfflineReport) -> void:
	if report.simulated_seconds <= 0.0:
		return
	var p := OfflineReportPanel.new()
	_open_modal(p)
	p.setup(world.registry, report)


func _on_world_event(ev: Dictionary) -> void:
	match String(ev.type):
		"level_up":
			var ch: Adventurer = world.characters.get(ev.character_id)
			toast("%s reached %s level %d!" % [ch.display_name if ch else "?", world.registry.skills[ev.skill].name, ev.level], UiTheme.ACCENT)
		"character_level_up":
			var ch2: Adventurer = world.characters.get(ev.character_id)
			toast("%s is now character level %d" % [ch2.display_name if ch2 else "?", ev.level], UiTheme.GOOD)
		"rare_drop":
			var ch3: Adventurer = world.characters.get(ev.character_id)
			toast("Rare find! %s found %s" % [ch3.display_name if ch3 else "?", world.registry.get_item_name(ev.item_id)], UiTheme.rarity_color("rare"))
		"interrupted":
			var ch4: Adventurer = world.characters.get(ev.character_id)
			toast("%s: %s" % [ch4.display_name if ch4 else "?", ev.reason], UiTheme.BAD)


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < 0.2 or world == null:
		return
	_refresh_accum = 0.0
	for id in _cards:
		_cards[id].refresh()
	if _panel.visible:
		_panel.refresh()
	var day_t := fmod(world.sim_time / DayNight.DAY_LENGTH_SECONDS, 1.0)
	var hours := int(day_t * 24.0)
	var mins := int(fmod(day_t * 24.0, 1.0) * 60.0)
	_clock.text = "Greenvale  |  %02d:%02d  |  Storage: %s items" % [hours, mins, ItemGrid._fmt(world.storage.total_units())]


# ---------------------------------------------------------------- screens ----

func _on_nav(key: String) -> void:
	match key:
		"world":
			_close_modals()
			Game.select_character("")
		"heroes":
			var cid := Game.selected_character_id
			if cid.is_empty() and not world.character_order.is_empty():
				cid = world.character_order[0]
			Game.select_character(cid, true)
		"skills":
			var cid2 := Game.selected_character_id
			if cid2.is_empty():
				cid2 = world.character_order[0]
			open_skills(world.characters[cid2])
		"town":
			open_storage()
		"market":
			toast("Marketplace arrives with multiplayer (Phase 4)", UiTheme.TEXT_DIM)
		"social":
			toast("Friends and guilds arrive with multiplayer (Phase 4)", UiTheme.TEXT_DIM)


func open_assign(ch: Adventurer) -> void:
	var p := ActivityPanel.new()
	_open_modal(p)
	p.setup(world, ch)


func open_bag(ch: Adventurer) -> void:
	var p := InventoryPanel.new()
	_open_modal(p)
	p.setup(world.registry, ch.inventory, "%s's Bag" % ch.display_name.split(" ")[0])


func open_skills(ch: Adventurer) -> void:
	var p := SkillsPanel.new()
	_open_modal(p)
	p.setup(world, ch)


func open_storage() -> void:
	var p := InventoryPanel.new()
	_open_modal(p)
	p.setup(world.registry, world.storage, "Village Storage", true)


func _open_modal(p: ModalPanel) -> void:
	_close_modals()
	_modal_layer.add_child(p)


func _close_modals() -> void:
	for c in _modal_layer.get_children():
		if c is ModalPanel:
			c.close()


func toast(text: String, color := UiTheme.TEXT) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.BG, 0.9), color, 10, 2, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(text, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------- dev ----

func _cycle_speed() -> void:
	var i := (_speeds.find(Game.time_scale) + 1) % _speeds.size()
	Game.time_scale = _speeds[i]
	_speed_btn.text = "x%d" % int(Game.time_scale)


func _open_dev_menu() -> void:
	var p := ModalPanel.new()
	_open_modal(p)
	p.set_title("Developer tools")
	p.body.add_child(UiTheme.label("Prototype-only helpers for testing automation and offline progression.", 18, UiTheme.TEXT_DIM))
	for spec in [["Simulate 10 minutes away", 600.0], ["Simulate 1 hour away", 3600.0], ["Simulate 8 hours away", 28800.0], ["Simulate 2 days away (cap test)", 172800.0]]:
		var b := UiTheme.button(spec[0])
		var secs: float = spec[1]
		b.pressed.connect(func() -> void:
			p.close()
			Game.simulate_time_away(secs))
		p.body.add_child(b)
	var save := UiTheme.button("Save now")
	save.pressed.connect(func() -> void:
		Game.save_now()
		toast("Saved", UiTheme.GOOD))
	p.body.add_child(save)
	var reset := UiTheme.button("Reset all progress")
	reset.add_theme_color_override("font_color", UiTheme.BAD)
	reset.pressed.connect(func() -> void:
		p.close()
		Game.select_character("")
		Game.reset_progress()
		toast("Progress reset", UiTheme.BAD))
	p.body.add_child(reset)
	var stats := UiTheme.label("", 16, UiTheme.TEXT_DIM)
	stats.text = "Sim time %s  |  Paths: %d requests, %d cached, %d searches\nBackend: %s" % [
		OfflineReport.format_duration(world.sim_time), world.pathfinder.stats.requests,
		world.pathfinder.stats.cache_hits, world.pathfinder.stats.searches, Game.backend.backend_name()]
	p.body.add_child(stats)
