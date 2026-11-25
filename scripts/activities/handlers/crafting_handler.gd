class_name CraftingHandler
extends ActivityHandler
## Smelting, smithing, crafting, cooking and brewing at a station.
##
## Loop: if the bag holds inputs for one craft, walk to the nearest station
## of the right type and craft until the inputs run out. Then go to storage,
## deposit the products, and RESTOCK inputs for as many crafts as fit in the
## bag. If storage lacks inputs the character waits and retries.
##
## Per-craft chances (from stats): preserve_chance keeps the inputs,
## double_craft_chance makes a second output. Cooking recipes with "burn"
## data can burn, which yields the burn item and no XP; the chance falls
## linearly to 0 at the recipe's stop_level.


func recipe_of(e: ActivityEngine, asg: Assignment) -> Dictionary:
	return e.registry.recipes.get(asg.recipe_id, {})


func validate(e: ActivityEngine, ch: Adventurer, asg: Assignment, act: Dictionary) -> String:
	var r := recipe_of(e, asg)
	if r.is_empty():
		return "Choose a recipe"
	if String(r.station) != String(act.get("station", "")):
		return "%s is not made at this station" % r.get("name", asg.recipe_id)
	if ch.skills.get_level(String(r.skill)) < int(r.get("required_level", 1)):
		return "%s needs %s level %d" % [ch.display_name, e.registry.skills.get(r.skill, {}).get("name", r.skill), int(r.required_level)]
	if not e.world.town.meets(r.get("requires_building", {})):
		var need: Dictionary = r.requires_building
		var b := String(need.keys()[0])
		return "Requires %s level %d" % [e.registry.buildings.get(b, {}).get("name", b), int(need[b])]
	if e.world.nearest_station(ch, String(r.station)).is_empty():
		return "No %s in this region" % r.station
	var units := 0
	for it in r.inputs:
		units += int(r.inputs[it])
	if units > ch.inventory.max_units:
		return "%s cannot carry the materials for one craft" % ch.display_name
	return ""


func primary_item(e: ActivityEngine, asg: Assignment) -> String:
	var outs: Dictionary = recipe_of(e, asg).get("outputs", {})
	return String(outs.keys()[0]) if not outs.is_empty() else ""


func has_inputs(ch: Adventurer, r: Dictionary) -> bool:
	for it in r.get("inputs", {}):
		if ch.inventory.get_quantity(it) < int(r.inputs[it]):
			return false
	return true


func decide(e: ActivityEngine, ch: Adventurer, asg: Assignment, _act: Dictionary) -> void:
	var r := recipe_of(e, asg)
	if r.is_empty():
		e.interrupt(ch, "Recipe no longer exists")
		return
	if ch.skills.get_level(String(r.skill)) < int(r.get("required_level", 1)):
		e.interrupt(ch, "Skill level too low for %s" % r.get("name", ""))
		return
	var outputs_in_bag := ch.inventory.get_quantity(primary_item(e, asg))
	if asg.is_quantity_reached() or (asg.continue_mode == Assignment.ContinueMode.UNTIL_QUANTITY
			and asg.target_quantity > 0 and asg.deposited_primary + outputs_in_bag >= asg.target_quantity):
		if ch.inventory.is_empty():
			e.complete(ch)
		else:
			e.begin_return(ch, "Target reached, returning")
		return
	if has_inputs(ch, r) and _output_units(r) > ch.inventory.free_units() + _input_units(r):
		e.begin_return(ch, "Bag full, returning")
		return
	if has_inputs(ch, r):
		var st: Dictionary = e.world.nearest_station(ch, String(r.station))
		if st.is_empty():
			e.interrupt(ch, "No %s nearby" % r.station)
			return
		ch.target_station_id = String(st.id)
		if WorldGrid.chebyshev(ch.tile, st.tile) == 1:
			_start(e, ch, st)
		else:
			e.travel_to(ch, st.tile, true, "Heading to the %s" % st.name)
		return
	# Out of inputs: go home to deposit products and restock.
	e.begin_return(ch, "Fetching materials")


func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	var st: Dictionary = e.world.stations.get(ch.target_station_id, {})
	if not st.is_empty() and WorldGrid.chebyshev(ch.tile, st.tile) == 1:
		_start(e, ch, st)
	else:
		e.set_state(ch, S.CHECKING_CONDITIONS)


func _start(e: ActivityEngine, ch: Adventurer, st: Dictionary) -> void:
	ch.action_elapsed = 0.0
	ch.travel_purpose = TP.NONE
	ch.facing = (Vector2i(st.tile) - ch.tile).sign()
	e.set_state(ch, S.PERFORMING_ACTIVITY, "Making %s" % recipe_of(e, ch.assignment).get("name", ""))


func perform(e: ActivityEngine, ch: Adventurer, t: float) -> float:
	var r := recipe_of(e, ch.assignment)
	if r.is_empty() or not has_inputs(ch, r):
		e.set_state(ch, S.CHECKING_CONDITIONS)
		return t
	var skill := String(r.skill)
	var duration := float(r.get("seconds", 3.0)) / ch.craft_speed_multiplier(skill, int(r.get("required_level", 1)))
	var need := duration - ch.action_elapsed
	if t < need:
		ch.action_elapsed += t
		return 0.0
	t -= need
	ch.action_elapsed = 0.0
	complete_craft(e, ch, r)
	e.set_state(ch, S.CHECKING_CONDITIONS)
	return t


func burn_chance(ch: Adventurer, r: Dictionary) -> float:
	var burn: Dictionary = r.get("burn", {})
	if burn.is_empty():
		return 0.0
	var req := int(r.get("required_level", 1))
	var stop := int(burn.get("stop_level", req + 1))
	var lvl := ch.skills.get_level(String(r.skill))
	if lvl >= stop:
		return 0.0
	return float(burn.get("base_chance", 0.0)) * (1.0 - float(lvl - req) / float(maxi(stop - req, 1)))


## Resolves one craft. Inputs are removed before outputs are added, and an
## output that cannot fit is never created (the inputs are then kept).
func complete_craft(e: ActivityEngine, ch: Adventurer, r: Dictionary) -> void:
	var world: SimulationWorld = e.world
	var skill := String(r.skill)
	var preserved := world.rng.randf() < ch.stat("preserve_chance", skill)
	var burnt := world.rng.randf() < burn_chance(ch, r)
	var outputs: Dictionary = {}
	if burnt:
		outputs[String(r.burn.item)] = 1
	else:
		for it in r.get("outputs", {}):
			outputs[it] = int(r.outputs[it])
		if world.rng.randf() < ch.stat("double_craft_chance", skill):
			for it in outputs:
				outputs[it] = int(outputs[it]) * 2
	# Check space as if inputs were removed.
	var free_after := ch.inventory.free_units() + (0 if preserved else _input_units(r))
	var out_units := 0
	for it in outputs:
		out_units += int(outputs[it])
	if out_units > free_after:
		# Drop the double-craft bonus first; if even one batch cannot fit, stop.
		if not burnt:
			outputs = r.outputs.duplicate()
			out_units = 0
			for it in outputs:
				out_units += int(outputs[it])
		if out_units > free_after:
			return  # decide() sends the character home to make room
	if not preserved:
		for it in r.inputs:
			ch.inventory.remove(it, int(r.inputs[it]))
			world.record_sink(it, int(r.inputs[it]), "crafting")
	for it in outputs:
		var added := ch.inventory.add(it, int(outputs[it]))
		world.record_source(it, added, "crafting")
		ch.record("crafted", it, added)
	ch.stats.actions = int(ch.stats.actions) + 1
	if world.wants_event("item_crafted"):
		world.emit_event("item_crafted", {"character_id": ch.id, "recipe": r.id, "outputs": outputs, "burnt": burnt, "preserved": preserved})
	if not burnt:
		e.grant_xp(ch, skill, float(r.get("xp", 0.0)))


func _output_units(r: Dictionary) -> int:
	var n := 0
	for it in r.get("outputs", {}):
		n += int(r.outputs[it])
	return n


func _input_units(r: Dictionary) -> int:
	var n := 0
	for it in r.get("inputs", {}):
		n += int(r.inputs[it])
	return n


func single_trip_done(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> bool:
	# One trip = one bag of crafts: done once we have deposited something.
	return asg.trips_completed > 0


func after_deposit(e: ActivityEngine, ch: Adventurer, _asg: Assignment) -> void:
	ch.action_elapsed = 0.0
	e.set_state(ch, S.RESTOCKING, "Taking materials")


func wants_restock(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment) -> bool:
	return true


## How many crafts' worth of inputs the character can take right now.
func restock_batches(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> int:
	var r := recipe_of(e, asg)
	var units := _input_units(r)
	if units <= 0:
		return 0
	var k := int(ch.inventory.free_units() / units)
	for it in r.inputs:
		if e.world.locked_items.has(it):
			return 0
		k = mini(k, int(e.world.storage.get_quantity(it) / int(r.inputs[it])))
	if asg.continue_mode == Assignment.ContinueMode.UNTIL_QUANTITY and asg.target_quantity > 0:
		var per := maxi(int(r.outputs.values()[0]), 1)
		k = mini(k, int(ceil(float(asg.target_quantity - asg.deposited_primary) / per)))
	return maxi(k, 0)


func restock(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> void:
	var r := recipe_of(e, asg)
	var k := restock_batches(e, ch, asg)
	if k <= 0:
		if has_inputs(ch, r):
			e.set_state(ch, S.CHECKING_CONDITIONS)
		elif asg.continue_mode == Assignment.ContinueMode.SINGLE_TRIP and asg.trips_completed > 0:
			e.complete(ch)
		else:
			e.wait(ch, e.materials_retry_seconds, "Waiting for materials")
		return
	for it in r.inputs:
		var q := int(r.inputs[it]) * k
		e.world.storage.remove(it, q)
		ch.inventory.add(it, q)
	e.set_state(ch, S.CHECKING_CONDITIONS, "Took materials for %d" % k)
