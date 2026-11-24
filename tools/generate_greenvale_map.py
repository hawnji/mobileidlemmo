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

fish_spots = []
for y in [34, 37, 40, 43]:
    cx = river_x[y]
    fish_spots.append((cx + 1, y))
for (x, y) in fish_spots:
    add_node("minnow_spot", x, y, "minnow_spot")


# --- Validation: everything reachable from spawn --------------------------
node_tiles = {tuple(n["tile"]) for n in nodes} | {storage_tile}


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


bad = [n for n in nodes if not reachable_adjacent(tuple(n["tile"]))]
assert reachable_adjacent(storage_tile), "storage unreachable"
assert not bad, f"unreachable nodes: {bad}"

locations = [
    {"id": "greenvale_hollow", "name": "Greenvale Hollow", "kind": "village", "rect": [35, 21, 18, 16]},
    {"id": "copper_mine", "name": "Greenvale Mine", "kind": "resource_area", "rect": [46, 2, 15, 15]},
    {"id": "oakwood_forest", "name": "Oakwood Forest", "kind": "resource_area", "rect": [1, 2, 21, 44]},
    {"id": "greenvale_river", "name": "Greenvale River", "kind": "resource_area", "rect": [24, 32, 10, 14]},
    {"id": "hollow_farms", "name": "Hollow Farms", "kind": "farmland", "rect": [35, 38, 17, 8]},
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
}
path = Path(__file__).resolve().parent.parent / "data" / "regions" / "greenvale_start.json"
path.write_text(json.dumps(out, indent=2))
print(f"wrote {path} ({len(nodes)} nodes, {len(seen)} reachable tiles)")
print("\n".join(out["rows"]))
