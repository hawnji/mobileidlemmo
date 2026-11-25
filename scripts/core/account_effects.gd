class_name AccountEffects
extends RefCounted
## Account-wide stat effects (buildings now; relics, pets, guild perks and
## ascension later) merged into one StatBlock. current() rebuilds lazily when
## any source changed, and `version` changes with it, so every character can
## cache its own stats and only re-read them after a real change.

var registry: DataRegistry
var town: TownState
## Extra sources added by later systems: Array of objects with `effects`
## (StatBlock) and `version` (int).
var extra_sources: Array = []
var block: StatBlock
var version := 0
var _seen := -1


func _init(p_registry: DataRegistry = null, p_town: TownState = null) -> void:
	registry = p_registry
	town = p_town


func _source_key() -> int:
	var k := town.version if town else 0
	for s in extra_sources:
		k = k * 31 + int(s.version)
	return k


func current() -> StatBlock:
	var key := _source_key()
	if block == null or key != _seen:
		_seen = key
		var sb := registry.new_stat_block()
		if town:
			sb = sb.merged_with(town.effects)
		for s in extra_sources:
			if s.effects:
				sb = sb.merged_with(s.effects)
		block = sb
		version += 1
	return block
