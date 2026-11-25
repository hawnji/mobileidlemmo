class_name RegionNavigator
extends RefCounted
## Hierarchical navigation: a graph of regions joined by gates sits on top of
## the tile-level A* (GridPathfinder).
##
## When a character's goal is in another region, next_hop() returns the next
## waypoint instead of the goal: either the far side of the next gate on the
## shortest region route (BFS over open gates), or a waystone teleport when
## both regions have an active waystone (home storage or a built outpost
## depot). A* then only ever searches inside one region at a time, which
## keeps path requests cheap on a large map, and the character re-plans at
## each waypoint.

## Returned by next_hop().
enum Hop { DIRECT, WALK, WALK_ADJACENT, TELEPORT, NO_ROUTE }

var world: SimulationWorld:
	get:
		return _world_ref.get_ref()
var _world_ref: WeakRef
var gates: Array = []  # {id, name, a: Vector2i, b: Vector2i, regions: [ra, rb]}
var fast_travel_min_distance := 40.0


func _init(p_world: SimulationWorld, gate_defs: Array) -> void:
	_world_ref = weakref(p_world)
	fast_travel_min_distance = float(p_world.registry.get_config("navigation.fast_travel_min_distance", 40))
	for g in gate_defs:
		gates.append({"id": String(g.id), "name": String(g.get("name", g.id)), "a": JsonData.to_vec2i(g.a), "b": JsonData.to_vec2i(g.b),
			"regions": [String(g.regions[0]), String(g.regions[1])]})


func gate_open(g: Dictionary) -> bool:
	var w := world
	return w.is_region_unlocked(g.regions[0]) and w.is_region_unlocked(g.regions[1])


## Region-level route from `from_region` to `to_region` as a list of
## {gate, region_from, region_to, entry} steps. [] if same region or no route.
func region_route(from_region: String, to_region: String) -> Array:
	if from_region == to_region:
		return []
	var prev := {from_region: null}
	var queue: Array[String] = [from_region]
	while not queue.is_empty():
		var r: String = queue.pop_front()
		if r == to_region:
			break
		for g in gates:
			if not gate_open(g) or not g.regions.has(r):
				continue
			var other: String = g.regions[1] if g.regions[0] == r else g.regions[0]
			if prev.has(other):
				continue
			var entry: Vector2i = g.b if g.regions[1] == other else g.a
			prev[other] = {"gate": g.id, "region_from": r, "region_to": other, "entry": entry}
			queue.append(other)
	if not prev.has(to_region):
		return []
	var steps := []
	var cur := to_region
	while prev[cur] != null:
		steps.push_front(prev[cur])
		cur = prev[cur].region_from
	return steps


## The next step towards `goal`: {"kind": Hop, "tile": Vector2i}.
func next_hop(from: Vector2i, goal: Vector2i) -> Dictionary:
	var w := world
	var rf := w.region_at(from)
	var rg := w.region_at(goal)
	if rf.is_empty() or rg.is_empty() or rf == rg:
		return {"kind": Hop.DIRECT, "tile": goal}
	var ws_from := w.waystone_of(rf)
	var ws_to := w.waystone_of(rg)
	if ws_from.x >= 0 and ws_to.x >= 0 and WorldGrid.octile(from, goal) >= fast_travel_min_distance:
		if WorldGrid.chebyshev(from, ws_from) <= 1:
			return {"kind": Hop.TELEPORT, "tile": ws_to}
		return {"kind": Hop.WALK_ADJACENT, "tile": ws_from}
	var route := region_route(rf, rg)
	if route.is_empty():
		return {"kind": Hop.NO_ROUTE, "tile": goal}
	return {"kind": Hop.WALK, "tile": route[0].entry}
