class_name SkillsPanel
extends ModalPanel
## All 24 skills for one character, grouped by category, with level and XP
## progress. Skills not yet playable are shown but marked with their phase.

var world: SimulationWorld
var character: Adventurer
var _refresh_timer := 0.0


func setup(p_world: SimulationWorld, p_character: Adventurer) -> void:
	world = p_world
	character = p_character
	set_title("%s - Skills" % character.display_name)
	_build()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer > 1.0:
		_refresh_timer = 0.0
		_build()


func _build() -> void:
	clear_body()
	var reg := world.registry
	var total := character.skills.total_level(reg.skill_order)
	body.add_child(UiTheme.label("Total level %d   |   Character level %d" % [total, character.character_level(reg)], 20, UiTheme.TEXT_DIM))
	for cat in ["gathering", "production", "combat", "utility"]:
		body.add_child(UiTheme.label(cat.capitalize(), 22, UiTheme.CATEGORY_COLORS[cat]))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		body.add_child(grid)
		for sid in reg.skill_order:
			var s: Dictionary = reg.skills[sid]
			if s.category == cat:
				grid.add_child(_skill_cell(s))


func _skill_cell(s: Dictionary) -> Control:
	var table := world.registry.skill_xp_table
	var xp := character.skills.get_xp(s.id)
	var lvl := character.skills.get_level(s.id)
	var playable := s.get("implemented_phase") != null
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT, UiTheme.CATEGORY_COLORS[s.category].darkened(0.3), 10, 2, 8))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(320, 0)
	p.modulate = Color.WHITE if playable else Color(1, 1, 1, 0.55)
	var h := HBoxContainer.new()
	p.add_child(h)
	var icon := TextureRect.new()
	icon.texture = UiTheme.texture(String(s.get("icon", "")))
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var top := HBoxContainer.new()
	var n := UiTheme.label(String(s.name), 20)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	top.add_child(UiTheme.label(str(lvl), 22, UiTheme.ACCENT))
	v.add_child(top)
	var bar := UiTheme.bar(UiTheme.CATEGORY_COLORS[s.category], 8)
	bar.value = table.progress_to_next(xp)
	v.add_child(bar)
	var sub := "%s xp" % ItemGrid._fmt(int(xp))
	if lvl < table.max_level:
		sub += "  |  %s to %d" % [ItemGrid._fmt(int(table.xp_to_next_level(xp))), lvl + 1]
	if not playable:
		sub = "Coming in a later phase"
	v.add_child(UiTheme.label(sub, 14, UiTheme.TEXT_DIM))
	p.tooltip_text = String(s.get("description", ""))
	return p
