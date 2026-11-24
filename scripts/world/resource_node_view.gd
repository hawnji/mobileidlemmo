class_name ResourceNodeView
extends Node2D
## Visual for one ResourceNodeState. Swaps to the depleted sprite and shows
## a small respawn ring; fishing spots bob gently.

var node_state: ResourceNodeState
var node_type: Dictionary
var _sprite: Sprite2D
var _tex_active: Texture2D
var _tex_depleted: Texture2D
var _was_depleted := false
var _t := 0.0


func setup(state: ResourceNodeState, ntype: Dictionary, tile_px: int) -> void:
	node_state = state
	node_type = ntype
	_tex_active = UiTheme.texture(String(ntype.get("sprite", "")))
	_tex_depleted = UiTheme.texture(String(ntype.get("depleted_sprite", "")))
	_sprite = Sprite2D.new()
	_sprite.texture = _tex_active
	_sprite.centered = true
	# Anchor sprite bottom near the tile's bottom edge for y-sorting.
	var h := _tex_active.get_height() if _tex_active else tile_px
	_sprite.offset = Vector2(0, -h / 2.0 + tile_px / 2.0 - 2)
	add_child(_sprite)
	position = Vector2(state.tile * tile_px) + Vector2(tile_px, tile_px) * 0.5
	_t = randf() * TAU
	_refresh()


func _process(delta: float) -> void:
	if node_state == null:
		return
	if node_state.is_depleted() != _was_depleted:
		_refresh()
	if node_state.is_depleted():
		queue_redraw()
	elif String(node_type.get("skill", "")) == "fishing":
		_t += delta
		_sprite.scale = Vector2.ONE * (1.0 + 0.06 * sin(_t * 3.0))


func _refresh() -> void:
	_was_depleted = node_state.is_depleted()
	_sprite.texture = _tex_depleted if _was_depleted and _tex_depleted else _tex_active
	_sprite.modulate = Color(0.85, 0.85, 0.85) if _was_depleted else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if node_state and node_state.is_depleted():
		var frac := 1.0 - node_state.respawn_remaining / node_state.respawn_seconds
		draw_arc(Vector2(0, -20), 5.0, -PI / 2, -PI / 2 + TAU * frac, 16, Color(1, 1, 1, 0.8), 2.0)
