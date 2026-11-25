class_name ExplorationState
extends RefCounted
## Fog of war, region membership and discoveries for the whole map.
##
## Fog: one byte per tile (0 = hidden, 1 = revealed). Characters reveal a
## circle around themselves as they walk (radius from data + exploration
## level + gear). Progress per region counts revealed *walkable* tiles, so
## mountains and lakes do not distort percentages.
##
## Revealing is the hot path during offline simulation, so it is cheap when
## nothing changes: the map is split into 8x8 blocks with a count of hidden
## tiles each, and a circle whose blocks are all revealed is skipped.
##
## Discoveries are authored points (data/regions/world_map.json). A character
## who passes within detection range and meets the requirements (exploration
## level, and for some a combat specialty or skill affinity) discovers it.

const BLOCK := 8

var width := 0
var height := 0
var revealed := PackedByteArray()
var region_index := PackedByteArray()  # 255 = no region
var region_ids: Array[String] = []
var region_walkable := PackedInt32Array()
var region_revealed := PackedInt32Array()
var _walkable := PackedByteArray()
var _block_hidden := PackedInt32Array()
var _blocks_w := 0
var discoveries := {}  # id -> def
var discovery_order: Array[String] = []
var discovered := {}  # id -> {time, by}
## Tiles that are walkable once a secret is revealed: tile -> secret id.
var version := 0


func setup(grid: WorldGrid, regions: Array, discovery_defs: Array) -> void:
	width = grid.width
	height = grid.height
	revealed.resize(width * height)
	revealed.fill(0)
	region_index.resize(width * height)
	region_index.fill(255)
	_walkable.resize(width * height)
	region_ids.clear()
	for r in regions:
		region_ids.append(String(r.id))
	region_walkable.resize(region_ids.size())
	region_walkable.fill(0)
	region_revealed.resize(region_ids.size())
	region_revealed.fill(0)
	for i in regions.size():
		var rc: Array = regions[i].get("rect", [0, 0, 0, 0])
		for y in range(int(rc[1]), int(rc[1]) + int(rc[3])):
			for x in range(int(rc[0]), int(rc[0]) + int(rc[2])):
				if x >= 0 and y >= 0 and x < width and y < height:
					region_index[y * width + x] = i
	for y in height:
		for x in width:
			var idx := y * width + x
			var w := grid.terrain_walkable(Vector2i(x, y))
			_walkable[idx] = 1 if w else 0
			if w and region_index[idx] != 255:
				region_walkable[region_index[idx]] += 1
	_blocks_w = ceili(float(width) / BLOCK)
	_block_hidden.resize(_blocks_w * ceili(float(height) / BLOCK))
	_block_hidden.fill(0)
	for y in height:
		for x in width:
			_block_hidden[(y / BLOCK) * _blocks_w + (x / BLOCK)] += 1
	discoveries.clear()
	discovery_order.clear()
	for d in discovery_defs:
		discoveries[String(d.id)] = d
		discovery_order.append(String(d.id))


func region_at(tile: Vector2i) -> String:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return ""
	var i := region_index[tile.y * width + tile.x]
	return region_ids[i] if i != 255 else ""


func is_revealed(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return false
	return revealed[tile.y * width + tile.x] != 0


## Reveals a circle. Returns the number of newly revealed walkable tiles.
func reveal(center: Vector2i, radius: int) -> int:
	var x0 := maxi(center.x - radius, 0)
	var x1 := mini(center.x + radius, width - 1)
	var y0 := maxi(center.y - radius, 0)
	var y1 := mini(center.y + radius, height - 1)
	var any_hidden := false
	for by in range(y0 / BLOCK, y1 / BLOCK + 1):
		for bx in range(x0 / BLOCK, x1 / BLOCK + 1):
			if _block_hidden[by * _blocks_w + bx] > 0:
				any_hidden = true
	if not any_hidden:
		return 0
	var r2 := radius * radius
	var gained := 0
	for y in range(y0, y1 + 1):
		var dy := y - center.y
		for x in range(x0, x1 + 1):
			var dx := x - center.x
			if dx * dx + dy * dy > r2:
				continue
			var idx := y * width + x
			if revealed[idx] != 0:
				continue
			revealed[idx] = 1
			_block_hidden[(y / BLOCK) * _blocks_w + (x / BLOCK)] -= 1
			if _walkable[idx] != 0:
				var ri := region_index[idx]
				if ri != 255:
					region_revealed[ri] += 1
				gained += 1
	if gained > 0:
		version += 1
	return gained


func explored_pct(region_id: String) -> float:
	var i := region_ids.find(region_id)
	if i < 0 or region_walkable[i] == 0:
		return 0.0
	return float(region_revealed[i]) / float(region_walkable[i])


## Nearest hidden walkable tile in a region (by straight-line distance),
## skipping tiles in `skip`. Vector2i(-1, -1) if the region is fully revealed.
func nearest_hidden(region_id: String, from: Vector2i, skip: Dictionary, grid: WorldGrid = null) -> Vector2i:
	var ri := region_ids.find(region_id)
	if ri < 0:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for idx in revealed.size():
		if revealed[idx] != 0 or _walkable[idx] == 0 or region_index[idx] != ri:
			continue
		var t := Vector2i(idx % width, idx / width)
		if skip.has(t) or (grid and not grid.is_walkable(t)):
			continue
		var d := WorldGrid.octile(from, t)
		if d < best_d:
			best_d = d
			best = t
	return best


# --- Discoveries -----------------------------------------------------------

func is_discovered(discovery_id: String) -> bool:
	return discovered.has(discovery_id)


func discovered_count(region_id := "") -> int:
	var n := 0
	for id in discovered:
		if region_id.is_empty() or String(discoveries.get(id, {}).get("region", "")) == region_id:
			n += 1
	return n


func total_count(region_id := "") -> int:
	var n := 0
	for id in discovery_order:
		if region_id.is_empty() or String(discoveries[id].get("region", "")) == region_id:
			n += 1
	return n


## "" if this character could make the discovery, otherwise why not.
static func requirement_gap(registry: DataRegistry, ch: Adventurer, d: Dictionary) -> String:
	var req: Dictionary = d.get("requires", {})
	var lvl := int(req.get("exploration", 1))
	if ch.skills.get_level("exploration") < lvl:
		return "Exploration level %d" % lvl
	if req.has("specialty") and String(ch.definition.get("combat_specialty", "")) != String(req.specialty):
		return "A %s" % String(req.specialty)
	if req.has("affinity") and not ch.definition.get("affinities", {}).has(String(req.affinity)):
		return "A character with %s affinity" % registry.skills.get(req.affinity, {}).get("name", req.affinity)
	return ""


## Undiscovered discoveries within `radius` of a tile, in data order.
func nearby_undiscovered(tile: Vector2i, radius: int) -> Array[String]:
	var out: Array[String] = []
	for id in discovery_order:
		if discovered.has(id):
			continue
		var t := JsonData.to_vec2i(discoveries[id].tile)
		if WorldGrid.chebyshev(t, tile) <= radius:
			out.append(id)
	return out


func mark_discovered(discovery_id: String, sim_time: float, by: String) -> void:
	discovered[discovery_id] = {"time": sim_time, "by": by}
	version += 1


# --- Persistence -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"fog": Marshalls.raw_to_base64(revealed.compress(FileAccess.COMPRESSION_DEFLATE)), "fog_size": revealed.size(),
		"discovered": discovered.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	var raw: Variant = d.get("fog", "")
	if raw is String and not String(raw).is_empty():
		var bytes := Marshalls.base64_to_raw(raw).decompress(int(d.get("fog_size", 0)), FileAccess.COMPRESSION_DEFLATE)
		if bytes.size() == revealed.size():
			_rebuild_from(bytes)
		elif bytes.size() < revealed.size() and width > 0 and bytes.size() % width == 0:
			# The map grew taller (Phase 5 added rows below): keep the old fog.
			var grown := PackedByteArray()
			grown.resize(revealed.size())
			for i in bytes.size():
				grown[i] = bytes[i]
			_rebuild_from(grown)
	discovered.clear()
	var disc: Variant = d.get("discovered", {})
	if disc is Dictionary:
		for id in disc:
			if discoveries.has(id) and disc[id] is Dictionary:
				discovered[String(id)] = {"time": float(disc[id].get("time", 0.0)), "by": String(disc[id].get("by", ""))}
	version += 1


func _rebuild_from(bytes: PackedByteArray) -> void:
	revealed = bytes
	region_revealed.fill(0)
	_block_hidden.fill(0)
	for idx in revealed.size():
		var x := idx % width
		var y := idx / width
		if revealed[idx] == 0:
			_block_hidden[(y / BLOCK) * _blocks_w + (x / BLOCK)] += 1
		elif _walkable[idx] != 0 and region_index[idx] != 255:
			region_revealed[region_index[idx]] += 1
