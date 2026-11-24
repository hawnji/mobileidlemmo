class_name XpTable
extends RefCounted
## Cumulative XP thresholds generated from a configurable curve
## (data/skills/xp_curve.json). Index L holds the total XP needed to *reach*
## level L. Level 1 always needs 0 XP.

var max_level := 99
var max_xp := 200000000.0
var _thresholds := PackedInt64Array()


static func from_curve(curve: Dictionary) -> XpTable:
	var table := XpTable.new()
	table.max_level = int(curve.get("max_level", 99))
	table.max_xp = float(curve.get("max_xp", 200000000))
	var base := float(curve.get("base", 300.0))
	var divisor := float(curve.get("divisor", 7.0))
	table._build(base, divisor)
	return table


func _build(base: float, divisor: float) -> void:
	_thresholds.resize(max_level + 1)
	_thresholds[0] = 0
	_thresholds[1] = 0
	var points := 0.0
	for lvl in range(1, max_level):
		points += floor(lvl + base * pow(2.0, lvl / divisor))
		_thresholds[lvl + 1] = int(floor(points / 4.0))


## Total XP required to reach `level` (clamped to 1..max_level).
func xp_for_level(level: int) -> int:
	return _thresholds[clampi(level, 1, max_level)]


## Level for a cumulative XP amount (binary search, O(log n)).
func level_for_xp(xp: float) -> int:
	if xp <= 0.0:
		return 1
	var lo := 1
	var hi := max_level
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(_thresholds[mid]) <= xp:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Fraction (0..1) of the way from the current level to the next.
func progress_to_next(xp: float) -> float:
	var lvl := level_for_xp(xp)
	if lvl >= max_level:
		return 1.0
	var a := float(_thresholds[lvl])
	var b := float(_thresholds[lvl + 1])
	return clampf((xp - a) / (b - a), 0.0, 1.0)


func xp_to_next_level(xp: float) -> float:
	var lvl := level_for_xp(xp)
	if lvl >= max_level:
		return 0.0
	return float(_thresholds[lvl + 1]) - xp
