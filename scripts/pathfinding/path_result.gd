class_name PathResult
extends RefCounted
## Outcome of a path request. `path` excludes the start tile, so an empty path
## with reachable == true means "already there".

var reachable := false
var path: Array[Vector2i] = []
var goal := Vector2i.ZERO
var cost := 0.0
var from_cache := false


static func unreachable() -> PathResult:
	return PathResult.new()


static func make(p: Array, p_goal: Vector2i, p_cost: float) -> PathResult:
	var r := PathResult.new()
	r.reachable = true
	r.path.assign(p)
	r.goal = p_goal
	r.cost = p_cost
	return r
