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
	_phase3(reg)
	_phase5(reg)
	quit()


## Phase 3: exploration pace, expedition odds and dungeon outcomes for teams
## at reference levels (all skills set to the level, character level too).
func _phase3(reg: DataRegistry) -> void:
	print("")
	print("| Region | Explorer time to 35% / 98% explored (one starter, fresh world) |")
	print("|---|---|")
	for rid in ["greenvale"]:
		var w := SimulationWorld.create_new(reg, 7)
		var cid: String = w.character_order[0]
		w.assign_activity(cid, Assignment.create(cid, reg.activities["explore_" + rid]))
		var t35 := -1.0
		var t := 0.0
		while t < 14400.0 and w.exploration.explored_pct(rid) < 0.98:
			w.advance(60.0, 1.0)
			t += 60.0
			if t35 < 0.0 and w.exploration.explored_pct(rid) >= 0.35:
				t35 = t
		print("| %s | %s / %s |" % [reg.region_name(rid), OfflineReport.format_duration(t35), OfflineReport.format_duration(t)])
	print("")
	print("| Reference member (geared) | Level 10 | 20 | 30 | 40 | 50 | 60 |")
	print("|---|---|---|---|---|---|---|")
	var cells0 := []
	for lv in [10, 20, 30, 40, 50, 60]:
		var w0 := SimulationWorld.create_new(reg, 7)
		cells0.append(str(int(ExpeditionState.member_power(_leveled(w0.characters[w0.character_order[0]], lv, w0)))))
	print("| Power | %s |" % " | ".join(cells0))
	print("")
	print("| Expedition | Recommended power | Chance at level 20 | 40 | 60 |")
	print("|---|---|---|---|---|")
	for xid in reg.expeditions:
		var x: Dictionary = reg.expeditions[xid]
		var cells := []
		for lv in [20, 40, 60]:
			var w := SimulationWorld.create_new(reg, 7)
			var team := []
			for cid in w.character_order.slice(0, int(x.team_size)):
				team.append(_leveled(w.characters[cid], lv, w))
			while team.size() < int(x.team_size):
				team.append(team[0])
			cells.append("%d%%" % roundi(w.expeditions.success_chance(w, x, team, true) * 100.0))
		print("| %s | %d | %s |" % [x.name, int(x.recommended_power), " | ".join(cells)])
	print("")
	print("| Dungeon | Party | Result at level 20 | 40 | 60 |")
	print("|---|---|---|---|---|")
	for did in reg.dungeons:
		var d: Dictionary = reg.dungeons[did]
		var cells := []
		for lv in [20, 40, 60]:
			var w := SimulationWorld.create_new(reg, 7)
			for rid in reg.map_region_order:
				w._set_region_unlocked(rid)
			w.storage.add("cooked_trout", 60)
			w.record_source("cooked_trout", 60, "report")
			var team := []
			for cid in w.character_order.slice(0, int(d.party_max)):
				_leveled(w.characters[cid], lv, w)
				team.append(cid)
			var run := DungeonRun.create(w, did, team)
			while not run.tick(w, 1.0):
				pass
			cells.append("%s %s" % [run.result, OfflineReport.format_duration(run.elapsed)])
		print("| %s | %d | %s |" % [d.name, int(d.party_max), " | ".join(cells)])


## Sets every relevant skill and the character level to `lv` and equips the
## gear tier a player would have at that level (bronze/iron/mithril/adamantite).
func _leveled(ch: Adventurer, lv: int, w: SimulationWorld = null) -> Adventurer:
	for s in ["attack", "strength", "defense", "ranged", "magic", "exploration", "mining", "archaeology", "woodcutting", "foraging"]:
		ch.skills.set_level(s, lv)
	ch.character_xp = float(ch.registry.character_xp_table.xp_for_level(lv))
	if w:
		var tier: String = "adamantite" if lv >= 45 else ("mithril" if lv >= 30 else ("iron" if lv >= 15 else "bronze"))
		var wood: String = "yew" if lv >= 45 else ("maple" if lv >= 30 else ("willow" if lv >= 15 else "oak"))
		var bow := wood + "_shortbow"
		if lv >= 70:  # Phase 5 gear
			tier = "starmetal" if lv >= 90 else "voidsteel"
			wood = "skywood" if lv >= 90 else "shadowbark"
			bow = wood + "_bow"
		var staff: String = wood + "_staff" if lv >= 15 else "apprentice_staff"
		var weapon: String = {"melee": tier + "_sword", "ranged": bow, "magic": staff}[ch.combat_style()]
		for it in [weapon, tier + "_helm", tier + "_platebody", tier + "_platelegs", tier + "_gloves", tier + "_boots"]:
			if w.registry.items.has(it):
				w.storage.add(it, 1)
				w.record_source(it, 1, "report")
				w.equip(ch.id, it)
	ch.invalidate_stats()
	ch.health = ch.max_health()
	return ch


## Phase 5: endgame dungeons and mythic tiers, mastery pace, ascension points.
func _phase5(reg: DataRegistry) -> void:
	print("")
	print("| Endgame dungeon | Party | Result at level 70 | 85 | 99 |")
	print("|---|---|---|---|---|")
	for did in ["dread_citadel", "starfall_sanctum"]:
		var d: Dictionary = reg.dungeons[did]
		var cells := []
		for lv in [70, 85, 99]:
			cells.append(_run(reg, did, int(d.party_max), lv, 0))
		print("| %s | %d | %s |" % [d.name, int(d.party_max), " | ".join(cells)])
	print("")
	print("| Mythic run (party of 4, level 99) | Tier 1 | 3 | 5 | 7 | 10 |")
	print("|---|---|---|---|---|---|")
	for did in ["goblin_warren", "tomb_of_the_sand_king", "dread_citadel"]:
		var cells := []
		for tier in [1, 3, 5, 7, 10]:
			cells.append(_run(reg, did, mini(4, int(reg.dungeons[did].party_max)), 99, tier))
		print("| %s | %s |" % [reg.dungeons[did].name, " | ".join(cells)])
	print("")
	var w := SimulationWorld.create_new(reg, 7)
	var ch: Adventurer = w.characters["brom_stonefist"]
	_leveled(ch, 99, w)
	ch.skills.set_level("mining", 99)
	for rid in reg.map_region_order:
		w._set_region_unlocked(rid)
	ch.tile = w.free_tile_near(w.locations["voidstone_pits"].rect.get_center())
	w.quiet = true
	w.assign_activity(ch.id, Assignment.create(ch.id, reg.activities["mine_voidstone"]))
	w.advance(3600.0, 1.0)
	var per := float(reg.endgame.mastery.get("xp_per_level", 2000000))
	var mxp := float(ch.mastery_xp.get("mining", 0.0))
	print("Mastery pace: Brom (mining 99, voidsteel gear) mining voidstone earns %d mastery XP/h, so a mastery level takes about %s." % [
		int(mxp), OfflineReport.format_duration(per / maxf(mxp, 1.0) * 3600.0)])
	var pc: Dictionary = reg.endgame.ascension.get("points", {})
	var rows := []
	for score in [1000, 2500, 4000, 6000]:
		rows.append("score %d = %d points" % [score, int(floor(float(pc.get("scale", 30.0)) * sqrt(score / float(pc.get("unit", 100.0)))))])
	print("Ascension points (first ascension): %s." % ", ".join(rows))


func _run(reg: DataRegistry, did: String, size: int, lv: int, tier: int) -> String:
	var w := SimulationWorld.create_new(reg, 7)
	for rid in reg.map_region_order:
		w._set_region_unlocked(rid)
	w.storage.add("cooked_gloom_eel", 120)
	w.record_source("cooked_gloom_eel", 120, "report")
	var team := []
	for cid in w.character_order:
		if team.size() >= size:
			break
		_leveled(w.characters[cid], lv, w)
		team.append(cid)
	for extra in ["elowen_starweaver", "nyx_voidwalker", "kaelen_stormforge"]:
		if team.size() >= size:
			break
		w.add_character(extra)
		_leveled(w.characters[extra], lv, w)
		team.append(extra)
	var run := DungeonRun.create(w, did, team, tier)
	while not run.tick(w, 1.0):
		pass
	return "%s %s" % [run.result, OfflineReport.format_duration(run.elapsed)]