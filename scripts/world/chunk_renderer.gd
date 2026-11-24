class_name ChunkRenderer
extends Node2D
## Chunk-based terrain rendering. The map is split into chunk_size x
## chunk_size tile chunks, each drawn by its own TileMapLayer. Only chunks
## overlapping the camera view (plus a margin) exist; others are returned to
## a pool. This keeps draw and memory cost flat as regions grow.

var registry: DataRegistry
var region: Dictionary
var tile_px := 32
var chunk_size := 16
var margin_chunks := 1
var _tileset: TileSet
var _rows: Array = []
var _active := {}  # Vector2i chunk -> TileMapLayer
var _pool: Array[TileMapLayer] = []
var _atlas_cache := {}
var _last_rect := Rect2i(-1, -1, 0, 0)


func setup(p_registry: DataRegistry, p_region: Dictionary) -> void:
	registry = p_registry
	region = p_region
	tile_px = int(registry.get_config("world.tile_size_px", 32))
	chunk_size = int(registry.get_config("world.chunk_size_tiles", 16))
	_tileset = TilesetFactory.build(registry, tile_px)
	_rows = region.rows
	for sym in registry.terrain_by_symbol:
		_atlas_cache[sym] = TilesetFactory.atlas_for_symbol(registry, sym)
	for c in _active.keys():
		_release(c)
	_last_rect = Rect2i(-1, -1, 0, 0)


## Call when the camera moves. `view` is the visible world rect in pixels.
func update_visible(view: Rect2) -> void:
	if _rows.is_empty():
		return
	var cpx := float(chunk_size * tile_px)
	var w := int(region.width)
	var h := int(region.height)
	var max_cx := ceili(float(w) / chunk_size) - 1
	var max_cy := ceili(float(h) / chunk_size) - 1
	var x0 := clampi(floori(view.position.x / cpx) - margin_chunks, 0, max_cx)
	var y0 := clampi(floori(view.position.y / cpx) - margin_chunks, 0, max_cy)
	var x1 := clampi(floori(view.end.x / cpx) + margin_chunks, 0, max_cx)
	var y1 := clampi(floori(view.end.y / cpx) + margin_chunks, 0, max_cy)
	var rect := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	if rect == _last_rect:
		return
	_last_rect = rect
	for c in _active.keys():
		if not rect.has_point(c):
			_release(c)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2i(cx, cy)
			if not _active.has(c):
				_build_chunk(c)


func active_chunk_count() -> int:
	return _active.size()


func _build_chunk(c: Vector2i) -> void:
	var layer: TileMapLayer = _pool.pop_back() if not _pool.is_empty() else TileMapLayer.new()
	layer.tile_set = _tileset
	layer.clear()
	layer.name = "Chunk_%d_%d" % [c.x, c.y]
	layer.position = Vector2(c * chunk_size * tile_px)
	var w := int(region.width)
	var h := int(region.height)
	for ly in chunk_size:
		var y := c.y * chunk_size + ly
		if y >= h:
			break
		var row: String = _rows[y]
		for lx in chunk_size:
			var x := c.x * chunk_size + lx
			if x >= w:
				break
			layer.set_cell(Vector2i(lx, ly), TilesetFactory.SOURCE_ID, _atlas_cache.get(row[x], Vector2i.ZERO))
	if layer.get_parent() == null:
		add_child(layer)
	layer.visible = true
	_active[c] = layer


func _release(c: Vector2i) -> void:
	var layer: TileMapLayer = _active[c]
	_active.erase(c)
	layer.visible = false
	layer.clear()
	_pool.append(layer)
