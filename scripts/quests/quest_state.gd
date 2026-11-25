class_name QuestState
extends RefCounted
## Main story quests, regional quests, repeatable contracts and regional
## reputation (data/quests/quests.json).
##
## Quests activate automatically once their prerequisites are met; counter
## objectives (gather, kill, craft, dungeon, expedition) count from that
## moment. A complete quest is claimed by the player, which consumes any
## "deliver" items and grants the rewards. Contracts become available again
## after their cooldown.
##
## Reputation is tracked per region; tiers (Neutral .. Exalted) unlock vendor
## stock, recipes, outpost levels and reputation characters.

var active := {}  # quest_id -> {baseline: {counter: value}, started: float}
var completed := {}  # quest_id -> times completed
var cooldowns := {}  # quest_id -> sim_time when available again
var reputation := {}  # region_id -> points
var _ready_announced := {}  # quest_id -> true
var _check_timer := 0.0
var _interval := 5.0
var registry: DataRegistry


func setup(p_registry: DataRegistry) -> void:
	registry = p_registry
	_interval = float(registry.quest_config.get("check_interval_seconds", 5.0))
	for r in registry.quest_config.get("reputation", {}).get("regions", []):
		reputation[String(r)] = 0


func tick(world, dt: float) -> void:
	_check_timer += dt
	if _check_timer >= _interval:
		_check_timer = 0.0
		refresh(world)


## Activates newly available quests and announces quests ready to claim.
func refresh(world) -> void:
	for qid in registry.quest_order:
		if not active.has(qid) and is_available(world, qid):
			_activate(world, qid)
	for qid in active:
		if not _ready_announced.has(qid) and is_complete(world, qid):
			_ready_announced[qid] = true
			world.emit_event("quest_ready", {"quest": qid, "name": registry.quests[qid].name})


func is_available(world, qid: String) -> bool:
	var q: Dictionary = registry.quests.get(qid, {})
	if q.is_empty() or active.has(qid):
		return false
	if completed.has(qid) and not bool(q.get("repeatable", false)):
		return false
	if float(cooldowns.get(qid, -1.0)) > world.sim_time:
		return false
	return Objectives.all_met(world, q.get("prerequisites", []))


func _activate(world, qid: String) -> void:
	var baseline := {}
	for o in registry.quests[qid].get("objectives", []):
		var key := Objectives.counter_key(o)
		if not key.is_empty():
			baseline[key] = int(world.counters.get(key, 0))
	active[qid] = {"baseline": baseline, "started": world.sim_time}
	world.emit_event("quest_started", {"quest": qid, "name": registry.quests[qid].name, "category": registry.quests[qid].get("category", "")})


func objective_progress(world, qid: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var base: Dictionary = active.get(qid, {}).get("baseline", {})
	for o in registry.quests[qid].get("objectives", []):
		out.append(Objectives.progress(world, o, base))
	return out


func is_complete(world, qid: String) -> bool:
	if not active.has(qid):
		return false
	return Objectives.all_met(world, registry.quests[qid].get("objectives", []), active[qid].baseline)


func has_completed(qid: String) -> bool:
	return int(completed.get(qid, 0)) > 0


## Claims a complete quest: consumes deliveries, grants rewards.
func claim(world, qid: String) -> String:
	if not active.has(qid):
		return "Quest is not active"
	if not is_complete(world, qid):
		return "Objectives are not complete"
	var q: Dictionary = registry.quests[qid]
	for o in q.get("objectives", []):
		if String(o.type) == "deliver":
			world.storage.remove(String(o.item), int(o.qty))
			world.record_sink(String(o.item), int(o.qty), "quest_delivery")
	active.erase(qid)
	_ready_announced.erase(qid)
	completed[qid] = int(completed.get(qid, 0)) + 1
	if bool(q.get("repeatable", false)):
		cooldowns[qid] = world.sim_time + float(q.get("cooldown_seconds", 3600.0))
	var summary: Dictionary = world.grant_rewards(q.get("rewards", {}), [], "quest:%s" % qid)
	world.emit_event("quest_completed", {"quest": qid, "name": q.name, "category": q.get("category", ""), "rewards": summary})
	refresh(world)
	return ""


# --- Reputation --------------------------------------------------------------

func add_reputation(world, region: String, points: int) -> void:
	if points <= 0:
		return
	var before := reputation_tier(region)
	reputation[region] = int(reputation.get(region, 0)) + points
	var after := reputation_tier(region)
	if after > before:
		world.emit_event("reputation_tier", {"region": region, "tier": after, "name": registry.reputation_tiers()[after].name})
		_check_reputation_characters(world, region, after)


func reputation_tier(region: String) -> int:
	var pts := int(reputation.get(region, 0))
	var tier := 0
	var tiers := registry.reputation_tiers()
	for i in tiers.size():
		if pts >= int(tiers[i].points):
			tier = i
	return tier


## {points, tier, tier_name, next_points (-1 at max)}
func reputation_progress(region: String) -> Dictionary:
	var tiers := registry.reputation_tiers()
	var t := reputation_tier(region)
	return {"points": int(reputation.get(region, 0)), "tier": t, "tier_name": tiers[t].name,
		"next_points": int(tiers[t + 1].points) if t + 1 < tiers.size() else -1}


## Reputation characters join once their region tier is reached.
func _check_reputation_characters(world, region: String, tier: int) -> void:
	for cid in registry.characters_by_acquisition("reputation"):
		var rq: Dictionary = registry.characters[cid].get("reputation", {})
		if String(rq.get("region", "")) == region and tier >= int(rq.get("tier", 99)) and not world.characters.has(cid):
			world.grant_character(cid, "reputation:%s" % region)


## Recipes can require a reputation tier ("requires_reputation": {region: tier}).
func recipe_gap(recipe: Dictionary) -> String:
	var rr: Dictionary = recipe.get("requires_reputation", {})
	for region in rr:
		if reputation_tier(String(region)) < int(rr[region]):
			return "Needs %s reputation with %s" % [registry.reputation_tiers()[int(rr[region])].name, registry.region_name(String(region))]
	return ""


# --- Persistence ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "completed": completed.duplicate(), "cooldowns": cooldowns.duplicate(),
		"reputation": reputation.duplicate()}


func load_dict(p_registry: DataRegistry, d: Dictionary) -> void:
	registry = p_registry
	active.clear()
	var a: Variant = d.get("active", {})
	if a is Dictionary:
		for qid in a:
			if registry.quests.has(qid) and a[qid] is Dictionary:
				var base := {}
				var b: Variant = a[qid].get("baseline", {})
				if b is Dictionary:
					for k in b:
						base[String(k)] = int(b[k])
				active[String(qid)] = {"baseline": base, "started": float(a[qid].get("started", 0.0))}
	for k in d.get("completed", {}):
		if registry.quests.has(k):
			completed[String(k)] = maxi(int(d.completed[k]), 0)
	for k in d.get("cooldowns", {}):
		if registry.quests.has(k):
			cooldowns[String(k)] = float(d.cooldowns[k])
	for k in d.get("reputation", {}):
		reputation[String(k)] = maxi(int(d.reputation[k]), 0)
	_ready_announced.clear()
