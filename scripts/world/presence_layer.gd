class_name PresenceLayer
extends Node2D
## Other players' heroes in the same region (online play): translucent blue
## markers with the owner's name, gliding between the positions the server
## broadcasts about once a second. Purely visual; they never interact with
## the local simulation.

const COLOR := Color(0.45, 0.7, 1.0, 0.75)

var tile_px := 32
var _targets := {}  # key -> {pos: Vector2, label: String}
var _shown := {}  # key -> Vector2
var _labels := {}  # key -> Label


func _ready() -> void:
	z_index = 4


func set_players(players: Dictionary) -> void:
	_targets.clear()
	for uid in players:
		var p: Dictionary = players[uid]
		for h in p.get("heroes", []):
			if int(h.get("x", -1)) < 0:
				continue
			var key := "%s/%s" % [uid, h.get("id", "")]
			_targets[key] = {"pos": (Vector2(int(h.x), int(h.y)) + Vector2(0.5, 0.5)) * tile_px, "label": String(p.get("name", "?"))}
	for key in _shown.keys():
		if not _targets.has(key):
			_shown.erase(key)
			_labels[key].queue_free()
			_labels.erase(key)
	for key in _targets:
		if not _shown.has(key):
			_shown[key] = _targets[key].pos
			var l := Label.new()
			l.text = _targets[key].label
			l.add_theme_font_size_override("font_size", 12)
			l.add_theme_color_override("font_color", COLOR.lightened(0.3))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			l.add_theme_constant_override("outline_size", 4)
			l.custom_minimum_size = Vector2(120, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(l)
			_labels[key] = l
	queue_redraw()


func _process(delta: float) -> void:
	if _shown.is_empty():
		return
	for key in _shown:
		_shown[key] = _shown[key].lerp(_targets[key].pos, minf(delta * 3.0, 1.0))
		_labels[key].position = _shown[key] - Vector2(60, tile_px * 1.3)
	queue_redraw()


func _draw() -> void:
	for key in _shown:
		var p: Vector2 = _shown[key]
		draw_circle(p, tile_px * 0.34, COLOR)
		draw_arc(p, tile_px * 0.34, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 2.0)
