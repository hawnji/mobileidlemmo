class_name Assignment
extends RefCounted
## A player's instructions for one character. Pure data: the ActivityEngine
## interprets it. Serialised into saves and (later) sent to the server, which
## re-validates every field.

enum ContinueMode { REPEAT, UNTIL_QUANTITY, SINGLE_TRIP }

var character_id := ""
var activity_id := ""
## Location id from the region data (e.g. "copper_mine"). Empty = anywhere.
var destination_id := ""
## Storage the character deposits into.
var deposit_target_id := "village_storage"
## Return to storage when bag fill ratio reaches this (0.1 .. 1.0).
var return_fill_ratio := 1.0
var continue_mode := ContinueMode.REPEAT
## For UNTIL_QUANTITY: stop after this many primary items are deposited.
var target_quantity := 0
## Node ids to try first (route priority). Others are used as fallback.
var preferred_node_ids: Array[String] = []
## Phase 2 hooks (combat/consumables). Stored and round-tripped, not yet used.
var safety := {"return_below_health_ratio": 0.0, "avoid_enemies_above_level": 0}

# Progress (part of persistent state)
var deposited_primary := 0
var trips_completed := 0
var started_at_sim_time := 0.0


static func create(p_character_id: String, p_activity: Dictionary) -> Assignment:
	var a := Assignment.new()
	a.character_id = p_character_id
	a.activity_id = String(p_activity.get("id", ""))
	a.destination_id = String(p_activity.get("default_destination", ""))
	return a


func is_quantity_reached() -> bool:
	return continue_mode == ContinueMode.UNTIL_QUANTITY and target_quantity > 0 and deposited_primary >= target_quantity


func describe_return_rule() -> String:
	if return_fill_ratio >= 0.999:
		return "Return when bag is full"
	return "Return at %d%% bag" % roundi(return_fill_ratio * 100.0)


func describe_continue_rule() -> String:
	match continue_mode:
		ContinueMode.REPEAT: return "Repeat forever"
		ContinueMode.UNTIL_QUANTITY: return "Until %d deposited (%d so far)" % [target_quantity, deposited_primary]
		ContinueMode.SINGLE_TRIP: return "One trip"
	return ""


func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"activity_id": activity_id,
		"destination_id": destination_id,
		"deposit_target_id": deposit_target_id,
		"return_fill_ratio": return_fill_ratio,
		"continue_mode": ContinueMode.keys()[continue_mode],
		"target_quantity": target_quantity,
		"preferred_node_ids": Array(preferred_node_ids),
		"safety": safety.duplicate(),
		"deposited_primary": deposited_primary,
		"trips_completed": trips_completed,
		"started_at_sim_time": started_at_sim_time,
	}


static func from_dict(d: Dictionary) -> Assignment:
	var a := Assignment.new()
	a.character_id = String(d.get("character_id", ""))
	a.activity_id = String(d.get("activity_id", ""))
	a.destination_id = String(d.get("destination_id", ""))
	a.deposit_target_id = String(d.get("deposit_target_id", "village_storage"))
	a.return_fill_ratio = clampf(float(d.get("return_fill_ratio", 1.0)), 0.1, 1.0)
	var mode_idx := ContinueMode.keys().find(String(d.get("continue_mode", "REPEAT")))
	a.continue_mode = mode_idx if mode_idx >= 0 else ContinueMode.REPEAT
	a.target_quantity = maxi(int(d.get("target_quantity", 0)), 0)
	for n in d.get("preferred_node_ids", []):
		a.preferred_node_ids.append(String(n))
	var saf: Variant = d.get("safety", {})
	if saf is Dictionary:
		a.safety.merge(saf, true)
	a.deposited_primary = maxi(int(d.get("deposited_primary", 0)), 0)
	a.trips_completed = maxi(int(d.get("trips_completed", 0)), 0)
	a.started_at_sim_time = float(d.get("started_at_sim_time", 0.0))
	return a
