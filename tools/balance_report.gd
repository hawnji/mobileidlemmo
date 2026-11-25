extends SceneTree
## Prints expected and simulated rates for every starter character x activity.
##   godot --headless --path . -s res://tools/balance_report.gd
func _initialize() -> void:
	var reg := DataRegistry.get_default()
	print("| Character | Activity | Est. items/h | Est. XP/h | Simulated items (1h) | Skill level after 1h |")
	print("|---|---|---|---|---|---|")
	for cid in reg.characters_by_acquisition("starter"):
		for aid in ["mine_copper", "chop_oak", "fish_minnow"]:
			var w := SimulationWorld.create_new(reg, 4242)
			var ch: Adventurer = w.characters[cid]
			var e := ActivityEstimator.estimate(w, ch, aid)
			var skill := String(reg.activities[aid].skill)
			var lv0 := ch.skills.get_level(skill)
			w.quiet = true
			w.assign_activity(cid, Assignment.create(cid, reg.activities[aid]))
			w.advance(3600.0, 1.0)
			var item := String(reg.node_types[reg.activities[aid].node_type].yield.item)
			print("| %s | %s | %d | %d | %d | %d -> %d |" % [ch.display_name, reg.activities[aid].name, e.items_per_hour, e.xp_per_hour, int(ch.stats.gathered.get(item, 0)), lv0, ch.skills.get_level(skill)])
	print("")
	print("| Character | Hunting ground | Kills (1h) | Gold (1h) | Knock-outs | Combat levels after 1h | Est. risk |")
	print("|---|---|---|---|---|---|---|")
	for cid in reg.characters_by_acquisition("starter"):
		for aid in ["hunt_meadows", "hunt_wolves", "raid_goblins", "slay_troll"]:
			var w := SimulationWorld.create_new(reg, 4242)
			w.storage.add("cooked_minnow", 200)
			w.record_source("cooked_minnow", 200, "report")
			var ch: Adventurer = w.characters[cid]
			var e := ActivityEstimator.estimate(w, ch, aid)
			var gold0 := w.wallet.get_balance("gold")
			w.quiet = true
			w.assign_activity(cid, Assignment.create(cid, reg.activities[aid]))
			w.advance(3600.0, 1.0)
			var kills := 0
			for k in ch.stats.kills:
				kills += int(ch.stats.kills[k])
			var style := CombatRules.offense_skill(ch.combat_style())
			print("| %s | %s | %d | %d | %d | %s %d, def %d, hunting %d | %s |" % [ch.display_name, reg.activities[aid].name, kills, w.wallet.get_balance("gold") - gold0,
				int(ch.stats.deaths), style, ch.skills.get_level(style), ch.skills.get_level("defense"), ch.skills.get_level("hunting"), e.get("risk", "?")])
	print("")
	print("| Character | Recipe | Crafts (1h, unlimited materials) | Skill level after 1h |")
	print("|---|---|---|---|")
	for spec in [["brom_stonefist", "smelt", "smelt_bronze", {"copper_ore": 2000, "tin_ore": 2000}], ["sylvara_moonleaf", "craft", "saw_oak", {"oak_log": 3000}],
			["tamsin_reed", "cook", "cook_minnow", {"raw_minnow": 3000}]]:
		var w := SimulationWorld.create_new(reg, 4242)
		for it in spec[3]:
			w.storage.add(it, spec[3][it])
		var ch: Adventurer = w.characters[spec[0]]
		var r: Dictionary = reg.recipes[spec[2]]
		var lv0 := ch.skills.get_level(String(r.skill))
		var a := Assignment.create(spec[0], reg.activities[spec[1]])
		a.recipe_id = spec[2]
		w.quiet = true
		w.assign_activity(spec[0], a)
		w.advance(3600.0, 1.0)
		var made := 0
		for it in ch.stats.crafted:
			made += int(ch.stats.crafted[it])
		print("| %s | %s | %d | %d -> %d |" % [ch.display_name, r.name, made, lv0, ch.skills.get_level(String(r.skill))])
	quit()
