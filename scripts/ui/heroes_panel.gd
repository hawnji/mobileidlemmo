class_name HeroesPanel
extends ModalPanel
## Roster: every owned adventurer with rarity, stars, level and state.
## Selecting one shows traits, specializations and star-up.

signal hero_selected(character_id: String)

var world: SimulationWorld
var _detail := ""
var _msg: Label


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	refresh()


func refresh() -> void:
	clear_body()
	set_title("Heroes (%d)  |  Workers %d / %d" % [world.character_order.size(), world.active_workers(), world.worker_capacity()])
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	body.add_child(_msg)
	if not _detail.is_empty():
		_show_detail(world.characters[_detail])
		return
	var order := world.character_order.duplicate()
	var ranks: Array = world.registry.recruitment_config.get("rarity_order", [])
	order.sort_custom(func(a, b):
		var ra := ranks.find(world.characters[a].rarity)
		var rb := ranks.find(world.characters[b].rarity)
		return ra > rb if ra != rb else a < b)
	for cid in order:
		var ch: Adventurer = world.characters[cid]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 88)
		b.pressed.connect(func() -> void:
			_detail = cid
			refresh())
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var p := TextureRect.new()
		p.texture = UiTheme.texture(String(ch.definition.get("portrait", "")))
		p.custom_minimum_size = Vector2(64, 64)
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(p)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		v.add_child(UiTheme.label("%s  %s" % [ch.display_name, "*".repeat(ch.stars)], 22, UiTheme.rarity_color(ch.rarity)))
		v.add_child(UiTheme.label("%s %s  |  Lv %d  |  %s  |  %d fragments" % [ch.rarity.capitalize(), ch.definition.get("title", ""),
			ch.character_level(), CharacterStates.label_of(ch.state), int(world.fragments.get(cid, 0))], 15, UiTheme.TEXT_DIM))
		for c in v.get_children():
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(b)


func _show_detail(ch: Adventurer) -> void:
	var reg := world.registry
	var back := UiTheme.button("< All heroes", 18)
	back.pressed.connect(func() -> void:
		_detail = ""
		refresh())
	body.add_child(back)
	body.add_child(UiTheme.label("%s  %s" % [ch.display_name, "*".repeat(ch.stars)], 28, UiTheme.rarity_color(ch.rarity)))
	var d := ch.definition
	for line in ["%s %s, %s" % [ch.rarity.capitalize(), d.get("origin", ""), d.get("title", "")],
			"Character level %d  |  Combat level %d  |  HP %d" % [ch.character_level(), ch.combat_level(), int(ch.max_health())],
			"Passive: %s - %s" % [d.get("passive", {}).get("name", ""), d.get("passive", {}).get("description", "")],
			String(d.get("personality", "")), String(d.get("background", ""))]:
		var l := UiTheme.label(line, 17, UiTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	var select := UiTheme.button("Select on map", 18)
	select.pressed.connect(func() -> void:
		hero_selected.emit(ch.id)
		close())
	body.add_child(select)
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Stars", 22, UiTheme.ACCENT))
	var cost := world.star_up_cost(ch.id)
	var star := UiTheme.button("Star up (%d / %d fragments)" % [int(world.fragments.get(ch.id, 0)), cost] if cost > 0 else "Maximum stars", 18)
	star.disabled = cost < 0 or int(world.fragments.get(ch.id, 0)) < cost
	star.pressed.connect(func() -> void: _act(world.star_up(ch.id)))
	body.add_child(star)
	body.add_child(UiTheme.label("Traits (unlock at character level %s)" % ", ".join(PackedStringArray(reg.get_config("progression.trait_unlock_levels", []).map(func(x): return str(x)))), 22, UiTheme.ACCENT))
	for t in d.get("traits", []):
		var td: Dictionary = reg.traits.get(t, {})
		var have := ch.traits.has(t)
		body.add_child(UiTheme.label("%s %s - %s" % ["[x]" if have else "[ ]", td.get("name", t), td.get("description", "")], 17, UiTheme.GOOD if have else UiTheme.TEXT_DIM))
	body.add_child(UiTheme.label("Specializations (%d / %d slots, skill level %d)" % [ch.specializations.size(), world.specialization_slots(ch),
		int(reg.specialization_config.get("unlock_skill_level", 30))], 22, UiTheme.ACCENT))
	for sid in reg.specializations:
		var sp: Dictionary = reg.specializations[sid]
		var row := HBoxContainer.new()
		var l := UiTheme.label("%s (%s %d) - %s" % [sp.name, reg.skills[sp.skill].name, ch.skills.get_level(String(sp.skill)), sp.description], 16,
			UiTheme.GOOD if ch.specializations.has(sid) else UiTheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		if not ch.specializations.has(sid):
			var b := UiTheme.button("Choose", 16)
			b.disabled = ch.skills.get_level(String(sp.skill)) < int(reg.specialization_config.get("unlock_skill_level", 30))
			b.pressed.connect(func() -> void: _act(world.choose_specialization(ch.id, sid)))
			row.add_child(b)
		body.add_child(row)
	if not ch.specializations.is_empty():
		var r := UiTheme.button("Reset specializations (%d gems)" % int(reg.specialization_config.get("respec_cost", {}).get("gems", 100)), 17)
		r.pressed.connect(func() -> void: _act(world.respec(ch.id)))
		body.add_child(r)


func _act(err: String) -> void:
	refresh()
	_msg.text = err
