class_name WorldGrid
extends RefCounted
## Authoritative tile grid used by the simulation and pathfinding. Holds the
## terrain index of every cell plus an overlay of cells blocked by world
## objects (resource nodes, storage chests). Rendering reads from here but
## never writes to it.

signal cells_changed(cells: Array)

var width := 0
var height := 0
var chunk_size := 16
var terrain_defs: Array = []  # index -> terrain dictionary
var _terrain := PackedInt32Array()
var _object_blocked := {}  # Vector2i -> true
## Incremented whenever walkability changes; path caches key on it.
var version := 0


static func from_rows(rows: Array, terrain_by_symbol: Dictionary, p_chunk_size := 16) -> WorldGrid:
	var g := WorldGrid.new()
	g.height = rows.size()
	g.width = String(rows[0]).length() if g.height > 0 else 0
	g.chunk_size = p_chunk_size
	var index_by_symbol := {}
	for sym in terrain_by_symbol:
		index_by_symbol[sym] = g.terrain_defs.size()
		g.terrain_defs.append(terrain_by_symbol[sym])
	g._terrain.resize(g.width * g.height)
	for y in g.height:
		var row := String(rows[y])
		for x in g.width:
			var sym := row[x] if x < row.length() else "."
			g._terrain[y * g.width + x] = int(index_by_symbol.get(sym, 0))
	return g


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func terrain_at(c: Vector2i) -> Dictionary:
	if not in_bounds(c):
		return {}
	return terrain_defs[_terrain[c.y * width + c.x]]


func terrain_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and bool(terrain_at(c).get("walkable", false))


func is_walkable(c: Vector2i) -> bool:
	return terrain_walkable(c) and not _object_blocked.has(c)


func move_cost(c: Vector2i) -> float:
	return maxf(float(terrain_at(c).get("move_cost", 1.0)), 0.1)


func set_object_blocked(c: Vector2i, blocked: bool) -> void:
	if blocked == _object_blocked.has(c):
		return
	if blocked:
		_object_blocked[c] = true
	else:
		_object_blocked.erase(c)
	version += 1
	cells_changed.emit([c])


func chunk_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / chunk_size), floori(float(c.y) / chunk_size))


func chunk_count() -> Vector2i:
	return Vector2i(ceili(float(width) / chunk_size), ceili(float(height) / chunk_size))


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + (sqrt(2.0) - 1.0) * float(mini(dx, dy))
