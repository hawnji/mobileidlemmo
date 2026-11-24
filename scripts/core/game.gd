extends Node
## Autoload "Game": owns the running session (registry, backend, world) and
## drives the fixed-step simulation clock. Scenes observe the world through
## `world.event_emitted` and the signals below. Nothing heavy happens in
## _ready(): Main calls start_session() so tests and tools can load the
## project without touching save files.

signal session_started(world: SimulationWorld)
signal offline_report_ready(report: OfflineReport)
signal world_event(event: Dictionary)
signal selection_changed(character_id: String)

var registry: DataRegistry
var backend: GameBackend
var world: SimulationWorld
var time_scale := 1.0
var tick_seconds := 0.1
var running := false

var _accumulator := 0.0
var _autosave_seconds := 30.0
var _since_save := 0.0
var _paused_at_unix := -1.0
var pending_report: OfflineReport
## Presentation state shared by the world view and HUD (not persisted).
var selected_character_id := ""
var follow_selected := false


func select_character(character_id: String, follow := false) -> void:
	selected_character_id = character_id
	follow_selected = follow
	selection_changed.emit(character_id)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start_session(p_backend: GameBackend = null) -> void:
	registry = DataRegistry.get_default()
	var problems := registry.validate()
	for p in problems:
		push_error("Data validation: " + p)
	tick_seconds = float(registry.get_config("simulation.tick_seconds", 0.1))
	_autosave_seconds = float(registry.get_config("save.autosave_seconds", 30))
	backend = p_backend if p_backend else LocalGameBackend.new(registry)
	var loaded := backend.load_world(registry)
	if loaded.is_empty():
		world = SimulationWorld.create_new(registry)
		pending_report = null
	else:
		world = loaded.world
		var elapsed: float = backend.now_unix() - float(loaded.saved_at_unix)
		pending_report = backend.get_offline_provider().apply_offline_progress(world, elapsed)
	world.event_emitted.connect(_on_world_event)
	running = true
	set_process(true)
	session_started.emit(world)
	if pending_report and pending_report.simulated_seconds > 0.0:
		offline_report_ready.emit(pending_report)
	save_now()


func _process(delta: float) -> void:
	if not running or world == null:
		return
	_accumulator += minf(delta, 0.25) * time_scale
	var steps := 0
	var max_steps := int(ceil(50.0 * maxf(time_scale, 1.0) / 10.0)) + 5
	while _accumulator >= tick_seconds and steps < max_steps:
		world.step(tick_seconds)
		_accumulator -= tick_seconds
		steps += 1
	if steps >= max_steps:
		_accumulator = 0.0  # drop backlog rather than spiral
	_since_save += delta
	if _since_save >= _autosave_seconds:
		save_now()


func save_now() -> void:
	_since_save = 0.0
	if world and backend:
		backend.save_world(world)


## Developer helper: pretend the player was away for `seconds`.
func simulate_time_away(seconds: float) -> OfflineReport:
	var report := backend.get_offline_provider().apply_offline_progress(world, seconds)
	pending_report = report
	offline_report_ready.emit(report)
	save_now()
	return report


func reset_progress() -> void:
	backend.delete_save()
	world.event_emitted.disconnect(_on_world_event)
	world = SimulationWorld.create_new(registry)
	world.event_emitted.connect(_on_world_event)
	session_started.emit(world)
	save_now()


func _on_world_event(ev: Dictionary) -> void:
	world_event.emit(ev)


func _notification(what: int) -> void:
	if not running:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_now()
		NOTIFICATION_APPLICATION_PAUSED:
			# Mobile backgrounding. Freeze the live clock so time away is
			# counted exactly once, by the offline provider on resume.
			if _paused_at_unix < 0.0:
				_paused_at_unix = backend.now_unix()
				set_process(false)
				save_now()
		NOTIFICATION_APPLICATION_RESUMED:
			if _paused_at_unix >= 0.0:
				var away := backend.now_unix() - _paused_at_unix
				_paused_at_unix = -1.0
				_accumulator = 0.0
				set_process(true)
				var report := backend.get_offline_provider().apply_offline_progress(world, away)
				if report.simulated_seconds > 0.0:
					pending_report = report
					offline_report_ready.emit(report)
