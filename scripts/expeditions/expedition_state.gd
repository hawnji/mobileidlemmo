class_name ExpeditionState
extends RefCounted
## Long-duration expeditions (data/expeditions/expeditions.json).
##
## A team of the expedition's size leaves the map (state AWAY) for the
## duration. The result is decided when the timer ends, using an RNG seeded
## when the expedition started, so it does not matter whether the player was
## online, offline, or reloaded a save in between.
##
## What influences the outcome:
##   * requirements (hard): each must be met by at least one team member;
##   * team power vs. recommended power: combat level, character level and
##     equipment (armour, weapon power, accuracy) -> success chance;
##   * preparation: optional supplies (food) taken from storage at the start;
##   * optional stages: taken when the team qualifies (branching), adding
##     rewards or lowering risk;
##   * random events: ambushes (power checks), hazards (skill checks),
##     hidden chambers and extra treasure (skill-gated bonuses), NPCs;
##   * traits/stats: "expedition_reward" multiplies rewards.
## Slots come from the Expedition Center ("expedition_slots").

var active: Array[Dictionary] = []  # {uid, expedition_id, team, started, ends_at, seed, supplied}
var history: Array[Dictionary] = []  # most recent results first (max 20)
var completed_total := 0
var _next_uid := 1


func slots(world) -> int:
	return int(world.account_stats().get_stat("expedition_slots"))


func has_member(cid: String) -> bool:
	for x in active:
		if x.team.has(cid):
			return true
	return false


static func member_power(ch: Adventurer) -> float:
	return ch.combat_level() * 4.0 + ch.character_level() * 2.0 + ch.stat("armor") * 0.5 + ch.stat("weapon_power") * 3.0 + ch.stat("accuracy")


static func team_power(team: Array) -> float:
	var p := 0.0
	for ch in team:
		p += member_power(ch)
	return p


## Requirement gaps for a team ([] = all met).
static func missing_requirements(registry: DataRegistry, x: Dictionary, team: Array) -> Array[String]:
	var out: Array[String] = []
	for req in x.get("requirements", []):
		if not Objectives.team_meets(registry, team, req):
			out.append(Objectives.describe(registry, req))
	return out


func success_chance(world, x: Dictionary, team: Array, supplied: bool) -> float:
	var cfg: Dictionary = world.registry.expedition_config
	var ratio := team_power(team) / maxf(float(x.get("recommended_power", 100)), 1.0)
	var p := float(cfg.get("base_success", 0.25)) + float(cfg.get("power_weight", 0.65)) * minf(ratio, 1.5)
	if supplied:
		p += float(cfg.get("supplies_bonus", 0.08))
	return clampf(p, float(cfg.get("min_success", 0.05)), float(cfg.get("max_success", 0.97)))


## Food needed for full preparation: one per member per started hour.
static func supplies_needed(x: Dictionary) -> int:
	return int(x.get("team_size", 1)) * maxi(ceili(float(x.get("duration_seconds", 3600)) / 3600.0), 1)


func start(world, expedition_id: String, team_ids: Array, use_supplies: bool) -> String:
	var reg: DataRegistry = world.registry
	var x: Dictionary = reg.expeditions.get(expedition_id, {})
	if x.is_empty():
		return "Unknown expedition"
	if not world.is_region_unlocked(String(x.region)):
		return "Unlock %s first" % reg.region_name(String(x.region))
	if active.size() >= slots(world):
		return "No free expedition slot (build or upgrade the Expedition Center)"
	if team_ids.size() != int(x.get("team_size", 1)):
		return "This expedition needs a team of %d" % int(x.get("team_size", 1))
	var err: String = world._check_team_available(team_ids)
	if not err.is_empty():
		return err
	var team := []
	for cid in team_ids:
		team.append(world.characters[cid])
	var missing := missing_requirements(reg, x, team)
	if not missing.is_empty():
		return "Team needs: %s" % ", ".join(missing)
	var supplied := false
	if use_supplies:
		supplied = _consume_supplies(world, supplies_needed(x))
	var run := {"uid": _next_uid, "expedition_id": expedition_id, "team": team_ids.duplicate(), "started": world.sim_time,
		"ends_at": world.sim_time + float(x.get("duration_seconds", 3600)), "seed": world.rng.randi(), "supplied": supplied}
	_next_uid += 1
	for cid in team_ids:
		world._send_away(world.characters[cid], "expedition:%s" % expedition_id)
	active.append(run)
	world.emit_event("expedition_started", {"expedition": expedition_id, "name": x.name, "team": team_ids.duplicate(), "ends_at": run.ends_at})
	return ""


## Rations first, then the most filling food. All or nothing.
func _consume_supplies(world, needed: int) -> bool:
	var foods := []
	for it in world.storage.items():
		var heal := float(world.registry.items.get(it, {}).get("heal", 0))
		if heal > 0.0 and not world.locked_items.has(it):
			foods.append([1000.0 if it == "expedition_rations" else heal, it])
	foods.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0
	for f in foods:
		total += world.storage.get_quantity(f[1])
	if total < needed:
		return false
	for f in foods:
		if needed <= 0:
			break
		var q := mini(world.storage.get_quantity(f[1]), needed)
		world.storage.remove(f[1], q)
		world.record_sink(f[1], q, "expedition_supplies")
		needed -= q
	return true


func tick(world) -> void:
	if active.is_empty():
		return
	for run in active.duplicate():
		if world.sim_time >= float(run.ends_at):
			active.erase(run)
			resolve(world, run)


func resolve(world, run: Dictionary) -> Dictionary:
	var reg: DataRegistry = world.registry
	var cfg: Dictionary = reg.expedition_config
	var x: Dictionary = reg.expeditions[run.expedition_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.seed)
	var team := []
	for cid in run.team:
		if world.characters.has(cid):
			team.append(world.characters[cid])
	var power := team_power(team)
	var recommended := maxf(float(x.get("recommended_power", 100)), 1.0)
	var reward_mult := 1.0
	var risk_mult := 1.0
	var extra_items := []
	var bonus_fragments := 0
	var injured := {}
	var story: Array[String] = []
	# Optional stages: the team takes every branch it qualifies for.
	for st in x.get("stages", []):
		var ok := true
		for req in st.get("requires", []):
			if not Objectives.team_meets(reg, team, req):
				ok = false
		if ok:
			reward_mult += float(st.get("reward_mult", 0.0))
			risk_mult *= float(st.get("risk_mult", 1.0))
			extra_items.append_array(st.get("extra_items", []))
			story.append(String(st.get("message", st.get("name", ""))))
	# Random events.
	for ev in x.get("events", []):
		var kind := String(ev.get("kind", "bonus"))
		var chance := float(ev.get("chance", 0.0))
		if kind == "ambush" or kind == "hazard":
			chance *= risk_mult
		if rng.randf() >= chance:
			continue
		match kind:
			"ambush":
				var need := recommended * float(ev.get("power_check", 1.0))
				var win := power >= need or rng.randf() < power / need * 0.5
				if win:
					story.append("%s The team fought them off." % ev.get("message", ""))
				else:
					reward_mult += float(ev.get("fail_reward_mult", -0.3))
					story.append("%s The team was driven back." % ev.get("message", ""))
					if bool(ev.get("injury", false)) and not team.is_empty():
						injured[team[rng.randi_range(0, team.size() - 1)].id] = true
			"hazard":
				var sc: Dictionary = ev.get("skill_check", {})
				if not sc.is_empty() and Objectives.team_meets(reg, team, {"type": "skill", "skill": sc.skill, "level": sc.level}):
					story.append(String(ev.get("pass_message", "The team avoided danger.")))
				else:
					reward_mult += float(ev.get("fail_reward_mult", -0.2))
					story.append(String(ev.get("message", "")))
					if bool(ev.get("injury", false)) and not team.is_empty():
						injured[team[rng.randi_range(0, team.size() - 1)].id] = true
			_:
				var sc2: Dictionary = ev.get("skill_check", {})
				if not sc2.is_empty() and not Objectives.team_meets(reg, team, {"type": "skill", "skill": sc2.skill, "level": sc2.level}):
					continue
				reward_mult += float(ev.get("reward_mult", 0.0))
				extra_items.append_array(ev.get("extra_items", []))
				bonus_fragments += int(ev.get("fragments", 0))
				story.append(String(ev.get("message", ev.get("name", ""))))
	var p := success_chance(world, x, team, bool(run.get("supplied", false)))
	var success := rng.randf() < p
	var stat_mult := 0.0
	for ch in team:
		stat_mult += ch.stat("expedition_reward")
	stat_mult = stat_mult / maxf(team.size(), 1) if not team.is_empty() else 1.0
	var mult := maxf(reward_mult, 0.1) * stat_mult
	if not success:
		mult *= float(cfg.get("failure_reward_fraction", 0.25))
		for i in range(0, team.size(), 2):
			injured[team[i].id] = true
	var rewards: Dictionary = x.get("rewards", {})
	var block := {"currencies": rewards.get("currencies", {}), "items": rewards.get("items", []) + extra_items,
		"xp": rewards.get("xp", {})}
	var summary: Dictionary = world.grant_rewards(block, team, "expedition:%s" % run.expedition_id, rng, mult)
	# Character fragments (to a random team member).
	var fr: Dictionary = rewards.get("fragments", {})
	var frags := bonus_fragments
	if success and rng.randf() < float(fr.get("chance", 0.0)):
		frags += int(fr.get("amount", 5))
	if frags > 0 and not team.is_empty():
		var who: Adventurer = team[rng.randi_range(0, team.size() - 1)]
		world.fragments[who.id] = int(world.fragments.get(who.id, 0)) + frags
		summary["fragments"] = {who.id: frags}
	var injury := float(cfg.get("injury_seconds", 600.0))
	for ch in team:
		world.return_from_away(ch, injury if injured.has(ch.id) else 0.0)
	completed_total += 1
	world.count("expedition")
	world.count("expedition:%s" % run.expedition_id)
	var result := {"expedition": run.expedition_id, "name": x.name, "success": success, "chance": p, "rewards": summary,
		"story": story, "injured": injured.keys(), "team": run.team.duplicate(), "time": world.sim_time}
	history.push_front(result)
	if history.size() > 20:
		history.resize(20)
	world.emit_event("expedition_completed", result)
	return result


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "history": history.duplicate(true), "completed_total": completed_total, "next_uid": _next_uid}


func load_dict(world, d: Dictionary) -> void:
	active.clear()
	for run in d.get("active", []):
		if run is Dictionary and world.registry.expeditions.has(run.get("expedition_id", "")):
			var team := []
			for cid in run.get("team", []):
				if world.characters.has(cid):
					team.append(String(cid))
			if team.is_empty():
				continue
			active.append({"uid": int(run.get("uid", 0)), "expedition_id": String(run.expedition_id), "team": team,
				"started": float(run.get("started", 0.0)), "ends_at": float(run.get("ends_at", 0.0)),
				"seed": int(run.get("seed", 1)), "supplied": bool(run.get("supplied", false))})
	history.clear()
	for h in d.get("history", []):
		if h is Dictionary:
			history.append(h)
	completed_total = maxi(int(d.get("completed_total", 0)), 0)
	_next_uid = maxi(int(d.get("next_uid", 1)), 1)
