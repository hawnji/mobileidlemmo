class_name OfflineReportPanel
extends ModalPanel
## "While you were away" summary built from an OfflineReport.


func setup(registry: DataRegistry, report: OfflineReport) -> void:
	set_title("While you were away")
	var away := OfflineReport.format_duration(report.elapsed_seconds)
	body.add_child(UiTheme.label("Time away: %s" % away, 24))
	if report.capped:
		body.add_child(UiTheme.label("Offline progress is capped at %s." % OfflineReport.format_duration(report.cap_seconds), 18, UiTheme.BAD))
	body.add_child(UiTheme.label("Total XP earned: %s" % ItemGrid._fmt(int(report.total_xp())), 22, UiTheme.GOOD))
	var cur := PackedStringArray()
	for c in report.currency_gained:
		if int(report.currency_gained[c]) != 0:
			cur.append("%+d %s" % [int(report.currency_gained[c]), registry.currencies.get(c, {}).get("name", c)])
	if not cur.is_empty():
		body.add_child(UiTheme.label(", ".join(cur), 20, UiTheme.ACCENT))
	for b in report.buildings_completed:
		body.add_child(UiTheme.label("%s reached level %d" % [registry.buildings.get(b.building, {}).get("name", b.building), int(b.level)], 20, UiTheme.GOOD))
	for rid in report.explored_after:
		var gain := float(report.explored_after[rid]) - float(report.explored_before.get(rid, 0.0))
		if gain >= 0.005:
			body.add_child(UiTheme.label("Explored %s: %d%% -> %d%%" % [registry.region_name(rid), roundi(float(report.explored_before.get(rid, 0.0)) * 100.0),
				roundi(float(report.explored_after[rid]) * 100.0)], 19, UiTheme.GOOD))
	for d in report.discoveries:
		body.add_child(UiTheme.label("Discovered %s (%s)" % [d.get("name", ""), registry.region_name(String(d.get("region", "")))], 19, UiTheme.rarity_color("rare")))
	for x in report.expeditions:
		body.add_child(UiTheme.label("Expedition %s: %s" % [x.get("name", ""), "success" if x.get("success", false) else "failed"], 19,
			UiTheme.GOOD if x.get("success", false) else UiTheme.BAD))
	for dg in report.dungeons:
		var res := String(dg.get("result", ""))
		body.add_child(UiTheme.label("%s: %s" % [dg.get("name", ""), "cleared" if res == "cleared" else res], 19, UiTheme.GOOD if res == "cleared" else UiTheme.BAD))
	for n in report.joined:
		body.add_child(UiTheme.label("%s joined your settlement" % n, 19, UiTheme.rarity_color("epic")))
	for q in report.quests_ready:
		body.add_child(UiTheme.label("Quest ready to claim: %s" % q, 19, UiTheme.ACCENT))
	if not report.encounters.is_empty():
		body.add_child(UiTheme.label("%d world event(s) came and went" % report.encounters.size(), 17, UiTheme.TEXT_DIM))
	if not report.storage_gained.is_empty():
		body.add_child(UiTheme.label("Added to storage", 22, UiTheme.ACCENT))
		var grid := ItemGrid.new()
		grid.registry = registry
		body.add_child(grid)
		var positive := {}
		for k in report.storage_gained:
			if int(report.storage_gained[k]) > 0:
				positive[k] = report.storage_gained[k]
		grid.show_items(positive)
	var finds := {}  # "name|item" -> count
	for rf in report.rare_finds:
		var key := "%s|%s" % [_name(report, rf.character_id), rf.item_id]
		finds[key] = int(finds.get(key, 0)) + 1
	for key in finds:
		var parts: PackedStringArray = key.split("|")
		var n := int(finds[key])
		body.add_child(UiTheme.label("Rare find: %s found %s%s!" % [parts[0], "" if n == 1 else "%d x " % n, registry.get_item_name(parts[1])], 20, UiTheme.rarity_color("rare")))
	body.add_child(HSeparator.new())
	for cid in report.characters:
		var c: Dictionary = report.characters[cid]
		var box := VBoxContainer.new()
		box.add_child(UiTheme.label(String(c.name), 24, UiTheme.ACCENT))
		var lines := PackedStringArray()
		for s in c.xp:
			var line := "+%s %s XP" % [ItemGrid._fmt(int(c.xp[s])), registry.skills[s].name]
			if c.levels.has(s):
				line += "  (level %d -> %d)" % [c.levels[s][0], c.levels[s][1]]
			lines.append(line)
		var gathered := PackedStringArray()
		for item in c.gathered:
			gathered.append("%d %s" % [c.gathered[item], registry.get_item_name(item)])
		if not gathered.is_empty():
			lines.append("Gathered " + ", ".join(gathered))
		var crafted := PackedStringArray()
		for item in c.get("crafted", {}):
			crafted.append("%d %s" % [c.crafted[item], registry.get_item_name(item)])
		if not crafted.is_empty():
			lines.append("Crafted " + ", ".join(crafted))
		var kills := PackedStringArray()
		for e in c.get("kills", {}):
			kills.append("%d %s" % [c.kills[e], registry.enemies.get(e, {}).get("name", e)])
		if not kills.is_empty():
			lines.append("Defeated " + ", ".join(kills))
		if int(c.get("deaths", 0)) > 0:
			lines.append("Interrupted: knocked out %d time(s)" % int(c.deaths))
		if int(c.trips) > 0:
			lines.append("%d trips to storage" % c.trips)
		if lines.is_empty():
			lines.append("Rested (no assignment)")
		for iv in c.interruptions:
			lines.append("Interrupted: %s" % iv)
		lines.append("Now: %s" % c.state_label)
		for l in lines:
			var lab := UiTheme.label(l, 18, UiTheme.BAD if l.begins_with("Interrupted") else UiTheme.TEXT)
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(lab)
		body.add_child(box)
	var ok := UiTheme.button("Collect", 24)
	ok.custom_minimum_size = Vector2(240, 64)
	ok.pressed.connect(close)
	footer.add_child(ok)


func _name(report: OfflineReport, cid: String) -> String:
	return String(report.characters.get(cid, {}).get("name", cid))
