extends SceneTree
## Prints expected and simulated rates for every starter character x activity.
##   godot --headless --path . -s res://tools/balance_report.gd
func _initialize() -> void:
	var reg := DataRegistry.get_default()
	print("| Character | Activity | Est. items/h | Est. XP/h | Simulated items (1h) | Skill level after 1h |")
	print("|---|---|---|---|---|---|")
	for cid in reg.character_order:
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
	quit()
