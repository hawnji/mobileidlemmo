class_name LocalOfflineSimulator
extends OfflineProgressionProvider
## Prototype offline progression: re-runs the exact same deterministic
## simulation the game uses while playing, with a coarser step. Because the
## ActivityEngine carries leftover time between states, coarse steps give the
## same results as fine ones (verified by tests/simulation/test_offline_progress.gd).

var step_seconds := 1.0
var cap_seconds := 8.0 * 3600.0
var minimum_elapsed := 60.0


func _init(registry: DataRegistry = null, cap_hours := -1.0) -> void:
	if registry:
		step_seconds = float(registry.get_config("offline.simulation_step_seconds", 1.0))
		cap_seconds = float(registry.get_config("offline.base_cap_hours", 8)) * 3600.0
		minimum_elapsed = float(registry.get_config("offline.minimum_elapsed_seconds", 60))
	if cap_hours > 0.0:
		cap_seconds = cap_hours * 3600.0


func get_cap_seconds() -> float:
	return cap_seconds


func apply_offline_progress(world: SimulationWorld, elapsed_seconds: float) -> OfflineReport:
	var report := OfflineReport.new()
	report.elapsed_seconds = maxf(elapsed_seconds, 0.0)  # clock rollback => no progress
	# Relics (Celestial Hourglass) and ascension perks (Long Rest) extend the cap.
	var cap := cap_seconds + world.account_stats().get_stat("offline_cap_hours") * 3600.0
	report.cap_seconds = cap
	var to_simulate := minf(report.elapsed_seconds, cap)
	report.capped = report.elapsed_seconds > cap
	if to_simulate < minimum_elapsed:
		return report
	var events: Array[Dictionary] = []
	var collector := func(ev: Dictionary) -> void:
		var t := String(ev.get("type", ""))
		if t == "rare_drop" or t == "interrupted":
			events.append(ev)
	world.event_emitted.connect(collector)
	var before := OfflineReport.capture(world)
	var was_quiet := world.quiet
	world.quiet = true
	world.advance(to_simulate, step_seconds)
	world.quiet = was_quiet
	var after := OfflineReport.capture(world)
	world.event_emitted.disconnect(collector)
	var built := OfflineReport.build(world, before, after, events)
	built.elapsed_seconds = report.elapsed_seconds
	built.simulated_seconds = to_simulate
	built.capped = report.capped
	built.cap_seconds = cap
	return built
