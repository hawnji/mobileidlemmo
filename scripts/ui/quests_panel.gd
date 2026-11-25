class_name QuestsPanel
extends ModalPanel
## Quests (main story, regional, contracts) with objective progress and a
## claim button, plus regional reputation and the reputation vendors.

var world: SimulationWorld
var _tab := "quests"
var _msg: Label
const CATEGORY_NAMES := {"main": "Main story", "regional": "Regional", "contract": "Contracts"}


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	refresh()


func refresh() -> void:
	clear_body()
	set_title("Quests" if _tab == "quests" else "Reputation & Vendors")
	var tabs := HBoxContainer.new()
	for spec in [["Quests", "quests"], ["Reputation & Vendors", "rep"]]:
		var b := UiTheme.button(spec[0], 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = _tab == spec[1]
		var key: String = spec[1]
		b.pressed.connect(func() -> void:
			_tab = key
			refresh())
		tabs.add_child(b)
	body.add_child(tabs)
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	if _tab == "quests":
		_quests()
	else:
		_reputation()
	wrap_labels(body)


func _quests() -> void:
	var reg := world.registry
	var by_cat := {}
	for qid in reg.quest_order:
		if world.quests.active.has(qid):
			var cat := String(reg.quests[qid].get("category", "main"))
			if not by_cat.has(cat):
				by_cat[cat] = []
			by_cat[cat].append(qid)
	if by_cat.is_empty():
		body.add_child(UiTheme.label("No active quests. New ones appear as you progress.", 18, UiTheme.TEXT_DIM))
	for cat in ["main", "regional", "contract"]:
		if not by_cat.has(cat):
			continue
		body.add_child(UiTheme.label(CATEGORY_NAMES.get(cat, cat), 22, UiTheme.ACCENT))
		for qid in by_cat[cat]:
			body.add_child(_quest_card(qid))
	# Contracts cooling down.
	var cooling := []
	for qid in world.quests.cooldowns:
		var left := float(world.quests.cooldowns[qid]) - world.sim_time
		if left > 0.0:
			cooling.append("%s: back in %s" % [reg.quests[qid].name, OfflineReport.format_duration(left)])
	if not cooling.is_empty():
		var cl := UiTheme.label("Cooling down\n" + "\n".join(cooling), 15, UiTheme.TEXT_DIM)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(cl)
	var done := 0
	for qid in world.quests.completed:
		done += int(world.quests.completed[qid])
	body.add_child(UiTheme.label("Quests completed: %d" % done, 15, UiTheme.TEXT_DIM))


func _quest_card(qid: String) -> Control:
	var reg := world.registry
	var q: Dictionary = reg.quests[qid]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiTheme.label(String(q.name), 20))
	if q.has("description"):
		var d := UiTheme.label(String(q.description), 14, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
	var prog := world.quests.objective_progress(world, qid)
	var objs: Array = q.get("objectives", [])
	for i in objs.size():
		var p: Vector2i = prog[i]
		var met := p.x >= p.y
		var l := UiTheme.label("%s %s  (%d / %d)" % ["[x]" if met else "[ ]", Objectives.describe(reg, objs[i]), mini(p.x, p.y), p.y], 15,
			UiTheme.GOOD if met else UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	box.add_child(UiTheme.label("Rewards: %s" % describe_rewards(reg, q.get("rewards", {})), 14, UiTheme.ACCENT))
	if world.quests.is_complete(world, qid):
		var b := UiTheme.button("Claim", 18)
		b.pressed.connect(func() -> void:
			var e := world.claim_quest(qid)
			refresh()
			_msg.text = e)
		box.add_child(b)
	box.add_child(HSeparator.new())
	return box


static func describe_rewards(reg: DataRegistry, r: Dictionary) -> String:
	var parts := []
	for c in r.get("currencies", {}):
		var v: Variant = r.currencies[c]
		parts.append("%s %s" % [("%d-%d" % [int(v[0]), int(v[1])]) if v is Array else str(int(v)), String(c).replace("_", " ")])
	var items: Variant = r.get("items", {})
	if items is Dictionary:
		for it in items:
			parts.append("%d %s" % [int(items[it]), reg.get_item_name(it)])
	elif items is Array:
		for e in items:
			parts.append("%s%s" % [reg.get_item_name(String(e.item)), "" if float(e.get("chance", 1.0)) >= 1.0 else " (chance)"])
	for reg_id in r.get("reputation", {}):
		parts.append("+%d %s reputation" % [int(r.reputation[reg_id]), reg.region_name(String(reg_id))])
	for s in r.get("xp", {}):
		parts.append("%d %s xp" % [int(r.xp[s]), reg.skills.get(s, {}).get("name", s)])
	if r.has("character"):
		parts.append("%s joins" % reg.characters.get(r.character, {}).get("name", r.character))
	return ", ".join(parts) if not parts.is_empty() else "-"


func _reputation() -> void:
	var reg := world.registry
	for rid in reg.map_region_order:
		var p := world.quests.reputation_progress(rid)
		body.add_child(UiTheme.label("%s: %s  (%d%s)" % [reg.region_name(rid), p.tier_name, int(p.points),
			"" if int(p.next_points) < 0 else " / %d" % int(p.next_points)], 18))
		var bar := UiTheme.bar(UiTheme.ACCENT, 8)
		bar.value = 1.0 if int(p.next_points) < 0 else float(p.points) / float(p.next_points)
		body.add_child(bar)
	body.add_child(HSeparator.new())
	var tiers := reg.reputation_tiers()
	for v in reg.vendors.values():
		var vid := String(v.id)
		var open := world.is_region_unlocked(String(v.region))
		body.add_child(UiTheme.label("%s  -  %s" % [v.name, reg.region_name(String(v.region))], 22, UiTheme.ACCENT if open else UiTheme.TEXT_DIM))
		if not open:
			body.add_child(UiTheme.label("Unlock the region to trade here.", 15, UiTheme.TEXT_DIM))
			continue
		for entry in v.get("stock", []):
			var row := HBoxContainer.new()
			var ok := world.vendor_unlocked(vid, entry)
			var l := UiTheme.label("%s  -  %d %s%s" % [reg.get_item_name(String(entry.item)), int(entry.price), v.get("currency", "gold"),
				"" if ok else "  (needs %s)" % tiers[int(entry.get("tier", 0))].name], 16, UiTheme.TEXT if ok else UiTheme.TEXT_DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var b := UiTheme.button("Buy", 16)
			b.disabled = not ok
			var item := String(entry.item)
			b.pressed.connect(func() -> void:
				var e := world.buy_from_vendor(vid, item, 1)
				refresh()
				_msg.text = e if not e.is_empty() else "Bought %s" % reg.get_item_name(item)
				_msg.add_theme_color_override("font_color", UiTheme.BAD if not e.is_empty() else UiTheme.GOOD))
			row.add_child(b)
			body.add_child(row)
		body.add_child(HSeparator.new())


## Long single-line labels would widen the card past the screen on phones.
static func wrap_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label and c.get_parent() is VBoxContainer:
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrap_labels(c)
