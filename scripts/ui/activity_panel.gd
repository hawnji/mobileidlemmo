class_name ActivityPanel
extends ModalPanel
## Assignment builder: pick a category and activity (and a recipe or enemy
## priority where relevant), review the expected results, configure the
## automation rules, then start.

const CATEGORIES := [["gathering", "Gather"], ["crafting", "Craft"], ["combat", "Fight"], ["construction", "Build"]]

var world: SimulationWorld
var character: Adventurer
var _category := "gathering"
var _selected_activity := ""
var _recipe := ""
var _return_ratio := 1.0
var _mode := Assignment.ContinueMode.REPEAT
var _quantity := 100
var _heal := 0.5
var _retreat := 0.25
var _food := 12
var _auto_repair := true
var _priority := ""
var _start_btn: Button
var _error_label: Label
## Route being built, per character (kept while the panel is reopened).
static var _routes := {}  # character_id -> {steps: Array[Assignment], loop: bool}


func setup(p_world: SimulationWorld, p_character: Adventurer) -> void:
	world = p_world
	character = p_character
	set_title("Assign %s" % character.display_name)
	var asg := character.assignment
	if asg and world.registry.activities.has(asg.activity_id):
		_selected_activity = asg.activity_id
		_category = String(world.registry.activities[asg.activity_id].get("type", "gathering"))
		_return_ratio = asg.return_fill_ratio
		_mode = asg.continue_mode
		_quantity = maxi(asg.target_quantity, 1) if _mode == Assignment.ContinueMode.UNTIL_QUANTITY else 100
		_recipe = asg.recipe_id
		_heal = asg.heal_threshold
		_retreat = asg.retreat_threshold()
		_food = asg.food_supply
		_auto_repair = asg.auto_repair
		_priority = asg.enemy_priority[0] if not asg.enemy_priority.is_empty() else ""
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
		if String(world.registry.activities[aid].get("skill", "")) == primary:
			_category = String(world.registry.activities[aid].get("type", "gathering"))
			return aid
	return world.registry.activity_order[0]


func _act() -> Dictionary:
	return world.registry.activities.get(_selected_activity, {})


func _rebuild() -> void:
	clear_body()
	var tabs := HBoxContainer.new()
	for c in CATEGORIES:
		var b := UiTheme.button(c[1], 20)
		b.toggle_mode = true
		b.button_pressed = _category == c[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = c[0]
		b.pressed.connect(func() -> void:
			_category = key
			_selected_activity = ""
			for aid in world.registry.activity_order:
				if String(world.registry.activities[aid].get("type", "")) == key:
					_selected_activity = aid
					break
			_recipe = ""
			_rebuild())
		tabs.add_child(b)
	body.add_child(tabs)
	for aid in world.registry.activity_order:
		if String(world.registry.activities[aid].get("type", "gathering")) == _category:
			body.add_child(_activity_row(aid))
	var act := _act()
	match _category:
		"crafting":
			_recipe_list(act)
		"combat":
			_combat_options(act)
		"construction":
			_construction_info()
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Automation", 24, UiTheme.ACCENT))
	if _category == "gathering" or _category == "combat":
		body.add_child(UiTheme.label("Return to storage when bag is", 18, UiTheme.TEXT_DIM))
		body.add_child(_choice_row([[0.5, "50%"], [0.75, "75%"], [1.0, "Full"]], _return_ratio, func(v): _return_ratio = v))
	if _category != "construction":
		body.add_child(UiTheme.label("Keep going", 18, UiTheme.TEXT_DIM))
		body.add_child(_choice_row([[Assignment.ContinueMode.REPEAT, "Repeat"], [Assignment.ContinueMode.UNTIL_QUANTITY, "Until amount"], [Assignment.ContinueMode.SINGLE_TRIP, "One trip"]], _mode, func(v): _mode = v))
		if _mode == Assignment.ContinueMode.UNTIL_QUANTITY:
			var q := HBoxContainer.new()
			q.add_child(UiTheme.label("Target", 20))
			var spin := SpinBox.new()
			spin.min_value = 1
			spin.max_value = 100000
			spin.step = 1
			spin.value = _quantity
			spin.custom_minimum_size = Vector2(180, 52)
			spin.value_changed.connect(func(v: float) -> void: _quantity = int(v))
			q.add_child(spin)
			q.add_child(UiTheme.label("kills" if _category == "combat" else world.registry.get_item_name(_primary_item()), 20))
			body.add_child(q)
	var rep := CheckBox.new()
	rep.text = "Repair equipment with gold at storage"
	rep.button_pressed = _auto_repair
	rep.toggled.connect(func(on: bool) -> void: _auto_repair = on)
	body.add_child(rep)
	body.add_child(HSeparator.new())
	body.add_child(_estimate_box())
	body.add_child(HSeparator.new())
	_route_box()
	_error_label = UiTheme.label("", 20, UiTheme.BAD)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_error_label)
	_start_btn.disabled = _selected_activity.is_empty() or not _meets_requirement(_selected_activity) \
		or (_category == "crafting" and _recipe.is_empty())


func _choice_row(options: Array, current: Variant, setter: Callable) -> Control:
	var row := HBoxContainer.new()
	for opt in options:
		var b := UiTheme.button(opt[1], 20)
		b.toggle_mode = true
		b.button_pressed = (current is float and is_equal_approx(current, opt[0])) or (not (current is float) and current == opt[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			setter.call(opt[0])
			_rebuild())
		row.add_child(b)
	return row


func _primary_item() -> String:
	var act := _act()
	if String(act.get("type", "")) == "crafting":
		var r: Dictionary = world.registry.recipes.get(_recipe, {})
		return String(r.outputs.keys()[0]) if not r.is_empty() else ""
	return String(world.registry.node_types.get(act.get("node_type", ""), {}).get("yield", {}).get("item", ""))


func _meets_requirement(aid: String) -> bool:
	var act: Dictionary = world.registry.activities[aid]
	var skill := String(act.get("skill", ""))
	return skill.is_empty() or character.skills.get_level(skill) >= int(act.get("required_level", 1))


func _activity_row(aid: String) -> Control:
	var reg := world.registry
	var act: Dictionary = reg.activities[aid]
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = aid == _selected_activity
	b.custom_minimum_size = Vector2(0, 84)
	b.disabled = not _meets_requirement(aid)
	b.pressed.connect(func() -> void:
		_selected_activity = aid
		_recipe = ""
		_priority = ""
		_rebuild())
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon_path := ""
	var detail := ""
	match String(act.get("type", "gathering")):
		"gathering":
			var ntype: Dictionary = reg.node_types[act.node_type]
			icon_path = String(reg.items.get(ntype.yield.item, {}).get("icon", ""))
			detail = "%s  |  %s %d  |  %.1f xp  |  %.1fs" % [world.locations.get(act.get("default_destination", ""), {}).get("name", "Anywhere"),
				reg.skills[act.skill].name, int(act.required_level), float(ntype.xp), float(ntype.gather_seconds)]
		"crafting":
			var recipes := reg.recipes_for_station(String(act.station))
			icon_path = "res://assets/environments/props/%s.png" % act.station
			detail = "%s  |  %d recipes" % [reg.skills[act.skill].name, recipes.size()]
		"combat":
			var names := {}
			for e in world.enemies_in(String(act.get("default_destination", ""))):
				names["%s (L%d)" % [e.def.name, int(e.def.level)]] = true
			icon_path = "res://assets/enemies/%s.png" % world.enemies_in(String(act.default_destination))[0].enemy_id if not world.enemies_in(String(act.default_destination)).is_empty() else ""
			detail = ", ".join(PackedStringArray(names.keys()))
		"construction":
			icon_path = "res://assets/ui/icons/build.png"
			detail = "Work on the active town project"
	var icon := TextureRect.new()
	icon.texture = UiTheme.texture(icon_path)
	icon.custom_minimum_size = Vector2(52, 52)
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
	v.add_child(UiTheme.label(String(act.name), 22))
	var d := UiTheme.label(detail, 15, UiTheme.TEXT_DIM)
	d.clip_text = true
	v.add_child(d)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _recipe_list(act: Dictionary) -> void:
	if act.is_empty():
		return
	var reg := world.registry
	body.add_child(UiTheme.label("Recipe", 22, UiTheme.ACCENT))
	for rid in reg.recipes_for_station(String(act.station)):
		var r: Dictionary = reg.recipes[rid]
		var ok := character.skills.get_level(String(r.skill)) >= int(r.required_level) and world.town.meets(r.get("requires_building", {}))
		var ins := []
		for it in r.inputs:
			ins.append("%d %s (%d)" % [int(r.inputs[it]), reg.get_item_name(it), world.storage.get_quantity(it)])
		var b := UiTheme.button("%s  -  %s" % [r.name, ", ".join(ins)], 17)
		b.toggle_mode = true
		b.button_pressed = rid == _recipe
		b.disabled = not ok
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		if not ok:
			var need := "%s %d" % [reg.skills[r.skill].name, int(r.required_level)]
			for bid in r.get("requires_building", {}):
				need += ", %s %d" % [reg.buildings[bid].name, int(r.requires_building[bid])]
			b.text = "%s  -  needs %s" % [r.name, need]
		b.pressed.connect(func() -> void:
			_recipe = rid
			_rebuild())
		body.add_child(b)


func _combat_options(act: Dictionary) -> void:
	if act.is_empty():
		return
	var ids := {}
	for e in world.enemies_in(String(act.default_destination)):
		ids[e.enemy_id] = e.def
	body.add_child(UiTheme.label("Fight first", 22, UiTheme.ACCENT))
	var opts: Array = [["", "Nearest"]]
	for eid in ids:
		opts.append([eid, "%s L%d" % [ids[eid].name, int(ids[eid].level)]])
	body.add_child(_choice_row(opts, _priority, func(v): _priority = v))
	body.add_child(UiTheme.label("Eat food below", 18, UiTheme.TEXT_DIM))
	body.add_child(_choice_row([[0.3, "30%"], [0.5, "50%"], [0.7, "70%"]], _heal, func(v): _heal = v))
	body.add_child(UiTheme.label("Retreat with no food below", 18, UiTheme.TEXT_DIM))
	body.add_child(_choice_row([[0.15, "15%"], [0.25, "25%"], [0.4, "40%"]], _retreat, func(v): _retreat = v))
	body.add_child(UiTheme.label("Food to carry", 18, UiTheme.TEXT_DIM))
	body.add_child(_choice_row([[0, "None"], [6, "6"], [12, "12"], [20, "20"]], _food, func(v): _food = v))
	body.add_child(UiTheme.label("HP %d / %d  |  %s style" % [int(character.health), int(character.max_health()), character.combat_style().capitalize()], 18))


func _construction_info() -> void:
	var p: Dictionary = world.town.project
	if p.is_empty():
		body.add_child(UiTheme.label("No project. Start one from the Town screen.", 20, UiTheme.BAD))
	else:
		body.add_child(UiTheme.label("Building %s level %d (%d%%)" % [world.registry.buildings[p.building].name, int(p.level), int(world.town.progress_ratio() * 100)], 20))


func _make_assignment() -> Assignment:
	var a := Assignment.create(character.id, _act())
	a.return_fill_ratio = _return_ratio if (_category == "gathering" or _category == "combat") else 1.0
	a.continue_mode = _mode if _category != "construction" else Assignment.ContinueMode.REPEAT
	a.target_quantity = _quantity if a.continue_mode == Assignment.ContinueMode.UNTIL_QUANTITY else 0
	a.recipe_id = _recipe
	a.heal_threshold = _heal
	a.safety.return_below_health_ratio = _retreat
	a.food_supply = _food
	a.auto_repair = _auto_repair
	if not _priority.is_empty():
		a.enemy_priority.append(_priority)
	return a


func _estimate_box() -> Control:
	var v := VBoxContainer.new()
	v.add_child(UiTheme.label("Expected results", 24, UiTheme.ACCENT))
	if _selected_activity.is_empty() or (_category == "crafting" and _recipe.is_empty()):
		return v
	var e := ActivityEstimator.estimate(world, character, _selected_activity, _return_ratio, _make_assignment())
	if not e.get("reachable", false):
		v.add_child(UiTheme.label("Destination unreachable", 20, UiTheme.BAD))
		return v
	var skill_name := String(world.registry.skills.get(e.skill, {}).get("name", ""))
	v.add_child(UiTheme.label("~%s %s XP / hour" % [_n(e.xp_per_hour), skill_name], 22, UiTheme.GOOD))
	match _category:
		"gathering":
			v.add_child(UiTheme.label("~%s %s / hour" % [_n(e.items_per_hour), world.registry.get_item_name(e.item)], 20))
			v.add_child(UiTheme.label("%d per trip, %.1fs each, %.0fs round trip" % [e.trip_items, e.gather_seconds, e.round_trip_seconds], 18, UiTheme.TEXT_DIM))
		"crafting":
			v.add_child(UiTheme.label("~%s %s / hour" % [_n(e.items_per_hour), world.registry.get_item_name(e.item)], 20))
			var ins := []
			for it in e.inputs_per_hour:
				ins.append("%s %s" % [_n(e.inputs_per_hour[it]), world.registry.get_item_name(it)])
			v.add_child(UiTheme.label("Uses ~" + ", ".join(ins) + " / hour", 18, UiTheme.TEXT_DIM))
		"combat":
			v.add_child(UiTheme.label("~%s %s kills / hour, ~%s gold" % [_n(e.kills_per_hour), e.enemy, _n(e.gold_per_hour)], 20))
			var col := UiTheme.GOOD if e.risk == "Low" else (UiTheme.ACCENT if e.risk == "Medium" else UiTheme.BAD)
			v.add_child(UiTheme.label("Risk: %s  |  %d%% hit chance  |  ~%.1f damage taken per kill" % [e.risk, int(e.hit_chance * 100), e.damage_per_kill], 18, col))
	return v


func _route() -> Dictionary:
	if not _routes.has(character.id):
		_routes[character.id] = {"steps": [], "loop": false}
	return _routes[character.id]


## Route builder: queue this configuration as a step, then run the steps in
## order (optionally looping). Saved routes can be loaded for any hero.
func _route_box() -> void:
	var r := _route()
	body.add_child(UiTheme.label("Route builder", 24, UiTheme.ACCENT))
	var hint := UiTheme.label("Add steps that end (Until amount or One trip), then start the route.", 15, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	var i := 0
	for st in r.steps:
		var a: Assignment = st
		var act: Dictionary = world.registry.activities.get(a.activity_id, {})
		var what := String(act.get("name", a.activity_id))
		if not a.recipe_id.is_empty():
			what += " (%s)" % world.registry.recipes.get(a.recipe_id, {}).get("name", "")
		body.add_child(UiTheme.label("%d. %s  -  %s" % [i + 1, what, a.describe_continue_rule()], 17))
		i += 1
	var row := HBoxContainer.new()
	var add := UiTheme.button("Add step", 18)
	add.disabled = _start_btn.disabled or _mode == Assignment.ContinueMode.REPEAT
	add.pressed.connect(func() -> void:
		r.steps.append(_make_assignment())
		_rebuild())
	row.add_child(add)
	var loop := CheckBox.new()
	loop.text = "Loop"
	loop.button_pressed = r.loop
	loop.toggled.connect(func(on: bool) -> void: r.loop = on)
	row.add_child(loop)
	var clear := UiTheme.button("Clear", 18)
	clear.pressed.connect(func() -> void:
		r.steps.clear()
		_rebuild())
	row.add_child(clear)
	var go := UiTheme.button("Start route", 18)
	go.disabled = r.steps.is_empty()
	go.pressed.connect(func() -> void:
		var err := world.start_route(character.id, r.steps, r.loop, "Route")
		if not err.is_empty():
			_error_label.text = err
			return
		close())
	row.add_child(go)
	body.add_child(row)
	var row2 := HBoxContainer.new()
	var save := UiTheme.button("Save as template", 16)
	save.disabled = r.steps.is_empty()
	save.pressed.connect(func() -> void:
		world.save_route_template("%s route %d" % [character.display_name.split(" ")[0], world.route_templates.size() + 1], r.steps, r.loop)
		_rebuild())
	row2.add_child(save)
	for tname in world.route_templates:
		var b := UiTheme.button("Load: %s" % tname, 16)
		b.pressed.connect(func() -> void:
			var t: Dictionary = world.route_templates[tname]
			r.steps.clear()
			for d in t.steps:
				var a := Assignment.from_dict(d)
				a.character_id = character.id
				r.steps.append(a)
			r.loop = bool(t.loop)
			_rebuild())
		row2.add_child(b)
	body.add_child(row2)


static func _n(x: float) -> String:
	return str(roundi(x)) if x < 10000 else "%.1fk" % (x / 1000.0)


func _start() -> void:
	var err := world.assign_activity(character.id, _make_assignment())
	if not err.is_empty():
		_error_label.text = err
		return
	close()
