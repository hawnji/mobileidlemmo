class_name ModalPanel
extends Control
## Full-screen dimmed overlay with a centred, scrollable card. Subclasses fill
## `body` in _build() and call refresh() when data changes.

signal closed

var card: PanelContainer
var title_label: Label
var body: VBoxContainer
var footer: HBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close())
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 110)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 16, 3, 18))
	margin.add_child(card)
	var v := VBoxContainer.new()
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_label = UiTheme.label("", 30, UiTheme.ACCENT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var x := UiTheme.button("Close", 20)
	x.custom_minimum_size = Vector2(110, 52)
	x.pressed.connect(close)
	head.add_child(x)
	v.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(footer)


func set_title(t: String) -> void:
	title_label.text = t


func clear_body() -> void:
	for c in body.get_children():
		c.queue_free()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
