class_name FloatingTextPool
extends Node2D
## Object pool of world-space floating labels ("+1 Copper Ore", "+19 XP").
## Labels are recycled instead of allocated per gather, so busy scenes with
## many workers do not churn the allocator.

const POOL_SIZE := 40
var _free: Array[Label] = []


func _ready() -> void:
	z_index = 100
	for i in POOL_SIZE:
		var l := Label.new()
		l.visible = false
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(160, 0)
		add_child(l)
		_free.append(l)


func spawn(text: String, at: Vector2, color := Color.WHITE) -> void:
	if _free.is_empty():
		return  # pool exhausted: drop cosmetic text rather than allocate
	var l: Label = _free.pop_back()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.position = at - Vector2(80, 0)
	l.modulate.a = 1.0
	l.visible = true
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(func() -> void:
		l.visible = false
		_free.append(l))
