extends SceneTree
## Online screenshots against a running server (server/run_local.sh):
## boots the real game signed in as a new player, with a second scripted
## player ("Mara") who sends a friend request, runs a guild with chat, lists
## ore on the market and walks her heroes nearby.
##   WB_NAKAMA_URL=http://127.0.0.1:7350 xvfb-run godot --path . --rendering-method gl_compatibility \
##     -s res://tools/capture_online_screenshots.gd -- --out=/tmp/shots
## Overwrites user://online.cfg and the local save (dev machines only).

var _out := "user://screenshots"
var _url := OS.get_environment("WB_NAKAMA_URL")
var _frame := 0
var _main: Node
var _mara: OnlineService
var _group_id := ""
var _run := ""
var _panel  # SocialPanel (untyped: it uses the Game autoload)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	if _url.is_empty():
		_url = "http://127.0.0.1:7350"
	_run = "%x" % (int(Time.get_unix_time_from_system()) % 100000)
	for f in ["user://worldbound_save.json", OnlineService.SETTINGS_PATH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	OnlineService.save_settings(_url, "wb-dev-server-key", "Wren%s" % _run)
	# The second player, driven from this script.
	_mara = OnlineService.new(_url, "wb-dev-server-key")
	_mara.synchronous = true
	_mara.connect_blocking("shot-mara-" + _run, "Mara%s" % _run)
	var mw := SimulationWorld.create_new(DataRegistry.get_default())
	mw.storage.add("iron_ore", 60)
	mw.record_source("iron_ore", 60, "setup")
	mw.storage.add("oak_log", 40)
	mw.record_source("oak_log", 40, "setup")
	_mara.attach_world(mw)
	_mara.upload_now()
	_mara.market_list("iron_ore", 30, 450, "", func(_r: Dictionary) -> void: pass)
	_mara.market_list("oak_log", 20, 160, "", func(_r: Dictionary) -> void: pass)
	var g := _mara.client.create_group("Lantern Guild %s" % _run, "Friendly idle folk")
	_group_id = String(g.data.get("id", ""))
	_main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	var game: Node = root.get_node("Game")
	var hud = _main.get_node("HUD")
	var me: OnlineService = game.online
	_mara.socket.poll()
	if _frame % 30 == 0:
		_mara._update_presence()
	match _frame:
		5:
			var w = game.world
			for p in [["brom_stonefist", "mine_copper"], ["sylvara_moonleaf", "chop_oak"], ["tamsin_reed", "fish_minnow"]]:
				w.assign_activity(p[0], Assignment.create(p[0], w.registry.activities[p[1]]))
			var mw := _mara.world
			for p in [["brom_stonefist", "chop_oak"], ["sylvara_moonleaf", "fish_minnow"], ["tamsin_reed", "mine_copper"]]:
				mw.assign_activity(p[0], Assignment.create(p[0], mw.registry.activities[p[1]]))
			_mara.client.add_friend_by_id(me.client.user_id)
			me.client.join_group(_group_id)
			me.refresh_social()
		60:
			_mara.refresh_social()
			for t in ["Welcome to the Lantern Guild!", "Weekend Bounty starts Saturday, bring your miners."]:
				_mara.send_chat(t)
		20:
			game.select_character("brom_stonefist", true)
	if _frame % 30 == 10 and _frame < 720:
		for i in 30:
			_mara.world.step(0.1)
	match _frame - 460:
		240:
			_snap("25_other_players_nearby")
		245:
			hud._on_nav("social")
			_panel = _modal(hud)
		300:
			_snap("26_social_account")
		305:
			me.client.add_friend_by_id(_mara.client.user_id)  # accept Mara's request
			_panel._open_tab("friends")
		340:
			_panel._visit = me.client.call_rpc("wb_visit_town", {"user_id": _mara.client.user_id}).data
			_panel.refresh()
		360:
			_snap("27_social_friends")
		365:
			_panel._open_tab("guild")
		430:
			_snap("28_social_guild_chat")
		435:
			_panel._open_tab("market")
		490:
			_snap("29_social_market")
		495:
			_panel._open_tab("world")
		560:
			_snap("30_social_world_boss")
		565:
			hud._on_nav("recruit")
		600:
			_snap("31_recruit_online")
		610:
			print("ONLINE SCREENSHOTS DONE: %s (status %s)" % [_out, me.status])
			_mara.socket.close()
			_mara.free()
			OnlineService.clear_settings()
			quit()
	return false


func _modal(hud) -> Node:
	for c in hud._modal_layer.get_children():
		if c.get_script() and c.get_script().get_global_name() == "SocialPanel":
			return c
	return null


func _snap(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
