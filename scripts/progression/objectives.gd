class_name Objectives
extends RefCounted
## One evaluator for every "condition" in the data: quest objectives and
## prerequisites, region unlock requirements, outpost level requirements,
## expedition requirements and discovery gates all use the same shapes:
##
##   {"type": "gather", "item": "copper_ore", "qty": 25}        counter since the quest started
##   {"type": "kill", "enemy": "wolf", "qty": 15}               counter
##   {"type": "kill_tag", "tag": "goblin", "qty": 20}           counter
##   {"type": "craft", "item": "bronze_bar", "qty": 40}         counter
##   {"type": "dungeon", "dungeon": "deepforge_vault", "qty": 1} counter (clears)
##   {"type": "expedition", "qty": 2}                           counter (successful or not)
##   {"type": "deliver", "item": "steel_bar", "qty": 20}        items in storage, consumed on claim
##   {"type": "explored", "region": "greenvale", "pct": 0.35}   fog of war revealed
##   {"type": "discover", "discovery": "kings_road"}
##   {"type": "discover_count", "region": "greenvale", "qty": 2}
##   {"type": "build", "building": "outpost_irondeep", "level": 1}
##   {"type": "skill", "skill": "mining", "level": 20}          any owned character
##   {"type": "character_level", "level": 30}                   any owned character
##   {"type": "combat_level", "level": 25}                      any owned character
##   {"type": "quest", "quest": "mq_01_roots"}                  completed at least once
##   {"type": "region", "region": "irondeep"}                   unlocked
##   {"type": "reputation", "region": "irondeep", "tier": 2}
##
## Counter objectives measure progress from a baseline snapshot taken when the
## quest became active, so old kills do not complete new quests.

const KNOWN_TYPES := ["gather", "kill", "kill_tag", "craft", "dungeon", "expedition", "deliver", "explored", "discover",
	"discover_count", "build", "skill", "character_level", "combat_level", "quest", "region", "reputation"]


## World counter key for counter-based objectives, or "" for state checks.
static func counter_key(obj: Dictionary) -> String:
	match String(obj.get("type", "")):
		"gather": return "gather:%s" % obj.get("item", "")
		"kill": return "kill:%s" % obj.get("enemy", "")
		"kill_tag": return "kill_tag:%s" % obj.get("tag", "")
		"craft": return "craft:%s" % obj.get("item", "")
		"dungeon": return "dungeon:%s" % obj.get("dungeon", "")
		"expedition":
			return "expedition:%s" % obj.expedition if obj.has("expedition") else "expedition"
	return ""


## [current, target] for an objective. Fractions (explored) are scaled to
## percent so the UI can always show "cur / target".
static func progress(world, obj: Dictionary, baseline := {}) -> Vector2i:
	var t := String(obj.get("type", ""))
	var key := counter_key(obj)
	if not key.is_empty():
		var cur := int(world.counters.get(key, 0)) - int(baseline.get(key, 0))
		return Vector2i(maxi(cur, 0), int(obj.get("qty", 1)))
	match t:
		"deliver":
			return Vector2i(world.storage.get_quantity(String(obj.item)), int(obj.get("qty", 1)))
		"explored":
			return Vector2i(int(floor(world.exploration.explored_pct(String(obj.region)) * 100.0)), int(round(float(obj.get("pct", 1.0)) * 100.0)))
		"discover":
			return Vector2i(1 if world.exploration.is_discovered(String(obj.discovery)) else 0, 1)
		"discover_count":
			return Vector2i(world.exploration.discovered_count(String(obj.get("region", ""))), int(obj.get("qty", 1)))
		"build":
			return Vector2i(world.town.level_of(String(obj.building)), int(obj.get("level", 1)))
		"skill":
			return Vector2i(world.max_skill_level(String(obj.skill)), int(obj.get("level", 1)))
		"character_level":
			return Vector2i(world.max_character_level(), int(obj.get("level", 1)))
		"combat_level":
			return Vector2i(world.max_combat_level(), int(obj.get("level", 1)))
		"quest":
			return Vector2i(1 if world.quests.has_completed(String(obj.quest)) else 0, 1)
		"region":
			return Vector2i(1 if world.is_region_unlocked(String(obj.region)) else 0, 1)
		"reputation":
			return Vector2i(world.quests.reputation_tier(String(obj.region)), int(obj.get("tier", 1)))
	return Vector2i(0, 1)


static func is_met(world, obj: Dictionary, baseline := {}) -> bool:
	var p := progress(world, obj, baseline)
	return p.x >= p.y


static func all_met(world, list: Array, baseline := {}) -> bool:
	for o in list:
		if not is_met(world, o, baseline):
			return false
	return true


## Requirement checked against one specific team (expeditions): "any member".
static func team_meets(registry: DataRegistry, team: Array, obj: Dictionary) -> bool:
	for ch in team:
		match String(obj.get("type", "")):
			"skill":
				if ch.skills.get_level(String(obj.skill)) >= int(obj.get("level", 1)):
					return true
			"combat_level":
				if ch.combat_level() >= int(obj.get("level", 1)):
					return true
			"character_level":
				if ch.character_level() >= int(obj.get("level", 1)):
					return true
			_:
				return true
	return false


static func describe(registry: DataRegistry, obj: Dictionary) -> String:
	var t := String(obj.get("type", ""))
	match t:
		"gather": return "Gather %d %s" % [int(obj.qty), registry.get_item_name(String(obj.item))]
		"kill": return "Defeat %d %s" % [int(obj.qty), registry.enemies.get(obj.enemy, {}).get("name", obj.enemy)]
		"kill_tag": return "Defeat %d %s enemies" % [int(obj.qty), String(obj.tag)]
		"craft": return "Craft %d %s" % [int(obj.qty), registry.get_item_name(String(obj.item))]
		"dungeon": return "Clear %s" % registry.dungeons.get(obj.dungeon, {}).get("name", obj.dungeon)
		"expedition":
			if obj.has("expedition"):
				return "Complete %s" % registry.expeditions.get(obj.expedition, {}).get("name", obj.expedition)
			return "Complete %d expeditions" % int(obj.get("qty", 1))
		"deliver": return "Deliver %d %s" % [int(obj.qty), registry.get_item_name(String(obj.item))]
		"explored": return "Explore %d%% of %s" % [int(round(float(obj.pct) * 100)), registry.region_name(String(obj.region))]
		"discover":
			for d in registry.world_map.get("discoveries", []):
				if d.id == obj.discovery:
					return "Discover %s" % d.name
			return "Discover %s" % obj.discovery
		"discover_count": return "Make %d discoveries in %s" % [int(obj.qty), registry.region_name(String(obj.region))]
		"build": return "Build %s level %d" % [registry.buildings.get(obj.building, {}).get("name", obj.building), int(obj.get("level", 1))]
		"skill": return "%s level %d" % [registry.skills.get(obj.skill, {}).get("name", obj.skill), int(obj.level)]
		"character_level": return "Character level %d" % int(obj.level)
		"combat_level": return "Combat level %d" % int(obj.level)
		"quest": return "Complete \"%s\"" % registry.quests.get(obj.quest, {}).get("name", obj.quest)
		"region": return "Unlock %s" % registry.region_name(String(obj.region))
		"reputation":
			var tiers := registry.reputation_tiers()
			var tier := clampi(int(obj.get("tier", 1)), 0, tiers.size() - 1)
			return "%s reputation: %s" % [registry.region_name(String(obj.region)), tiers[tier].name]
	return t
