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
var _vis_accum := 0.0


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
	_day_night.world = world
	_terrain.setup(world.registry, world.region)
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
		var cv := CharacterView.new()
		cv.name = cid
		_entities.add_child(cv)
		cv.setup(world.characters[cid], world)
		_char_views[cid] = cv
	_on_selection_changed(Game.selected_character_id)


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
			cv.on_screen = grown.has_point(cv.position)
			cv.visible = cv.on_screen
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
	var cv: CharacterView = _char_views.get(ev.get("character_id", ""))
	if cv == null or not cv.on_screen:
		return
	match String(ev.type):
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
