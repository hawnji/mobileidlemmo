class_name EncounterDirector
extends RefCounted
## Dynamic encounters (data/world/encounters.json): at random intervals a
## short-lived event appears in a random location of an unlocked region.
##
##   spawn_enemy     a temporary enemy (Treasure Goblin) in a hunting ground
##   bonus_location  double yields at a resource area (Bountiful Harvest)
##   merchant        a travelling merchant with special stock
##   surge           faster respawns and more gold at a hunting ground
##   hero            a wandering adventurer who joins the first character
##                   to come within range
##
## The director runs on simulation time with the world RNG, so encounters
## also happen (and expire) during offline catch-up.

var active: Array[Dictionary] = []  # {uid, id, kind, location, region, ends_at, ...}
var next_roll_at := 0.0
var _next_uid := 1
## Own random stream, so encounters do not shift when other systems draw
## numbers (and vice versa). Seeded from the world seed.
var rng := RandomNumberGenerator.new()


func schedule_first(world) -> void:
	rng.seed = world.rng.seed ^ 0xE7C0
	next_roll_at = world.sim_time + float(world.registry.encounter_config.get("first_delay_seconds", 300.0))


func tick(world, _dt: float) -> void:
	if not active.is_empty():
		for enc in active.duplicate():
			if world.sim_time >= float(enc.ends_at):
				_expire(world, enc)
	if world.sim_time >= next_roll_at:
		var iv: Array = world.registry.encounter_config.get("interval_seconds", [600.0, 1200.0])
		next_roll_at = world.sim_time + rng.randf_range(float(iv[0]), float(iv[1]))
		if active.size() < int(world.registry.encounter_config.get("max_active", 2)):
			spawn_random(world)


## Picks an encounter type by weight and a location for it. Returns the
## encounter or {} if nothing fitted.
func spawn_random(world, forced_id := "") -> Dictionary:
	var defs: Array = world.registry.encounter_config.get("encounters", [])
	var def := {}
	if not forced_id.is_empty():
		for d in defs:
			if d.id == forced_id:
				def = d
	else:
		var total := 0.0
		for d in defs:
			total += float(d.get("weight", 1))
		var r: float = rng.randf() * total
		for d in defs:
			r -= float(d.get("weight", 1))
			if r <= 0.0:
				def = d
				break
	if def.is_empty():
		return {}
	var candidates: Array[String] = []
	for lid in world.locations:
		var loc: Dictionary = world.locations[lid]
		if String(loc.kind) == String(def.get("location_kind", "")) and world.is_region_unlocked(String(loc.get("region", ""))):
			var busy := false
			for a in active:
				if a.location == lid:
					busy = true
			if not busy:
				candidates.append(lid)
	if candidates.is_empty():
		return {}
	candidates.sort()
	var lid: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	var loc: Dictionary = world.locations[lid]
	var enc := {"uid": _next_uid, "id": String(def.id), "kind": String(def.kind), "name": String(def.get("name", def.id)), "location": lid,
		"region": String(loc.get("region", "")), "ends_at": world.sim_time + float(def.get("duration", 600.0))}
	_next_uid += 1
	match String(def.kind):
		"spawn_enemy":
			var tile := _free_tile_in(world, loc.rect)
			if tile.x < 0:
				return {}
			var sid := "enc_%d" % enc.uid
			if world.add_temp_enemy(sid, String(def.enemy), tile) == null:
				return {}
			enc["spawn_id"] = sid
		"bonus_location":
			enc["yield_mult"] = float(def.get("yield_mult", 2.0))
		"surge":
			enc["respawn_mult"] = float(def.get("respawn_mult", 0.5))
			enc["gold_mult"] = float(def.get("gold_mult", 1.5))
		"merchant":
			var stock := []
			for s in def.get("stock", []):
				stock.append({"item": String(s.item), "price": s.price.duplicate(), "qty": int(s.get("qty", 1))})
			enc["stock"] = stock
		"hero":
			var pool: Array[String] = []
			for cid in world.registry.characters_by_acquisition("gacha"):
				if def.get("rarities", []).has(world.registry.characters[cid].get("rarity", "")):
					pool.append(cid)
			if pool.is_empty():
				return {}
			enc["character_id"] = pool[rng.randi_range(0, pool.size() - 1)]
			enc["tile"] = _free_tile_in(world, loc.rect)
			enc["radius"] = int(def.get("radius", 4))
			if enc.tile.x < 0:
				return {}
	active.append(enc)
	world.emit_event("encounter_started", {"uid": enc.uid, "id": enc.id, "name": enc.name, "kind": enc.kind, "location": lid,
		"region": enc.region, "message": String(def.get("message", "%s")) % String(loc.name)})
	return enc


func _free_tile_in(world, rect: Rect2i) -> Vector2i:
	for i in 60:
		var t := Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rng.randi_range(rect.position.y, rect.end.y - 1))
		if world.grid.is_walkable(t) and world.pathfinder.adjacent_walkable(t).size() >= 2:
			var occupied := false
			for cid in world.character_order:
				if world.characters[cid].tile == t:
					occupied = true
			if not occupied:
				return t
	return Vector2i(-1, -1)


func _expire(world, enc: Dictionary) -> void:
	active.erase(enc)
	if enc.kind == "spawn_enemy" and world.enemies.has(String(enc.get("spawn_id", ""))):
		world.remove_temp_enemy(String(enc.spawn_id))
	world.emit_event("encounter_ended", {"uid": enc.uid, "id": enc.id, "name": enc.name})


func _in_location(world, enc: Dictionary, tile: Vector2i) -> bool:
	return world.locations.has(enc.location) and world.locations[enc.location].rect.has_point(tile)


func yield_multiplier_at(tile: Vector2i) -> float:
	return _mult_at(tile, "bonus_location", "yield_mult")


func gold_multiplier_at(tile: Vector2i) -> float:
	return _mult_at(tile, "surge", "gold_mult")


## Respawn timers tick this many times faster during a surge.
func respawn_speed_at(tile: Vector2i) -> float:
	var m := _mult_at(tile, "surge", "respawn_mult")
	return 1.0 / maxf(m, 0.05)


var _rects := {}  # location -> Rect2i (bind_locations)


func bind_locations(locations: Dictionary) -> void:
	_rects.clear()
	for lid in locations:
		_rects[lid] = locations[lid].rect


func _mult_at(tile: Vector2i, kind: String, key: String) -> float:
	if active.is_empty():
		return 1.0
	for enc in active:
		if enc.kind == kind and _rects.has(enc.location) and _rects[enc.location].has_point(tile):
			return float(enc.get(key, 1.0))
	return 1.0


func on_character_moved(world, ch: Adventurer) -> void:
	if active.is_empty():
		return
	for enc in active.duplicate():
		if enc.kind != "hero":
			continue
		if WorldGrid.chebyshev(ch.tile, enc.tile) <= int(enc.radius):
			active.erase(enc)
			world.grant_character(String(enc.character_id), "encounter")
			world.emit_event("encounter_ended", {"uid": enc.uid, "id": enc.id, "name": enc.name, "met_by": ch.id})


func merchant(uid: int) -> Dictionary:
	for enc in active:
		if enc.kind == "merchant" and int(enc.uid) == uid:
			return enc
	return {}


func buy(world, uid: int, item_id: String, qty: int) -> String:
	var enc := merchant(uid)
	if enc.is_empty():
		return "The merchant has moved on"
	for s in enc.stock:
		if s.item != item_id:
			continue
		if int(s.qty) < qty or qty <= 0:
			return "Only %d left" % int(s.qty)
		if world.storage.can_add(item_id, qty) < qty:
			return "Storage is full"
		var cost := {}
		for c in s.price:
			cost[c] = int(s.price[c]) * qty
		if not world.wallet.spend_many(cost, "merchant"):
			return "Cannot afford"
		s.qty = int(s.qty) - qty
		world.storage.add(item_id, qty)
		world.record_source(item_id, qty, "merchant")
		world.emit_event("item_bought", {"vendor": "travelling_merchant", "item_id": item_id, "qty": qty})
		return ""
	return "Not sold here"


func to_dict(world) -> Dictionary:
	var list := []
	for enc in active:
		var e: Dictionary = enc.duplicate(true)
		if e.has("tile"):
			e.tile = [e.tile.x, e.tile.y]
		if e.kind == "spawn_enemy" and world.enemies.has(String(e.get("spawn_id", ""))):
			var t: Vector2i = world.enemies[e.spawn_id].tile
			e["spawn_tile"] = [t.x, t.y]
		list.append(e)
	return {"active": list, "next_roll_at": next_roll_at, "next_uid": _next_uid, "rng_state": str(rng.state)}


static func _def(world, encounter_id: String) -> Dictionary:
	for d in world.registry.encounter_config.get("encounters", []):
		if d.id == encounter_id:
			return d
	return {}


func load_dict(world, d: Dictionary) -> void:
	active.clear()
	next_roll_at = float(d.get("next_roll_at", world.sim_time + 300.0))
	_next_uid = maxi(int(d.get("next_uid", 1)), 1)
	rng.seed = world.rng.seed ^ 0xE7C0
	rng.state = String(d.get("rng_state", str(rng.state))).to_int()
	for enc in d.get("active", []):
		if not (enc is Dictionary) or not world.locations.has(enc.get("location", "")):
			continue
		var e: Dictionary = enc.duplicate(true)
		e.uid = int(e.get("uid", 0))
		e.ends_at = float(e.get("ends_at", 0.0))
		if e.has("tile"):
			e.tile = JsonData.to_vec2i(e.tile)
		if e.kind == "spawn_enemy":
			var sid := "enc_%d" % e.uid
			var tile := JsonData.to_vec2i(enc.get("spawn_tile"), Vector2i(-1, -1))
			if tile.x < 0 or world.add_temp_enemy(sid, String(_def(world, String(e.id)).get("enemy", "")), tile) == null:
				continue
			e.spawn_id = sid
		active.append(e)
