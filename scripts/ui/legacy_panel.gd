class_name LegacyPanel
extends ModalPanel
## Phase 5 endgame screen: relics, pets, mounts, mastery, World Ascension and
## the current season. Everything here survives an ascension, hence "Legacy".

var world: SimulationWorld
var _tab := "relics"
var _hero := ""
var _msg: Label
const TABS := [["Relics", "relics"], ["Pets", "pets"], ["Mounts", "mounts"], ["Mastery", "mastery"],
	["Ascension", "ascension"], ["Season", "season"]]


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("Legacy")
	_hero = Game.selected_character_id if world.characters.has(Game.selected_character_id) else String(world.character_order[0])
	refresh()


func _open_tab(t: String) -> void:
	_tab = t
	refresh()


func refresh() -> void:
	clear_body()
	var tabs := HFlowContainer.new()
	for spec in TABS:
		var b := UiTheme.button(spec[0], 17)
		b.custom_minimum_size = Vector2(118, 52)
		b.toggle_mode = true
		b.button_pressed = _tab == spec[1]
		var key: String = spec[1]
		b.pressed.connect(func() -> void: _open_tab(key))
		tabs.add_child(b)
	body.add_child(tabs)
	_msg = UiTheme.label("", 17, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	match _tab:
		"relics": _relics()
		"pets": _pets()
		"mounts": _mounts()
		"mastery": _mastery()
		"ascension": _ascension()
		"season": _season()
	QuestsPanel.wrap_labels(body)


func _say(err: String, ok_text := "") -> void:
	if err.is_empty():
		refresh()
		_msg.text = ok_text
		_msg.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		_msg.text = err
		_msg.add_theme_color_override("font_color", UiTheme.BAD)


func _row(icon: String, title: String, sub: String, color := UiTheme.TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tex := TextureRect.new()
	tex.texture = UiTheme.texture(icon)
	tex.custom_minimum_size = Vector2(48, 48)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(tex)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiTheme.label(title, 20, color))
	var d := UiTheme.label(sub, 15, UiTheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	row.add_child(v)
	return row


func _btn(text: String, cb: Callable, disabled := false) -> Button:
	var b := UiTheme.button(text, 16)
	b.custom_minimum_size = Vector2(120, 48)
	b.disabled = disabled
	b.pressed.connect(cb)
	return b


func _hero_picker() -> void:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(0, 52)
	opt.add_theme_font_size_override("font_size", 18)
	for i in world.character_order.size():
		var cid: String = world.character_order[i]
		opt.add_item(world.characters[cid].display_name, i)
		if cid == _hero:
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void:
		_hero = world.character_order[i]
		refresh())
	var row := HBoxContainer.new()
	row.add_child(UiTheme.label("Hero:", 18))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	body.add_child(row)


func _fx(effects: Dictionary, scale := 1.0) -> String:
	var parts := []
	for k in effects:
		var v := float(effects[k])
		var fam := String(k).get_slice(".", 0)
		var key := String(k).replace(".all", "").replace("_", " ").replace(".", " ")
		if String(world.registry.stat_families.get(fam, "mul")) == "mul":
			parts.append("+%s%% %s" % [String.num((pow(v, scale) - 1.0) * 100.0, 1), key])
		elif absf(v) < 1.0:
			parts.append("+%s%% %s" % [String.num(v * scale * 100.0, 1), key])
		else:
			parts.append("+%s %s" % [String.num(v * scale, 1), key])
	return ", ".join(parts)


# ---------------------------------------------------------------- tabs ----

func _relics() -> void:
	var eg := world.endgame
	body.add_child(SocialPanel._dim("Relics are account-wide. Equipped: %d / %d slots. Relic dust: %d. Find relics in mythic dungeons, buy them from the Skyreach Archivist, or use relic items from Storage." % [
		eg.equipped_relics.size(), eg.relic_slots(), world.wallet.get_balance("relic_dust")]))
	if eg.relics.is_empty():
		body.add_child(SocialPanel._dim("You own no relics yet."))
	for rid in eg.relic_defs:
		if not eg.relics.has(rid):
			continue
		var def: Dictionary = eg.relic_defs[rid]
		var lvl := int(eg.relics[rid])
		var on := eg.equipped_relics.has(rid)
		body.add_child(_row(String(def.icon), "%s  (level %d)%s" % [def.name, lvl, "  - equipped" if on else ""],
			"%s now. %s" % [_fx(def.get("effects_per_level", {}), lvl), def.get("description", "")], UiTheme.rarity_color(String(def.rarity))))
		var row := HBoxContainer.new()
		var rel: String = rid
		if on:
			row.add_child(_btn("Unequip", func() -> void: _say(world.unequip_relic(rel)), false))
		else:
			row.add_child(_btn("Equip", func() -> void: _say(world.equip_relic(rel)), false))
		var cost := eg.relic_upgrade_cost(rid)
		row.add_child(_btn("Upgrade (%d dust)" % cost if cost > 0 else "Max level", func() -> void: _say(world.upgrade_relic(rel), "Upgraded"), cost < 0))
		body.add_child(row)


func _pets() -> void:
	var eg := world.endgame
	_hero_picker()
	body.add_child(SocialPanel._dim("A pet follows one hero and learns from them: it gains %d%% of its owner's XP. Hatch eggs from Storage." % int(float(eg.pet_cfg.get("xp_share", 0.05)) * 100)))
	if eg.pets.is_empty():
		body.add_child(SocialPanel._dim("No pets yet. Eggs drop rarely from gathering, and the stables and Festival Merchant sell some."))
	for pid in eg.pet_defs:
		if not eg.pets.has(pid):
			continue
		var def: Dictionary = eg.pet_defs[pid]
		var p: Dictionary = eg.pets[pid]
		var owner := ""
		for cid in eg.pet_assign:
			if eg.pet_assign[cid] == pid:
				owner = world.characters[cid].display_name
		body.add_child(_row(String(def.icon), "%s  (level %d)" % [def.name, int(p.level)],
			"%s. %s" % [_fx(def.get("effects_per_level", {}), int(p.level)), "With %s" % owner if not owner.is_empty() else "Resting at home"],
			UiTheme.rarity_color(String(def.rarity))))
		var bar := UiTheme.bar(UiTheme.GOOD, 10)
		bar.value = eg.pet_progress(pid) * 100.0
		body.add_child(bar)
		var pet: String = pid
		var row := HBoxContainer.new()
		row.add_child(_btn("Give to %s" % world.characters[_hero].display_name.split(" ")[0], func() -> void: _say(world.assign_pet(_hero, pet))))
		if not owner.is_empty():
			row.add_child(_btn("Send home", func() -> void:
				for cid in eg.pet_assign.keys():
					if eg.pet_assign[cid] == pet:
						_say(world.assign_pet(cid, ""))))
		body.add_child(row)


func _mounts() -> void:
	var eg := world.endgame
	_hero_picker()
	body.add_child(SocialPanel._dim("One rider per mount. A flying mount opens the road to the Celestial Isles."))
	if eg.mounts.is_empty():
		body.add_child(SocialPanel._dim("No mounts yet. Visit the Hollow Stables in Greenvale."))
	for mid in eg.mount_defs:
		if not eg.mounts.has(mid):
			continue
		var def: Dictionary = eg.mount_defs[mid]
		var rider := ""
		for cid in eg.mount_assign:
			if eg.mount_assign[cid] == mid:
				rider = world.characters[cid].display_name
		body.add_child(_row(String(def.icon), String(def.name), "%s %s" % [def.get("description", ""), "Ridden by %s." % rider if not rider.is_empty() else ""],
			UiTheme.rarity_color(String(def.rarity))))
		var m: String = mid
		var row := HBoxContainer.new()
		row.add_child(_btn("Ride with %s" % world.characters[_hero].display_name.split(" ")[0], func() -> void: _say(world.assign_mount(_hero, m))))
		if not rider.is_empty():
			row.add_child(_btn("Stable", func() -> void:
				for cid in eg.mount_assign.keys():
					if eg.mount_assign[cid] == m:
						_say(world.assign_mount(cid, ""))))
		body.add_child(row)


func _mastery() -> void:
	var eg := world.endgame
	_hero_picker()
	var ch: Adventurer = world.characters[_hero]
	var per := float(eg.mastery_cfg.get("xp_per_level", 2000000))
	body.add_child(SocialPanel._dim("Skills at level %d keep earning XP as mastery: every %s XP is a mastery level (max %d) with a bonus for that skill." % [
		ch.skills.table.max_level, ItemGrid._fmt(int(per)), int(eg.mastery_cfg.get("max_level", 20))]))
	var any := false
	for skill in world.registry.skill_order:
		var at_max := ch.skills.get_level(skill) >= ch.skills.table.max_level
		if not at_max and not ch.mastery_xp.has(skill):
			continue
		any = true
		var lvl := eg.mastery_level(ch, skill)
		var cat := String(world.registry.skills[skill].get("category", ""))
		body.add_child(_row("res://assets/ui/skills/%s.png" % skill, "%s mastery %d" % [world.registry.skills[skill].name, lvl],
			"%s per level" % _fx(eg.mastery_cfg.get("effects_per_level", {}).get(cat, {}))))
		var bar := UiTheme.bar(UiTheme.ACCENT, 10)
		bar.value = fmod(float(ch.mastery_xp.get(skill, 0.0)), per) / per * 100.0
		body.add_child(bar)
	if not any:
		body.add_child(SocialPanel._dim("%s has no skill at level %d yet." % [ch.display_name, ch.skills.table.max_level]))


func _ascension() -> void:
	var eg := world.endgame
	var gap := world.ascension_gap()
	body.add_child(UiTheme.label("Ascensions: %d   Points: %d   Score: %d" % [eg.ascensions, world.wallet.get_balance("ascension_points"), eg.score(world)], 20, UiTheme.ACCENT))
	body.add_child(SocialPanel._dim(String(world.registry.endgame.get("ascension", {}).get("description", ""))))
	var asc := _btn("Ascend now (+%d points)" % eg.points_preview(world), func() -> void: _confirm_ascend(), not gap.is_empty())
	asc.custom_minimum_size = Vector2(0, 56)
	body.add_child(asc)
	if not gap.is_empty():
		body.add_child(SocialPanel._dim("Requires: %s" % gap))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Perks", 22, UiTheme.ACCENT))
	for pid in eg.perk_defs:
		var def: Dictionary = eg.perk_defs[pid]
		var rank := int(eg.perks.get(pid, 0))
		var cost := eg.perk_cost(pid)
		var row := _row("res://assets/ui/icons/ascension.png", "%s  (rank %d/%d)" % [def.name, rank, int(def.max_rank)], String(def.description))
		var perk: String = pid
		row.add_child(_btn("%d pts" % cost if cost > 0 else "Max", func() -> void: _say(world.buy_perk(perk), "Perk bought"), cost < 0))
		body.add_child(row)


func _confirm_ascend() -> void:
	clear_body()
	body.add_child(UiTheme.label("Ascend the world?", 24, UiTheme.ACCENT))
	body.add_child(SocialPanel._dim("Your town, storage, gold, regions, quests, reputation and map return to the start. Heroes, their skills and gear, gems, tokens, relics, pets, mounts and mastery stay. This cannot be undone."))
	var row := HBoxContainer.new()
	row.add_child(_btn("Ascend", func() -> void:
		var res: Dictionary = world.ascend()
		if not String(res.error).is_empty():
			refresh()
			_say(String(res.error))
			return
		Game.replace_world(res.world)
		close()))
	row.add_child(_btn("Cancel", refresh))
	body.add_child(row)


func _season() -> void:
	var eg := world.endgame
	var def := eg.season_def()
	if def.is_empty():
		body.add_child(SocialPanel._dim("No season is active."))
		return
	body.add_child(UiTheme.label(String(def.name), 26, UiTheme.ACCENT))
	body.add_child(SocialPanel._dim(String(def.get("description", ""))))
	body.add_child(SocialPanel._dim("Festival tokens: %d. Seasonal contracts appear on the Quests board; the Festival Merchant in Greenvale changes stock with the season." % world.wallet.get_balance("event_tokens")))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Festival Merchant", 22, UiTheme.ACCENT))
	var v: Dictionary = world.registry.vendors.get("festival_merchant", {})
	for entry in v.get("stock", []):
		if not world.vendor_unlocked("festival_merchant", entry):
			continue
		var it: Dictionary = world.registry.items.get(entry.item, {})
		var row := _row(String(it.get("icon", "")), String(it.get("name", entry.item)), "%d festival tokens" % int(entry.price))
		var item: String = entry.item
		row.add_child(_btn("Buy", func() -> void: _say(world.buy_from_vendor("festival_merchant", item, 1), "Bought")))
		body.add_child(row)
