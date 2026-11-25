class_name SimulationWorld
extends RefCounted
## The authoritative gameplay simulation for one player's world.
##
## Pure logic: no Nodes, no rendering, no input. It can run inside the game,
## inside tests, inside the offline simulator, and (later) on a server with
## the same rules. Presentation code observes it through `event_emitted` and
## by reading state, and changes it only through the player command methods
## in the "Player commands" section.

signal event_emitted(event: Dictionary)

const SAVE_FORMAT := 3
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
var enemies := {}  # spawn_id -> EnemyState
var enemy_order: Array[String] = []
var stations := {}  # station_id -> {id, type, name, tile}
var plots := {}  # building_id -> {building, rect: Rect2i, work_tile}
var locations := {}  # location_id -> {id, name, kind, rect: Rect2i}
var characters := {}  # character_id -> Adventurer (owned characters only)
var character_order: Array[String] = []

var storage: Inventory
var storage_id := "village_storage"
var storage_tile := Vector2i.ZERO
var spawn_tile := Vector2i.ZERO
## Storage item flags: item_id -> true. Locked items cannot be sold or used
## by automation restocking; favourites are sorted first in the UI.
var locked_items := {}
var favorite_items := {}

var wallet: Wallet
var town: TownState
var recruitment: RecruitmentState
var fragments := {}  # character_id -> int
## Used / upgraded equipment that is not equipped.
var armory: Array[Dictionary] = []
var _next_uid := 1
## Saved route templates: name -> {loop, steps: [assignment dicts]}
var route_templates := {}
var token_progress := 0.0

var sim_time := 0.0
## Item conservation ledger. Every unit that enters the world (gathering,
## loot, crafting output) is a source; every unit that leaves (crafting
## input, food eaten, building cost, sold) is a sink. At all times
## held_totals() == sources - sinks for every item. Tests enforce this.
var item_sources := {}
var item_sinks := {}
var event_log: Array[Dictionary] = []
var _event_head := 0
var _depleted := {}  # node_id -> ResourceNodeState (only these need ticking)
var _respawning := {}  # spawn_id -> EnemyState
var emit_signals := true
## When true (offline fast-forward), high-frequency presentation events are
## skipped entirely.
var quiet := false
const _CHATTY_EVENTS := {"state_changed": true, "item_gathered": true, "xp_gained": true,
	"node_depleted": true, "node_respawned": true, "combat_hit": true, "enemy_respawned": true,
	"item_crafted": true, "construction_progress": true, "food_eaten": true,
	"fog_revealed": true, "dungeon_hit": true}

var _path_budget := 0
var _path_budget_per_tick := 4
var _day_length := 1440.0
var account: AccountEffects
var _applied_account_version := -1

# --- Phase 3: world expansion -----------------------------------------------
var exploration: ExplorationState
var nav: RegionNavigator
var unlocked_regions := {}  # region_id -> true
var secrets := {}  # secret_id -> {tiles: Array[Vector2i], region, reveals_as}
var revealed_secrets := {}  # secret_id -> true
var outposts := {}  # building_id -> {building, region, rect, work_tile, depot_tile}
var dungeon_entrances := {}  # dungeon_id -> Vector2i
var temp_enemies := {}  # spawn_id -> true (encounter spawns, removed when killed/expired)
## World counters used by quests and achievements: "gather:<item>",
## "kill:<enemy>", "kill_tag:<tag>", "craft:<item>", "dungeon:<id>", "expedition".
var counters := {}
## Reward items that did not fit in storage wait here (claim from Storage).
var mailbox := {}
var quests: QuestState
var expeditions: ExpeditionState
var dungeon_runs: Array[DungeonRun] = []
var dungeon_records := {}  # dungeon_id -> {clears, best_time}
var encounters: EncounterDirector
var notifications: NotificationCenter
var _last_reveal := {}  # character_id -> Vector2i


## Builds a brand-new world from data: map, nodes, enemies, storage, wallet
## and the starter characters standing in the village.
static func create_new(p_registry: DataRegistry, seed_value := 0) -> SimulationWorld:
	var w := SimulationWorld.new()
	w._setup(p_registry)
	w.rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	w.recruitment.rng.seed = w.rng.seed ^ 0x5EED
	w.wallet.setup_starting(p_registry.currency_list)
	for spawn_id in w.enemy_order:
		w.enemies[spawn_id].spawn(w.rng, p_registry.enemy_variants)
	for cid in p_registry.characters_by_acquisition("starter"):
		w.add_character(cid)
	w.exploration.reveal(w.spawn_tile, 8)
	w.encounters.schedule_first(w)
	return w


func _setup(p_registry: DataRegistry) -> void:
	registry = p_registry
	region = registry.world_map
	region_id = String(region.get("id", "world"))
	assert(not region.is_empty(), "World map not loaded")
	grid = WorldGrid.from_rows(region.rows, registry.terrain_by_symbol, int(registry.get_config("world.chunk_size_tiles", 16)))
	_path_budget_per_tick = int(registry.get_config("simulation.pathfinding_requests_per_tick", 4))
	_day_length = float(registry.get_config("world.day_length_seconds", 1440.0))
	spawn_tile = JsonData.to_vec2i(region.get("spawn_tile"))
	var st: Dictionary = region.get("storage", {})
	storage_id = String(st.get("id", "village_storage"))
	storage_tile = JsonData.to_vec2i(st.get("tile"))
	storage = Inventory.new(Inventory.UNLIMITED, int(registry.get_config("storage.starting_distinct_item_slots", 48)))
	grid.set_object_blocked(storage_tile, true)
	wallet = Wallet.new(registry.currency_list)
	town = TownState.new()
	town.setup(registry)
	account = AccountEffects.new(registry, town)
	recruitment = RecruitmentState.new()
	for loc in region.get("locations", []):
		var r: Array = loc.get("rect", [0, 0, 0, 0])
		locations[loc.id] = {"id": loc.id, "name": loc.get("name", loc.id), "kind": loc.get("kind", ""),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))}
	for loc_id in locations:
		locations[loc_id]["region"] = String(_loc_region(loc_id))
	for n in region.get("resource_nodes", []):
		var ntype: Dictionary = registry.node_types.get(n.type, {})
		if ntype.is_empty():
			push_error("SimulationWorld: unknown node type %s" % n.type)
			continue
		var node := ResourceNodeState.create(String(n.id), ntype, JsonData.to_vec2i(n.tile))
		node.hidden = bool(n.get("hidden", false))
		nodes[node.id] = node
		node_order.append(node.id)
		if bool(ntype.get("blocks_movement", true)):
			grid.set_object_blocked(node.tile, true)
	for s in region.get("stations", []):
		var t := JsonData.to_vec2i(s.tile)
		stations[String(s.id)] = {"id": String(s.id), "type": String(s.type), "name": String(s.get("name", s.type)), "tile": t,
			"outpost": String(s.get("outpost", ""))}
		grid.set_object_blocked(t, true)
	for e in region.get("enemy_spawns", []):
		var edef: Dictionary = registry.enemies.get(e.enemy, {})
		if edef.is_empty():
			continue
		var es := EnemyState.create(String(e.id), edef, JsonData.to_vec2i(e.tile))
		enemies[es.id] = es
		enemy_order.append(es.id)
		grid.set_object_blocked(es.tile, true)
	for p in region.get("building_plots", []):
		var r: Array = p.get("rect", [0, 0, 0, 0])
		plots[String(p.building)] = {"building": String(p.building), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"work_tile": JsonData.to_vec2i(p.work_tile)}
	for op in region.get("outposts", []):
		var r: Array = op.get("rect", [0, 0, 0, 0])
		var depot := JsonData.to_vec2i(op.depot_tile)
		outposts[String(op.building)] = {"building": String(op.building), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"work_tile": JsonData.to_vec2i(op.work_tile), "depot_tile": depot,
			"region": String(registry.buildings.get(op.building, {}).get("region", ""))}
		grid.set_object_blocked(depot, true)
	for de in region.get("dungeon_entrances", []):
		dungeon_entrances[String(de.id)] = JsonData.to_vec2i(de.tile)
		grid.set_object_blocked(JsonData.to_vec2i(de.tile), true)
	exploration = ExplorationState.new()
	exploration.setup(grid, region.get("regions", []), region.get("discoveries", []))
	for r in region.get("regions", []):
		if bool(r.get("unlocked_by_default", false)):
			unlocked_regions[String(r.id)] = true
	for sec in region.get("secrets", []):
		var tiles: Array[Vector2i] = []
		for t in sec.get("tiles", []):
			tiles.append(JsonData.to_vec2i(t))
			grid.set_object_blocked(JsonData.to_vec2i(t), true)
		secrets[String(sec.id)] = {"id": String(sec.id), "tiles": tiles, "region": String(sec.get("region", "")),
			"reveals_as": String(sec.get("reveals_as", "c"))}
	nav = RegionNavigator.new(self, region.get("gates", []))
	_refresh_gates()
	pathfinder = GridPathfinder.new(grid)
	engine = ActivityEngine.new(self, registry)
	quests = QuestState.new()
	quests.setup(registry)
	expeditions = ExpeditionState.new()
	encounters = EncounterDirector.new()
	encounters.bind_locations(locations)
	notifications = NotificationCenter.new()
	notifications.setup(registry)
	_apply_account_effects()


func _loc_region(loc_id: String) -> String:
	var r: Rect2i = locations[loc_id].rect
	var c := r.position + r.size / 2
	for rid in registry.map_region_order:
		var rc: Array = registry.map_regions[rid].rect
		if Rect2i(int(rc[0]), int(rc[1]), int(rc[2]), int(rc[3])).has_point(c):
			return rid
	return ""


func add_character(character_id: String, at_tile := Vector2i(-1, -1)) -> Adventurer:
	var def: Dictionary = registry.characters.get(character_id, {})
	if def.is_empty() or characters.has(character_id):
		return null
	var ch := Adventurer.create(def, registry)
	ch.account = account
	ch.tile = at_tile if at_tile.x >= 0 else free_tile_near(spawn_tile, character_order.size())
	sync_traits(ch)
	ch.refresh_capacity()
	ch.health = ch.max_health()
	characters[ch.id] = ch
	character_order.append(ch.id)
	return ch


## A walkable tile near `center`, spreading characters out by index.
func free_tile_near(center: Vector2i, index := 0) -> Vector2i:
	var ring: Array[Vector2i] = [center]
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					ring.append(center + Vector2i(dx, dy))
	var walkable: Array[Vector2i] = []
	for c in ring:
		if grid.is_walkable(c):
			walkable.append(c)
	if walkable.is_empty():
		return center
	return walkable[index % walkable.size()]


# ==========================================================================
# Simulation
# ==========================================================================

## Advances the world by one fixed step.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	account.current()
	if _applied_account_version != account.version:
		_apply_account_effects()
	sim_time += dt
	_path_budget = _path_budget_per_tick
	if not _depleted.is_empty():
		for nid in _depleted.keys():
			var node: ResourceNodeState = _depleted[nid]
			if node.tick(dt):
				_depleted.erase(nid)
				emit_event("node_respawned", {"node_id": nid})
	if not _respawning.is_empty():
		for sid in _respawning.keys():
			var e: EnemyState = _respawning[sid]
			if e.tick(dt * encounters.respawn_speed_at(e.tile)):
				_respawning.erase(sid)
				e.spawn(rng, registry.enemy_variants)
				emit_event("enemy_respawned", {"spawn_id": sid, "variant": e.variant})
				if not e.variant.is_empty():
					emit_event("rare_enemy", {"spawn_id": sid, "name": e.display_name()})
	_tick_tavern(dt)
	for cid in character_order:
		engine.tick(characters[cid], dt)
	quests.tick(self, dt)
	expeditions.tick(self)
	if not dungeon_runs.is_empty():
		for run in dungeon_runs.duplicate():
			if run.tick(self, dt):
				_finish_dungeon(run)
	encounters.tick(self, dt)


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


## 0 = midnight, 0.5 = noon. A new world starts mid-morning.
func day_phase() -> float:
	return fmod(sim_time / _day_length + 0.35, 1.0)


func is_night() -> bool:
	var phase := day_phase()
	return phase < 0.25 or phase > 0.85


func _tick_tavern(dt: float) -> void:
	var rate := account_stats().get_stat("token_rate")  # tokens per hour
	if rate <= 0.0:
		return
	token_progress += rate * dt / 3600.0
	if token_progress >= 1.0:
		var whole := int(floor(token_progress))
		token_progress -= whole
		var before := wallet.get_balance("recruitment_tokens")
		wallet.earn("recruitment_tokens", whole, "tavern")
		emit_event("currency_earned", {"currency": "recruitment_tokens", "amount": whole, "reason": "tavern"})
		var ten := int(registry.recruitment_config.get("banners", [{}])[0].get("costs", {}).get("recruitment_tokens", 1)) * 10
		if before < ten and wallet.get_balance("recruitment_tokens") >= ten:
			emit_event("tokens_ready", {"amount": wallet.get_balance("recruitment_tokens")})


# ==========================================================================
# Account-wide effects (buildings now; relics, pets, guild perks later)
# ==========================================================================

func account_stats() -> StatBlock:
	return account.current()


## Re-applies effects that live outside characters (storage slots).
func _apply_account_effects() -> void:
	account.current()
	_applied_account_version = account.version
	var base := int(registry.get_config("storage.starting_distinct_item_slots", 48))
	storage.max_distinct = maxi(base + int(account_stats().get_stat("storage_slots")), storage.distinct_count())
	for cid in character_order:
		var ch: Adventurer = characters[cid]
		ch.refresh_capacity()


func worker_capacity() -> int:
	return int(registry.town_config.get("base_worker_capacity", 4)) + int(account_stats().get_stat("worker_capacity"))


func active_workers(except_id := "") -> int:
	var n := 0
	for cid in character_order:
		if cid != except_id and characters[cid].assignment != null and characters[cid].is_busy():
			n += 1
	return n


# ==========================================================================
# Player commands (the only mutations presentation code may request).
# Each returns "" on success or a player-facing reason.
# ==========================================================================

func assign_activity(character_id: String, asg: Assignment) -> String:
	var ch: Adventurer = characters.get(character_id)
	if ch == null:
		return "Unknown character"
	if ch.state == CharacterStates.State.AWAY:
		return "%s is away (%s)" % [ch.display_name, away_reason(ch)]
	if active_workers(character_id) >= worker_capacity():
		return "All %d worker slots are busy. Build Housing or upgrade the Town Hall." % worker_capacity()
	return engine.assign(ch, asg)


## Route builder: runs `steps` in order (each must end: Until amount or One
## trip), optionally looping. Returns "" or the first step's error.
func start_route(character_id: String, steps: Array, loop := false, name := "") -> String:
	if steps.is_empty():
		return "A route needs at least one step"
	var dicts: Array[Dictionary] = []
	for st in steps:
		var a: Assignment = st if st is Assignment else Assignment.from_dict(st)
		if a.continue_mode == Assignment.ContinueMode.REPEAT and steps.size() > 1:
			return "Route steps must end (use Until amount or One trip)"
		dicts.append(a.step_dict())
	var first := Assignment.from_dict(dicts[0])
	first.route = dicts
	first.route_loop = loop
	first.route_name = name
	return assign_activity(character_id, first)


func save_route_template(name: String, steps: Array, loop: bool) -> String:
	if name.strip_edges().is_empty() or steps.is_empty():
		return "Name the route and add steps"
	var dicts := []
	for st in steps:
		dicts.append(st.step_dict() if st is Assignment else st)
	route_templates[name.strip_edges()] = {"loop": loop, "steps": dicts}
	return ""


func cancel_assignment(character_id: String) -> void:
	var ch: Adventurer = characters.get(character_id)
	if ch:
		engine.cancel(ch)


func equip(character_id: String, item_id: String, armory_uid := 0) -> String:
	return EquipmentService.equip(self, character_id, item_id, armory_uid)


func unequip(character_id: String, slot: String) -> String:
	return EquipmentService.unequip(self, character_id, slot)


func repair(character_id: String, slot: String) -> String:
	return EquipmentService.repair(self, character_id, slot)


func upgrade_equipment(character_id: String, slot: String) -> String:
	return EquipmentService.upgrade(self, character_id, slot)


func sell_price(item_id: String) -> int:
	var item: Dictionary = registry.items.get(item_id, {})
	return int(floor(float(item.get("sell_price", 0)) * account_stats().get_stat("sell_price")))


## Sells from storage to the NPC shop for gold.
func sell_item(item_id: String, qty: int) -> String:
	if qty <= 0:
		return "Nothing to sell"
	if locked_items.has(item_id):
		return "%s is locked" % registry.get_item_name(item_id)
	if storage.get_quantity(item_id) < qty:
		return "Not enough %s" % registry.get_item_name(item_id)
	var gold := sell_price(item_id) * qty
	storage.remove(item_id, qty)
	record_sink(item_id, qty, "sold")
	if gold > 0:
		wallet.earn("gold", gold, "sell:%s" % item_id)
	emit_event("item_sold", {"item_id": item_id, "qty": qty, "gold": gold})
	return ""


func set_item_locked(item_id: String, locked: bool) -> void:
	if locked:
		locked_items[item_id] = true
	else:
		locked_items.erase(item_id)


func set_item_favorite(item_id: String, fav: bool) -> void:
	if fav:
		favorite_items[item_id] = true
	else:
		favorite_items.erase(item_id)


func start_construction(building_id: String) -> String:
	var err := town.can_start(registry, building_id)
	if not err.is_empty():
		return err
	var ld := town.level_def(registry, building_id, town.level_of(building_id) + 1)
	for req in ld.get("requires", []):
		if not Objectives.is_met(self, req):
			return "Needs: %s" % Objectives.describe(registry, req)
	var cost: Dictionary = ld.get("cost", {})
	var items: Dictionary = cost.get("items", {})
	for it in items:
		if storage.get_quantity(it) < int(items[it]):
			return "Needs %d %s in storage" % [int(items[it]), registry.get_item_name(it)]
	var gold := int(cost.get("gold", 0))
	if gold > 0 and not wallet.spend("gold", gold, "build:%s" % building_id):
		return "Not enough gold (%d needed)" % gold
	for it in items:
		storage.remove(it, int(items[it]))
		record_sink(it, int(items[it]), "construction")
	town.start_project(registry, building_id)
	emit_event("construction_started", {"building": building_id, "level": town.project.level})
	return ""


func complete_construction() -> void:
	var done := town.complete_project(registry)
	_apply_account_effects()
	emit_event("building_completed", {"building": done.get("building", ""), "level": done.get("level", 0)})


## Spends currency and pulls `count` times on a banner. Duplicates become
## fragments. Returns {error, results}.
func recruit(banner_id: String, count: int) -> Dictionary:
	var banner: Dictionary = registry.banners.get(banner_id, {})
	if banner.is_empty():
		return {"error": "Unknown banner", "results": []}
	if count != 1 and count != 10:
		return {"error": "Pull 1 or 10", "results": []}
	var costs := recruit_cost(banner_id, count)
	if costs.is_empty():
		return {"error": "Not enough tokens or gems", "results": []}
	if not wallet.spend_many(costs, "recruit:%s" % banner_id):
		return {"error": "Not enough tokens or gems", "results": []}
	var results := recruitment.pull(registry, banner, count)
	var dup_frags: Dictionary = registry.recruitment_config.get("duplicate_fragments", {})
	for res in results:
		var cid := String(res.character_id)
		if cid.is_empty():
			continue
		if characters.has(cid):
			var f := int(dup_frags.get(res.rarity, 5))
			fragments[cid] = int(fragments.get(cid, 0)) + f
			res["fragments"] = f
			res["new"] = false
		else:
			add_character(cid)
			res["new"] = true
		emit_event("recruited", res)
	return {"error": "", "results": results}


## The currency a pull would use: recruitment / event tokens first, gems
## otherwise (ten pulls with gems get the banner discount). {} if unaffordable.
func recruit_cost(banner_id: String, count: int) -> Dictionary:
	var banner: Dictionary = registry.banners.get(banner_id, {})
	var costs: Dictionary = banner.get("costs", {})
	for cur in costs:
		if cur == "gems":
			continue
		var c := {cur: int(costs[cur]) * count}
		if wallet.can_afford(c):
			return c
	if costs.has("gems"):
		var g := int(costs.gems) * count
		if count == 10:
			g = int(round(g * float(banner.get("ten_pull_discount", 1.0))))
		if wallet.can_afford({"gems": g}):
			return {"gems": g}
	return {}


func star_up_cost(character_id: String) -> int:
	var ch: Adventurer = characters.get(character_id)
	var costs: Array = registry.get_config("progression.star_fragment_costs", [])
	if ch == null or ch.stars - 1 >= costs.size():
		return -1
	return int(costs[ch.stars - 1])


func star_up(character_id: String) -> String:
	var ch: Adventurer = characters.get(character_id)
	if ch == null:
		return "Unknown character"
	var cost := star_up_cost(character_id)
	if cost < 0 or ch.stars >= int(registry.get_config("progression.max_stars", 6)):
		return "Already at maximum stars"
	if int(fragments.get(character_id, 0)) < cost:
		return "Needs %d fragments" % cost
	fragments[character_id] = int(fragments[character_id]) - cost
	ch.stars += 1
	ch.invalidate_stats()
	ch.refresh_capacity()
	emit_event("star_up", {"character_id": character_id, "stars": ch.stars})
	return ""


func specialization_slots(ch: Adventurer) -> int:
	var n := 0
	var by_level: Dictionary = registry.specialization_config.get("slots_by_character_level", {"1": 1})
	for lvl in by_level:
		if ch.character_level() >= int(lvl):
			n = maxi(n, int(by_level[lvl]))
	return n


func choose_specialization(character_id: String, spec_id: String) -> String:
	var ch: Adventurer = characters.get(character_id)
	var spec: Dictionary = registry.specializations.get(spec_id, {})
	if ch == null or spec.is_empty():
		return "Unknown character or specialization"
	if ch.specializations.has(spec_id):
		return "Already chosen"
	var need := int(registry.specialization_config.get("unlock_skill_level", 30))
	if ch.skills.get_level(String(spec.skill)) < need:
		return "Needs %s level %d" % [registry.skills.get(spec.skill, {}).get("name", spec.skill), need]
	for s in ch.specializations:
		if String(registry.specializations[s].skill) == String(spec.skill):
			return "Only one specialization per skill"
	if ch.specializations.size() >= specialization_slots(ch):
		return "No free specialization slot"
	ch.specializations.append(spec_id)
	ch.invalidate_stats()
	emit_event("specialization_chosen", {"character_id": character_id, "specialization": spec_id})
	return ""


func respec(character_id: String) -> String:
	var ch: Adventurer = characters.get(character_id)
	if ch == null or ch.specializations.is_empty():
		return "Nothing to reset"
	if not wallet.spend_many(registry.specialization_config.get("respec_cost", {"gems": 100}), "respec"):
		return "Not enough gems"
	ch.specializations.clear()
	ch.invalidate_stats()
	return ""



# ==========================================================================
# Phase 3 commands: regions, quests, vendors, expeditions, dungeons
# ==========================================================================

## "" if the region could be unlocked now, otherwise the first missing requirement.
func region_unlock_gap(p_region_id: String) -> String:
	var r: Dictionary = registry.map_regions.get(p_region_id, {})
	if r.is_empty():
		return "Unknown region"
	if is_region_unlocked(p_region_id):
		return "Already unlocked"
	var unlock: Dictionary = r.get("unlock", {})
	for c in unlock.get("conditions", []):
		if not Objectives.is_met(self, c):
			return Objectives.describe(registry, c)
	var cost: Dictionary = unlock.get("cost", {})
	if not wallet.can_afford(cost):
		return "Needs %d gold" % int(cost.get("gold", 0))
	return ""


func unlock_region(p_region_id: String) -> String:
	var gap := region_unlock_gap(p_region_id)
	if not gap.is_empty():
		return gap
	var cost: Dictionary = registry.map_regions[p_region_id].get("unlock", {}).get("cost", {})
	if not cost.is_empty() and not wallet.spend_many(cost, "unlock:%s" % p_region_id):
		return "Cannot afford"
	_set_region_unlocked(p_region_id)
	return ""


func _set_region_unlocked(p_region_id: String) -> void:
	unlocked_regions[p_region_id] = true
	_refresh_gates()
	emit_event("region_unlocked", {"region": p_region_id, "name": registry.region_name(p_region_id)})


## Gate tiles stay blocked until both regions they join are unlocked.
func _refresh_gates() -> void:
	for g in nav.gates:
		var open := nav.gate_open(g)
		grid.set_object_blocked(g.a, not open)
		grid.set_object_blocked(g.b, not open)


func claim_quest(quest_id: String) -> String:
	return quests.claim(self, quest_id)


func vendor_unlocked(vendor_id: String, entry: Dictionary) -> bool:
	var v: Dictionary = registry.vendors.get(vendor_id, {})
	return is_region_unlocked(String(v.get("region", ""))) and quests.reputation_tier(String(v.get("region", ""))) >= int(entry.get("tier", 0))


func buy_from_vendor(vendor_id: String, item_id: String, qty: int) -> String:
	var v: Dictionary = registry.vendors.get(vendor_id, {})
	if v.is_empty() or qty <= 0:
		return "Unknown vendor"
	for entry in v.get("stock", []):
		if String(entry.item) != item_id:
			continue
		if not vendor_unlocked(vendor_id, entry):
			return "Needs %s reputation with %s" % [registry.reputation_tiers()[int(entry.get("tier", 0))].name, registry.region_name(String(v.region))]
		if storage.can_add(item_id, qty) < qty:
			return "Storage is full"
		var cost := {String(v.get("currency", "gold")): int(entry.price) * qty}
		if not wallet.spend_many(cost, "vendor:%s" % vendor_id):
			return "Not enough %s" % v.get("currency", "gold")
		storage.add(item_id, qty)
		record_source(item_id, qty, "vendor")
		emit_event("item_bought", {"vendor": vendor_id, "item_id": item_id, "qty": qty})
		return ""
	return "Not sold here"


func buy_from_merchant(encounter_uid: int, item_id: String, qty: int) -> String:
	return encounters.buy(self, encounter_uid, item_id, qty)


func claim_mailbox() -> int:
	var moved := 0
	for it in mailbox.keys():
		var fit := storage.can_add(it, int(mailbox[it]))
		if fit > 0:
			storage.add(it, fit)
			mailbox[it] = int(mailbox[it]) - fit
			moved += fit
			if int(mailbox[it]) <= 0:
				mailbox.erase(it)
	return moved


func start_expedition(expedition_id: String, team: Array, use_supplies := true) -> String:
	return expeditions.start(self, expedition_id, team, use_supplies)


func start_dungeon(dungeon_id: String, team: Array) -> String:
	var d: Dictionary = registry.dungeons.get(dungeon_id, {})
	if d.is_empty():
		return "Unknown dungeon"
	if not is_region_unlocked(String(d.region)):
		return "Unlock %s first" % registry.region_name(String(d.region))
	if team.size() < int(d.get("party_min", 1)) or team.size() > int(d.get("party_max", 4)):
		return "Party size must be %d-%d" % [int(d.get("party_min", 1)), int(d.get("party_max", 4))]
	for run in dungeon_runs:
		if run.dungeon_id == dungeon_id:
			return "A party is already inside"
	var err := _check_team_available(team)
	if not err.is_empty():
		return err
	var run := DungeonRun.create(self, dungeon_id, team)
	for cid in team:
		_send_away(characters[cid], "dungeon:%s" % dungeon_id)
	dungeon_runs.append(run)
	emit_event("dungeon_started", {"dungeon": dungeon_id, "team": team.duplicate()})
	return ""


func _check_team_available(team: Array) -> String:
	var seen := {}
	for cid in team:
		var ch: Adventurer = characters.get(cid)
		if ch == null:
			return "Unknown character"
		if seen.has(cid):
			return "%s is listed twice" % ch.display_name
		seen[cid] = true
		if ch.state == CharacterStates.State.AWAY:
			return "%s is away" % ch.display_name
		if ch.state == CharacterStates.State.INJURED or ch.health <= 0.0:
			return "%s is injured" % ch.display_name
	return ""


## Takes a character off the map (expedition or dungeon). Bag contents stay
## with the character.
func _send_away(ch: Adventurer, reason: String) -> void:
	engine.cancel(ch, "")
	if ch.state == CharacterStates.State.RESTING:
		engine.set_state(ch, CharacterStates.State.IDLE)
	ch.away = reason
	engine.set_state(ch, CharacterStates.State.AWAY, "Away: %s" % away_reason(ch))


## Brings a character back next to `tile` (home storage by default).
func return_from_away(ch: Adventurer, injured_seconds := 0.0, near := Vector2i(-1, -1)) -> void:
	ch.away = ""
	ch.tile = free_tile_near(near if near.x >= 0 else storage_tile, character_order.find(ch.id))
	ch.path.clear()
	if injured_seconds > 0.0:
		ch.health = 0.0
		ch.injured_remaining = injured_seconds
		engine.set_state(ch, CharacterStates.State.INJURED, "Recovering")
	else:
		engine.set_state(ch, CharacterStates.State.IDLE, "Back")
	_last_reveal.erase(ch.id)


func away_reason(ch: Adventurer) -> String:
	var parts := ch.away.split(":")
	if parts.size() == 2 and parts[0] == "expedition":
		return "on %s" % registry.expeditions.get(parts[1], {}).get("name", "an expedition")
	if parts.size() == 2 and parts[0] == "dungeon":
		return "in %s" % registry.dungeons.get(parts[1], {}).get("name", "a dungeon")
	return "away"


func dungeon_run_of(ch_id: String) -> DungeonRun:
	for run in dungeon_runs:
		if run.has_member(ch_id):
			return run
	return null


func _finish_dungeon(run: DungeonRun) -> void:
	dungeon_runs.erase(run)
	var d: Dictionary = registry.dungeons[run.dungeon_id]
	var cleared := run.result == "cleared"
	var summary := {}
	# Unused food goes back to storage; loot is created only now.
	for it in run.food:
		if int(run.food[it]) > 0:
			_store_or_mail(it, int(run.food[it]))
	run.food.clear()
	for it in run.loot:
		_store_or_mail(it, int(run.loot[it]))
		record_source(it, int(run.loot[it]), "dungeon")
	if run.gold > 0:
		wallet.earn("gold", run.gold, "dungeon:%s" % run.dungeon_id)
	if cleared:
		var rec: Dictionary = dungeon_records.get(run.dungeon_id, {"clears": 0, "best_time": 0.0})
		var first := int(rec.clears) == 0
		rec.clears = int(rec.clears) + 1
		rec.best_time = run.elapsed if float(rec.best_time) <= 0.0 else minf(float(rec.best_time), run.elapsed)
		dungeon_records[run.dungeon_id] = rec
		counters["dungeon:%s" % run.dungeon_id] = int(counters.get("dungeon:%s" % run.dungeon_id, 0)) + 1
		summary = grant_rewards(d.get("clear_rewards", {}), [], "dungeon:%s" % run.dungeon_id)
		if first:
			var fs := grant_rewards(d.get("first_clear", {}), [], "dungeon_first:%s" % run.dungeon_id)
			summary["first_clear"] = fs
	var near: Vector2i = dungeon_entrances.get(run.dungeon_id, storage_tile)
	var injury := float(registry.get_config("combat.injury_seconds", 60.0))
	for m in run.party:
		var ch: Adventurer = characters.get(m.id)
		if ch == null:
			continue
		ch.health = clampf(float(m.hp), 0.0, ch.max_health())
		return_from_away(ch, injury if float(m.hp) <= 0.0 else 0.0, near)
	emit_event("dungeon_completed", {"dungeon": run.dungeon_id, "name": d.get("name", run.dungeon_id), "result": run.result,
		"loot": run.loot.duplicate(), "gold": run.gold, "elapsed": run.elapsed, "rewards": summary, "log": run.log_lines.duplicate()})


## Adds to storage, overflowing into the mailbox. Never destroys items.
func _store_or_mail(item_id: String, qty: int) -> void:
	var fit := storage.can_add(item_id, qty)
	if fit > 0:
		storage.add(item_id, fit)
	if qty - fit > 0:
		mailbox[item_id] = int(mailbox.get(item_id, 0)) + qty - fit


## Grants a reward block from data. `members` receive skill XP (empty = the
## whole roster gets nothing; XP rewards need someone to earn them).
## Returns a summary {currencies, items, xp, reputation, character}.
func grant_rewards(rewards: Dictionary, members: Array, reason: String, rng_override: RandomNumberGenerator = null, mult := 1.0) -> Dictionary:
	var r := rng_override if rng_override else rng
	var out := {"currencies": {}, "items": {}, "xp": {}, "reputation": {}}
	var cur: Dictionary = rewards.get("currencies", {})
	for c in cur:
		var v: Variant = cur[c]
		var amount := r.randi_range(int(v[0]), int(v[1])) if v is Array else int(v)
		amount = int(round(amount * mult))
		if amount > 0:
			wallet.earn(String(c), amount, reason)
			out.currencies[c] = amount
	var items: Variant = rewards.get("items", {})
	if items is Dictionary:
		for it in items:
			var q := int(round(int(items[it]) * mult))
			if q > 0:
				_store_or_mail(it, q)
				record_source(it, q, reason)
				out.items[it] = q
	elif items is Array:
		for e in items:
			if r.randf() >= float(e.get("chance", 1.0)):
				continue
			var q := int(round(r.randi_range(int(e.get("min", 1)), int(e.get("max", 1))) * mult))
			q = maxi(q, 1)
			_store_or_mail(String(e.item), q)
			record_source(String(e.item), q, reason)
			out.items[e.item] = int(out.items.get(e.item, 0)) + q
	var xp: Dictionary = rewards.get("xp", {})
	for skill in xp:
		for ch in members:
			engine.grant_xp(ch, String(skill), float(xp[skill]) * mult)
		if not members.is_empty():
			out.xp[skill] = float(xp[skill]) * mult
	var rep: Dictionary = rewards.get("reputation", {})
	for reg in rep:
		var pts := int(round(int(rep[reg]) * mult))
		quests.add_reputation(self, String(reg), pts)
		out.reputation[reg] = pts
	if rewards.has("character"):
		grant_character(String(rewards.character), reason)
		out["character"] = String(rewards.character)
	if rewards.has("reveal_secret"):
		reveal_secret(String(rewards.reveal_secret))
	if rewards.has("reveal_node"):
		reveal_node(String(rewards.reveal_node))
	return out


## Adds a non-gacha character (quest, discovery, reputation, encounter).
## Already owned: converts to fragments instead.
func grant_character(character_id: String, source: String) -> void:
	if not registry.characters.has(character_id):
		return
	if characters.has(character_id):
		var frags := int(registry.recruitment_config.get("duplicate_fragments", {}).get(registry.characters[character_id].get("rarity", "rare"), 10))
		fragments[character_id] = int(fragments.get(character_id, 0)) + frags
		emit_event("fragments_gained", {"character_id": character_id, "amount": frags, "source": source})
		return
	add_character(character_id)
	emit_event("character_joined", {"character_id": character_id, "name": registry.characters[character_id].get("name", character_id), "source": source})


func reveal_secret(secret_id: String) -> void:
	var sec: Dictionary = secrets.get(secret_id, {})
	if sec.is_empty() or revealed_secrets.has(secret_id):
		return
	revealed_secrets[secret_id] = true
	for t in sec.tiles:
		grid.set_object_blocked(t, false)
	emit_event("secret_revealed", {"secret": secret_id, "region": sec.region})


func reveal_node(node_id: String) -> void:
	var n: ResourceNodeState = nodes.get(node_id)
	if n and n.hidden:
		n.hidden = false
		emit_event("node_revealed", {"node_id": node_id})


## Called by the engine whenever a character steps onto a new tile: lifts
## the fog, checks discoveries and wandering-hero encounters.
func on_character_moved(ch: Adventurer) -> void:
	var last: Vector2i = _last_reveal.get(ch.id, Vector2i(-1000, -1000))
	if WorldGrid.chebyshev(last, ch.tile) < 2:
		return
	_last_reveal[ch.id] = ch.tile
	_reveal_around(ch, int(registry.get_config("exploration.walk_reveal_radius", 1)))
	var detect := int(registry.get_config("exploration.discovery_detect_radius", 2)) + int(floor((ch.stat("discovery") - 1.0) * 5.0))
	for did in exploration.nearby_undiscovered(ch.tile, maxi(detect, 1)):
		try_discover(ch, did)
	encounters.on_character_moved(self, ch)


func _reveal_around(ch: Adventurer, radius: int) -> int:
	var gained := exploration.reveal(ch.tile, radius)
	if gained > 0:
		engine.grant_xp(ch, "exploration", gained * float(registry.get_config("exploration.xp_per_tile", 0.6)))
		if wants_event("fog_revealed"):
			emit_event("fog_revealed", {"center": ch.tile, "radius": radius})
	return gained


## An explorer's survey: lifts the fog in the full reveal radius and checks
## discoveries in a wider ring.
func survey(ch: Adventurer) -> int:
	var gained := _reveal_around(ch, reveal_radius(ch))
	var detect := reveal_radius(ch) + int(floor((ch.stat("discovery") - 1.0) * 5.0))
	for did in exploration.nearby_undiscovered(ch.tile, maxi(detect, 1)):
		if exploration.is_revealed(JsonData.to_vec2i(exploration.discoveries[did].tile)):
			continue
		# Spotted from afar: reveal the spot so the explorer walks over to it.
		exploration.reveal(JsonData.to_vec2i(exploration.discoveries[did].tile), 0)
	return gained


func reveal_radius(ch: Adventurer) -> int:
	var per := maxi(int(registry.get_config("exploration.reveal_radius_per_levels", 25)), 1)
	return int(registry.get_config("exploration.base_reveal_radius", 4)) + ch.skills.get_level("exploration") / per + int(ch.stat("reveal_radius"))


func try_discover(ch: Adventurer, discovery_id: String) -> bool:
	var d: Dictionary = exploration.discoveries.get(discovery_id, {})
	if d.is_empty() or exploration.is_discovered(discovery_id):
		return false
	if not ExplorationState.requirement_gap(registry, ch, d).is_empty():
		return false
	exploration.mark_discovered(discovery_id, sim_time, ch.id)
	var summary := grant_rewards(d.get("rewards", {}), [ch], "discovery:%s" % discovery_id)
	emit_event("discovery", {"character_id": ch.id, "discovery": discovery_id, "name": d.get("name", discovery_id), "kind": d.get("kind", ""),
		"region": d.get("region", ""), "rewards": summary})
	return true


# --- Region / outpost queries -----------------------------------------------

func region_at(tile: Vector2i) -> String:
	return exploration.region_at(tile)


func is_region_unlocked(p_region_id: String) -> bool:
	return unlocked_regions.has(p_region_id)


func location_region(location_id: String) -> String:
	return String(locations.get(location_id, {}).get("region", ""))


func outpost_of(p_region_id: String) -> Dictionary:
	var bid := String(registry.map_regions.get(p_region_id, {}).get("outpost", ""))
	return outposts.get(bid, {})


func outpost_level(p_region_id: String) -> int:
	var op := outpost_of(p_region_id)
	return town.level_of(String(op.building)) if not op.is_empty() else 0


## Fast-travel anchor of a region: home storage in the start region, the
## outpost depot once built elsewhere. Vector2i(-1, -1) if none.
func waystone_of(p_region_id: String) -> Vector2i:
	if region_at(storage_tile) == p_region_id:
		return storage_tile
	if outpost_level(p_region_id) > 0:
		return outpost_of(p_region_id).depot_tile
	return Vector2i(-1, -1)


## Where a character should deposit: its own region's outpost depot if built,
## otherwise the village storage. Every depot feeds the same shared storage.
func nearest_deposit(ch: Adventurer) -> Vector2i:
	var r := region_at(ch.tile)
	if outpost_level(r) > 0:
		return outpost_of(r).depot_tile
	return storage_tile


func deposit_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = [storage_tile]
	for bid in outposts:
		if town.level_of(bid) > 0:
			out.append(outposts[bid].depot_tile)
	return out


## Outpost bonus for activities at `tile` ("gather_speed", "xp"); 1.0 if none.
func local_multiplier(tile: Vector2i, key: String) -> float:
	var r := region_at(tile)
	var lv := outpost_level(r)
	if lv <= 0:
		return 1.0
	var ld := town.level_def(registry, String(outpost_of(r).building), lv)
	return float(ld.get("local_effects", {}).get(key, 1.0))


func station_active(s: Dictionary) -> bool:
	var op := String(s.get("outpost", ""))
	return op.is_empty() or town.level_of(op) > 0


func max_skill_level(skill: String) -> int:
	var best := 0
	for cid in character_order:
		best = maxi(best, characters[cid].skills.get_level(skill))
	return best


func max_character_level() -> int:
	var best := 0
	for cid in character_order:
		best = maxi(best, characters[cid].character_level())
	return best


func max_combat_level() -> int:
	var best := 0
	for cid in character_order:
		best = maxi(best, characters[cid].combat_level())
	return best


func count(key: String, amount := 1) -> void:
	counters[key] = int(counters.get(key, 0)) + amount


func count_kill(enemy_def: Dictionary) -> void:
	count("kill:%s" % enemy_def.get("id", ""))
	for tag in enemy_def.get("tags", []):
		count("kill_tag:%s" % tag)

# ==========================================================================
# Progression hooks (called by the engine)
# ==========================================================================

## Unlocks traits from the character definition at the configured
## character levels (10 / 30 / 60 by default).
func sync_traits(ch: Adventurer) -> void:
	var unlocks: Array = registry.get_config("progression.trait_unlock_levels", [10, 30, 60])
	var def_traits: Array = ch.definition.get("traits", [])
	var lvl := ch.character_level()
	var changed := false
	for i in mini(unlocks.size(), def_traits.size()):
		var t := String(def_traits[i])
		if lvl >= int(unlocks[i]) and not ch.traits.has(t) and registry.traits.has(t):
			ch.traits.append(t)
			changed = true
			emit_event("trait_unlocked", {"character_id": ch.id, "trait": t})
	if changed:
		ch.invalidate_stats()
		ch.refresh_capacity()


func on_skill_level_up(ch: Adventurer, skill: String, from_level: int, to_level: int) -> void:
	var every := int(registry.economy_config.get("milestones", {}).get("skill_level_every", 10))
	var reward: Dictionary = registry.economy_config.get("milestones", {}).get("reward", {})
	if every <= 0:
		return
	var milestones := int(to_level / every) - int(from_level / every)
	for i in milestones:
		for cur in reward:
			wallet.earn(String(cur), int(reward[cur]), "milestone:%s" % skill)
		emit_event("milestone", {"character_id": ch.id, "skill": skill, "reward": reward})
	if skill == "defense":
		pass  # max health derives from defense level; nothing cached to refresh


func on_character_level_up(ch: Adventurer) -> void:
	sync_traits(ch)


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
		if n.type_id == type_id and not n.hidden and (not use_rect or rect.has_point(n.tile)) and is_region_unlocked(region_at(n.tile)):
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


func enemies_in(location_id: String) -> Array[EnemyState]:
	var out: Array[EnemyState] = []
	var rect: Rect2i = locations[location_id].rect if locations.has(location_id) else Rect2i()
	for sid in enemy_order:
		var e: EnemyState = enemies[sid]
		if (location_id.is_empty() or rect.has_point(e.tile)) and is_region_unlocked(region_at(e.tile)):
			out.append(e)
	return out


## Next enemy to fight: highest priority type first, then nearest. Skips
## enemies engaged by someone else and (optionally) those above a level.
func find_best_enemy(ch: Adventurer, location_id: String, priority: Array[String], max_level := 0) -> EnemyState:
	var best: EnemyState = null
	var best_score := INF
	for e in enemies_in(location_id):
		if not e.is_available_for(ch.id):
			continue
		if max_level > 0 and e.level() > max_level:
			continue
		if float(ch.unreachable_until.get(e.id, -1.0)) > sim_time:
			continue
		var score := WorldGrid.octile(ch.tile, e.tile)
		var p := priority.find(e.enemy_id)
		if p >= 0:
			score -= 10000.0 - p * 100.0
		if score < best_score:
			best_score = score
			best = e
	return best


func nearest_station(ch: Adventurer, station_type: String) -> Dictionary:
	var best := {}
	var best_d := INF
	for sid in stations:
		var s: Dictionary = stations[sid]
		if s.type == station_type and station_active(s) and is_region_unlocked(region_at(s.tile)):
			var d := WorldGrid.octile(ch.tile, s.tile)
			if d < best_d:
				best_d = d
				best = s
	return best


func location_name_at(tile: Vector2i) -> String:
	for lid in locations:
		if locations[lid].kind != "village" and locations[lid].rect.has_point(tile):
			return String(locations[lid].name)
	for lid in locations:
		if locations[lid].rect.has_point(tile):
			return String(locations[lid].name)
	var r := region_at(tile)
	return "%s wilds" % registry.region_name(r) if not r.is_empty() else "The wilds"


func mark_depleted(node: ResourceNodeState) -> void:
	_depleted[node.id] = node


func mark_enemy_dead(e: EnemyState) -> void:
	e.kill()
	if temp_enemies.has(e.id):
		remove_temp_enemy(e.id)
		return
	_respawning[e.id] = e


## Adds a temporary enemy (dynamic encounter). It blocks its tile until
## killed or expired and never respawns.
func add_temp_enemy(spawn_id: String, enemy_id: String, tile: Vector2i) -> EnemyState:
	var def: Dictionary = registry.enemies.get(enemy_id, {})
	if def.is_empty() or enemies.has(spawn_id):
		return null
	var es := EnemyState.create(spawn_id, def, tile)
	es.spawn(rng, [])
	enemies[spawn_id] = es
	enemy_order.append(spawn_id)
	temp_enemies[spawn_id] = true
	grid.set_object_blocked(tile, true)
	emit_event("enemy_spawned", {"spawn_id": spawn_id, "enemy_id": enemy_id})
	return es


func remove_temp_enemy(spawn_id: String) -> void:
	var e: EnemyState = enemies.get(spawn_id)
	if e == null:
		return
	if not e.engaged_by.is_empty():
		var ch: Adventurer = characters.get(e.engaged_by)
		if ch and ch.target_enemy_id == spawn_id:
			ch.target_enemy_id = ""
	enemies.erase(spawn_id)
	enemy_order.erase(spawn_id)
	temp_enemies.erase(spawn_id)
	_respawning.erase(spawn_id)
	grid.set_object_blocked(e.tile, false)
	emit_event("enemy_removed", {"spawn_id": spawn_id})


func next_item_uid() -> int:
	_next_uid += 1
	return _next_uid - 1


# --- Item ledger ------------------------------------------------------------

func record_source(item_id: String, qty: int, reason := "") -> void:
	if qty > 0:
		item_sources[item_id] = int(item_sources.get(item_id, 0)) + qty
		match reason:
			"gathered", "rare_drop":
				count("gather:%s" % item_id, qty)
			"crafting":
				count("craft:%s" % item_id, qty)


func record_sink(item_id: String, qty: int, _reason := "") -> void:
	if qty > 0:
		item_sinks[item_id] = int(item_sinks.get(item_id, 0)) + qty


## Kept for Phase 1 callers.
func record_production(item_id: String, qty: int) -> void:
	record_source(item_id, qty, "gathered")


## Net units that should exist for each item (sources - sinks).
func ledger_totals() -> Dictionary:
	var out := {}
	for k in item_sources:
		out[k] = int(item_sources[k])
	for k in item_sinks:
		out[k] = int(out.get(k, 0)) - int(item_sinks[k])
	for k in out.keys():
		if int(out[k]) == 0:
			out.erase(k)
	return out


## Total units of every item currently held anywhere: storage, bags,
## equipped items and the armory.
func held_totals() -> Dictionary:
	var totals := storage.items()
	for cid in character_order:
		var ch: Adventurer = characters[cid]
		var bag: Dictionary = ch.inventory.items()
		for item_id in bag:
			totals[item_id] = int(totals.get(item_id, 0)) + int(bag[item_id])
		for slot in ch.equipment:
			var iid := String(ch.equipment[slot].item_id)
			totals[iid] = int(totals.get(iid, 0)) + 1
	for inst in armory:
		totals[inst.item_id] = int(totals.get(inst.item_id, 0)) + 1
	for it in mailbox:
		totals[it] = int(totals.get(it, 0)) + int(mailbox[it])
	for run in dungeon_runs:
		for it in run.food:
			totals[it] = int(totals.get(it, 0)) + int(run.food[it])
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
	if type == "enemy_killed":
		var edef: Dictionary = registry.enemies.get(String(data.get("enemy_id", "")), {})
		count_kill(edef)
		var reg := region_at(enemies[data.spawn_id].tile) if enemies.has(data.get("spawn_id", "")) else ""
		if not reg.is_empty():
			count("kill_region:%s" % reg)
	if quiet and _CHATTY_EVENTS.has(type):
		return
	var ev := data.duplicate()
	ev["type"] = type
	ev["time"] = sim_time
	if event_log.size() < MAX_EVENT_LOG:
		event_log.append(ev)
	else:
		event_log[_event_head] = ev
		_event_head = (_event_head + 1) % MAX_EVENT_LOG
	if notifications:
		notifications.on_event(self, ev)
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
	var enemy_states := {}
	for sid in enemy_order:
		enemy_states[sid] = enemies[sid].to_dict()
	return {
		"format": SAVE_FORMAT,
		"region_id": region_id,
		"sim_time": sim_time,
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
		"storage": storage.to_dict(),
		"locked_items": locked_items.keys(),
		"favorite_items": favorite_items.keys(),
		"character_order": Array(character_order),
		"characters": chars,
		"nodes": node_states,
		"enemies": enemy_states,
		"wallet": wallet.to_dict(),
		"town": town.to_dict(),
		"recruitment": recruitment.to_dict(),
		"fragments": fragments.duplicate(),
		"armory": armory.duplicate(true),
		"next_uid": _next_uid,
		"route_templates": route_templates.duplicate(true),
		"token_progress": token_progress,
		"item_sources": item_sources.duplicate(),
		"item_sinks": item_sinks.duplicate(),
		# Phase 3
		"exploration": exploration.to_dict(),
		"unlocked_regions": unlocked_regions.keys(),
		"revealed_secrets": revealed_secrets.keys(),
		"counters": counters.duplicate(),
		"mailbox": mailbox.duplicate(),
		"quests": quests.to_dict(),
		"expeditions": expeditions.to_dict(),
		"dungeon_runs": dungeon_runs.map(func(r): return r.to_dict()),
		"dungeon_records": dungeon_records.duplicate(true),
		"encounters": encounters.to_dict(self),
		"notifications": notifications.to_dict(),
		"last_reveal": _last_reveal.keys().map(func(k): return [k, _last_reveal[k].x, _last_reveal[k].y]),
	}


static func from_dict(p_registry: DataRegistry, d: Dictionary) -> SimulationWorld:
	var w := SimulationWorld.new()
	w._setup(p_registry)
	for r in d.get("unlocked_regions", []):
		if p_registry.map_regions.has(r):
			w.unlocked_regions[String(r)] = true
	w._refresh_gates()
	var fmt := int(d.get("format", 1))
	w.sim_time = float(d.get("sim_time", 0.0))
	w.rng.seed = String(d.get("rng_seed", "1")).to_int()
	w.rng.state = String(d.get("rng_state", "0")).to_int()
	w.recruitment.rng.seed = w.rng.seed ^ 0x5EED
	var tw: Variant = d.get("town", {})
	if tw is Dictionary:
		w.town.load_dict(p_registry, tw)
	w._apply_account_effects()
	var st_dict: Variant = d.get("storage", {})
	if st_dict is Dictionary:
		var slots := w.storage.max_distinct
		w.storage.load_dict(st_dict)
		w.storage.max_distinct = maxi(slots, w.storage.max_distinct)
	for k in d.get("locked_items", []):
		w.locked_items[String(k)] = true
	for k in d.get("favorite_items", []):
		w.favorite_items[String(k)] = true
	if d.get("wallet") is Dictionary:
		w.wallet.load_dict(d.wallet)
	else:
		w.wallet.setup_starting(p_registry.currency_list)  # Phase 1 save
	if d.get("recruitment") is Dictionary:
		w.recruitment.load_dict(p_registry, d.recruitment)
	for cid in d.get("fragments", {}):
		if p_registry.characters.has(cid):
			w.fragments[String(cid)] = maxi(int(d.fragments[cid]), 0)
	w._next_uid = maxi(int(d.get("next_uid", 1)), 1)
	for inst in d.get("armory", []):
		if inst is Dictionary and p_registry.items.has(inst.get("item_id", "")):
			var item: Dictionary = p_registry.items[inst.item_id]
			w.armory.append({"uid": int(inst.get("uid", 0)), "item_id": String(inst.item_id),
				"durability": clampi(int(inst.get("durability", 0)), 0, int(item.get("max_durability", 1))),
				"upgrade": clampi(int(inst.get("upgrade", 0)), 0, 5)})
	var rt: Variant = d.get("route_templates", {})
	if rt is Dictionary:
		for k in rt:
			if rt[k] is Dictionary and rt[k].get("steps") is Array:
				w.route_templates[String(k)] = {"loop": bool(rt[k].get("loop", false)), "steps": rt[k].steps}
	w.token_progress = clampf(float(d.get("token_progress", 0.0)), 0.0, 1.0)
	var chars: Dictionary = d.get("characters", {})
	for cid in d.get("character_order", []):
		var ch := w.add_character(String(cid))
		if ch and chars.has(cid):
			ch.load_dict(chars[cid])
			if not w.grid.is_walkable(ch.tile):
				ch.tile = w.free_tile_near(w.spawn_tile)
			w.sync_traits(ch)
	# Starters added to data after this save was made join at spawn.
	for cid in p_registry.characters_by_acquisition("starter"):
		if not w.characters.has(cid):
			w.add_character(cid)
	var node_states: Dictionary = d.get("nodes", {})
	for nid in node_states:
		if w.nodes.has(nid):
			w.nodes[nid].load_dict(node_states[nid])
			if w.nodes[nid].is_depleted():
				w.mark_depleted(w.nodes[nid])
	var enemy_states: Variant = d.get("enemies", {})
	for sid in w.enemy_order:
		var e: EnemyState = w.enemies[sid]
		if enemy_states is Dictionary and enemy_states.has(sid):
			e.load_dict(enemy_states[sid], p_registry.enemy_variants)
			if not e.is_alive():
				w._respawning[sid] = e
		else:
			e.spawn(w.rng, p_registry.enemy_variants)
	# Reservations must match a character that actually targets them.
	for nid in w.node_order:
		var n: ResourceNodeState = w.nodes[nid]
		if not n.reserved_by.is_empty():
			var owner: Adventurer = w.characters.get(n.reserved_by)
			if owner == null or owner.target_node_id != nid:
				n.reserved_by = ""
	for sid in w.enemy_order:
		var e: EnemyState = w.enemies[sid]
		if not e.engaged_by.is_empty():
			var owner: Adventurer = w.characters.get(e.engaged_by)
			if owner == null or owner.target_enemy_id != sid:
				e.disengage(e.engaged_by)
	if fmt < 2:
		var ledger: Variant = d.get("production_ledger", {})
		if ledger is Dictionary:
			for k in ledger:
				w.item_sources[String(k)] = int(ledger[k])
	else:
		for k in d.get("item_sources", {}):
			w.item_sources[String(k)] = int(d.item_sources[k])
		for k in d.get("item_sinks", {}):
			w.item_sinks[String(k)] = int(d.item_sinks[k])
	w._load_phase3(d, fmt)
	return w


func _load_phase3(d: Dictionary, fmt: int) -> void:
	for r in d.get("unlocked_regions", []):
		if registry.map_regions.has(r):
			unlocked_regions[String(r)] = true
	_refresh_gates()
	var ex: Variant = d.get("exploration", {})
	if ex is Dictionary:
		exploration.load_dict(ex)
	if fmt < 3:
		# Pre-Phase-3 save: reveal what the characters could already see.
		exploration.reveal(spawn_tile, 8)
		for cid in character_order:
			exploration.reveal(characters[cid].tile, reveal_radius(characters[cid]))
	# Secrets and hidden nodes follow from discoveries already made.
	for sid in d.get("revealed_secrets", []):
		if secrets.has(sid):
			reveal_secret(String(sid))
	for did in exploration.discovered:
		var rw: Dictionary = exploration.discoveries.get(did, {}).get("rewards", {})
		if rw.has("reveal_secret"):
			reveal_secret(String(rw.reveal_secret))
		if rw.has("reveal_node"):
			reveal_node(String(rw.reveal_node))
	var ct: Variant = d.get("counters", {})
	if ct is Dictionary:
		for k in ct:
			counters[String(k)] = maxi(int(ct[k]), 0)
	var mb: Variant = d.get("mailbox", {})
	if mb is Dictionary:
		for k in mb:
			if registry.items.has(k) and int(mb[k]) > 0:
				mailbox[String(k)] = int(mb[k])
	if d.get("quests") is Dictionary:
		quests.load_dict(registry, d.quests)
	if d.get("expeditions") is Dictionary:
		expeditions.load_dict(self, d.expeditions)
	for rd in d.get("dungeon_runs", []):
		if rd is Dictionary:
			var run := DungeonRun.from_dict(self, rd)
			if run:
				dungeon_runs.append(run)
	var recs: Variant = d.get("dungeon_records", {})
	if recs is Dictionary:
		for k in recs:
			if registry.dungeons.has(k) and recs[k] is Dictionary:
				dungeon_records[String(k)] = {"clears": int(recs[k].get("clears", 0)), "best_time": float(recs[k].get("best_time", 0.0))}
	if d.get("encounters") is Dictionary:
		encounters.load_dict(self, d.encounters)
	else:
		encounters.schedule_first(self)
	if d.get("notifications") is Dictionary:
		notifications.load_dict(d.notifications)
	for lr in d.get("last_reveal", []):
		if lr is Array and lr.size() == 3 and characters.has(String(lr[0])):
			_last_reveal[String(lr[0])] = Vector2i(int(lr[1]), int(lr[2]))
	# A character saved as away must belong to a running expedition or dungeon.
	for cid in character_order:
		var ch: Adventurer = characters[cid]
		if ch.state == CharacterStates.State.AWAY and not expeditions.has_member(cid) and dungeon_run_of(cid) == null:
			return_from_away(ch)
