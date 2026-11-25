extends Node
## Entry scene. Instances the world view and HUD, then starts the session
## (load save -> apply offline progress -> run).
##
## `-- --smoke-test` (used by tools/run_tests.sh) runs against a throwaway
## save file, assigns every character, and quits after a few seconds.

const WORLD_VIEW := preload("res://scenes/world/WorldView.tscn")
const HUD := preload("res://scenes/ui/HUD.tscn")
const SMOKE_SAVE := "user://smoke_test_save.json"

var _smoke := false
var _smoke_time := 0.0


func _ready() -> void:
	_smoke = OS.get_cmdline_user_args().has("--smoke-test")
	add_child(WORLD_VIEW.instantiate())
	add_child(HUD.instantiate())
	if _smoke:
		var registry := DataRegistry.get_default()
		var backend := LocalGameBackend.new(registry, SMOKE_SAVE)
		backend.delete_save()
		Game.start_session(backend)
		for cid in Game.world.character_order:
			var act: String = {"brom_stonefist": "mine_copper", "sylvara_moonleaf": "chop_oak"}.get(cid, "fish_minnow")
			Game.world.assign_activity(cid, Assignment.create(cid, registry.activities[act]))
		Game.time_scale = 20.0
	else:
		var settings := OnlineService.load_settings()
		if settings.is_empty():
			Game.start_session()
		else:
			Game.start_session(NakamaGameBackend.new(DataRegistry.get_default(), settings))


func _process(delta: float) -> void:
	if not _smoke:
		return
	_smoke_time += delta
	if _smoke_time > 4.0:
		var w: SimulationWorld = Game.world
		var ledger_ok: bool = w.held_totals() == w.ledger_totals()
		var ok: bool = ledger_ok and w.sim_time > 10.0
		print("SMOKE TEST %s: sim_time=%.1f storage=%d ledger_ok=%s" % ["PASSED" if ok else "FAILED", w.sim_time, w.storage.total_units(), ledger_ok])
		Game.backend.delete_save()
		get_tree().quit(0 if ok else 1)
