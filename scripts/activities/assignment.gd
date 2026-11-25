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
## For UNTIL_QUANTITY: stop after this many primary items are deposited
## (gathering / crafting) or enemies defeated (combat).
var target_quantity := 0
## Node ids to try first (route priority). Others are used as fallback.
var preferred_node_ids: Array[String] = []
## Combat safety: retreat when health falls below `return_below_health_ratio`
## with no food left; never engage enemies above `avoid_enemies_above_level`
## (0 = no limit).
var safety := {"return_below_health_ratio": 0.25, "avoid_enemies_above_level": 0}
## Crafting: which recipe to make (must be made at the activity's station).
var recipe_id := ""
## Combat: enemy ids to fight first, in order.
var enemy_priority: Array[String] = []
## Combat: eat when health ratio falls below this.
var heal_threshold := 0.5
## Combat: how much food to take from storage on each restock (0 = none).
var food_supply := 12
## Combat: a specific food item, or "" for the best food available.
var food_item := ""
## Repair equipment with gold whenever the character visits storage.
var auto_repair := false
## Route builder: an ordered list of step assignments (as dictionaries).
## When this step completes the engine starts route[route_index + 1], and
## wraps to 0 when route_loop is set. Empty = a plain single assignment.
var route: Array[Dictionary] = []
var route_index := 0
var route_loop := false
var route_name := ""

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


## A plain copy of this assignment's own settings, for storing as a route
## step (progress and route fields are left out).
func step_dict() -> Dictionary:
	var d := to_dict()
	for k in ["route", "route_index", "route_loop", "route_name", "deposited_primary", "trips_completed", "started_at_sim_time"]:
		d.erase(k)
	return d


func describe_route() -> String:
	if route.is_empty():
		return ""
	return "%s step %d / %d%s" % [route_name if not route_name.is_empty() else "Route", route_index + 1, route.size(), " (loops)" if route_loop else ""]


func retreat_threshold() -> float:
	return float(safety.get("return_below_health_ratio", 0.25))


func max_enemy_level() -> int:
	return int(safety.get("avoid_enemies_above_level", 0))


func is_quantity_reached() -> bool:
	return continue_mode == ContinueMode.UNTIL_QUANTITY and target_quantity > 0 and deposited_primary >= target_quantity


func describe_return_rule() -> String:
	if return_fill_ratio >= 0.999:
		return "Return when bag is full"
	return "Return at %d%% bag" % roundi(return_fill_ratio * 100.0)


func describe_continue_rule() -> String:
	match continue_mode:
		ContinueMode.REPEAT: return "Repeat forever"
		ContinueMode.UNTIL_QUANTITY: return "Until %d done (%d so far)" % [target_quantity, deposited_primary]
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
		"recipe_id": recipe_id,
		"enemy_priority": Array(enemy_priority),
		"heal_threshold": heal_threshold,
		"food_supply": food_supply,
		"food_item": food_item,
		"auto_repair": auto_repair,
		"route": route.duplicate(true),
		"route_index": route_index,
		"route_loop": route_loop,
		"route_name": route_name,
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
	a.recipe_id = String(d.get("recipe_id", ""))
	for e in d.get("enemy_priority", []):
		a.enemy_priority.append(String(e))
	a.heal_threshold = clampf(float(d.get("heal_threshold", 0.5)), 0.0, 0.95)
	a.food_supply = clampi(int(d.get("food_supply", 12)), 0, 100)
	a.food_item = String(d.get("food_item", ""))
	a.auto_repair = bool(d.get("auto_repair", false))
	for step in d.get("route", []):
		if step is Dictionary:
			a.route.append(step)
	a.route_index = clampi(int(d.get("route_index", 0)), 0, maxi(a.route.size() - 1, 0))
	a.route_loop = bool(d.get("route_loop", false))
	a.route_name = String(d.get("route_name", ""))
	a.safety.return_below_health_ratio = clampf(float(a.safety.get("return_below_health_ratio", 0.25)), 0.0, 0.9)
	a.deposited_primary = maxi(int(d.get("deposited_primary", 0)), 0)
	a.trips_completed = maxi(int(d.get("trips_completed", 0)), 0)
	a.started_at_sim_time = float(d.get("started_at_sim_time", 0.0))
	return a
