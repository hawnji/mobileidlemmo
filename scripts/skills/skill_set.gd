class_name SkillSet
extends RefCounted
## Per-character skill XP store. Levels are always derived from XP so they can
## never disagree with each other.

var table: XpTable
var _xp := {}  # skill_id -> float


func _init(p_table: XpTable) -> void:
	table = p_table


func get_xp(skill_id: String) -> float:
	return float(_xp.get(skill_id, 0.0))


func get_level(skill_id: String) -> int:
	return table.level_for_xp(get_xp(skill_id))


func set_level(skill_id: String, level: int) -> void:
	_xp[skill_id] = float(table.xp_for_level(level))


## Adds XP and returns the number of levels gained. Non-positive or NaN
## amounts are ignored, and XP is capped at the table's max_xp.
func add_xp(skill_id: String, amount: float) -> int:
	if not (amount > 0.0) or is_inf(amount):
		return 0
	var before := get_level(skill_id)
	_xp[skill_id] = minf(get_xp(skill_id) + amount, table.max_xp)
	return get_level(skill_id) - before


func total_level(skill_ids: Array) -> int:
	var total := 0
	for id in skill_ids:
		total += get_level(id)
	return total


func to_dict() -> Dictionary:
	return _xp.duplicate()


func load_dict(d: Dictionary) -> void:
	_xp.clear()
	for k in d:
		var v := float(d[k])
		if v > 0.0:
			_xp[String(k)] = minf(v, table.max_xp)
