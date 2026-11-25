class_name StatBlock
extends RefCounted
## Combines stat effects from any number of sources (affinities, passives,
## traits, specializations, stars, equipment, buildings, relics, pets...).
##
## Effect keys are "<family>.<skill>", "<family>.all" or a bare "<family>".
## data/config/stats.json says whether a family multiplies ("mul", default
## 1.0) or adds ("add", default 0.0). get(family, skill) folds the skill
## specific and ".all" values together.

var _families := {}  # family -> "mul" | "add"
var _values := {}  # full key -> combined value


func _init(families: Dictionary = {}) -> void:
	_families = families


func combine_of(key: String) -> String:
	var fam := key.get_slice(".", 0)
	return String(_families.get(fam, "mul"))


func apply(effects: Dictionary, scale := 1.0) -> void:
	for key in effects:
		var v := float(effects[key])
		if combine_of(key) == "add":
			_values[key] = float(_values.get(key, 0.0)) + v * scale
		else:
			# scale (e.g. stacking N stars) raises the multiplier to that power
			_values[key] = float(_values.get(key, 1.0)) * pow(v, scale)


func raw(key: String) -> float:
	return float(_values.get(key, 0.0 if combine_of(key) == "add" else 1.0))


## Combined value for a family, optionally specialised to a skill.
func get_stat(family: String, skill := "") -> float:
	var is_add := String(_families.get(family, "mul")) == "add"
	var v := raw(family)
	if not _values.has(family):
		v = 0.0 if is_add else 1.0
	var all_key := family + ".all"
	if _values.has(all_key):
		v = v + raw(all_key) if is_add else v * raw(all_key)
	if not skill.is_empty():
		var sk := family + "." + skill
		if _values.has(sk):
			v = v + raw(sk) if is_add else v * raw(sk)
	return v


func values() -> Dictionary:
	return _values.duplicate()


func merged_with(other: StatBlock) -> StatBlock:
	var s := StatBlock.new(_families)
	s._values = _values.duplicate()
	for k in other._values:
		s.apply({k: other._values[k]})
	return s
