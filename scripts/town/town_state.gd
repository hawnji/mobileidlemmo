class_name TownState
extends RefCounted
## Building levels and the single active construction project.
##
## A building's effects are the values listed for its *current* level (not a
## sum over levels). All active buildings' effects are folded into one
## StatBlock that every character reads through Adventurer.stat(). `version`
## changes whenever that block changes so characters can cache their stats.
##
## Starting a project pays its whole cost up front (gold from the wallet,
## items from storage). Characters on the "construct" activity then add work
## seconds until the project completes.

var levels := {}  # building_id -> level (0 = not built)
var project := {}  # {building, level, work_done, work_needed} or {}
var version := 1
var effects: StatBlock


func setup(registry: DataRegistry) -> void:
	for b in registry.building_order:
		levels[b] = 0
	for b in registry.town_config.get("starting_levels", {"town_hall": 1}):
		levels[b] = int(registry.town_config.get("starting_levels", {"town_hall": 1})[b])
	recompute(registry)


func level_of(building_id: String) -> int:
	return int(levels.get(building_id, 0))


func level_def(registry: DataRegistry, building_id: String, level: int) -> Dictionary:
	var b: Dictionary = registry.buildings.get(building_id, {})
	for l in b.get("levels", []):
		if int(l.get("level", 0)) == level:
			return l
	return {}


func recompute(registry: DataRegistry) -> void:
	var sb := registry.new_stat_block()
	for b in levels:
		var lv := level_of(b)
		if lv > 0:
			sb.apply(level_def(registry, b, lv).get("effects", {}))
	effects = sb
	version += 1


func meets(requirements: Dictionary) -> bool:
	for b in requirements:
		if level_of(b) < int(requirements[b]):
			return false
	return true


## Returns "" if the next level of `building_id` could be started now
## (ignoring cost), otherwise a player-facing reason.
func can_start(registry: DataRegistry, building_id: String) -> String:
	if not registry.buildings.has(building_id):
		return "Unknown building"
	if not project.is_empty():
		return "Another project is already under construction"
	var next := level_of(building_id) + 1
	var b: Dictionary = registry.buildings[building_id]
	if next > int(b.get("max_level", 1)):
		return "%s is at its maximum level" % b.get("name", building_id)
	if building_id != "town_hall" and next > level_of("town_hall") + 1:
		return "Upgrade the Town Hall first"
	if level_def(registry, building_id, next).is_empty():
		return "No data for level %d" % next
	return ""


func start_project(registry: DataRegistry, building_id: String) -> void:
	var next := level_of(building_id) + 1
	var ld := level_def(registry, building_id, next)
	project = {"building": building_id, "level": next, "work_done": 0.0,
		"work_needed": float(ld.get("work_seconds", 60))}


func add_work(seconds: float) -> bool:
	if project.is_empty():
		return false
	project.work_done = minf(float(project.work_done) + seconds, float(project.work_needed))
	return float(project.work_done) >= float(project.work_needed) - 0.000001


func complete_project(registry: DataRegistry) -> Dictionary:
	var done := project.duplicate()
	levels[String(project.building)] = int(project.level)
	project = {}
	recompute(registry)
	return done


func progress_ratio() -> float:
	if project.is_empty():
		return 0.0
	return float(project.work_done) / maxf(float(project.work_needed), 0.001)


func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(), "project": project.duplicate()}


func load_dict(registry: DataRegistry, d: Dictionary) -> void:
	for b in d.get("levels", {}):
		if registry.buildings.has(b):
			levels[String(b)] = clampi(int(d.levels[b]), 0, int(registry.buildings[b].get("max_level", 1)))
	var p: Variant = d.get("project", {})
	project = {}
	if p is Dictionary and registry.buildings.has(p.get("building", "")):
		var lvl := int(p.get("level", 0))
		if lvl == level_of(String(p.building)) + 1:
			project = {"building": String(p.building), "level": lvl,
				"work_done": maxf(float(p.get("work_done", 0.0)), 0.0),
				"work_needed": maxf(float(p.get("work_needed", 60.0)), 1.0)}
	recompute(registry)
