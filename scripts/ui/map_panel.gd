class_name MapPanel
extends ModalPanel
## World map: a minimap of every region with fog of war and hero markers,
## then one card per region with exploration progress, discoveries,
## reputation, outpost level and the unlock requirements / button.

var world: SimulationWorld
var _msg: Label
static var _symbol_colors := {}


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("World Map")
	refresh()


func refresh() -> void:
	clear_body()
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(build_minimap(world))
	tr.custom_minimum_size = Vector2(0, 420)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(tr)
	body.add_child(UiTheme.label("Gold dots are heroes. Dark areas are unexplored; black regions are locked.", 15, UiTheme.TEXT_DIM))
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	for rid in world.registry.map_region_order:
		body.add_child(_region_card(rid))
	wrap_labels(body)


func _region_card(rid: String) -> Control:
	var reg := world.registry
	var r: Dictionary = reg.map_regions[rid]
	var unlocked := world.is_region_unlocked(rid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiTheme.label("%s%s" % [r.get("name", rid), "" if unlocked else "  (locked)"], 24, UiTheme.ACCENT if unlocked else UiTheme.TEXT_DIM))
	var desc := UiTheme.label(String(r.get("description", "")), 15, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var rep := world.quests.reputation_progress(rid)
	var lines := ["Explored %d%%  |  Discoveries %d / %d" % [roundi(world.exploration.explored_pct(rid) * 100.0),
		world.exploration.discovered_count(rid), world.exploration.total_count(rid)]]
	lines.append("Reputation: %s (%d%s)" % [rep.tier_name, int(rep.points), "" if int(rep.next_points) < 0 else " / %d" % int(rep.next_points)])
	var op := String(r.get("outpost", ""))
	if not op.is_empty():
		lines.append("Outpost: %s" % ("level %d (waystone active)" % world.outpost_level(rid) if world.outpost_level(rid) > 0 else "not built"))
	var heroes := 0
	for cid in world.character_order:
		if world.region_at(world.characters[cid].tile) == rid and world.characters[cid].state != CharacterStates.State.AWAY:
			heroes += 1
	lines.append("Heroes here: %d" % heroes)
	var info := UiTheme.label("\n".join(lines), 16)
	box.add_child(info)
	var bar := UiTheme.bar(UiTheme.GOOD, 10)
	bar.value = world.exploration.explored_pct(rid)
	box.add_child(bar)
	if not unlocked:
		var unlock: Dictionary = r.get("unlock", {})
		var reqs := []
		for c in unlock.get("conditions", []):
			reqs.append("%s %s" % ["[x]" if Objectives.is_met(world, c) else "[ ]", Objectives.describe(reg, c)])
		var cost := int(unlock.get("cost", {}).get("gold", 0))
		if cost > 0:
			reqs.append("%s %d gold" % ["[x]" if world.wallet.get_balance("gold") >= cost else "[ ]", cost])
		var rl := UiTheme.label("Requires:\n" + "\n".join(reqs), 15)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(rl)
		var gap := world.region_unlock_gap(rid)
		var btn := UiTheme.button("Unlock %s" % r.get("name", rid), 18)
		btn.disabled = not gap.is_empty()
		btn.tooltip_text = gap
		btn.pressed.connect(func() -> void:
			var e := world.unlock_region(rid)
			refresh()
			_msg.text = e)
		box.add_child(btn)
	box.add_child(HSeparator.new())
	return box


## One pixel per tile: terrain colour, fog, locked regions, heroes.
static func build_minimap(w: SimulationWorld) -> Image:
	_load_symbol_colors(w.registry)
	var ex := w.exploration
	var img := Image.create(ex.width, ex.height, false, Image.FORMAT_RGBA8)
	var rows: Array = w.region.rows
	var locked := {}
	for i in ex.region_ids.size():
		locked[i] = not w.is_region_unlocked(ex.region_ids[i])
	for y in ex.height:
		var row: String = rows[y]
		for x in ex.width:
			var idx := y * ex.width + x
			var c: Color = _symbol_colors.get(row[x], Color(0.3, 0.5, 0.3))
			var ri := ex.region_index[idx]
			if ri != 255 and locked.get(ri, false):
				c = c.darkened(0.85)
			elif ex.revealed[idx] == 0:
				c = c.darkened(0.6)
			img.set_pixel(x, y, c)
	for t in w.deposit_tiles():
		_dot(img, t, Color(0.9, 0.9, 1.0))
	for did in w.dungeon_entrances:
		_dot(img, w.dungeon_entrances[did], Color(0.9, 0.3, 0.3))
	for cid in w.character_order:
		var ch: Adventurer = w.characters[cid]
		if ch.state != CharacterStates.State.AWAY:
			_dot(img, ch.tile, UiTheme.ACCENT)
	return img


static func _dot(img: Image, t: Vector2i, c: Color) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := t + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixel(p.x, p.y, c)


## Average colour of each terrain's atlas cell, so the minimap matches the art.
static func _load_symbol_colors(reg: DataRegistry) -> void:
	if not _symbol_colors.is_empty():
		return
	var tex: Texture2D = load(TilesetFactory.ATLAS_PATH)
	var atlas := tex.get_image() if tex else null
	if atlas and atlas.is_compressed():
		atlas.decompress()
	var px := int(reg.get_config("world.tile_size_px", 32))
	for sym in reg.terrain_by_symbol:
		var a := TilesetFactory.atlas_for_symbol(reg, sym)
		var sum := Color(0, 0, 0, 0)
		var n := 0
		if atlas:
			for sy in range(2, px, 6):
				for sx in range(2, px, 6):
					var p := Vector2i(a.x * px + sx, a.y * px + sy)
					if p.x < atlas.get_width() and p.y < atlas.get_height():
						sum += atlas.get_pixelv(p)
						n += 1
		_symbol_colors[sym] = Color(sum.r / n, sum.g / n, sum.b / n, 1.0) if n > 0 else Color(0.3, 0.5, 0.3)


## Long single-line labels would widen the card past the screen on phones.
static func wrap_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label and c.get_parent() is VBoxContainer:
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrap_labels(c)
