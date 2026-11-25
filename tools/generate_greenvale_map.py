#!/usr/bin/env python3
"""Generates data/regions/greenvale_start.json — the Phase 1 starter map.

The map is authored procedurally (deterministic seed) so it can be regenerated
and tweaked quickly. Phase 3 will replace this with hand-painted Godot
TileMapLayer chunks exported to the same JSON schema (see docs/DATA_SCHEMA.md).

Usage:  python3 tools/generate_greenvale_map.py
The script validates that every resource node and the storage chest are
reachable from the village spawn and fails loudly otherwise.
"""
import json
import math
import random
from collections import deque
from pathlib import Path

W, H = 64, 48
SEED = 1337
rng = random.Random(SEED)
WALKABLE = set(".,=fbcpsx")

g = [["." for _ in range(W)] for _ in range(H)]


def put(x, y, ch):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = ch


def rect(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, ch)


# --- Meadow patches -------------------------------------------------------
for _ in range(140):
    put(rng.randrange(W), rng.randrange(H), ",")

# --- Western forest (Oakwood Forest) ------------------------------------
for y in range(2, 46):
    for x in range(1, 22):
        edge = 19 + int(2 * math.sin(y / 4.0))
        if x <= edge:
            put(x, y, "f")
# dense tree clusters (impassable)
for _ in range(26):
    cx, cy = rng.randrange(3, 19), rng.randrange(4, 44)
    for _ in range(rng.randrange(3, 7)):
        put(cx + rng.randrange(-1, 2), cy + rng.randrange(-1, 2), "T")

# --- North-east mountains + mine -----------------------------------------
for y in range(0, 17):
    for x in range(40, W):
        slope = 40 + int((y / 16.0) ** 2 * 12)
        if x >= slope or y < 2:
            put(x, y, "^")
rect(47, 3, 60, 10, "c")      # main cave hall
rect(50, 11, 54, 13, "c")     # cave mouth
rect(56, 11, 59, 12, "c")     # side gallery
for x in range(51, 54):
    for y in range(14, 17):
        put(x, y, "c")

# --- River (meandering N->S, 3 wide) --------------------------------------
river_x = {}
for y in range(H):
    cx = 27 + int(round(2.5 * math.sin(y / 6.0)))
    river_x[y] = cx
    for dx in (-1, 0, 1):
        put(cx + dx, y, "~")
    put(cx - 2, y, "s") if g[y][cx - 2] not in "^T" else None
    put(cx + 2, y, "s") if g[y][cx + 2] not in "^T" else None

# --- Village (Greenvale Hollow) -------------------------------------------
rect(36, 22, 52, 35, "p")
# buildings
for (x0, y0, x1, y1) in [(37, 23, 40, 25), (44, 23, 48, 25), (50, 23, 52, 26),
                          (37, 31, 40, 34), (49, 31, 52, 34), (43, 33, 46, 35)]:
    rect(x0, y0, x1, y1, "H")

# --- Farmland south of the village ----------------------------------------
rect(36, 39, 50, 44, "x")
for x in range(35, 52):
    put(x, 38, "w")
    put(x, 45, "w")
put(43, 38, "=")  # gate

# --- Roads ----------------------------------------------------------------
# village -> mine (north)
for y in range(14, 23):
    put(52, y, "=")
for x in range(44, 53):
    put(x, 21, "=")
# village -> west bridge -> forest
bridge_y = 29
for x in range(14, 37):
    ch = "b" if g[bridge_y][x] == "~" else "="
    put(x, bridge_y, ch)
    if g[bridge_y + 1][x] == "~":
        put(x, bridge_y + 1, "b")
    elif x < 36:
        put(x, bridge_y + 1, "=")
# village -> farm
for y in range(36, 39):
    put(43, y, "=")
# village -> river fishing bank (south-west)
for x in range(31, 37):
    put(x, 37, "=")

# --- Map border -----------------------------------------------------------
for x in range(W):
    if g[0][x] != "^":
        put(x, 0, "T")
    if g[H - 1][x] not in "~":
        put(x, H - 1, "T")
for y in range(H):
    if g[y][0] != "~":
        put(0, y, "T")
    if g[y][W - 1] not in "^~":
        put(W - 1, y, "^")

# --- Points of interest ---------------------------------------------------
storage_tile = (44, 28)
put(*storage_tile, "p")
spawn_tile = (44, 30)

nodes = []


def add_node(node_type, x, y, prefix):
    nodes.append({"id": f"{prefix}_{len([n for n in nodes if n['type'] == node_type]) + 1}",
                  "type": node_type, "tile": [x, y]})


for (x, y) in [(48, 5), (51, 4), (55, 5), (58, 8), (49, 9), (57, 11)]:
    put(x, y, "c")
    add_node("copper_rock", x, y, "copper_rock")
for (x, y) in [(53, 7), (59, 4), (47, 7)]:
    put(x, y, "c")
    add_node("tin_rock", x, y, "tin_rock")
for (x, y) in [(56, 12), (59, 12), (60, 9)]:   # deep gallery: iron
    put(x, y, "c")
    add_node("iron_rock", x, y, "iron_rock")

oak_spots = []
tries = 0
while len(oak_spots) < 12 and tries < 5000:
    tries += 1
    x, y = rng.randrange(4, 19), rng.randrange(8, 40)
    if g[y][x] != "f" or abs(y - bridge_y) <= 1:
        continue
    if any(abs(x - ox) + abs(y - oy) < 4 for ox, oy in oak_spots):
        continue
    oak_spots.append((x, y))
for (x, y) in oak_spots:
    add_node("oak_tree", x, y, "oak_tree")

herb_spots = []
tries = 0
while len(herb_spots) < 8 and tries < 5000:
    tries += 1
    x, y = rng.randrange(3, 19), rng.randrange(10, 38)
    if g[y][x] != "f" or abs(y - bridge_y) <= 1:
        continue
    if any(abs(x - ox) + abs(y - oy) < 3 for ox, oy in oak_spots + herb_spots):
        continue
    herb_spots.append((x, y))
for (x, y) in herb_spots:
    add_node("herb_bush", x, y, "herb_bush")

fish_spots = []
for y in [34, 37, 40, 43]:
    cx = river_x[y]
    fish_spots.append((cx + 1, y))
for (x, y) in fish_spots:
    add_node("minnow_spot", x, y, "minnow_spot")
for y in [4, 8, 12]:          # upper river: trout
    add_node("trout_spot", river_x[y] + 1, y, "trout_spot")
for y in [18, 21, 24]:        # willow bend: willows on the east sand bank
    x = river_x[y] + 2
    put(x, y, "s")
    add_node("willow_tree", x, y, "willow_tree")

for (x, y) in [(38, 40), (41, 40), (44, 40), (47, 40)]:
    add_node("potato_patch", x, y, "potato_patch")
for (x, y) in [(38, 43), (42, 43), (46, 43)]:
    add_node("marrentill_patch", x, y, "marrentill_patch")

# --- Crafting stations in the village plaza -------------------------------
stations = [
    {"id": "furnace_1", "type": "furnace", "name": "Furnace", "tile": [37, 28]},
    {"id": "anvil_1", "type": "anvil", "name": "Anvil", "tile": [39, 28]},
    {"id": "workbench_1", "type": "workbench", "name": "Workbench", "tile": [48, 28]},
    {"id": "range_1", "type": "range", "name": "Cooking Range", "tile": [50, 28]},
    {"id": "alchemy_table_1", "type": "alchemy_table", "name": "Alchemy Table", "tile": [52, 30]},
]

# --- Enemy spawns ----------------------------------------------------------
enemies = []


def add_enemy(enemy, x, y):
    if g[y][x] in "T^~Hw":
        put(x, y, "." if g[y][x] != "T" else "f")
    enemies.append({"id": f"{enemy}_{len([e for e in enemies if e['enemy'] == enemy]) + 1}", "enemy": enemy, "tile": [x, y]})


for (x, y) in [(58, 19), (61, 22), (58, 26), (60, 30)]:
    add_enemy("slime", x, y)
for (x, y) in [(60, 18), (57, 23), (61, 27), (58, 33)]:
    add_enemy("giant_rat", x, y)
for (x, y) in [(4, 4), (7, 5), (5, 7), (9, 3)]:
    add_enemy("wolf", x, y)
for (x, y) in [(55, 41), (58, 40), (60, 43)]:
    add_enemy("goblin", x, y)
for (x, y) in [(57, 44), (61, 41)]:
    add_enemy("goblin_archer", x, y)
add_enemy("goblin_warrior", 59, 45)
add_enemy("forest_troll", 5, 43)
# clear space around the troll
for dx in range(-2, 3):
    for dy in range(-2, 3):
        if g[43 + dy][5 + dx] == "T":
            put(5 + dx, 43 + dy, "f")

# --- Building plots ---------------------------------------------------------
buildings = [
    {"building": "town_hall", "rect": [37, 23, 4, 3], "work_tile": [38, 26]},
    {"building": "bank", "rect": [44, 23, 5, 3], "work_tile": [46, 26]},
    {"building": "tavern", "rect": [50, 23, 3, 4], "work_tile": [49, 25]},
    {"building": "blacksmith", "rect": [37, 31, 4, 4], "work_tile": [38, 30]},
    {"building": "workshop", "rect": [49, 31, 4, 4], "work_tile": [50, 30]},
    {"building": "academy", "rect": [43, 33, 4, 3], "work_tile": [44, 32]},
    {"building": "farm", "rect": [36, 39, 15, 6], "work_tile": [41, 37]},
    {"building": "housing", "rect": [54, 23, 2, 2], "work_tile": [54, 25]},
    {"building": "marketplace", "rect": [54, 27, 2, 2], "work_tile": [54, 29]},
    {"building": "barracks", "rect": [54, 31, 2, 2], "work_tile": [54, 33]},
    {"building": "guild_hall", "rect": [33, 23, 2, 2], "work_tile": [34, 25]},
    {"building": "expedition_center", "rect": [33, 32, 2, 2], "work_tile": [34, 34]},
]

# --- Validation: everything reachable from spawn --------------------------
node_tiles = {tuple(n["tile"]) for n in nodes} | {storage_tile} | {tuple(st["tile"]) for st in stations} | {tuple(e["tile"]) for e in enemies}


def walkable(x, y):
    return 0 <= x < W and 0 <= y < H and g[y][x] in WALKABLE and (x, y) not in node_tiles


seen = {spawn_tile}
q = deque([spawn_tile])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (x + dx, y + dy)
        if n not in seen and walkable(*n):
            seen.add(n)
            q.append(n)


def reachable_adjacent(t):
    x, y = t
    return any((x + dx, y + dy) in seen for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)


bad = [n for n in nodes + stations + enemies if not reachable_adjacent(tuple(n["tile"]))]
assert reachable_adjacent(storage_tile), "storage unreachable"
assert not bad, f"unreachable objects: {bad}"
bad_work = [b for b in buildings if tuple(b["work_tile"]) not in seen]
assert not bad_work, f"unreachable building work tiles: {bad_work}"

locations = [
    {"id": "greenvale_hollow", "name": "Greenvale Hollow", "kind": "village", "rect": [35, 21, 18, 16]},
    {"id": "copper_mine", "name": "Greenvale Mine", "kind": "resource_area", "rect": [46, 2, 15, 15]},
    {"id": "oakwood_forest", "name": "Oakwood Forest", "kind": "resource_area", "rect": [1, 2, 21, 44]},
    {"id": "greenvale_river", "name": "Greenvale River", "kind": "resource_area", "rect": [24, 32, 10, 14]},
    {"id": "hollow_farms", "name": "Hollow Farms", "kind": "resource_area", "rect": [35, 38, 17, 8]},
    {"id": "upper_river", "name": "Upper River", "kind": "resource_area", "rect": [22, 1, 12, 16]},
    {"id": "willow_bend", "name": "Willow Bend", "kind": "resource_area", "rect": [26, 16, 8, 10]},
    {"id": "east_meadows", "name": "East Meadows", "kind": "hunting_ground", "rect": [56, 17, 7, 20]},
    {"id": "wolf_den", "name": "Wolf Den", "kind": "hunting_ground", "rect": [1, 1, 11, 9]},
    {"id": "goblin_camp", "name": "Goblin Camp", "kind": "hunting_ground", "rect": [53, 38, 10, 9]},
    {"id": "troll_hollow", "name": "Troll Hollow", "kind": "hunting_ground", "rect": [1, 39, 9, 8]},
]

out = {
    "schema_version": 1,
    "id": "greenvale_start",
    "name": "Greenvale",
    "description": "The starting valley: a riverside village, an oak forest and a small copper mine.",
    "width": W,
    "height": H,
    "rows": ["".join(r) for r in g],
    "spawn_tile": list(spawn_tile),
    "storage": {"id": "village_storage", "name": "Village Storage", "tile": list(storage_tile)},
    "locations": locations,
    "resource_nodes": nodes,
    "stations": stations,
    "enemy_spawns": enemies,
    "building_plots": buildings,
}
path = Path(__file__).resolve().parent.parent / "data" / "regions" / "greenvale_start.json"
path.write_text(json.dumps(out, indent=2))
print(f"wrote {path} ({len(nodes)} nodes, {len(seen)} reachable tiles)")
print("\n".join(out["rows"]))
