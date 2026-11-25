class_name FogOverlay
extends Sprite2D
## Fog of war drawn as one low-resolution texture (one pixel per tile),
## stretched over the map with linear filtering so edges look soft.
## Hidden tiles are dark; tiles in a locked region are darker still.
## Rebuilt only when ExplorationState.version or the unlocked set changes.

var world: SimulationWorld
var _image: Image
var _tex: ImageTexture
var _shown_key := ""
var _accum := 0.0

const HIDDEN := Color(0.04, 0.05, 0.08, 0.82)
const LOCKED := Color(0.02, 0.02, 0.04, 0.93)


func setup(p_world: SimulationWorld, tile_px: int) -> void:
	world = p_world
	centered = false
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var ex := world.exploration
	_image = Image.create(ex.width, ex.height, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_image)
	texture = _tex
	scale = Vector2(tile_px, tile_px)
	_shown_key = ""
	rebuild()


func _key() -> String:
	return "%d|%s" % [world.exploration.version, ",".join(world.unlocked_regions.keys())]


func rebuild() -> void:
	var ex := world.exploration
	var locked := {}
	for i in ex.region_ids.size():
		locked[i] = not world.is_region_unlocked(ex.region_ids[i])
	for y in ex.height:
		for x in ex.width:
			var idx := y * ex.width + x
			var ri := ex.region_index[idx]
			var c := Color(0, 0, 0, 0)
			if ri != 255 and locked.get(ri, false):
				c = LOCKED
			elif ex.revealed[idx] == 0:
				c = HIDDEN
			_image.set_pixel(x, y, c)
	_tex.update(_image)
	_shown_key = _key()


func _process(delta: float) -> void:
	if world == null:
		return
	_accum += delta
	if _accum < 0.4:
		return
	_accum = 0.0
	if _key() != _shown_key:
		rebuild()
