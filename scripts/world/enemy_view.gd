class_name EnemyView
extends Node2D
## Visual for one EnemyState: sprite, health bar while hurt, variant tint and
## a respawn ring while dead. Read-only.

const VARIANT_TINT := {"champion": Color(1.0, 0.85, 0.6), "elite": Color(0.75, 0.85, 1.2), "ancient": Color(1.2, 1.0, 0.6),
	"corrupted": Color(0.9, 0.5, 1.1), "legendary": Color(1.3, 1.1, 0.5)}

var enemy: EnemyState
var _sprite: Sprite2D
var _t := 0.0
var _hit_flash := 0.0


func setup(e: EnemyState, tile_px: int) -> void:
	enemy = e
	_sprite = Sprite2D.new()
	_sprite.texture = UiTheme.texture(String(e.def.get("sprite", "")))
	var h := _sprite.texture.get_height() if _sprite.texture else tile_px
	_sprite.offset = Vector2(0, -h / 2.0 + tile_px / 2.0 - 2)
	add_child(_sprite)
	position = Vector2(e.tile * tile_px) + Vector2(tile_px, tile_px) * 0.5
	_t = randf() * TAU


func flash() -> void:
	_hit_flash = 0.15


func _process(delta: float) -> void:
	if enemy == null:
		return
	_t += delta
	var alive := enemy.is_alive()
	_sprite.visible = alive
	if alive:
		_sprite.position.y = sin(_t * 2.5) * 1.0
		var tint: Color = VARIANT_TINT.get(enemy.variant, Color.WHITE)
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		_sprite.modulate = Color(2, 2, 2) if _hit_flash > 0.0 else tint
		_sprite.scale = Vector2.ONE * (1.25 if not enemy.variant.is_empty() else 1.0)
	queue_redraw()


func _draw() -> void:
	if enemy == null:
		return
	if not enemy.is_alive():
		var total := maxf(float(enemy.def.get("respawn_seconds", 20)), 0.1)
		var frac := 1.0 - enemy.respawn_remaining / total
		draw_arc(Vector2(0, -6), 5.0, -PI / 2, -PI / 2 + TAU * frac, 16, Color(1, 0.5, 0.5, 0.7), 2.0)
		return
	if enemy.health < enemy.max_health or not enemy.engaged_by.is_empty():
		var w := 22.0
		var y := -(_sprite.texture.get_height() if _sprite.texture else 32) + 10.0
		draw_rect(Rect2(-w / 2, y, w, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2, y, w * enemy.health / enemy.max_health, 3), Color(0.9, 0.25, 0.25))
