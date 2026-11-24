class_name GridPathfinder
extends RefCounted
## A* pathfinding over a WorldGrid, built on Godot's native AStarGrid2D.
##
## * 8-directional movement, no corner cutting past blocked tiles.
## * Terrain move_cost becomes the point weight, so roads/bridges are
##   preferred and dense forest is avoided where possible.
## * Results are cached per (from, to) and the cache is dropped whenever the
##   grid's walkability version changes.
## * Unreachable destinations return PathResult.unreachable() instead of
##   hanging or producing partial paths.

const MAX_CACHE := 512

var grid: WorldGrid
var stats := {"requests": 0, "cache_hits": 0, "failures": 0, "searches": 0}
var _astar := AStarGrid2D.new()
var _cache := {}
var _adj_cache := {}
var _cache_version := -1
## Weights are normalised so the cheapest terrain costs 1.0. The octile
## heuristic assumes >= 1 per step; without this, roads (0.6) would make the
## heuristic inadmissible and A* would ignore them.
var _min_cost := 1.0


func _init(p_grid: WorldGrid) -> void:
	grid = p_grid
	rebuild()
	grid.cells_changed.connect(_on_cells_changed)


func rebuild() -> void:
	_astar.region = Rect2i(0, 0, grid.width, grid.height)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	_min_cost = 1.0
	for t in grid.terrain_defs:
		if bool(t.get("walkable", false)):
			_min_cost = minf(_min_cost, maxf(float(t.get("move_cost", 1.0)), 0.1))
	for y in grid.height:
		for x in grid.width:
			_sync_cell(Vector2i(x, y))
	_cache.clear()
	_adj_cache.clear()
	_cache_version = grid.version


func _sync_cell(c: Vector2i) -> void:
	var walk := grid.is_walkable(c)
	_astar.set_point_solid(c, not walk)
	if walk:
		_astar.set_point_weight_scale(c, grid.move_cost(c) / _min_cost)


func _on_cells_changed(cells: Array) -> void:
	for c in cells:
		if grid.in_bounds(c):
			_sync_cell(c)


func _check_cache_version() -> void:
	if _cache_version != grid.version:
		_cache.clear()
		_adj_cache.clear()
		_cache_version = grid.version


## Path from `from` to the walkable tile `to`.
func find_path(from: Vector2i, to: Vector2i) -> PathResult:
	stats.requests += 1
	_check_cache_version()
	if from == to:
		return PathResult.make([], to, 0.0)
	if not grid.is_walkable(to) or not grid.in_bounds(from):
		stats.failures += 1
		return PathResult.unreachable()
	var key := _key(from, to)
	if _cache.has(key):
		stats.cache_hits += 1
		var cached: PathResult = _cache[key]
		var copy := PathResult.make(cached.path.duplicate(), cached.goal, cached.cost)
		copy.from_cache = true
		return copy
	stats.searches += 1
	# A character may be standing on a tile that just became blocked; allow
	# it to path out by temporarily treating its own tile as open.
	var start_was_solid := _astar.is_point_solid(from)
	if start_was_solid:
		_astar.set_point_solid(from, false)
	var ids: Array[Vector2i] = _astar.get_id_path(from, to)
	if start_was_solid:
		_astar.set_point_solid(from, true)
	if ids.is_empty():
		stats.failures += 1
		return PathResult.unreachable()
	ids.remove_at(0)
	var result := PathResult.make(ids, to, path_cost(from, ids))
	if _cache.size() >= MAX_CACHE:
		_cache.erase(_cache.keys()[0])
	_cache[key] = PathResult.make(ids.duplicate(), to, result.cost)
	return result


## Path to any walkable tile adjacent (8-neighbourhood) to `target`, which is
## usually a blocking object such as a rock, tree, fishing spot or chest.
## Candidates are tried nearest-first; the first reachable one wins.
func find_path_to_adjacent(from: Vector2i, target: Vector2i) -> PathResult:
	if WorldGrid.chebyshev(from, target) == 1:
		return PathResult.make([], from, 0.0)
	_check_cache_version()
	var akey := _key(from, target) ^ 0x5bd1e995
	var hit: Variant = _adj_cache.get(akey)
	if hit != null:
		stats.requests += 1
		stats.cache_hits += 1
		var cached: PathResult = hit
		var copy := PathResult.make(cached.path, cached.goal, cached.cost)
		copy.from_cache = true
		return copy
	var result := _search_adjacent(from, target)
	if result.reachable:
		if _adj_cache.size() >= MAX_CACHE:
			_adj_cache.erase(_adj_cache.keys()[0])
		_adj_cache[akey] = PathResult.make(result.path, result.goal, result.cost)
	return result


func _search_adjacent(from: Vector2i, target: Vector2i) -> PathResult:
	var candidates: Array[Vector2i] = adjacent_walkable(target)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return WorldGrid.octile(from, a) + _diag_penalty(a, target) < WorldGrid.octile(from, b) + _diag_penalty(b, target))
	for c in candidates:
		var r := find_path(from, c)
		if r.reachable:
			return r
	return PathResult.unreachable()


func _diag_penalty(c: Vector2i, target: Vector2i) -> float:
	# Prefer standing orthogonally next to the target (looks better).
	return 0.0 if (c.x == target.x or c.y == target.y) else 0.5


func adjacent_walkable(target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := target + Vector2i(dx, dy)
			if grid.is_walkable(c):
				out.append(c)
	return out


func path_cost(from: Vector2i, p: Array[Vector2i]) -> float:
	var total := 0.0
	var prev := from
	for c in p:
		var step := 1.41421356 if (c.x != prev.x and c.y != prev.y) else 1.0
		total += step * grid.move_cost(c)
		prev = c
	return total


func clear_cache() -> void:
	_cache.clear()
	_adj_cache.clear()


static func _key(a: Vector2i, b: Vector2i) -> int:
	return ((a.x & 0xFFFF) << 48) | ((a.y & 0xFFFF) << 32) | ((b.x & 0xFFFF) << 16) | (b.y & 0xFFFF)
