extends SceneTree
## Visual smoke test: boots the real Main scene, assigns all three starter
## characters, lets automation run, and saves screenshots of the key screens.
##   xvfb-run godot --path . --rendering-method gl_compatibility -s res://tools/capture_screenshots.gd -- --out=/tmp/shots
## Requires a display (Xvfb is fine); headless mode cannot render.

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


func _process(_delta: float) -> bool:
	_frame += 1
	var game: Node = root.get_node("Game")
	var hud = _main.get_node("HUD")
	match _frame:
		5:
			var w = game.world
			for p in [["brom_stonefist", "mine_copper"], ["sylvara_moonleaf", "chop_oak"], ["tamsin_reed", "fish_minnow"]]:
				w.assign_activity(p[0], Assignment.create(p[0], w.registry.activities[p[1]]))
			game.time_scale = 20.0
		40:
			_snap("01_village_start")
		400:
			game.time_scale = 1.0
			game.select_character("sylvara_moonleaf", true)
		460:
			_snap("02_forest_woodcutting")
		470:
			game.select_character("brom_stonefist", true)
		540:
			_snap("03_mine_selected_panel")
		545:
			hud.open_assign(game.world.characters.brom_stonefist)
		560:
			_snap("04_assignment_panel")
		565:
			hud.open_skills(game.world.characters.brom_stonefist)
		580:
			_snap("05_skills_panel")
		585:
			hud.open_storage()
		600:
			_snap("06_storage_panel")
		605:
			hud._close_modals()
			game.simulate_time_away(3600.0)
		625:
			_snap("07_offline_report")
		630:
			hud._close_modals()
			game.select_character("tamsin_reed", true)
		700:
			_snap("08_river_fishing")
		705:
			# Phase 2: combat, crafting, recruitment, town, gear.
			var w = game.world
			w.storage.add("bronze_sword", 1)
			w.record_source("bronze_sword", 1, "screenshot")
			w.equip("brom_stonefist", "bronze_sword")
			w.assign_activity("brom_stonefist", Assignment.create("brom_stonefist", w.registry.activities["hunt_meadows"]))
			w.storage.add("oak_plank", 10)
			w.record_source("oak_plank", 10, "screenshot")
			w.start_construction("bank")
			w.assign_activity("tamsin_reed", Assignment.create("tamsin_reed", w.registry.activities["construct"]))
			game.time_scale = 5.0
			game.select_character("brom_stonefist", true)
		820:
			game.time_scale = 1.0
		860:
			_snap("09_combat_meadows")
		865:
			var w2 = game.world
			hud.open_assign(w2.characters.brom_stonefist)
			for c in hud._modal_layer.get_children():
				if c is ActivityPanel:
					c._category = "combat"
					c._selected_activity = "hunt_meadows"
					c._rebuild()
		885:
			_snap("10_assign_combat")
		890:
			var w3 = game.world
			hud.open_assign(w3.characters.sylvara_moonleaf)
			for c in hud._modal_layer.get_children():
				if c is ActivityPanel:
					c._category = "crafting"
					c._selected_activity = "craft"
					c._recipe = "saw_oak"
					c._rebuild()
		910:
			_snap("11_assign_crafting")
		915:
			hud._on_nav("recruit")
			for c in hud._modal_layer.get_children():
				if c is RecruitPanel:
					var res = game.world.recruit("standard", 10)
					c._results = res.results
					c.refresh()
		940:
			_snap("12_recruit")
		945:
			hud._on_nav("heroes")
		965:
			_snap("13_heroes")
		970:
			hud._on_nav("town")
		990:
			_snap("14_town")
		995:
			hud.open_gear(game.world.characters.brom_stonefist)
		1015:
			_snap("15_gear")
		1020:
			hud._close_modals()
			game.select_character("tamsin_reed", true)
		1060:
			_snap("16_construction")
		1065:
			print("screenshots: %d saved to %s" % [_shots, ProjectSettings.globalize_path(_out)])
			return true
	return false


func _snap(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	_shots += 1
