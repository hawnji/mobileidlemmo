class_name TimeSource
extends RefCounted
## Wall-clock provider. The prototype trusts the device clock; the server
## build replaces this with the authoritative server timestamp (see
## docs/TECHNICAL_ARCHITECTURE.md, "Offline progression").


func now_unix() -> float:
	return Time.get_unix_time_from_system()


## Deterministic clock for tests and simulations.
class Fixed:
	extends TimeSource
	var value := 0.0

	func _init(start := 0.0) -> void:
		value = start

	func now_unix() -> float:
		return value

	func advance(seconds: float) -> void:
		value += seconds
