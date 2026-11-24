class_name CharacterPanel
extends PanelContainer
## Details for the selected character: identity, live state, location,
## current activity, bag, XP rate and the automation rules in effect.

signal assign_requested
signal bag_requested
signal skills_requested

var world: SimulationWorld
var character: Adventurer
var _portrait: TextureRect
var _name: Label
var _sub: Label
var _state: Label
var _activity: Label
var _rules: Label
var _bag_label: Label
var _bag: ProgressBar
var _skill_label: Label
var _skill_bar: ProgressBar
var _stop_btn: Button
var _follow_btn: Button
var _rate_cache := {}


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.PANEL, 0.96), UiTheme.BORDER, 14, 2, 14))
	var v := VBoxContainer.new()
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.add_child(_portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	top.add_child(info)
	_name = UiTheme.label("", 26)
	info.add_child(_name)
	_sub = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	info.add_child(_sub)
	_state = UiTheme.label("", 20, UiTheme.ACCENT)
	info.add_child(_state)
	_activity = UiTheme.label("", 17)
	_activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_activity)
	_rules = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rules)
	var bars := HBoxContainer.new()
	v.add_child(bars)
	var bagbox := VBoxContainer.new()
	bagbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bagbox.add_theme_constant_override("separation", 2)
	_bag_label = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	bagbox.add_child(_bag_label)
	_bag = UiTheme.bar(UiTheme.ACCENT, 12)
	bagbox.add_child(_bag)
	bars.add_child(bagbox)
	var skbox := VBoxContainer.new()
	skbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skbox.add_theme_constant_override("separation", 2)
	_skill_label = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	skbox.add_child(_skill_label)
	_skill_bar = UiTheme.bar(UiTheme.GOOD, 12)
	skbox.add_child(_skill_bar)
	bars.add_child(skbox)
	var buttons := HBoxContainer.new()
	v.add_child(buttons)
	for spec in [["Assign", "assign"], ["Bag", "bag"], ["Skills", "skills"], ["Stop", "stop"], ["Follow", "follow"]]:
		var b := UiTheme.button(spec[0], 19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 58)
		buttons.add_child(b)
		match spec[1]:
			"assign": b.pressed.connect(func() -> void: assign_requested.emit())
			"bag": b.pressed.connect(func() -> void: bag_requested.emit())
			"skills": b.pressed.connect(func() -> void: skills_requested.emit())
			"stop":
				_stop_btn = b
				b.pressed.connect(func() -> void:
					if world and character:
						world.cancel_assignment(character.id))
			"follow":
				_follow_btn = b
				b.toggle_mode = true
				b.toggled.connect(func(on: bool) -> void:
					if character:
						Game.select_character(character.id, on))


func show_character(p_world: SimulationWorld, p_character: Adventurer) -> void:
	world = p_world
	character = p_character
	_rate_cache.clear()
	_portrait.texture = UiTheme.texture(String(character.definition.get("portrait", "")))
	_name.text = character.display_name
	_name.add_theme_color_override("font_color", UiTheme.rarity_color(character.rarity))
	var d := character.definition
	_sub.text = "%s %s  |  %s  |  %s" % [String(character.rarity).capitalize(), d.get("title", ""), String(d.get("combat_specialty", "")).capitalize(), d.get("passive", {}).get("name", "")]
	_follow_btn.set_pressed_no_signal(Game.follow_selected)
	refresh()


func refresh() -> void:
	if character == null:
		return
	var reg := world.registry
	_state.text = "%s  -  %s" % [CharacterStates.label_of(character.state), world.location_name_at(character.tile)]
	var asg := character.assignment
	_stop_btn.disabled = asg == null or not character.is_busy()
	if asg:
		var act: Dictionary = reg.activities.get(asg.activity_id, {})
		var skill := String(act.get("skill", ""))
		var rate := _rate(asg.activity_id, asg.return_fill_ratio)
		_activity.text = "%s  |  ~%s XP/h  |  %s" % [act.get("name", "?"), ActivityPanel._n(rate.get("xp_per_hour", 0.0)), character.status_message]
		_rules.text = "%s.  %s.  Trips: %d" % [asg.describe_return_rule(), asg.describe_continue_rule(), asg.trips_completed]
		var xp := character.skills.get_xp(skill)
		_skill_label.text = "%s %d" % [reg.skills.get(skill, {}).get("name", skill), character.skills.get_level(skill)]
		_skill_bar.value = reg.skill_xp_table.progress_to_next(xp)
	else:
		_activity.text = character.status_message if not character.status_message.is_empty() else "No assignment. Tap Assign to put them to work."
		_rules.text = String(character.definition.get("passive", {}).get("description", ""))
		_skill_label.text = "Character level %d" % character.character_level(reg)
		_skill_bar.value = reg.character_xp_table.progress_to_next(character.character_xp)
	_bag_label.text = "Bag %d / %d" % [character.inventory.total_units(), character.inventory.max_units]
	_bag.value = character.inventory.fill_ratio()


func _rate(activity_id: String, ratio: float) -> Dictionary:
	var key := "%s:%s:%d" % [activity_id, ratio, character.skills.get_level(String(world.registry.activities[activity_id].skill))]
	if not _rate_cache.has(key):
		_rate_cache[key] = ActivityEstimator.estimate(world, character, activity_id, ratio)
	return _rate_cache[key]
