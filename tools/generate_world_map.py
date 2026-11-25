#!/usr/bin/env python3
"""Generates data/regions/world_map.json: the connected Phase 3 world.

The world is one seamless tile grid made of four regions laid out as a 2x2:

    +-------------------+--------------------+
    | Greenvale (start) | Irondeep Mountains |   y 0..47
    +-------------------+--------------------+
    | Whisperwood       | Ashen Desert       |   y 48..95
    +-------------------+--------------------+
      x 0..63             x 64..127

Greenvale is copied unchanged from data/regions/greenvale_start.json (made by
tools/generate_greenvale_map.py), so Phase 1/2 saves keep valid tile
coordinates. Regions are separated by impassable borders and joined only by
gates. A gate is a pair of walkable tiles, one on each side of the border;
the simulation keeps both blocked until the region behind them is unlocked.

Also authored here: resource nodes, enemy spawns, stations, outposts,
dungeon entrances, discoveries and secret passages for every region.

Usage:  python3 tools/generate_greenvale_map.py && python3 tools/generate_world_map.py
The script fails loudly if anything is unreachable from the village spawn
with every gate open and every secret passage still closed.
"""
import json
import math
import random
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
W, H = 128, 96
rng = random.Random(4242)
# Walkable terrain symbols (must match data/regions/terrain.json).
WALKABLE = set(".,=fbcpsxgdrmkQq")

green = json.loads((ROOT / "data/regions/greenvale_start.json").read_text())
g = [["^" for _ in range(W)] for _ in range(H)]
for y, row in enumerate(green["rows"]):
    for x, ch in enumerate(row):
        g[y][x] = ch


def put(x, y, ch):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = ch


def get(x, y):
    return g[y][x] if 0 <= x < W and 0 <= y < H else "^"


def rect(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, ch)


def line(x0, y0, x1, y1, ch, width=1, only=None):
    """Axis-aligned path (horizontal then vertical)."""
    xs = range(min(x0, x1), max(x0, x1) + 1)
    for x in xs:
        for w in range(width):
            if only is None or get(x, y0 + w) in only:
                put(x, y0 + w, ch)
    for y in range(min(y0, y1), max(y0, y1) + 1):
        for w in range(width):
            if only is None or get(x1 + w, y) in only:
                put(x1 + w, y, ch)


def blob(cx, cy, rx, ry, ch, only=None):
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            if ((x - cx) / max(rx, 0.5)) ** 2 + ((y - cy) / max(ry, 0.5)) ** 2 <= 1.0:
                if only is None or get(x, y) in only:
                    put(x, y, ch)


nodes = list(green["resource_nodes"])
for n in nodes:
    n["region"] = "greenvale"
enemies = list(green["enemy_spawns"])
stations = list(green["stations"])
plots = list(green["building_plots"])
locations = []
for loc in green["locations"]:
    loc = dict(loc)
    loc["region"] = "greenvale"
    locations.append(loc)
hidden_node_ids = set()


def node(ntype, x, y, region, hidden=False):
    nid = f"{ntype}_{len([n for n in nodes if n['type'] == ntype]) + 1}"
    n = {"id": nid, "type": ntype, "tile": [x, y], "region": region}
    if hidden:
        n["hidden"] = True
        hidden_node_ids.add(nid)
    nodes.append(n)
    return nid


def enemy(eid, x, y, region):
    if get(x, y) not in WALKABLE:
        raise SystemExit(f"enemy {eid} on blocked tile {x},{y} ({get(x, y)})")
    enemies.append({"id": f"{eid}_{len([e for e in enemies if e['enemy'] == eid]) + 1}", "enemy": eid, "tile": [x, y], "region": region})


def scatter(n, x0, y0, x1, y1, allowed, min_dist, taken):
    out = []
    tries = 0
    while len(out) < n and tries < 20000:
        tries += 1
        x, y = rng.randint(x0, x1), rng.randint(y0, y1)
        if get(x, y) not in allowed:
            continue
        if any(abs(x - a) + abs(y - b) < min_dist for a, b in out + taken):
            continue
        # keep at least two walkable neighbours so nothing seals a corridor
        free = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if get(x + dx, y + dy) in WALKABLE)
        if free < 3:
            continue
        out.append((x, y))
    if len(out) < n:
        raise SystemExit(f"scatter: only placed {len(out)}/{n} in {x0},{y0}-{x1},{y1}")
    taken.extend(out)
    return out


taken = [tuple(n["tile"]) for n in nodes] + [tuple(e["tile"]) for e in enemies]

# ======================================================================
# Gates
# ======================================================================
# Greenvale -> Irondeep: east meadows, through the eastern mountain wall.
put(63, 25, "g")
put(64, 25, "g")
# Greenvale -> Whisperwood: south edge of Oakwood Forest.
for y in range(44, 47):
    if get(16, y) == "T":
        put(16, y, "f")
put(16, 47, "g")
put(16, 48, "g")
# Irondeep -> Ashen Desert and Whisperwood <-> Ashen Desert.
put(100, 47, "g")
put(100, 48, "g")
put(63, 80, "g")
put(64, 80, "g")
gates = [
    {"id": "gate_irondeep", "name": "Eastern Pass", "a": [63, 25], "b": [64, 25], "regions": ["greenvale", "irondeep"]},
    {"id": "gate_whisperwood", "name": "Whisperwood Trail", "a": [16, 47], "b": [16, 48], "regions": ["greenvale", "whisperwood"]},
    {"id": "gate_ashen_north", "name": "Scorched Stair", "a": [100, 47], "b": [100, 48], "regions": ["irondeep", "ashen_desert"]},
    {"id": "gate_ashen_west", "name": "Dune Gate", "a": [63, 80], "b": [64, 80], "regions": ["whisperwood", "ashen_desert"]},
]

# ======================================================================
# Irondeep Mountains (x 64..127, y 0..47)
# ======================================================================
R = "irondeep"
rect(65, 22, 78, 28, "k")                      # the pass
line(65, 25, 78, 25, "=")
rect(78, 17, 93, 31, "p")                      # Irondeep Hold
for (x0, y0, x1, y1) in [(79, 18, 82, 20), (89, 18, 92, 20), (79, 28, 82, 30), (89, 28, 92, 30)]:
    rect(x0, y0, x1, y1, "H")
# silver galleries (north)
rect(68, 3, 98, 12, "c")
for _ in range(16):
    blob(rng.randint(70, 96), rng.randint(4, 11), 1, 0, "^")
rect(84, 12, 86, 17, "c")                      # tunnel from the hold
line(85, 3, 85, 17, "c")
# underground lake
rect(100, 2, 121, 15, "c")
rect(104, 5, 116, 12, "~")
line(98, 7, 100, 7, "c")
# deep tunnels (east)
rect(94, 23, 99, 26, "k")
line(93, 24, 100, 24, "=")
rect(100, 18, 125, 41, "c")
for _ in range(26):
    blob(rng.randint(103, 123), rng.randint(20, 39), rng.randint(0, 1), rng.randint(0, 1), "^")
rect(100, 23, 104, 26, "c")                    # keep the entrance open
rect(98, 41, 102, 46, "k")                     # descent towards the desert
line(100, 41, 100, 46, "=")
# secret passage: an ancient dwarven tunnel from the galleries to the deep tunnels
secret_irondeep = [(99, y) for y in range(13, 19)] + [(98, 12)]
for (x, y) in secret_irondeep:
    put(x, y, "Q")

locations += [
    {"id": "irondeep_hold", "name": "Irondeep Hold", "kind": "village", "rect": [77, 16, 18, 17], "region": R},
    {"id": "silver_galleries", "name": "Silver Galleries", "kind": "resource_area", "rect": [67, 2, 33, 12], "region": R},
    {"id": "underground_lake", "name": "Underground Lake", "kind": "resource_area", "rect": [100, 1, 22, 16], "region": R},
    {"id": "deep_tunnels", "name": "Deep Tunnels", "kind": "resource_area", "rect": [100, 17, 26, 13], "region": R},
    {"id": "golem_halls", "name": "Golem Halls", "kind": "hunting_ground", "rect": [100, 30, 26, 12], "region": R},
    {"id": "bat_roost", "name": "Bat Roost", "kind": "hunting_ground", "rect": [67, 2, 16, 12], "region": R},
]
for (x, y) in scatter(5, 86, 4, 97, 11, "c", 3, taken):
    node("silver_rock", x, y, R)
for (x, y) in scatter(6, 69, 4, 84, 11, "c", 3, taken):
    node("coal_rock", x, y, R)
for (x, y) in [(104, 6), (104, 10), (110, 12), (116, 7), (116, 11), (110, 5)]:
    node("cave_eel_spot", x, y, R)
for (x, y) in scatter(5, 103, 18, 124, 28, "c", 4, taken):
    node("mithril_rock", x, y, R)
for (x, y) in scatter(3, 103, 18, 124, 28, "c", 4, taken):
    node("gem_rock", x, y, R)
for (x, y) in scatter(3, 103, 18, 124, 28, "c", 4, taken):
    node("coal_rock", x, y, R)
hidden_gem = node("gem_rock", 92, 4, R, hidden=True)
put(92, 4, "c")
for (x, y) in scatter(5, 69, 3, 82, 11, "c", 3, taken):
    enemy("cave_bat", x, y, R)
for (x, y) in scatter(5, 103, 31, 124, 40, "c", 4, taken):
    enemy("rock_golem", x, y, R)
for (x, y) in scatter(3, 103, 31, 124, 40, "c", 5, taken):
    enemy("stone_troll", x, y, R)

# ======================================================================
# Whisperwood (x 0..63, y 48..95)
# ======================================================================
R = "whisperwood"
rect(1, 48, 62, 94, "f")
for _ in range(70):
    blob(rng.randint(2, 61), rng.randint(50, 93), rng.randint(0, 2), rng.randint(0, 1), "e")
for _ in range(18):
    blob(rng.randint(4, 58), rng.randint(52, 90), rng.randint(1, 3), rng.randint(1, 2), "m", only="f")
line(16, 48, 16, 58, "=")                      # trail from the gate
line(16, 58, 30, 58, "=")
rect(24, 57, 40, 69, "m")                      # Druid Grove
for (x0, y0, x1, y1) in [(25, 58, 27, 60), (37, 58, 39, 60), (25, 66, 27, 68)]:
    rect(x0, y0, x1, y1, "H")
blob(10, 70, 5, 4, "m")                        # Moonwell
blob(10, 70, 3, 2, "~")
line(14, 70, 24, 70, "=")
rect(40, 50, 60, 60, "f")                      # maple grove
line(40, 62, 40, 62, "=")
line(32, 62, 46, 62, "=")
line(46, 55, 46, 62, "=")
rect(40, 77, 60, 92, "c")                      # mushroom caves
for _ in range(14):
    blob(rng.randint(42, 58), rng.randint(79, 90), 1, 0, "^")
line(32, 69, 32, 80, "=")
line(32, 80, 63, 80, "=")
rect(3, 80, 26, 93, "f")                       # yew thicket
for _ in range(10):
    blob(rng.randint(5, 24), rng.randint(82, 92), 1, 1, "e")
line(8, 76, 32, 76, "=")
line(8, 76, 8, 81, "=")
put(63, 80, "g")
# secret trail: a ranger-only shortcut between the maple grove and the mushroom caves
secret_whisperwood = [(58, y) for y in range(61, 77)]
for (x, y) in secret_whisperwood:
    put(x, y, "q")
# keep a hard edge so the secret trail is the only shortcut
for y in range(61, 77):
    for x in (57, 59):
        put(x, y, "e")

locations += [
    {"id": "druid_grove", "name": "Druid Grove", "kind": "village", "rect": [23, 56, 19, 15], "region": R},
    {"id": "maple_grove", "name": "Maple Grove", "kind": "resource_area", "rect": [40, 49, 22, 12], "region": R},
    {"id": "moonwell", "name": "Moonwell", "kind": "resource_area", "rect": [4, 65, 13, 11], "region": R},
    {"id": "mushroom_caves", "name": "Mushroom Caves", "kind": "resource_area", "rect": [40, 77, 22, 17], "region": R},
    {"id": "yew_thicket", "name": "Yew Thicket", "kind": "resource_area", "rect": [2, 79, 26, 16], "region": R},
    {"id": "spirit_glades", "name": "Spirit Glades", "kind": "hunting_ground", "rect": [2, 49, 20, 14], "region": R},
    {"id": "wolfsong_ridge", "name": "Wolfsong Ridge", "kind": "hunting_ground", "rect": [42, 63, 14, 13], "region": R},
    {"id": "rotting_heart", "name": "Rotting Heart", "kind": "hunting_ground", "rect": [2, 84, 24, 11], "region": R},
]
for (x, y) in scatter(8, 41, 50, 56, 60, "f", 3, taken):
    node("maple_tree", x, y, R)
for (x, y) in scatter(5, 4, 80, 25, 88, "f", 4, taken):
    node("yew_tree", x, y, R)
for (x, y) in [(8, 70), (12, 70), (10, 69)]:
    node("moonfish_spot", x, y, R)
for (x, y) in scatter(5, 42, 78, 59, 91, "c", 3, taken):
    node("glowcap_mushroom", x, y, R)
for (x, y) in scatter(6, 3, 52, 38, 75, "m", 3, taken):
    node("ranarr_patch", x, y, R)
for (x, y) in scatter(4, 3, 50, 20, 62, "fm", 4, taken):
    enemy("forest_spirit", x, y, R)
for (x, y) in scatter(5, 43, 64, 55, 75, "fm", 3, taken):
    enemy("enchanted_wolf", x, y, R)
for (x, y) in scatter(3, 3, 89, 25, 93, "fm", 4, taken):
    enemy("corrupted_treant", x, y, R)

# ======================================================================
# Ashen Desert (x 64..127, y 48..95)
# ======================================================================
R = "ashen_desert"
rect(65, 49, 126, 94, "d")
for _ in range(40):
    blob(rng.randint(66, 125), rng.randint(50, 93), rng.randint(1, 3), rng.randint(1, 2), "s", only="d")
line(100, 48, 100, 60, "=")                    # scorched stair down to the oasis
line(65, 80, 86, 80, "=")
line(86, 64, 86, 80, "=")
rect(86, 58, 97, 70, "p")                      # Sunwell Oasis
for (x0, y0, x1, y1) in [(87, 59, 89, 61), (94, 59, 96, 61), (87, 67, 89, 69)]:
    rect(x0, y0, x1, y1, "H")
blob(103, 65, 6, 5, ".")
blob(103, 65, 3, 3, "~")
line(97, 64, 98, 64, "=")
# old ruins (north-west)
rect(66, 50, 84, 64, "r")
for _ in range(22):
    x, y = rng.randint(67, 83), rng.randint(51, 63)
    if rng.random() < 0.5:
        line(x, y, x + rng.randint(1, 3), y, "R")
    else:
        line(x, y, x, y + rng.randint(1, 3), "R")
line(84, 58, 86, 58, "=")
# rocky mesa (south-west)
rect(68, 83, 84, 93, "k")
for _ in range(10):
    blob(rng.randint(69, 83), rng.randint(84, 92), 1, 1, "^")
line(76, 80, 76, 83, "=")
# buried city (south-east)
rect(104, 76, 126, 94, "r")
for xx in range(106, 126, 5):
    line(xx, 78, xx, 81, "R")
    line(xx, 88, xx, 91, "R")
line(97, 70, 97, 84, "=")
line(97, 84, 104, 84, "=")
# dunes of the east: sand wyrms
locations += [
    {"id": "sunwell_oasis", "name": "Sunwell Oasis", "kind": "village", "rect": [85, 57, 26, 15], "region": R},
    {"id": "old_ruins", "name": "Old Ruins", "kind": "resource_area", "rect": [65, 49, 21, 17], "region": R},
    {"id": "red_mesa", "name": "Red Mesa", "kind": "resource_area", "rect": [67, 82, 19, 13], "region": R},
    {"id": "buried_city", "name": "Buried City", "kind": "resource_area", "rect": [103, 75, 24, 20], "region": R},
    {"id": "raider_camp", "name": "Raider Camp", "kind": "hunting_ground", "rect": [65, 66, 20, 13], "region": R},
    {"id": "wyrm_dunes", "name": "Wyrm Dunes", "kind": "hunting_ground", "rect": [108, 49, 19, 24], "region": R},
    {"id": "guardian_court", "name": "Guardian Court", "kind": "hunting_ground", "rect": [103, 75, 24, 20], "region": R},
]
for (x, y) in scatter(6, 67, 51, 83, 63, "r", 3, taken):
    node("dig_site", x, y, R)
for (x, y) in scatter(4, 105, 76, 125, 86, "r", 4, taken):
    node("buried_cache", x, y, R)
for (x, y) in scatter(3, 105, 87, 125, 93, "r", 4, taken):
    node("royal_dig_site", x, y, R)
for (x, y) in scatter(4, 69, 84, 83, 92, "k", 3, taken):
    node("adamantite_rock", x, y, R)
for (x, y) in scatter(2, 69, 84, 83, 92, "k", 4, taken):
    node("sunstone_rock", x, y, R)
for (x, y) in [(100, 65), (106, 65), (103, 62)]:
    node("oasis_carp_spot", x, y, R)
for (x, y) in scatter(5, 66, 67, 84, 78, "ds", 3, taken):
    enemy("desert_raider", x, y, R)
for (x, y) in scatter(4, 110, 50, 125, 71, "ds", 4, taken):
    enemy("sand_wyrm", x, y, R)
for (x, y) in scatter(4, 105, 76, 125, 93, "r", 4, taken):
    enemy("ancient_guardian", x, y, R)

# ======================================================================
# Outposts, stations, dungeon entrances
# ======================================================================
outposts = [
    {"building": "outpost_irondeep", "rect": [84, 18, 4, 3], "work_tile": [85, 21], "depot_tile": [86, 24],
     "stations": [{"id": "furnace_irondeep", "type": "furnace", "name": "Dwarven Furnace", "tile": [80, 24]},
                  {"id": "anvil_irondeep", "type": "anvil", "name": "Dwarven Anvil", "tile": [82, 24]}]},
    {"building": "outpost_whisperwood", "rect": [30, 58, 4, 3], "work_tile": [31, 61], "depot_tile": [32, 64],
     "stations": [{"id": "range_whisperwood", "type": "range", "name": "Druid Hearth", "tile": [28, 64]},
                  {"id": "alchemy_whisperwood", "type": "alchemy_table", "name": "Druid Still", "tile": [36, 64]}]},
    {"building": "outpost_ashen", "rect": [90, 59, 3, 3], "work_tile": [91, 62], "depot_tile": [92, 64],
     "stations": [{"id": "workbench_ashen", "type": "workbench", "name": "Oasis Workbench", "tile": [88, 64]},
                  {"id": "furnace_ashen", "type": "furnace", "name": "Sun Furnace", "tile": [95, 64]}]},
]
for op in outposts:
    x, y, w, h = op["rect"]
    rect(x, y, x + w - 1, y + h - 1, "p")
    plots.append({"building": op["building"], "rect": op["rect"], "work_tile": op["work_tile"]})
    for st in op["stations"]:
        st = dict(st)
        st["outpost"] = op["building"]
        stations.append(st)
dungeons = [
    {"id": "goblin_warren", "tile": [58, 46], "region": "greenvale"},
    {"id": "deepforge_vault", "tile": [124, 40], "region": "irondeep"},
    {"id": "heartrot_hollow", "tile": [3, 93], "region": "whisperwood"},
    {"id": "tomb_of_the_sand_king", "tile": [125, 93], "region": "ashen_desert"},
]
for dg in dungeons:
    x, y = dg["tile"]
    if dg["region"] != "greenvale":
        put(x, y, "c" if dg["region"] != "ashen_desert" else "r")

# ======================================================================
# Discoveries (fog of war rewards)
# ======================================================================
# requires: exploration level, and optionally a combat specialty or affinity
# (character-specific discoveries). rewards are granted once.
discoveries = [
    # Greenvale
    {"id": "old_watchtower", "name": "Old Watchtower", "kind": "ruin", "tile": [33, 9], "region": "greenvale", "requires": {"exploration": 1},
     "rewards": {"xp": {"exploration": 120}, "currencies": {"gold": 80}}, "description": "A crumbling tower overlooking the upper river."},
    {"id": "forest_shrine", "name": "Forgotten Forest Shrine", "kind": "shrine", "tile": [11, 22], "region": "greenvale", "requires": {"exploration": 1},
     "rewards": {"xp": {"exploration": 150}, "currencies": {"recruitment_tokens": 2}}, "description": "Moss-covered stones still hum faintly."},
    {"id": "smugglers_cache", "name": "Smuggler's Cache", "kind": "chest", "tile": [60, 46], "region": "greenvale", "requires": {"exploration": 5, "specialty": "assassin"},
     "rewards": {"xp": {"exploration": 200}, "currencies": {"gold": 400, "gems": 20}}, "description": "Only a sharp-eyed rogue would notice the loose stones."},
    {"id": "river_spirit_stone", "name": "River Spirit Stone", "kind": "magic", "tile": [30, 44], "region": "greenvale", "requires": {"exploration": 5, "specialty": "mage"},
     "rewards": {"xp": {"exploration": 200, "magic": 300}, "items": {"river_pearl": 2}}, "description": "A mage feels the stone's pull."},
    {"id": "abandoned_shaft", "name": "Abandoned Mine Shaft", "kind": "cave", "tile": [60, 13], "region": "greenvale", "requires": {"exploration": 3, "affinity": "mining"},
     "rewards": {"xp": {"exploration": 200, "mining": 250}, "items": {"iron_ore": 25}}, "description": "A miner recognises old tool marks."},
    {"id": "meadow_ring", "name": "Fairy Ring", "kind": "magic", "tile": [59, 35], "region": "greenvale", "requires": {"exploration": 1},
     "rewards": {"xp": {"exploration": 100}, "currencies": {"gems": 10}}, "description": "Mushrooms in a perfect circle."},
    # Irondeep
    {"id": "dwarven_tunnel", "name": "Ancient Dwarven Tunnel", "kind": "secret_passage", "tile": [98, 13], "region": "irondeep",
     "requires": {"exploration": 10, "affinity": "mining"}, "rewards": {"xp": {"exploration": 600}, "reveal_secret": "irondeep_tunnel"},
     "description": "A miner finds a sealed tunnel linking the galleries to the deep mines."},
    {"id": "hidden_gem_vein", "name": "Hidden Gem Vein", "kind": "hidden_node", "tile": [92, 5], "region": "irondeep", "requires": {"exploration": 25},
     "rewards": {"xp": {"exploration": 500}, "reveal_node": hidden_gem}, "description": "Glittering rock behind a fallen slab."},
    {"id": "dwarven_cache", "name": "Dwarven Supply Cache", "kind": "chest", "tile": [70, 10], "region": "irondeep", "requires": {"exploration": 12},
     "rewards": {"xp": {"exploration": 400}, "items": {"steel_bar": 10, "cooked_trout": 20}, "currencies": {"gold": 600}}, "description": "Provisions left for travellers."},
    {"id": "lake_shrine", "name": "Lakeside Shrine", "kind": "shrine", "tile": [118, 3], "region": "irondeep", "requires": {"exploration": 15},
     "rewards": {"xp": {"exploration": 500}, "currencies": {"recruitment_tokens": 5}}, "description": "A shrine to the deep waters."},
    {"id": "golem_forge", "name": "Ruined Golem Forge", "kind": "ruin", "tile": [113, 41], "region": "irondeep", "requires": {"exploration": 20, "specialty": "mage"},
     "rewards": {"xp": {"exploration": 700, "magic": 800}, "items": {"uncut_sapphire": 3}}, "description": "Runes only a mage can read."},
    # Whisperwood
    {"id": "lost_camp", "name": "Fenwick's Lost Camp", "kind": "npc", "tile": [12, 63], "region": "whisperwood", "requires": {"exploration": 15},
     "rewards": {"xp": {"exploration": 800}, "character": "fenwick_the_lost"}, "description": "A cold campfire, a hand-drawn map, and a very lost explorer."},
    {"id": "ranger_trail", "name": "Hidden Ranger Trail", "kind": "secret_passage", "tile": [56, 61], "region": "whisperwood",
     "requires": {"exploration": 15, "specialty": "ranger"}, "rewards": {"xp": {"exploration": 600}, "reveal_secret": "whisperwood_trail"},
     "description": "Bent twigs mark a trail through the thicket."},
    {"id": "moonwell_altar", "name": "Moonwell Altar", "kind": "magic", "tile": [10, 66], "region": "whisperwood", "requires": {"exploration": 18},
     "rewards": {"xp": {"exploration": 600}, "items": {"moonfish": 5}, "currencies": {"gems": 30}}, "description": "Moonlight pools on the altar stone."},
    {"id": "druid_circle", "name": "Druid Circle", "kind": "ruin", "tile": [20, 90], "region": "whisperwood", "requires": {"exploration": 22},
     "rewards": {"xp": {"exploration": 700, "herblore": 500}, "items": {"ranarr": 10}}, "description": "Standing stones wrapped in roots."},
    {"id": "spore_hoard", "name": "Spore Hoard", "kind": "chest", "tile": [60, 91], "region": "whisperwood", "requires": {"exploration": 20, "specialty": "assassin"},
     "rewards": {"xp": {"exploration": 600}, "currencies": {"gold": 1500, "gems": 40}}, "description": "Someone hid their savings in the mushrooms."},
    # Ashen Desert
    {"id": "sunken_obelisk", "name": "Sunken Obelisk", "kind": "magic", "tile": [80, 52], "region": "ashen_desert", "requires": {"exploration": 25, "specialty": "mage"},
     "rewards": {"xp": {"exploration": 1000, "magic": 1500}, "items": {"sunstone": 1}}, "description": "Half-buried glyphs glow at dusk."},
    {"id": "caravan_wreck", "name": "Caravan Wreck", "kind": "chest", "tile": [92, 88], "region": "ashen_desert", "requires": {"exploration": 25},
     "rewards": {"xp": {"exploration": 900}, "currencies": {"gold": 2500}, "items": {"cooked_carp": 20}}, "description": "Bleached wagons, half full."},
    {"id": "kings_road", "name": "The King's Road", "kind": "ruin", "tile": [110, 74], "region": "ashen_desert", "requires": {"exploration": 30},
     "rewards": {"xp": {"exploration": 1200, "archaeology": 1500}, "currencies": {"recruitment_tokens": 8}}, "description": "Paving stones lead to the buried city."},
    {"id": "tomb_robbers_stash", "name": "Tomb Robber's Stash", "kind": "chest", "tile": [124, 77], "region": "ashen_desert", "requires": {"exploration": 30, "specialty": "assassin"},
     "rewards": {"xp": {"exploration": 1000}, "currencies": {"gems": 80}, "items": {"golden_idol": 1}}, "description": "Rogues leave marks for other rogues."},
]
secrets = [
    {"id": "irondeep_tunnel", "tiles": [list(t) for t in secret_irondeep], "region": "irondeep", "reveals_as": "c"},
    {"id": "whisperwood_trail", "tiles": [list(t) for t in secret_whisperwood], "region": "whisperwood", "reveals_as": "m"},
]

# ======================================================================
# Regions
# ======================================================================
regions = [
    {"id": "greenvale", "name": "Greenvale", "rect": [0, 0, 64, 48], "level_range": [1, 25], "color": "#6fae4f",
     "description": "The starting valley: a riverside village, an oak forest and a small copper mine.",
     "waystone": [44, 28], "unlocked_by_default": True},
    {"id": "irondeep", "name": "Irondeep Mountains", "rect": [64, 0, 64, 48], "level_range": [20, 55], "color": "#9aa3ab",
     "description": "Dwarven halls, silver galleries and an underground lake beneath the peaks.",
     "outpost": "outpost_irondeep",
     "unlock": {"conditions": [{"type": "quest", "quest": "mq_02_eastern_pass"}, {"type": "skill", "skill": "mining", "level": 20},
                               {"type": "explored", "region": "greenvale", "pct": 0.35}], "cost": {"gold": 500}}},
    {"id": "whisperwood", "name": "Whisperwood", "rect": [0, 48, 64, 48], "level_range": [25, 60], "color": "#7a5ab0",
     "description": "An enchanted forest of ancient trees, spirit glades and mushroom caves.",
     "outpost": "outpost_whisperwood",
     "unlock": {"conditions": [{"type": "quest", "quest": "mq_04_whispers"}, {"type": "skill", "skill": "woodcutting", "level": 30},
                               {"type": "explored", "region": "greenvale", "pct": 0.5}], "cost": {"gold": 2000}}},
    {"id": "ashen_desert", "name": "Ashen Desert", "rect": [64, 48, 64, 48], "level_range": [40, 75], "color": "#d8a85a",
     "description": "Sand dunes over a buried kingdom: ruins, tombs and rare minerals.",
     "outpost": "outpost_ashen",
     "unlock": {"conditions": [{"type": "quest", "quest": "mq_06_into_the_sands"}, {"type": "character_level", "level": 30},
                               {"type": "explored", "region": "irondeep", "pct": 0.3}], "cost": {"gold": 6000}}},
]
for op in outposts:
    for r in regions:
        if r.get("outpost") == op["building"]:
            r["outpost_depot"] = op["depot_tile"]
            r["outpost_rect"] = op["rect"]

# ======================================================================
# Borders: make sure regions only touch through gates
# ======================================================================
gate_tiles = {tuple(t) for gt in gates for t in (gt["a"], gt["b"])}
for x in range(W):
    for y in (47, 48):
        if (x, y) not in gate_tiles and x >= 64:
            put(x, y, "^")
        if (x, y) not in gate_tiles and x < 64 and y == 48:
            put(x, y, "e")
for y in range(H):
    for x in (63, 64):
        if (x, y) not in gate_tiles and y >= 48:
            put(x, y, "e" if x == 63 else "^")
        if (x, y) not in gate_tiles and y < 48 and x == 64:
            put(x, y, "^")
for x in range(W):
    if (x, 95) not in gate_tiles:
        put(x, 95, "e" if x < 64 else "^")
    if x >= 64:
        put(x, 0, "^")
for y in range(H):
    put(127, y, "^")
    if y >= 48:
        put(0, y, "e")
# gate approaches must stay open after the border pass
put(62, 80, "=")
put(65, 80, "=")
put(65, 25, "=")
put(16, 49, "=")
put(100, 49, "=")
put(100, 46, "=")

# ======================================================================
# Validation
# ======================================================================
block = {tuple(n["tile"]) for n in nodes} | {tuple(s["tile"]) for s in stations} | {tuple(e["tile"]) for e in enemies}
block |= {tuple(green["storage"]["tile"])} | {tuple(op["depot_tile"]) for op in outposts} | {tuple(d["tile"]) for d in dungeons}
secret_tiles = {tuple(t) for s in secrets for t in s["tiles"]}


def walkable(x, y):
    return 0 <= x < W and 0 <= y < H and g[y][x] in WALKABLE and (x, y) not in block and (x, y) not in secret_tiles


start = tuple(green["spawn_tile"])
seen = {start}
q = deque([start])
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


bad = [o for o in nodes + stations + enemies if not reachable_adjacent(tuple(o["tile"]))]
bad += [d for d in dungeons if not reachable_adjacent(tuple(d["tile"]))]
bad += [op for op in outposts if not reachable_adjacent(tuple(op["depot_tile"])) or tuple(op["work_tile"]) not in seen]
bad += [d for d in discoveries if not any(abs(d["tile"][0] - x) <= 2 and abs(d["tile"][1] - y) <= 2 for (x, y) in seen if abs(d["tile"][0] - x) <= 2)]
bad += [p for p in plots if tuple(p["work_tile"]) not in seen]
assert not bad, f"unreachable: {bad}"
for gt in gates:
    for t in (gt["a"], gt["b"]):
        assert tuple(t) in seen, f"gate tile unreachable {gt}"
for s in secrets:
    for t in s["tiles"]:
        assert g[t[1]][t[0]] in "Qq", s
for r in regions:
    rx, ry, rw, rh = r["rect"]
    cnt = sum(1 for (x, y) in seen if rx <= x < rx + rw and ry <= y < ry + rh)
    assert cnt > 300, f"region {r['id']} has only {cnt} reachable tiles"

out = {
    "schema_version": 3,
    "id": "world",
    "name": "Worldbound",
    "description": "The connected world: Greenvale, Irondeep Mountains, Whisperwood and the Ashen Desert.",
    "width": W,
    "height": H,
    "rows": ["".join(r) for r in g],
    "spawn_tile": green["spawn_tile"],
    "storage": green["storage"],
    "regions": regions,
    "gates": gates,
    "locations": locations,
    "resource_nodes": nodes,
    "stations": stations,
    "enemy_spawns": enemies,
    "building_plots": plots,
    "outposts": outposts,
    "dungeon_entrances": dungeons,
    "discoveries": discoveries,
    "secrets": secrets,
}
path = ROOT / "data" / "regions" / "world_map.json"
path.write_text(json.dumps(out, indent=1))
print(f"wrote {path}: {len(nodes)} nodes, {len(enemies)} enemy spawns, {len(discoveries)} discoveries, {len(seen)} reachable tiles")
