class_name EquipmentService
extends RefCounted
## Equip, unequip, wear, repair and upgrade. Static helpers that operate on a
## SimulationWorld so the rules live in one place.
##
## Item instances: {uid, item_id, durability, upgrade}. A pristine item
## (full durability, +0) is stored as a plain stack in village storage. An
## item that has been used or upgraded keeps its identity in the world
## "armory" list when unequipped. Equipped and armory items count as held for
## the item ledger, so equipping never creates or destroys items.

const ARMOR_SLOTS := ["head", "body", "legs", "gloves", "boots"]


static func slot_for(item: Dictionary, ch: Adventurer) -> String:
	var s := String(item.get("equip_slot", ""))
	if s == "accessory":
		if not ch.equipment.has("accessory_1"):
			return "accessory_1"
		if not ch.equipment.has("accessory_2"):
			return "accessory_2"
		return "accessory_1"
	return s


static func requirement_error(world: SimulationWorld, ch: Adventurer, item: Dictionary) -> String:
	for skill in item.get("requirements", {}):
		var need := int(item.requirements[skill])
		if ch.skills.get_level(skill) < need:
			return "%s needs %s level %d" % [ch.display_name, world.registry.skills.get(skill, {}).get("name", skill), need]
	return ""


static func is_pristine(world: SimulationWorld, inst: Dictionary) -> bool:
	var item: Dictionary = world.registry.items.get(inst.get("item_id", ""), {})
	return int(inst.get("upgrade", 0)) == 0 and int(inst.get("durability", 0)) >= int(item.get("max_durability", 1))


## Equips from a storage stack (item_id) or from the armory (uid > 0).
static func equip(world: SimulationWorld, character_id: String, item_id: String, armory_uid := 0) -> String:
	var ch: Adventurer = world.characters.get(character_id)
	if ch == null:
		return "Unknown character"
	var inst := {}
	var armory_index := -1
	if armory_uid > 0:
		for i in world.armory.size():
			if int(world.armory[i].uid) == armory_uid:
				armory_index = i
				inst = world.armory[i]
		if armory_index < 0:
			return "That item is no longer in the armory"
		item_id = String(inst.item_id)
	var item: Dictionary = world.registry.items.get(item_id, {})
	if item.is_empty() or String(item.get("equip_slot", "")).is_empty():
		return "That item cannot be equipped"
	var err := requirement_error(world, ch, item)
	if not err.is_empty():
		return err
	if armory_index < 0:
		if world.storage.get_quantity(item_id) <= 0:
			return "No %s in storage" % item.get("name", item_id)
		world.storage.remove(item_id, 1)
		inst = {"uid": world.next_item_uid(), "item_id": item_id,
			"durability": int(item.get("max_durability", 1)), "upgrade": 0}
	else:
		world.armory.remove_at(armory_index)
	var slot := slot_for(item, ch)
	if ch.equipment.has(slot):
		_return_instance(world, ch.equipment[slot])
	ch.equipment[slot] = inst
	_changed(world, ch)
	world.emit_event("equipment_changed", {"character_id": ch.id, "slot": slot, "item_id": item_id})
	return ""


static func unequip(world: SimulationWorld, character_id: String, slot: String) -> String:
	var ch: Adventurer = world.characters.get(character_id)
	if ch == null or not ch.equipment.has(slot):
		return "Nothing equipped there"
	var inst: Dictionary = ch.equipment[slot]
	ch.equipment.erase(slot)
	_return_instance(world, inst)
	_changed(world, ch)
	world.emit_event("equipment_changed", {"character_id": ch.id, "slot": slot, "item_id": ""})
	return ""


static func _return_instance(world: SimulationWorld, inst: Dictionary) -> void:
	if is_pristine(world, inst) and world.storage.can_add(String(inst.item_id), 1) == 1:
		world.storage.add(String(inst.item_id), 1)
	else:
		world.armory.append(inst)


static func _changed(world: SimulationWorld, ch: Adventurer) -> void:
	ch.invalidate_stats()
	ch.refresh_capacity()
	ch.health = minf(ch.health, ch.max_health())


## Reduces durability of the item in `slot`. Breaking removes its stats.
static func wear(world: SimulationWorld, ch: Adventurer, slot: String, amount: int) -> void:
	if amount <= 0 or not ch.equipment.has(slot):
		return
	var inst: Dictionary = ch.equipment[slot]
	var before := int(inst.durability)
	if before <= 0:
		return
	inst.durability = maxi(before - amount, 0)
	if inst.durability == 0:
		ch.invalidate_stats()
		ch.refresh_capacity()
		world.emit_event("equipment_broken", {"character_id": ch.id, "slot": slot, "item_id": inst.item_id})


static func wear_random_armor(world: SimulationWorld, ch: Adventurer, amount: int) -> void:
	var worn: Array[String] = []
	for s in ARMOR_SLOTS:
		if ch.equipment.has(s) and int(ch.equipment[s].durability) > 0:
			worn.append(s)
	if worn.is_empty():
		return
	wear(world, ch, worn[world.rng.randi_range(0, worn.size() - 1)], amount)


static func repair_cost(world: SimulationWorld, inst: Dictionary) -> int:
	var item: Dictionary = world.registry.items.get(inst.get("item_id", ""), {})
	var missing := int(item.get("max_durability", 0)) - int(inst.get("durability", 0))
	if missing <= 0:
		return 0
	var per := float(world.registry.get_config("equipment.repair_gold_per_point_per_tier", 0.25)) * maxi(int(item.get("tier", 1)), 1)
	var discount := clampf(world.account_stats().get_stat("repair_discount"), 0.0, 0.9)
	return maxi(int(ceil(missing * per * (1.0 - discount))), 1)


static func repair(world: SimulationWorld, character_id: String, slot: String) -> String:
	var ch: Adventurer = world.characters.get(character_id)
	if ch == null or not ch.equipment.has(slot):
		return "Nothing equipped there"
	var inst: Dictionary = ch.equipment[slot]
	var cost := repair_cost(world, inst)
	if cost == 0:
		return "Already fully repaired"
	if not world.wallet.spend("gold", cost, "repair:%s" % inst.item_id):
		return "Not enough gold (%d needed)" % cost
	var was_broken := int(inst.durability) <= 0
	inst.durability = int(world.registry.items[inst.item_id].get("max_durability", 1))
	if was_broken:
		_changed(world, ch)
	world.emit_event("equipment_repaired", {"character_id": ch.id, "slot": slot, "gold": cost})
	return ""


static func repair_all(world: SimulationWorld, ch: Adventurer) -> int:
	var spent := 0
	for slot in ch.equipment.keys():
		var cost := repair_cost(world, ch.equipment[slot])
		if cost > 0 and world.wallet.can_afford({"gold": cost}):
			if repair(world, ch.id, slot).is_empty():
				spent += cost
	return spent


static func upgrade_cost(world: SimulationWorld, inst: Dictionary) -> Dictionary:
	var item: Dictionary = world.registry.items.get(inst.get("item_id", ""), {})
	var next := int(inst.get("upgrade", 0)) + 1
	var bar := "iron_bar" if int(item.get("tier", 1)) >= 2 else "bronze_bar"
	return {"gold": int(world.registry.get_config("equipment.upgrade_cost.gold_per_level", 100)) * next,
		"items": {bar: int(world.registry.get_config("equipment.upgrade_cost.bars_per_level", 2)) * next}}


static func upgrade(world: SimulationWorld, character_id: String, slot: String) -> String:
	var ch: Adventurer = world.characters.get(character_id)
	if ch == null or not ch.equipment.has(slot):
		return "Nothing equipped there"
	var inst: Dictionary = ch.equipment[slot]
	var max_up := int(world.account_stats().get_stat("max_upgrade_level"))
	if int(inst.upgrade) >= mini(max_up, 5):
		return "Upgrade the Blacksmith to go beyond +%d" % max_up if max_up < 5 else "Already at +5"
	var cost := upgrade_cost(world, inst)
	for it in cost.items:
		if world.storage.get_quantity(it) < int(cost.items[it]):
			return "Needs %d %s in storage" % [int(cost.items[it]), world.registry.get_item_name(it)]
	if not world.wallet.spend("gold", int(cost.gold), "upgrade:%s" % inst.item_id):
		return "Not enough gold (%d needed)" % int(cost.gold)
	for it in cost.items:
		world.storage.remove(it, int(cost.items[it]))
		world.record_sink(it, int(cost.items[it]), "upgrade")
	inst.upgrade = int(inst.upgrade) + 1
	_changed(world, ch)
	world.emit_event("equipment_upgraded", {"character_id": ch.id, "slot": slot, "level": inst.upgrade})
	return ""


## Equips the best tool for `skill` from storage if the slot is empty.
static func best_tool_in_storage(world: SimulationWorld, ch: Adventurer, skill: String) -> String:
	var best := ""
	var best_tier := -1
	for item_id in world.storage.items():
		var item: Dictionary = world.registry.items.get(item_id, {})
		if String(item.get("tool_skill", "")) == skill and requirement_error(world, ch, item).is_empty():
			if int(item.get("tier", 0)) > best_tier:
				best_tier = int(item.get("tier", 0))
				best = item_id
	return best
