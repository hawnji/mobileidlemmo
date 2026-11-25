class_name BuildingView
extends Node2D
## Draws a building plot: nothing (just a marker) when unbuilt, scaffolding
## while under construction, the building sprite once level >= 1, with a
## level badge.

var world: SimulationWorld
var building_id := ""
var plot: Dictionary
var tile_px := 32
var _sprite: Sprite2D
var _label: Label
var _shown := ""


func setup(p_world: SimulationWorld, p_building: String, p_plot: Dictionary, p_tile_px: int) -> void:
	world = p_world
	building_id = p_building
	plot = p_plot
	tile_px = p_tile_px
	var r: Rect2i = plot.rect
	position = Vector2(r.position.x * tile_px + r.size.x * tile_px * 0.5, (r.position.y + r.size.y) * tile_px)
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(140, 0)
	_label.position = Vector2(-70, -r.size.y * tile_px - 14)
	add_child(_label)
	_refresh()


func _process(_delta: float) -> void:
	var key := "%d:%s" % [world.town.level_of(building_id), world.town.project.get("building", "")]
	if key != _shown:
		_refresh()
	if world.town.project.get("building", "") == building_id:
		_label.text = "%s %d%%" % [world.registry.buildings[building_id].name, int(world.town.progress_ratio() * 100)]


func _refresh() -> void:
	var lvl := world.town.level_of(building_id)
	var building: bool = world.town.project.get("building", "") == building_id
	_shown = "%d:%s" % [lvl, world.town.project.get("building", "")]
	var path := ""
	if lvl > 0:
		path = "res://assets/environments/buildings/%s.png" % building_id
	elif building:
		path = "res://assets/environments/buildings/construction_site.png"
	_sprite.texture = UiTheme.texture(path) if not path.is_empty() else null
	if _sprite.texture:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)
	_sprite.modulate = Color(1, 1, 1, 0.75) if building and lvl > 0 else Color.WHITE
	var name := String(world.registry.buildings.get(building_id, {}).get("name", building_id))
	_label.text = "%s L%d" % [name, lvl] if lvl > 0 else ("" if not building else name)
	_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 0.9))
	queue_redraw()


func _draw() -> void:
	if world.town.level_of(building_id) == 0 and world.town.project.get("building", "") != building_id:
		var r: Rect2i = plot.rect
		var size := Vector2(r.size) * tile_px
		draw_rect(Rect2(Vector2(-size.x / 2, -size.y), size), Color(1, 1, 1, 0.12), false, 1.0)
