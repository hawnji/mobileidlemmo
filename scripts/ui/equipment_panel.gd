class_name EquipmentPanel
extends ModalPanel
## A character's gear: nine slots with durability and upgrade level, repair,
## upgrade and unequip, plus every item in storage or the armory that fits.

var world: SimulationWorld
var character: Adventurer
var _msg: Label


func setup(p_world: SimulationWorld, p_character: Adventurer) -> void:
	world = p_world
	character = p_character
	set_title("%s's Gear" % character.display_name.split(" ")[0])
	refresh()


func refresh() -> void:
	clear_body()
	var reg := world.registry
	body.add_child(UiTheme.label("HP %d / %d  |  Armor %d  |  Accuracy +%d  |  %s style" % [int(character.health), int(character.max_health()),
		int(character.stat("armor")), int(character.stat("accuracy")), character.combat_style().capitalize()], 18, UiTheme.TEXT_DIM))
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	for slot in Adventurer.SLOTS:
		var row := HBoxContainer.new()
		var name := UiTheme.label(String(slot).replace("_", " ").capitalize(), 18, UiTheme.TEXT_DIM)
		name.custom_minimum_size = Vector2(150, 0)
		row.add_child(name)
		if character.equipment.has(slot):
			var inst: Dictionary = character.equipment[slot]
			var item: Dictionary = reg.items.get(inst.item_id, {})
			var txt := "%s%s  %d/%d" % [item.get("name", inst.item_id), " +%d" % inst.upgrade if int(inst.upgrade) > 0 else "", int(inst.durability), int(item.get("max_durability", 1))]
			var l := UiTheme.label(txt, 18, UiTheme.BAD if int(inst.durability) == 0 else UiTheme.rarity_color(String(item.get("rarity", "common"))))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var cost := EquipmentService.repair_cost(world, inst)
			if cost > 0:
				row.add_child(_btn("Repair %dg" % cost, func(): return world.repair(character.id, slot)))
			var up := EquipmentService.upgrade_cost(world, inst)
			row.add_child(_btn("+1 (%dg)" % int(up.gold), func(): return world.upgrade_equipment(character.id, slot)))
			row.add_child(_btn("Remove", func(): return world.unequip(character.id, slot)))
		else:
			var l := UiTheme.label("empty", 18, UiTheme.TEXT_DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
		body.add_child(row)
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Available in storage", 22, UiTheme.ACCENT))
	var any := false
	for item_id in world.storage.items():
		var item: Dictionary = reg.items.get(item_id, {})
		if String(item.get("equip_slot", "")).is_empty():
			continue
		any = true
		body.add_child(_candidate(item_id, item, "x%d" % world.storage.get_quantity(item_id), 0))
	for inst in world.armory:
		var item: Dictionary = reg.items.get(inst.item_id, {})
		any = true
		body.add_child(_candidate(String(inst.item_id), item, "%d/%d%s" % [int(inst.durability), int(item.max_durability), " +%d" % inst.upgrade if int(inst.upgrade) > 0 else ""], int(inst.uid)))
	if not any:
		body.add_child(UiTheme.label("No equipment yet. Forge or craft some, or find it while hunting.", 18, UiTheme.TEXT_DIM))


func _candidate(item_id: String, item: Dictionary, extra: String, uid: int) -> Control:
	var row := HBoxContainer.new()
	var stats := []
	for k in item.get("stats", {}):
		stats.append("%s %s" % [k.replace("_", " ").replace(".", " "), str(item.stats[k])])
	var req := EquipmentService.requirement_error(world, character, item)
	var l := UiTheme.label("%s (%s)  %s  -  %s" % [item.get("name", item_id), item.get("equip_slot", ""), extra, ", ".join(stats)], 17,
		UiTheme.TEXT if req.is_empty() else UiTheme.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var b := _btn("Equip", func(): return world.equip(character.id, item_id, uid))
	b.disabled = not req.is_empty()
	b.tooltip_text = req
	row.add_child(b)
	return row


func _btn(text: String, action: Callable) -> Button:
	var b := UiTheme.button(text, 17)
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(func() -> void:
		var err: String = action.call()
		refresh()
		_msg.text = err)
	return b
