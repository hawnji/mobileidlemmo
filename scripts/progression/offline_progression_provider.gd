class_name OfflineProgressionProvider
extends RefCounted
## Interface for offline progression. The prototype uses
## LocalOfflineSimulator; the live game will use a server-backed provider
## (ServerOfflineProvider, Phase 4) that asks the authoritative Offline
## Simulation Service for the result and applies the returned state.
##
## Contract:
##   * elapsed_seconds comes from the trusted time source (server time later).
##   * The provider caps the elapsed time (8h base) and never runs negative time.
##   * The world is mutated in place and a report describing the diff returned.


func get_cap_seconds() -> float:
	return 8.0 * 3600.0


func apply_offline_progress(_world: SimulationWorld, _elapsed_seconds: float) -> OfflineReport:
	push_error("OfflineProgressionProvider.apply_offline_progress is abstract")
	return OfflineReport.new()
