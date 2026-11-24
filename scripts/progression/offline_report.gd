class_name OfflineReport
extends RefCounted
## Summary of what happened while the player was away. Built by diffing a
## snapshot taken before the offline simulation with one taken after, plus the
## notable events captured while it ran. Because it is a diff of real state it
## can never report more than was actually granted.

var elapsed_seconds := 0.0
var simulated_seconds := 0.0
var capped := false
var cap_seconds := 0.0
var storage_gained := {}  # item_id -> qty
## character_id -> {name, xp: {skill: amount}, levels: {skill: [from, to]},
##                  gathered: {item: qty}, deposited: {item: qty}, trips,
##                  state_label, interruptions: [reason]}
var characters := {}
var rare_finds: Array[Dictionary] = []
var interruptions: Array[Dictionary] = []


static func capture(world: SimulationWorld) -> Dictionary:
	var snap := {"storage": world.storage.items(), "characters": {}}
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		var levels := {}
		for s in world.registry.skill_order:
			levels[s] = ch.skills.get_level(s)
		snap.characters[cid] = {
			"xp": ch.skills.to_dict(),
			"levels": levels,
			"gathered": ch.stats.gathered.duplicate(),
			"deposited": ch.stats.deposited.duplicate(),
			"trips": int(ch.stats.trips),
		}
	return snap


static func build(world: SimulationWorld, before: Dictionary, after: Dictionary, events: Array) -> OfflineReport:
	var r := OfflineReport.new()
	r.storage_gained = _diff(before.storage, after.storage)
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		var b: Dictionary = before.characters.get(cid, {})
		var a: Dictionary = after.characters[cid]
		var lv := {}
		for s in a.levels:
			var from_l := int(b.get("levels", {}).get(s, 1))
			if int(a.levels[s]) > from_l:
				lv[s] = [from_l, int(a.levels[s])]
		var xp := {}
		var xp_diff := _diff_f(b.get("xp", {}), a.xp)
		for s in xp_diff:
			xp[s] = xp_diff[s]
		r.characters[cid] = {
			"name": ch.display_name,
			"xp": xp,
			"levels": lv,
			"gathered": _diff(b.get("gathered", {}), a.gathered),
			"deposited": _diff(b.get("deposited", {}), a.deposited),
			"trips": int(a.trips) - int(b.get("trips", 0)),
			"state_label": CharacterStates.label_of(ch.state),
			"status": ch.status_message,
			"interruptions": [],
		}
	for ev in events:
		match String(ev.get("type", "")):
			"rare_drop":
				r.rare_finds.append(ev)
			"interrupted":
				r.interruptions.append(ev)
				var c: Dictionary = r.characters.get(ev.get("character_id", ""), {})
				if not c.is_empty():
					c.interruptions.append(String(ev.get("reason", "")))
	return r


func total_xp() -> float:
	var t := 0.0
	for cid in characters:
		for s in characters[cid].xp:
			t += float(characters[cid].xp[s])
	return t


func total_items_gathered() -> int:
	var t := 0
	for cid in characters:
		for item in characters[cid].gathered:
			t += int(characters[cid].gathered[item])
	return t


func has_progress() -> bool:
	return simulated_seconds > 0.0 and (total_xp() > 0.0 or total_items_gathered() > 0)


static func _diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for k in after:
		var d := int(after[k]) - int(before.get(k, 0))
		if d != 0:
			out[k] = d
	return out


static func _diff_f(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for k in after:
		var d := float(after[k]) - float(before.get(k, 0.0))
		if d > 0.0001:
			out[k] = d
	return out


static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, s % 60]
	return "%ds" % s
