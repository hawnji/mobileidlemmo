class_name WorldCamera
extends Camera2D
## Touch-first camera: one-finger drag pans, pinch / wheel zooms, optional
## follow of the selected character. Clamped to the map.

signal tapped(world_pos: Vector2)

const MIN_ZOOM := 0.75
const MAX_ZOOM := 3.0
const TAP_SLOP := 14.0

var follow_target: Node2D
var map_size_px := Vector2(2048, 1536)
var _touches := {}  # index -> position
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0
var _drag_distance := 0.0


func _ready() -> void:
	zoom = Vector2(1.6, 1.6)
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0


func set_map_size(px: Vector2) -> void:
	map_size_px = px
	limit_left = 0
	limit_top = 0
	limit_right = int(px.x)
	limit_bottom = int(px.y)


func _process(_delta: float) -> void:
	if follow_target and is_instance_valid(follow_target):
		global_position = follow_target.global_position


func view_rect() -> Rect2:
	var vp := get_viewport_rect().size / zoom
	var c := get_screen_center_position()
	return Rect2(c - vp * 0.5, vp)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag_distance = 0.0
			elif _touches.size() == 2:
				_pinch_start_dist = _pinch_distance()
				_pinch_start_zoom = zoom.x
		else:
			if _touches.size() == 1 and _drag_distance < TAP_SLOP:
				tapped.emit(get_canvas_transform().affine_inverse() * event.position)
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_drag_distance += event.relative.length()
			if _drag_distance >= TAP_SLOP:
				follow_target = null
				Game.follow_selected = false
				_pan(-event.relative / zoom)
		elif _touches.size() == 2 and _pinch_start_dist > 0.0:
			_set_zoom(_pinch_start_zoom * _pinch_distance() / _pinch_start_dist)
	elif event is InputEventMagnifyGesture:
		_set_zoom(zoom.x * event.factor)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x / 1.1)


func _pan(delta_world: Vector2) -> void:
	var half := get_viewport_rect().size / zoom * 0.5
	var target := get_screen_center_position() + delta_world
	target.x = clampf(target.x, half.x, maxf(half.x, map_size_px.x - half.x))
	target.y = clampf(target.y, half.y, maxf(half.y, map_size_px.y - half.y))
	global_position = target
	reset_smoothing()


func _set_zoom(z: float) -> void:
	var zz := clampf(z, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(zz, zz)


func _pinch_distance() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0
