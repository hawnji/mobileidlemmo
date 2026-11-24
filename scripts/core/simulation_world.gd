class_name SimulationWorld
extends RefCounted
## The authoritative gameplay simulation for one player's world.
##
## Pure logic: no Nodes, no rendering, no input. It can run inside the game,
## inside tests, inside the offline simulator, and (later) on a server with
## the same rules. Presentation code observes it through `event_emitted` and
## by reading state; it never mutates it except through the public API
## (assign_activity / cancel_assignment).

signal event_emitted(event: Dictionary)

const SAVE_FORMAT := 1
const MAX_EVENT_LOG := 200

var registry: DataRegistry
var region: Dictionary
var region_id := ""
var grid: WorldGrid
var pathfinder: GridPathfinder
var engine: ActivityEngine
var rng := RandomNumberGenerator.new()

var nodes := {}  # node_id -> ResourceNodeState
var node_order: Array[String] = []
var locations := {}  # location_id -> {id, name, kind, rect: Rect2i}
var characters := {}  # character_id -> Adventurer
var character_order: Array[String] = []

var storage: Inventory
var storage_id := "village_storage"
var storage_tile := Vector2i.ZERO
var spawn_tile := Vector2i.ZERO

var sim_time := 0.0
## Total units of each item ever produced by gathering. Used to prove that
## nothing is created out of thin air: storage + all bags must equal this.
var production_ledger := {}
var event_log: Array[Dictionary] = []
var _event_head := 0
## Only depleted nodes need ticking (respawn timers).
var _depleted := {}  # node_id -> ResourceNodeState
var emit_signals := true
## When true (offline fast-forward), high-frequency presentation events
## (state changes, per-item gathers, xp ticks) are skipped entirely.
var quiet := false
const _CHATTY_EVENTS := {"state_changed": true, "item_gathered": true, "xp_gained": true, "node_depleted": true, "node_respawned": true}

var _path_budget := 0
var _path_budget_per_tick := 4


## Builds a brand-new world from data: map, nodes, storage and the starter
## characters standing in the village.
static func create_new(p_registry: DataRegistry, seed_value := 0) -> SimulationWorld:
	var w := SimulationWorld.new()
	w._setup(p_registry, String(p_registry.get_config("world.start_region", "greenvale_start")))
	w.rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	var offsets := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(2, 0)]
	var i := 0
	for cid in p_registry.character_order:
		w.add_character(cid, w.spawn_tile + offsets[i % offsets.size()])
		i += 1
	return w


func _setup(p_registry: DataRegistry, p_region_id: String) -> void:
	registry = p_registry
	region_id = p_region_id
	region = registry.regions.get(region_id, {})
	assert(not region.is_empty(), "Region %s not loaded" % region_id)
	grid = WorldGrid.from_rows(region.rows, registry.terrain_by_symbol, int(registry.get_config("world.chunk_size_tiles", 16)))
	_path_budget_per_tick = int(registry.get_config("simulation.pathfinding_requests_per_tick", 4))
	spawn_tile = JsonData.to_vec2i(region.get("spawn_tile"))
	var st: Dictionary = region.get("storage", {})
	storage_id = String(st.get("id", "village_storage"))
	storage_tile = JsonData.to_vec2i(st.get("tile"))
	storage = Inventory.new(Inventory.UNLIMITED, int(registry.get_config("storage.starting_distinct_item_slots", 48)))
	grid.set_object_blocked(storage_tile, true)
	for loc in region.get("locations", []):
		var r: Array = loc.get("rect", [0, 0, 0, 0])
		locations[loc.id] = {"id": loc.id, "name": loc.get("name", loc.id), "kind": loc.get("kind", ""),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))}
	for n in region.get("resource_nodes", []):
		var ntype: Dictionary = registry.node_types.get(n.type, {})
		if ntype.is_empty():
			push_error("SimulationWorld: unknown node type %s" % n.type)
			continue
		var node := ResourceNodeState.create(String(n.id), ntype, JsonData.to_vec2i(n.tile))
		nodes[node.id] = node
		node_order.append(node.id)
		if bool(ntype.get("blocks_movement", true)):
			grid.set_object_blocked(node.tile, true)
	pathfinder = GridPathfinder.new(grid)
	engine = ActivityEngine.new(self, registry)


func add_character(character_id: String, at_tile: Vector2i) -> Adventurer:
	var def: Dictionary = registry.characters.get(character_id, {})
	if def.is_empty() or characters.has(character_id):
		return null
	var ch := Adventurer.create(def, registry)
	ch.tile = at_tile
	characters[ch.id] = ch
	character_order.append(ch.id)
	return ch


# ==========================================================================
# Simulation
# ==========================================================================

## Advances the world by one fixed step.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	sim_time += dt
	_path_budget = _path_budget_per_tick
	if not _depleted.is_empty():
		for nid in _depleted.keys():
			var node: ResourceNodeState = _depleted[nid]
			if node.tick(dt):
				_depleted.erase(nid)
				emit_event("node_respawned", {"node_id": nid})
	for cid in character_order:
		engine.tick(characters[cid], dt)


## Runs `seconds` of simulation in fixed steps of `step_seconds`.
func advance(seconds: float, step_seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var dt := minf(step_seconds, remaining)
		step(dt)
		remaining -= dt


func take_path_budget() -> bool:
	if _path_budget <= 0:
		return false
	_path_budget -= 1
	return true


# ==========================================================================
# Player commands (the only mutations presentation code may request)
# ==========================================================================

func assign_activity(character_id: String, asg: Assignment) -> String:
	var ch: Adventurer = characters.get(character_id)
	if ch == null:
		return "Unknown character"
	return engine.assign(ch, asg)


func cancel_assignment(character_id: String) -> void:
	var ch: Adventurer = characters.get(character_id)
	if ch:
		engine.cancel(ch)


# ==========================================================================
# Queries
# ==========================================================================

func nodes_of_type(type_id: String, location_id := "") -> Array[ResourceNodeState]:
	var out: Array[ResourceNodeState] = []
	var rect := Rect2i()
	var use_rect := false
	if not location_id.is_empty() and locations.has(location_id):
		rect = locations[location_id].rect
		use_rect = true
	for nid in node_order:
		var n: ResourceNodeState = nodes[nid]
		if n.type_id == type_id and (not use_rect or rect.has_point(n.tile)):
			out.append(n)
	return out


## Chooses the node a character should work next: preferred nodes first,
## then the nearest free, non-depleted node not on cooldown as unreachable.
func find_best_node(ch: Adventurer, type_id: String, location_id: String, preferred: Array[String]) -> ResourceNodeState:
	var best: ResourceNodeState = null
	var best_score := INF
	for n in nodes_of_type(type_id, location_id):
		if not n.is_available_for(ch.id):
			continue
		if float(ch.unreachable_until.get(n.id, -1.0)) > sim_time:
			continue
		var score := WorldGrid.octile(ch.tile, n.tile)
		if preferred.has(n.id):
			score -= 10000.0 - preferred.find(n.id)
		if score < best_score:
			best_score = score
			best = n
	return best


func location_name_at(tile: Vector2i) -> String:
	for lid in locations:
		if locations[lid].rect.has_point(tile):
			return String(locations[lid].name)
	return "Greenvale wilds"


func mark_depleted(node: ResourceNodeState) -> void:
	_depleted[node.id] = node


func record_production(item_id: String, qty: int) -> void:
	production_ledger[item_id] = int(production_ledger.get(item_id, 0)) + qty


## Total units of every item currently held anywhere (storage + bags).
func held_totals() -> Dictionary:
	var totals := storage.items()
	for cid in character_order:
		var bag: Dictionary = characters[cid].inventory.items()
		for item_id in bag:
			totals[item_id] = int(totals.get(item_id, 0)) + int(bag[item_id])
	return totals


## Most recent events, oldest first.
func recent_events() -> Array[Dictionary]:
	if event_log.size() < MAX_EVENT_LOG:
		return event_log.duplicate()
	var out: Array[Dictionary] = []
	out.append_array(event_log.slice(_event_head))
	out.append_array(event_log.slice(0, _event_head))
	return out


func wants_event(type: String) -> bool:
	return not (quiet and _CHATTY_EVENTS.has(type))


func emit_event(type: String, data: Dictionary) -> void:
	if quiet and _CHATTY_EVENTS.has(type):
		return
	var ev := data.duplicate()
	ev["type"] = type
	ev["time"] = sim_time
	# Fixed-size ring buffer (no O(n) pop_front on hot paths).
	if event_log.size() < MAX_EVENT_LOG:
		event_log.append(ev)
	else:
		event_log[_event_head] = ev
		_event_head = (_event_head + 1) % MAX_EVENT_LOG
	if emit_signals:
		event_emitted.emit(ev)


# ==========================================================================
# Persistence
# ==========================================================================

func to_dict() -> Dictionary:
	var chars := {}
	for cid in character_order:
		chars[cid] = characters[cid].to_dict()
	var node_states := {}
	for nid in node_order:
		var n: ResourceNodeState = nodes[nid]
		if n.charges != n.max_charges or not n.reserved_by.is_empty():
			node_states[nid] = n.to_dict()
	return {
		"format": SAVE_FORMAT,
		"region_id": region_id,
		"sim_time": sim_time,
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
		"storage": storage.to_dict(),
		"character_order": Array(character_order),
		"characters": chars,
		"nodes": node_states,
		"production_ledger": production_ledger.duplicate(),
	}


static func from_dict(p_registry: DataRegistry, d: Dictionary) -> SimulationWorld:
	var w := SimulationWorld.new()
	w._setup(p_registry, String(d.get("region_id", p_registry.get_config("world.start_region", "greenvale_start"))))
	w.sim_time = float(d.get("sim_time", 0.0))
	w.rng.seed = String(d.get("rng_seed", "1")).to_int()
	w.rng.state = String(d.get("rng_state", "0")).to_int()
	var st_dict: Variant = d.get("storage", {})
	if st_dict is Dictionary:
		var slots := w.storage.max_distinct
		w.storage.load_dict(st_dict)
		w.storage.max_distinct = maxi(slots, w.storage.max_distinct)
	var chars: Dictionary = d.get("characters", {})
	for cid in d.get("character_order", p_registry.character_order):
		var ch := w.add_character(String(cid), w.spawn_tile)
		if ch and chars.has(cid):
			ch.load_dict(chars[cid])
			if not w.grid.is_walkable(ch.tile):
				ch.tile = w.spawn_tile
	# Characters added to data after this save was made join at spawn.
	for cid in p_registry.character_order:
		if not w.characters.has(cid):
			w.add_character(cid, w.spawn_tile)
	var node_states: Dictionary = d.get("nodes", {})
	for nid in node_states:
		if w.nodes.has(nid):
			w.nodes[nid].load_dict(node_states[nid])
			if w.nodes[nid].is_depleted():
				w.mark_depleted(w.nodes[nid])
	# Reservations must match a character that actually targets the node.
	for nid in w.node_order:
		var n: ResourceNodeState = w.nodes[nid]
		if not n.reserved_by.is_empty():
			var owner: Adventurer = w.characters.get(n.reserved_by)
			if owner == null or owner.target_node_id != nid:
				n.reserved_by = ""
	var ledger: Variant = d.get("production_ledger", {})
	if ledger is Dictionary:
		for k in ledger:
			w.production_ledger[String(k)] = int(ledger[k])
	return w
