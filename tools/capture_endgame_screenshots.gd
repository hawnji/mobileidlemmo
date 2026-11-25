extends SceneTree
## Phase 5 screenshots: boots the real Main scene, turns the new world into a
## late-game account (all regions open, relics, pets, mounts, mastery, a
## mythic record) and captures the endgame regions and the Legacy screen.
##   xvfb-run godot --path . --rendering-method gl_compatibility -s res://tools/capture_endgame_screenshots.gd -- --out=/tmp/shots
## Deletes the local save first (dev machines only).

var _out := "user://screenshots"
var _frame := 0
var _main: Node
var _shots := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var save := ProjectSettings.globalize_path("user://worldbound_save.json")
	if FileAccess.file_exists(save):
		DirAccess.remove_absolute(save)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(_main)


func _give(w, item: String, qty := 1) -> void:
	w.storage.add(item, qty)
	w.record_source(item, qty, "screenshot")


func _legacy(hud, tab: String) -> void:
	for c in hud._modal_layer.get_children():
		if c.get_script() and c.get_script().get_global_name() == "LegacyPanel":
			c._open_tab(tab)


func _process(_delta: float) -> bool:
	_frame += 1
	var game: Node = root.get_node("Game")
	var hud = _main.get_node("HUD")
	var w = game.world
	match _frame:
		5:
			for rid in w.registry.map_region_order:
				if not w.is_region_unlocked(rid):
					w._set_region_unlocked(rid)
			w.endgame.set_calendar(Time.get_unix_time_from_datetime_string("2026-11-20T12:00:00"))
			for cid in w.character_order:
				var ch = w.characters[cid]
				for sk in ["attack", "strength", "defense", "ranged", "magic", "mining", "woodcutting", "fishing", "foraging", "exploration"]:
					ch.skills.set_level(sk, 92)
				ch.skills.set_level("mining", 99)
				ch.character_xp = float(w.registry.character_xp_table.xp_for_level(85))
				ch.invalidate_stats()
			var brom = w.characters["brom_stonefist"]
			brom.mastery_xp["mining"] = 7300000.0
			w.town.levels["outpost_shadowlands"] = 1
			w.town.levels["outpost_celestial"] = 1
			w.town.recompute(w.registry)
			w._apply_account_effects()
			for it in ["relic_miners_lantern", "relic_scholars_tome", "relic_celestial_hourglass", "relic_warlords_banner",
					"pet_egg_rock_crab", "pet_egg_study_owl", "pet_egg_cloud_sprite", "mount_griffin", "mount_pack_pony", "mount_shadow_steed"]:
				_give(w, it)
				w.use_item(it)
			w.wallet.earn("relic_dust", 400, "screenshot")
			w.upgrade_relic("miners_lantern")
			w.upgrade_relic("miners_lantern")
			w.endgame.pets["rock_crab"] = {"level": 6, "xp": 90000.0}
			w.assign_pet("brom_stonefist", "rock_crab")
			w.assign_pet("sylvara_moonleaf", "study_owl")
			w.assign_mount("brom_stonefist", "pack_pony")
			w.assign_mount("sylvara_moonleaf", "griffin")
			w.assign_mount("tamsin_reed", "shadow_steed")
			w.wallet.earn("ascension_points", 60, "screenshot")
			w.buy_perk("insight")
			w.buy_perk("swift_hands")
			w.dungeon_records["dread_citadel"] = {"clears": 3, "best_time": 640.0}
			w.endgame.mythic_records["dread_citadel"] = 3
			w.wallet.earn("event_tokens", 260, "screenshot")
			var places := {"brom_stonefist": ["voidstone_pits", "mine_voidstone"], "sylvara_moonleaf": ["shadowbark_wood", "chop_shadowbark"],
				"tamsin_reed": ["black_marsh", "fish_gloom_eel"]}
			for cid in places:
				var ch = w.characters[cid]
				ch.tile = w.free_tile_near(w.locations[places[cid][0]].rect.get_center())
				w.assign_activity(cid, Assignment.create(cid, w.registry.activities[places[cid][1]]))
			w.exploration.reveal(Vector2i(32, 112), 26)
			w.exploration.reveal(Vector2i(96, 120), 34)
			game.time_scale = 5.0
			game.select_character("brom_stonefist", true)
		240:
			game.time_scale = 1.0
		260:
			_snap("32_shadowlands")
		265:
			var ch = w.characters["sylvara_moonleaf"]
			w.cancel_assignment(ch.id)
			ch.tile = w.free_tile_near(w.locations["skyreach"].rect.get_center())
			ch.path.clear()
			w.assign_activity(ch.id, Assignment.create(ch.id, w.registry.activities["chop_skywood"]))
			game.select_character("sylvara_moonleaf", true)
		340:
			_snap("33_celestial_isles")
		345:
			hud._on_nav("legacy")
		370:
			_snap("34_legacy_relics")
		372:
			_legacy(hud, "pets")
		390:
			_snap("35_legacy_pets")
		392:
			_legacy(hud, "mounts")
		410:
			_snap("36_legacy_mounts")
		412:
			game.select_character("brom_stonefist", false)
			hud._on_nav("legacy")
			_legacy(hud, "mastery")
		430:
			_snap("37_legacy_mastery")
		432:
			_legacy(hud, "ascension")
		450:
			_snap("38_legacy_ascension")
		452:
			_legacy(hud, "season")
		470:
			_snap("39_legacy_season")
		472:
			hud._on_nav("journeys")
			for c in hud._modal_layer.get_children():
				if c is JourneysPanel:
					c._tab = "dungeons"
					c._tiers["dread_citadel"] = 4
					c.refresh()
		485:
			for c in hud._modal_layer.get_children():
				if c is JourneysPanel:
					c._scroll.scroll_vertical = 100000
		495:
			_snap("40_mythic_tiers")
		497:
			hud._on_nav("map")
		520:
			_snap("41_world_map_endgame")
		525:
			print("endgame screenshots: %d saved to %s" % [_shots, ProjectSettings.globalize_path(_out)])
			return true
	return false


func _snap(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	_shots += 1
