class_name WorldView
extends Node2D
## Main world presentation: chunked terrain, resource nodes, storage chest,
## characters, location labels, floating text and the camera. Rebuilt
## whenever Game starts a session.

var world: SimulationWorld
var tile_px := 32
var _terrain: ChunkRenderer
var _entities: Node2D
var _labels: Node2D
var _camera: WorldCamera
var _floating: FloatingTextPool
var _day_night: DayNight
var _char_views := {}  # id -> CharacterView
var _enemy_views := {}  # spawn id -> EnemyView
var _vis_accum := 0.0
var _fog: FogOverlay
var _encounter_marks: Node2D
var _encounter_key := ""


func _ready() -> void:
	_day_night = DayNight.new()
	add_child(_day_night)
	_terrain = ChunkRenderer.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	_labels = Node2D.new()
	_labels.name = "LocationLabels"
	_labels.z_index = 5
	add_child(_labels)
	_entities = Node2D.new()
	_entities.name = "Entities"
	_entities.y_sort_enabled = true
	add_child(_entities)
	_fog = FogOverlay.new()
	_fog.name = "Fog"
	add_child(_fog)
	_encounter_marks = Node2D.new()
	_encounter_marks.name = "Encounters"
	_encounter_marks.z_index = 6
	add_child(_encounter_marks)
	_floating = FloatingTextPool.new()
	add_child(_floating)
	_camera = WorldCamera.new()
	add_child(_camera)
	_camera.make_current()
	_camera.tapped.connect(_on_tapped)
	Game.session_started.connect(_on_session_started)
	Game.world_event.connect(_on_world_event)
	Game.selection_changed.connect(_on_selection_changed)
	if Game.world:
		_on_session_started(Game.world)


func _on_session_started(w: SimulationWorld) -> void:
	world = w
	tile_px = int(world.registry.get_config("world.tile_size_px", 32))
	for c in _entities.get_children():
		c.queue_free()
	for c in _labels.get_children():
		c.queue_free()
	_char_views.clear()
	_enemy_views.clear()
	_day_night.world = world
	_terrain.setup(world.registry, world.region)
	_apply_secrets()
	_fog.setup(world, tile_px)
	_encounter_key = ""
	_camera.set_map_size(Vector2(world.grid.width, world.grid.height) * tile_px)
	_camera.global_position = (Vector2(world.spawn_tile) + Vector2(0.5, -2.0)) * tile_px
	_camera.reset_smoothing()
	for nid in world.node_order:
		var n: ResourceNodeState = world.nodes[nid]
		var v := ResourceNodeView.new()
		v.name = nid
		_entities.add_child(v)
		v.setup(n, world.registry.node_types[n.type_id], tile_px)
	var chest := Sprite2D.new()
	chest.name = "Storage"
	chest.texture = UiTheme.texture("res://assets/environments/props/storage_chest.png")
	chest.position = Vector2(world.storage_tile * tile_px) + Vector2(tile_px, tile_px) * 0.5
	chest.offset = Vector2(0, -4)
	_entities.add_child(chest)
	for sid in world.stations:
		var st: Dictionary = world.stations[sid]
		var sp := Sprite2D.new()
		sp.name = sid
		sp.texture = UiTheme.texture("res://assets/environments/props/%s.png" % st.type)
		sp.position = Vector2(st.tile * tile_px) + Vector2(tile_px, tile_px) * 0.5
		sp.offset = Vector2(0, -4)
		_entities.add_child(sp)
	for eid in world.enemy_order:
		var ev := EnemyView.new()
		ev.name = eid
		_entities.add_child(ev)
		ev.setup(world.enemies[eid], tile_px)
		_enemy_views[eid] = ev
	for bid in world.plots:
		var bv := BuildingView.new()
		bv.name = "plot_" + bid
		_entities.add_child(bv)
		bv.setup(world, bid, world.plots[bid], tile_px)
	for bid in world.outposts:
		var ov := BuildingView.new()
		ov.name = "outpost_" + bid
		_entities.add_child(ov)
		ov.setup(world, bid, world.outposts[bid], tile_px)
		var depot := Sprite2D.new()
		depot.name = "depot_" + bid
		depot.texture = UiTheme.texture("res://assets/environments/props/outpost_depot.png")
		depot.position = Vector2(world.outposts[bid].depot_tile * tile_px) + Vector2(tile_px, tile_px) * 0.5
		depot.offset = Vector2(0, -4)
		_entities.add_child(depot)
	for did in world.dungeon_entrances:
		var de := Sprite2D.new()
		de.name = "dungeon_" + did
		de.texture = UiTheme.texture("res://assets/environments/props/dungeon_entrance.png")
		de.position = Vector2(world.dungeon_entrances[did] * tile_px) + Vector2(tile_px, tile_px) * 0.5
		de.offset = Vector2(0, -6)
		_entities.add_child(de)
		var dl := _map_label(String(world.registry.dungeons.get(did, {}).get("name", did)), Color(1, 0.75, 0.6, 0.9))
		dl.position = Vector2(world.dungeon_entrances[did]) * tile_px + Vector2(-80, -40)
		_labels.add_child(dl)
	for lid in world.locations:
		var loc: Dictionary = world.locations[lid]
		var l := Label.new()
		l.text = String(loc.name)
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 0.85))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		var r: Rect2i = loc.rect
		l.position = Vector2(r.position.x + r.size.x * 0.5, r.position.y + 0.3) * tile_px - Vector2(80, 0)
		l.custom_minimum_size = Vector2(160, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_labels.add_child(l)
	for cid in world.character_order:
		_add_character_view(cid)
	_on_selection_changed(Game.selected_character_id)


func _map_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.custom_minimum_size = Vector2(160, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Revealed secret passages are drawn with their real terrain.
func _apply_secrets() -> void:
	_terrain.overrides.clear()
	for sid in world.revealed_secrets:
		var sec: Dictionary = world.secrets.get(sid, {})
		for t in sec.get("tiles", []):
			_terrain.overrides[t] = String(sec.reveals_as)
	_terrain.invalidate()


## Markers above active dynamic encounters (merchant, hero, bonus areas).
func _refresh_encounters() -> void:
	var key := ""
	for enc in world.encounters.active:
		key += "%d," % int(enc.uid)
	if key == _encounter_key:
		return
	_encounter_key = key
	for c in _encounter_marks.get_children():
		c.queue_free()
	for enc in world.encounters.active:
		var loc: Dictionary = world.locations.get(enc.location, {})
		if loc.is_empty():
			continue
		var r: Rect2i = loc.rect
		var at := Vector2(r.position.x + r.size.x * 0.5, r.position.y - 0.6) * tile_px
		if enc.has("tile"):
			at = (Vector2(enc.tile) + Vector2(0.5, -1.2)) * tile_px
		var l := _map_label("! %s" % enc.name, UiTheme.rarity_color("epic"))
		l.position = at - Vector2(80, 0)
		_encounter_marks.add_child(l)


func _add_character_view(cid: String) -> void:
	var cv := CharacterView.new()
	cv.name = cid
	_entities.add_child(cv)
	cv.setup(world.characters[cid], world)
	_char_views[cid] = cv


func _process(delta: float) -> void:
	if world == null:
		return
	var view := _camera.view_rect()
	_terrain.update_visible(view)
	_vis_accum += delta
	if _vis_accum >= 0.25:
		_vis_accum = 0.0
		var grown := view.grow(tile_px * 2.0)
		for cid in _char_views:
			var cv: CharacterView = _char_views[cid]
			cv.on_screen = grown.has_point(cv.position) and cv.character.state != CharacterStates.State.AWAY
			cv.visible = cv.on_screen
		_refresh_encounters()
	if Game.follow_selected and _char_views.has(Game.selected_character_id):
		_camera.follow_target = _char_views[Game.selected_character_id]
	else:
		_camera.follow_target = null


func _on_selection_changed(cid: String) -> void:
	for id in _char_views:
		_char_views[id].set_selected(id == cid)


func _on_tapped(world_pos: Vector2) -> void:
	var best := ""
	var best_d := tile_px * 1.2
	for cid in _char_views:
		var d: float = (_char_views[cid].position + Vector2(0, -10)).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = cid
	Game.select_character(best, false)


func _on_world_event(ev: Dictionary) -> void:
	var joined: bool = (ev.type == "recruited" and ev.get("new", false)) or ev.type == "character_joined"
	if joined and not _char_views.has(ev.character_id) and world.characters.has(ev.character_id):
		_add_character_view(String(ev.character_id))
	if ev.type == "secret_revealed":
		_apply_secrets()
	if ev.type == "encounter_started" and ev.kind == "spawn_enemy":
		for eid in world.enemies:
			if not _enemy_views.has(eid):
				var env := EnemyView.new()
				env.name = eid
				_entities.add_child(env)
				env.setup(world.enemies[eid], tile_px)
				_enemy_views[eid] = env
	if ev.type == "encounter_ended":
		for eid in _enemy_views.keys():
			if not world.enemies.has(eid):
				_enemy_views[eid].queue_free()
				_enemy_views.erase(eid)
	var cv: CharacterView = _char_views.get(ev.get("character_id", ""))
	if cv == null or not cv.on_screen:
		return
	match String(ev.type):
		"combat_hit":
			var en: EnemyView = _enemy_views.get(ev.spawn_id)
			if ev.by == "player" and en:
				_floating.spawn(str(ev.damage) if int(ev.damage) > 0 else "miss", en.position + Vector2(0, -30), Color("ffd27a") if int(ev.damage) > 0 else Color(0.8, 0.8, 0.8))
				if int(ev.damage) > 0:
					en.flash()
				cv.play_attack()
			elif int(ev.damage) > 0:
				_floating.spawn("-%d" % ev.damage, cv.position + Vector2(0, -40), Color("ff6a6a"))
		"enemy_killed":
			var en2: EnemyView = _enemy_views.get(ev.spawn_id)
			if en2 and int(ev.gold) > 0:
				_floating.spawn("+%d gold" % ev.gold, en2.position + Vector2(0, -44), Color("f0c040"))
		"food_eaten":
			_floating.spawn("+%d hp" % int(ev.heal), cv.position + Vector2(0, -40), Color("7ae08a"))
		"item_crafted":
			for it in ev.outputs:
				_floating.spawn("+%d %s" % [ev.outputs[it], world.registry.get_item_name(it)], cv.position + Vector2(0, -52), Color("f3e2b0") if not ev.burnt else Color(0.6, 0.6, 0.6))
			cv.play_gather_effect("smithing")
		"item_gathered":
			_floating.spawn("+%d %s" % [ev.qty, world.registry.get_item_name(ev.item_id)], cv.position + Vector2(0, -52), Color("f3e2b0"))
			var node: ResourceNodeState = world.nodes.get(ev.node_id)
			if node:
				cv.play_gather_effect(String(world.registry.node_types[node.type_id].skill))
		"xp_gained":
			_floating.spawn("+%.1f xp" % ev.xp, cv.position + Vector2(0, -40), Color("9fe08a"))
		"level_up":
			_floating.spawn("LEVEL UP! %s %d" % [world.registry.skills[ev.skill].name, ev.level], cv.position + Vector2(0, -64), UiTheme.ACCENT)
		"rare_drop":
			_floating.spawn("Rare: %s" % world.registry.get_item_name(ev.item_id), cv.position + Vector2(0, -76), UiTheme.rarity_color("rare"))
		"deposited":
			if int(ev.total) > 0:
				_floating.spawn("Deposited %d" % ev.total, cv.position + Vector2(0, -52), Color("e0b85a"))
