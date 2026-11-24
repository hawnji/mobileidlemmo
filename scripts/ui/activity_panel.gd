class_name ActivityPanel
extends ModalPanel
## Assignment builder: choose activity, review expected results, configure
## automation (return threshold + continuation), start.

var world: SimulationWorld
var character: Adventurer
var _selected_activity := ""
var _return_ratio := 1.0
var _mode := Assignment.ContinueMode.REPEAT
var _quantity := 100
var _start_btn: Button
var _error_label: Label


func setup(p_world: SimulationWorld, p_character: Adventurer) -> void:
	world = p_world
	character = p_character
	set_title("Assign %s" % character.display_name)
	if character.assignment:
		_selected_activity = character.assignment.activity_id
		_return_ratio = character.assignment.return_fill_ratio
		_mode = character.assignment.continue_mode
		_quantity = maxi(character.assignment.target_quantity, 1) if _mode == Assignment.ContinueMode.UNTIL_QUANTITY else 100
	else:
		_selected_activity = _suggest_activity()
	_start_btn = UiTheme.button("Start assignment", 24)
	_start_btn.custom_minimum_size = Vector2(300, 64)
	_start_btn.pressed.connect(_start)
	footer.add_child(_start_btn)
	_rebuild()


func _suggest_activity() -> String:
	var primary := String(character.definition.get("primary_affinity", ""))
	for aid in world.registry.activity_order:
		if String(world.registry.activities[aid].skill) == primary:
			return aid
	return world.registry.activity_order[0]


func _rebuild() -> void:
	clear_body()
	body.add_child(UiTheme.label("Activity", 24, UiTheme.ACCENT))
	for aid in world.registry.activity_order:
		body.add_child(_activity_row(aid))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Automation", 24, UiTheme.ACCENT))
	body.add_child(UiTheme.label("Return to storage when bag is", 18, UiTheme.TEXT_DIM))
	var ret := HBoxContainer.new()
	for opt in [[0.5, "50%"], [0.75, "75%"], [1.0, "Full"]]:
		var b := UiTheme.button(opt[1], 20)
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(_return_ratio, opt[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_return_ratio = opt[0]
			_rebuild())
		ret.add_child(b)
	body.add_child(ret)
	body.add_child(UiTheme.label("After depositing", 18, UiTheme.TEXT_DIM))
	var mode := HBoxContainer.new()
	for opt in [[Assignment.ContinueMode.REPEAT, "Repeat"], [Assignment.ContinueMode.UNTIL_QUANTITY, "Until amount"], [Assignment.ContinueMode.SINGLE_TRIP, "One trip"]]:
		var b := UiTheme.button(opt[1], 20)
		b.toggle_mode = true
		b.button_pressed = _mode == opt[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_mode = opt[0]
			_rebuild())
		mode.add_child(b)
	body.add_child(mode)
	if _mode == Assignment.ContinueMode.UNTIL_QUANTITY:
		var q := HBoxContainer.new()
		q.add_child(UiTheme.label("Deposit", 20))
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 100000
		spin.step = 10
		spin.value = _quantity
		spin.custom_minimum_size = Vector2(180, 52)
		spin.value_changed.connect(func(v: float) -> void: _quantity = int(v))
		q.add_child(spin)
		q.add_child(UiTheme.label(world.registry.get_item_name(_primary_item()), 20))
		body.add_child(q)
	body.add_child(HSeparator.new())
	body.add_child(_estimate_box())
	_error_label = UiTheme.label("", 20, UiTheme.BAD)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_error_label)
	_start_btn.disabled = _selected_activity.is_empty() or not _meets_requirement(_selected_activity)


func _primary_item() -> String:
	var act: Dictionary = world.registry.activities.get(_selected_activity, {})
	return String(world.registry.node_types.get(act.get("node_type", ""), {}).get("yield", {}).get("item", ""))


func _meets_requirement(aid: String) -> bool:
	var act: Dictionary = world.registry.activities[aid]
	return character.skills.get_level(String(act.skill)) >= int(act.get("required_level", 1))


func _activity_row(aid: String) -> Control:
	var act: Dictionary = world.registry.activities[aid]
	var ntype: Dictionary = world.registry.node_types[act.node_type]
	var skill := String(act.skill)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = aid == _selected_activity
	b.custom_minimum_size = Vector2(0, 92)
	b.disabled = not _meets_requirement(aid)
	b.pressed.connect(func() -> void:
		_selected_activity = aid
		_rebuild())
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon := TextureRect.new()
	icon.texture = UiTheme.texture(String(world.registry.items.get(ntype.yield.item, {}).get("icon", "")))
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(UiTheme.label(String(act.name), 24))
	var dest := String(world.locations.get(act.get("default_destination", ""), {}).get("name", "Anywhere"))
	var req := "%s %d" % [world.registry.skills[skill].name, int(act.required_level)]
	v.add_child(UiTheme.label("%s  |  needs %s  |  %.1f xp  |  %.1fs" % [dest, req, float(ntype.xp), float(ntype.gather_seconds)], 16, UiTheme.TEXT_DIM))
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _estimate_box() -> Control:
	var v := VBoxContainer.new()
	v.add_child(UiTheme.label("Expected results", 24, UiTheme.ACCENT))
	if _selected_activity.is_empty():
		return v
	var e := ActivityEstimator.estimate(world, character, _selected_activity, _return_ratio)
	if not e.get("reachable", false):
		v.add_child(UiTheme.label("Destination unreachable", 20, UiTheme.BAD))
		return v
	var act: Dictionary = world.registry.activities[_selected_activity]
	var skill_name := String(world.registry.skills[act.skill].name)
	v.add_child(UiTheme.label("~%s %s XP / hour" % [_n(e.xp_per_hour), skill_name], 22, UiTheme.GOOD))
	v.add_child(UiTheme.label("~%s %s / hour" % [_n(e.items_per_hour), world.registry.get_item_name(_primary_item())], 20))
	v.add_child(UiTheme.label("%d per trip, %.1fs each, %.0fs round trip" % [e.trip_items, e.gather_seconds, e.round_trip_seconds], 18, UiTheme.TEXT_DIM))
	return v


static func _n(x: float) -> String:
	return str(roundi(x)) if x < 10000 else "%.1fk" % (x / 1000.0)


func _start() -> void:
	var a := Assignment.create(character.id, world.registry.activities[_selected_activity])
	a.return_fill_ratio = _return_ratio
	a.continue_mode = _mode
	a.target_quantity = _quantity if _mode == Assignment.ContinueMode.UNTIL_QUANTITY else 0
	var err := world.assign_activity(character.id, a)
	if not err.is_empty():
		_error_label.text = err
		return
	close()
