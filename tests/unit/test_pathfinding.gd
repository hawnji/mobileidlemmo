extends WbTestCase


func test_straight_line_path() -> void:
	var pf := GridPathfinder.new(grid_from([".....", ".....", "....."]))
	var r := pf.find_path(Vector2i(0, 1), Vector2i(4, 1))
	assert_true(r.reachable)
	assert_eq(r.path.size(), 4)
	assert_eq(r.path[-1], Vector2i(4, 1))
	assert_almost(r.cost, 4.0)


func test_routes_around_obstacles() -> void:
	var g := grid_from([
		".....",
		".^^^.",
		".^...",
		".^.^.",
		"...^.",
	])
	var pf := GridPathfinder.new(g)
	var r := pf.find_path(Vector2i(2, 2), Vector2i(0, 0))
	assert_true(r.reachable)
	for c in r.path:
		assert_true(g.is_walkable(c), "path crosses blocked tile %s" % c)


func test_no_corner_cutting() -> void:
	var g := grid_from([
		".^",
		"^.",
	])
	var pf := GridPathfinder.new(g)
	assert_false(pf.find_path(Vector2i(0, 0), Vector2i(1, 1)).reachable, "diagonal squeeze between two blocks is not allowed")


func test_unreachable_destination_detected() -> void:
	var g := grid_from([
		"..~..",
		"..~..",
		"..~..",
	])
	var pf := GridPathfinder.new(g)
	assert_false(pf.find_path(Vector2i(0, 0), Vector2i(4, 0)).reachable)
	assert_false(pf.find_path(Vector2i(0, 0), Vector2i(2, 0)).reachable, "blocked goal")
	assert_false(pf.find_path(Vector2i(0, 0), Vector2i(50, 50)).reachable, "out of bounds goal")


func test_prefers_roads() -> void:
	# Grass costs 1.0, road 0.6. A detour along the road is cheaper than the
	# straight grass line, so the path must use the road.
	var g := grid_from([
		"..........",
		"=========.",
	])
	var pf := GridPathfinder.new(g)
	var r := pf.find_path(Vector2i(0, 0), Vector2i(9, 0))
	var road_steps := 0
	for c in r.path:
		if g.terrain_at(c).id == "road":
			road_steps += 1
	assert_gt(road_steps, 4)


func test_path_to_adjacent_of_blocking_object() -> void:
	var g := grid_from([
		".....",
		".....",
		".....",
	])
	g.set_object_blocked(Vector2i(4, 1), true)
	var pf := GridPathfinder.new(g)
	var r := pf.find_path_to_adjacent(Vector2i(0, 1), Vector2i(4, 1))
	assert_true(r.reachable)
	assert_eq(WorldGrid.chebyshev(r.path[-1], Vector2i(4, 1)), 1)
	assert_eq(r.path[-1], Vector2i(3, 1), "prefers orthogonal standing spot")
	var here := pf.find_path_to_adjacent(Vector2i(3, 1), Vector2i(4, 1))
	assert_true(here.reachable and here.path.is_empty(), "already adjacent")


func test_cache_hits_and_invalidation() -> void:
	var g := grid_from(["......", "......"])
	var pf := GridPathfinder.new(g)
	pf.find_path(Vector2i(0, 0), Vector2i(5, 0))
	var r2 := pf.find_path(Vector2i(0, 0), Vector2i(5, 0))
	assert_true(r2.from_cache)
	assert_eq(pf.stats.searches, 1)
	g.set_object_blocked(Vector2i(3, 0), true)
	var r3 := pf.find_path(Vector2i(0, 0), Vector2i(5, 0))
	assert_false(r3.from_cache, "cache dropped after walkability change")
	assert_false(r3.path.has(Vector2i(3, 0)))


func test_cached_paths_are_copies() -> void:
	var pf := GridPathfinder.new(grid_from(["....."]))
	var r1 := pf.find_path(Vector2i(0, 0), Vector2i(4, 0))
	r1.path.clear()
	var r2 := pf.find_path(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(r2.path.size(), 4, "mutating a returned path must not corrupt the cache")


func test_every_node_in_starter_map_is_reachable_from_storage() -> void:
	var w := new_world()
	var start := w.pathfinder.adjacent_walkable(w.storage_tile)[0]
	for nid in w.node_order:
		if w.region_at(w.nodes[nid].tile) != "greenvale":
			continue
		var r := w.pathfinder.find_path_to_adjacent(start, w.nodes[nid].tile)
		assert_true(r.reachable, "node %s unreachable" % nid)


func test_every_node_in_the_world_is_reachable_once_all_regions_are_open() -> void:
	var w := new_world()
	for rid in w.registry.map_region_order:
		w._set_region_unlocked(rid)
	var start := w.pathfinder.adjacent_walkable(w.storage_tile)[0]
	for nid in w.node_order:
		if w.nodes[nid].hidden:
			continue
		var r := w.pathfinder.find_path_to_adjacent(start, w.nodes[nid].tile)
		assert_true(r.reachable, "node %s unreachable" % nid)
	for sid in w.enemy_order:
		assert_true(w.pathfinder.find_path_to_adjacent(start, w.enemies[sid].tile).reachable, "enemy %s unreachable" % sid)


func test_locked_gates_block_other_regions() -> void:
	var w := new_world()
	var start := w.pathfinder.adjacent_walkable(w.storage_tile)[0]
	var silver: ResourceNodeState = w.nodes["silver_rock_1"]
	assert_false(w.pathfinder.find_path_to_adjacent(start, silver.tile).reachable, "Irondeep must be sealed while locked")
	w._set_region_unlocked("irondeep")
	assert_true(w.pathfinder.find_path_to_adjacent(start, silver.tile).reachable)
