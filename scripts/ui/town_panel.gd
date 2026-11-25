class_name TownPanel
extends ModalPanel
## Town buildings: levels, effects, next-level cost and the construction
## project, which characters complete through the "Construct" activity.

var world: SimulationWorld
var _msg: Label


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("Greenvale Hollow")
	refresh()


func refresh() -> void:
	clear_body()
	var reg := world.registry
	var town := world.town
	body.add_child(UiTheme.label("Gold %d  |  Workers %d / %d  |  Storage slots %d" % [world.wallet.get_balance("gold"), world.active_workers(),
		world.worker_capacity(), world.storage.max_distinct], 19))
	if not town.project.is_empty():
		var p := town.project
		body.add_child(UiTheme.label("Under construction: %s level %d" % [reg.buildings[p.building].name, int(p.level)], 22, UiTheme.ACCENT))
		var bar := UiTheme.bar(UiTheme.GOOD, 16)
		bar.value = town.progress_ratio()
		body.add_child(bar)
		var builders := 0
		for cid in world.character_order:
			var ch: Adventurer = world.characters[cid]
			if ch.assignment and ch.assignment.activity_id == "construct" and ch.is_busy():
				builders += 1
		body.add_child(UiTheme.label("%d builders. Assign heroes to \"Construct Buildings\" to finish it." % builders, 16, UiTheme.TEXT_DIM))
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	for bid in reg.building_order:
		var b: Dictionary = reg.buildings[bid]
		if int(b.get("phase", 2)) > 3:
			continue
		var is_outpost := String(b.get("kind", "")) == "outpost"
		if is_outpost and not world.is_region_unlocked(String(b.get("region", ""))) and town.level_of(bid) == 0:
			continue
		var lvl := town.level_of(bid)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.add_child(UiTheme.label("%s  -  level %d / %d" % [b.name, lvl, int(b.max_level)], 22, UiTheme.TEXT if lvl > 0 else UiTheme.TEXT_DIM))
		var dl := UiTheme.label(String(b.description), 15, UiTheme.TEXT_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(dl)
		if lvl > 0:
			var now := UiTheme.label("Now: " + _effects(town.level_def(reg, bid, lvl).get("effects", {})), 15, UiTheme.GOOD)
			now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(now)
		var next := town.level_def(reg, bid, lvl + 1)
		if not next.is_empty():
			var cost: Dictionary = next.get("cost", {})
			var parts := ["%d gold" % int(cost.get("gold", 0))]
			for it in cost.get("items", {}):
				parts.append("%d %s (%d)" % [int(cost.items[it]), reg.get_item_name(it), world.storage.get_quantity(it)])
			var nl := UiTheme.label("Next: %s\nCost: %s\nNeeds Construction %d, %ds of work" % [_effects(next.get("effects", {})), ", ".join(parts),
				int(next.get("construction_level", 1)), int(next.get("work_seconds", 60))], 15)
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(nl)
			var err := town.can_start(reg, bid)
			for req in next.get("requires", []):
				if err.is_empty() and not Objectives.is_met(world, req):
					err = "Needs: %s" % Objectives.describe(reg, req)
			if not err.is_empty():
				var el := UiTheme.label(err, 14, UiTheme.BAD)
				el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				box.add_child(el)
			if next.has("local_effects"):
				var le := UiTheme.label("In %s: %s" % [reg.region_name(String(b.get("region", ""))), _effects(next.local_effects)], 15, UiTheme.GOOD)
				le.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				box.add_child(le)
			var btn := UiTheme.button("Build" if lvl == 0 else "Upgrade to %d" % (lvl + 1), 18)
			btn.disabled = not err.is_empty()
			btn.tooltip_text = err
			btn.pressed.connect(func() -> void:
				var e := world.start_construction(bid)
				refresh()
				_msg.text = e)
			box.add_child(btn)
		box.add_child(HSeparator.new())
		body.add_child(box)


static func _effects(eff: Dictionary) -> String:
	var parts := []
	for k in eff:
		var v := float(eff[k])
		var name := String(k).replace("_", " ").replace(".", " ")
		if v > 0.0 and v < 3.0 and (String(k).begins_with("xp") or String(k).begins_with("craft_speed") or String(k).begins_with("damage") or String(k).begins_with("sell_price") or String(k).begins_with("gather_speed")):
			parts.append("%s +%d%%" % [name, roundi((v - 1.0) * 100.0)])
		else:
			parts.append("%s %s" % [name, str(eff[k])])
	return ", ".join(parts) if not parts.is_empty() else "-"
