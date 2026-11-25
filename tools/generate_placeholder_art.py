#!/usr/bin/env python3
"""Generates Worldbound's placeholder pixel art.

Every placeholder lives at the exact path final art will use (see
docs/TECHNICAL_ARCHITECTURE.md "Asset pipeline"), with the same dimensions and
layout, so artists can overwrite files one by one without code changes.

Standards used here (and required of final art):
  * Tiles: 32x32 px, atlas assets/environments/tiles/greenvale_tiles.png,
    8 columns, coordinates referenced from data/regions/terrain.json.
  * Water: 4 animation frames on atlas row 2.
  * Characters: 128x128 sheet = 4 frames x 4 directions (down, left, right, up)
    of 32x32. Frame 0 doubles as idle.
  * Portraits: 64x64. Item icons: 32x32. Resource nodes: 32x32 (trees 32x48).

Usage: python3 tools/generate_placeholder_art.py   (deterministic)
"""
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
T = 32
rng = random.Random(42)


def hexrgb(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3] if len(c) > 3 else 255,)


def noise_tile(base, var=0.08, speck=None, speck_n=0):
    im = Image.new("RGBA", (T, T), base)
    px = im.load()
    for y in range(T):
        for x in range(T):
            f = 1.0 + rng.uniform(-var, var)
            px[x, y] = shade(base, f)
    if speck:
        for _ in range(speck_n):
            x, y = rng.randrange(T), rng.randrange(T)
            px[x, y] = speck
    return im


def save(im, rel):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    im.save(p)


# ---------------------------------------------------------------- tiles ----
GRASS = hexrgb("#4f8a3c")
atlas = Image.new("RGBA", (T * 8, T * 4), (0, 0, 0, 0))


def put_tile(im, cx, cy):
    atlas.paste(im, (cx * T, cy * T))


grass = noise_tile(GRASS, 0.07, hexrgb("#6fae4f"), 18)
d = ImageDraw.Draw(grass)
for _ in range(6):
    x, y = rng.randrange(2, 30), rng.randrange(3, 30)
    d.line([(x, y), (x, y - 2)], fill=hexrgb("#3d6e2e"))
put_tile(grass, 0, 0)

meadow = noise_tile(hexrgb("#5a9443"), 0.07, hexrgb("#7cbc58"), 14)
d = ImageDraw.Draw(meadow)
for col in ("#f2e86b", "#f4f4f4", "#e889c9"):
    for _ in range(3):
        x, y = rng.randrange(2, 30), rng.randrange(2, 30)
        d.point([(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)], fill=hexrgb(col))
put_tile(meadow, 1, 0)

road = noise_tile(hexrgb("#a88a5c"), 0.06, hexrgb("#8b7048"), 30)
d = ImageDraw.Draw(road)
for _ in range(5):
    x, y = rng.randrange(1, 30), rng.randrange(1, 30)
    d.rectangle([x, y, x + 1, y + 1], fill=hexrgb("#c2a676"))
put_tile(road, 2, 0)

forest = noise_tile(hexrgb("#3b6b30"), 0.08, hexrgb("#2c5224"), 40)
d = ImageDraw.Draw(forest)
for _ in range(4):
    x, y = rng.randrange(2, 28), rng.randrange(2, 28)
    d.ellipse([x, y, x + 3, y + 2], fill=hexrgb("#6b4a2a"))
put_tile(forest, 3, 0)

dense = noise_tile(hexrgb("#2c5224"), 0.05)
d = ImageDraw.Draw(dense)
for (cx, cy, r) in [(8, 10, 9), (23, 9, 9), (16, 22, 10), (4, 26, 6), (28, 25, 6)]:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexrgb("#1f4a1d"))
    d.ellipse([cx - r + 2, cy - r + 1, cx + r - 3, cy + r - 4], fill=hexrgb("#2f6a2a"))
    d.ellipse([cx - r + 4, cy - r + 2, cx, cy - 1], fill=hexrgb("#3f8236"))
put_tile(dense, 4, 0)


def water_frame(i):
    im = noise_tile(hexrgb("#2f6fa8"), 0.04)
    d = ImageDraw.Draw(im)
    for k in range(5):
        y = (k * 7 + i * 2) % T
        x = (k * 11 + i * 3) % T
        d.line([(x, y), (x + 5, y)], fill=hexrgb("#6aa8d8"))
        d.line([(x + 1, y + 1), (x + 4, y + 1)], fill=hexrgb("#4a8cc4"))
    return im


put_tile(water_frame(0), 5, 0)
for i in range(4):
    put_tile(water_frame(i), i, 2)

bridge = noise_tile(hexrgb("#8a6239"), 0.05)
d = ImageDraw.Draw(bridge)
for y in range(0, T, 6):
    d.line([(0, y), (T, y)], fill=hexrgb("#5e3f22"))
d.rectangle([0, 0, 2, T], fill=hexrgb("#4a3019"))
d.rectangle([T - 3, 0, T, T], fill=hexrgb("#4a3019"))
put_tile(bridge, 6, 0)

mountain = noise_tile(hexrgb("#6d6a66"), 0.08, hexrgb("#55524e"), 40)
d = ImageDraw.Draw(mountain)
d.polygon([(0, 31), (10, 6), (18, 18), (24, 4), (31, 31)], fill=hexrgb("#7d7974"))
d.polygon([(10, 6), (13, 12), (8, 12)], fill=hexrgb("#e8e8ea"))
d.polygon([(24, 4), (27, 11), (21, 11)], fill=hexrgb("#e8e8ea"))
d.line([(0, 31), (10, 6), (18, 18), (24, 4), (31, 31)], fill=hexrgb("#4b4844"))
put_tile(mountain, 7, 0)

cave = noise_tile(hexrgb("#4a4038"), 0.08, hexrgb("#3a322b"), 40)
put_tile(cave, 0, 1)

building = noise_tile(hexrgb("#8c4a32"), 0.04)
d = ImageDraw.Draw(building)
for y in range(0, T, 5):
    d.line([(0, y), (T, y)], fill=hexrgb("#6e3424"))
    for x in range((y // 5 % 2) * 4, T, 8):
        d.line([(x, y), (x, y + 4)], fill=hexrgb("#6e3424"))
d.rectangle([0, 0, T - 1, T - 1], outline=hexrgb("#4a2216"))
put_tile(building, 1, 1)

plaza = noise_tile(hexrgb("#9c968a"), 0.05)
d = ImageDraw.Draw(plaza)
for y in range(0, T, 8):
    d.line([(0, y), (T, y)], fill=hexrgb("#7d776c"))
    off = 0 if (y // 8) % 2 == 0 else 8
    for x in range(off, T, 16):
        d.line([(x, y), (x, y + 8)], fill=hexrgb("#7d776c"))
put_tile(plaza, 2, 1)

sand = noise_tile(hexrgb("#c9b37a"), 0.06, hexrgb("#b39c62"), 25)
put_tile(sand, 3, 1)

farm = noise_tile(hexrgb("#6e4a2c"), 0.05)
d = ImageDraw.Draw(farm)
for y in range(3, T, 8):
    d.line([(0, y), (T, y)], fill=hexrgb("#553820"))
    for x in range(2, T, 5):
        d.line([(x, y - 2), (x, y)], fill=hexrgb("#7fbf4f"))
put_tile(farm, 4, 1)

fence = grass.copy()
d = ImageDraw.Draw(fence)
d.rectangle([0, 13, T, 15], fill=hexrgb("#8a6239"))
d.rectangle([0, 20, T, 22], fill=hexrgb("#8a6239"))
for x in (3, 15, 27):
    d.rectangle([x, 9, x + 2, 26], fill=hexrgb("#6b4a2a"))
put_tile(fence, 5, 1)
save(atlas, "assets/environments/tiles/greenvale_tiles.png")

# ---------------------------------------------------------- resource nodes ----


def rock(base, ore):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([3, 22, 29, 31], fill=(0, 0, 0, 70))
    d.polygon([(4, 26), (7, 10), (15, 5), (25, 8), (29, 20), (26, 28), (8, 29)], fill=base)
    d.polygon([(7, 10), (15, 5), (25, 8), (18, 13)], fill=shade(base, 1.25))
    d.line([(4, 26), (7, 10), (15, 5), (25, 8), (29, 20), (26, 28), (8, 29), (4, 26)], fill=shade(base, 0.6))
    if ore:
        for (x, y) in [(10, 15), (19, 18), (14, 23), (22, 12)]:
            d.rectangle([x, y, x + 2, y + 2], fill=ore)
            d.point([(x, y)], fill=shade(ore, 1.4))
    return im


save(rock(hexrgb("#7a7470"), hexrgb("#d9763a")), "assets/resources/nodes/copper_rock.png")
save(rock(hexrgb("#7a7470"), hexrgb("#c8cdd2")), "assets/resources/nodes/tin_rock.png")
save(rock(hexrgb("#5d5854"), None), "assets/resources/nodes/rock_depleted.png")

tree = Image.new("RGBA", (T, 48), (0, 0, 0, 0))
d = ImageDraw.Draw(tree)
d.ellipse([5, 40, 27, 47], fill=(0, 0, 0, 80))
d.rectangle([13, 28, 18, 44], fill=hexrgb("#6b4a2a"))
d.line([(13, 28), (13, 44)], fill=hexrgb("#4a3019"))
for (cx, cy, r, col) in [(16, 18, 13, "#2f6a2a"), (10, 14, 8, "#3a7d32"), (21, 12, 8, "#3a7d32"), (15, 8, 7, "#4b9440"), (12, 6, 3, "#6bb85a")]:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexrgb(col))
save(tree, "assets/resources/nodes/oak_tree.png")

stump = Image.new("RGBA", (T, 48), (0, 0, 0, 0))
d = ImageDraw.Draw(stump)
d.ellipse([7, 40, 25, 47], fill=(0, 0, 0, 70))
d.rectangle([11, 34, 21, 43], fill=hexrgb("#6b4a2a"))
d.ellipse([11, 31, 21, 37], fill=hexrgb("#c9a26b"))
d.ellipse([14, 33, 18, 35], outline=hexrgb("#8a6239"))
save(stump, "assets/resources/nodes/tree_stump.png")

for name, active in (("fishing_spot", True), ("fishing_spot_calm", False)):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if active:
        d.ellipse([4, 9, 28, 23], outline=(220, 240, 255, 200), width=2)
        d.ellipse([10, 12, 22, 20], outline=(220, 240, 255, 150))
        for (x, y) in [(8, 6), (22, 5), (25, 24)]:
            d.point([(x, y), (x + 1, y)], fill=(255, 255, 255, 220))
        d.polygon([(14, 15), (19, 13), (19, 17)], fill=(60, 90, 120, 200))
    else:
        d.ellipse([8, 12, 24, 20], outline=(200, 225, 245, 90))
    save(im, f"assets/resources/nodes/{name}.png")

chest = Image.new("RGBA", (T, T), (0, 0, 0, 0))
d = ImageDraw.Draw(chest)
d.ellipse([3, 25, 29, 31], fill=(0, 0, 0, 80))
d.rectangle([4, 12, 28, 28], fill=hexrgb("#8a5a2b"))
d.rectangle([4, 8, 28, 14], fill=hexrgb("#a26b34"))
d.line([(4, 14), (28, 14)], fill=hexrgb("#4a3019"))
for x in (8, 23):
    d.rectangle([x, 8, x + 2, 28], fill=hexrgb("#d6b25e"))
d.rectangle([14, 13, 18, 18], fill=hexrgb("#f1d27a"))
d.rectangle([4, 8, 28, 28], outline=hexrgb("#3a2414"))
save(chest, "assets/environments/props/storage_chest.png")

# ------------------------------------------------------------ item icons ----


def icon(draw_fn, rel):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(im))
    save(im, rel)


def ore_icon(col):
    def f(d):
        d.polygon([(6, 22), (9, 10), (17, 6), (26, 11), (27, 22), (17, 27)], fill=hexrgb("#6d6864"))
        d.polygon([(9, 10), (17, 6), (26, 11), (17, 14)], fill=hexrgb("#8a8580"))
        for (x, y) in [(11, 15), (18, 18), (14, 21), (21, 12)]:
            d.rectangle([x, y, x + 3, y + 3], fill=hexrgb(col))
        d.line([(6, 22), (9, 10), (17, 6), (26, 11), (27, 22), (17, 27), (6, 22)], fill=hexrgb("#3d3a37"))
    return f


icon(ore_icon("#d9763a"), "assets/resources/items/copper_ore.png")
icon(ore_icon("#c8cdd2"), "assets/resources/items/tin_ore.png")


def log_icon(d):
    d.polygon([(4, 20), (22, 6), (28, 12), (10, 26)], fill=hexrgb("#7a532e"))
    d.line([(4, 20), (22, 6)], fill=hexrgb("#4a3019"))
    d.line([(10, 26), (28, 12)], fill=hexrgb("#4a3019"))
    d.ellipse([22, 5, 30, 13], fill=hexrgb("#c9a26b"), outline=hexrgb("#4a3019"))
    d.ellipse([25, 8, 27, 10], outline=hexrgb("#8a6239"))


icon(log_icon, "assets/resources/items/oak_log.png")


def fish_icon(d):
    d.ellipse([5, 11, 23, 21], fill=hexrgb("#8fa9b8"), outline=hexrgb("#3d5566"))
    d.polygon([(22, 16), (29, 10), (29, 22)], fill=hexrgb("#6e8a9c"), outline=hexrgb("#3d5566"))
    d.point([(9, 14)], fill=(20, 20, 20, 255))
    d.line([(8, 18), (18, 18)], fill=hexrgb("#c6d6e0"))


icon(fish_icon, "assets/resources/items/raw_minnow.png")


def quartz(d):
    d.polygon([(16, 3), (25, 12), (16, 29), (7, 12)], fill=(220, 225, 245, 255), outline=hexrgb("#7a80a0"))
    d.polygon([(16, 3), (20, 12), (16, 29), (12, 12)], fill=(245, 248, 255, 255))
    d.line([(7, 12), (25, 12)], fill=hexrgb("#9aa0c0"))


icon(quartz, "assets/resources/items/uncut_quartz.png")


def nest(d):
    d.ellipse([4, 12, 28, 26], fill=hexrgb("#8a6239"), outline=hexrgb("#4a3019"))
    d.ellipse([8, 12, 24, 20], fill=hexrgb("#5e3f22"))
    for x in (11, 16, 20):
        d.ellipse([x - 2, 11, x + 2, 17], fill=hexrgb("#e8e2cf"), outline=hexrgb("#9a927c"))


icon(nest, "assets/resources/items/bird_nest.png")


def pearl(d):
    d.ellipse([7, 7, 25, 25], fill=hexrgb("#efe8f2"), outline=hexrgb("#a89ab0"))
    d.ellipse([11, 10, 16, 15], fill=(255, 255, 255, 255))


icon(pearl, "assets/resources/items/river_pearl.png")

# -------------------------------------------------------------- characters ----
chars = json.loads((ROOT / "data/characters/characters.json").read_text())["characters"]
SKIN = {"Dwarf": "#e0a77a", "Elf": "#f0d2b0", "Human": "#d9a982", "Halfling": "#e6b48c", "Gnome": "#f0c8a0", "Half-orc": "#8fa86a"}
HAIR = {"brom_stonefist": "#b5532a", "sylvara_moonleaf": "#e9e4c8", "tamsin_reed": "#4a3019"}


def draw_char(d, ox, oy, direction, frame, c):
    prim = hexrgb(c["palette"]["primary"])
    sec = hexrgb(c["palette"]["secondary"])
    skin = hexrgb(SKIN.get(c["origin"], "#d9a982"))
    hair = hexrgb(HAIR[c["id"]]) if c["id"] in HAIR else shade(hexrgb(c["palette"]["secondary"]), 0.55)
    dwarf = c["origin"] in ("Dwarf", "Halfling", "Gnome")
    top = 6 if not dwarf else 9
    bob = 1 if frame in (1, 3) else 0
    # shadow
    d.ellipse([ox + 9, oy + 27, ox + 23, oy + 31], fill=(0, 0, 0, 80))
    # legs
    step = {0: (0, 0), 1: (-2, 2), 2: (0, 0), 3: (2, -2)}[frame]
    leg = shade(prim, 0.55)
    if direction in (0, 3):
        d.rectangle([ox + 12, oy + 22, ox + 14, oy + 28 + min(step[0], 0)], fill=leg)
        d.rectangle([ox + 17, oy + 22, ox + 19, oy + 28 + min(step[1], 0)], fill=leg)
    else:
        d.rectangle([ox + 14 + step[0], oy + 22, ox + 16 + step[0], oy + 28], fill=leg)
        d.rectangle([ox + 15 + step[1], oy + 22, ox + 17 + step[1], oy + 28], fill=shade(leg, 0.8))
    # body
    by = oy + top + 8 + bob
    d.rectangle([ox + 10, by, ox + 21, oy + 23 + bob], fill=prim)
    d.rectangle([ox + 10, oy + 19 + bob, ox + 21, oy + 20 + bob], fill=sec)  # belt
    d.line([(ox + 10, by), (ox + 10, oy + 23 + bob)], fill=shade(prim, 0.7))
    # arms
    arm_sw = 1 if frame in (1, 3) else 0
    d.rectangle([ox + 8, by + 1 + arm_sw, ox + 9, by + 8 + arm_sw], fill=shade(prim, 0.85))
    d.rectangle([ox + 22, by + 1 - arm_sw, ox + 23, by + 8 - arm_sw], fill=shade(prim, 0.85))
    # head
    hy = oy + top + bob
    d.rectangle([ox + 11, hy, ox + 20, hy + 8], fill=skin)
    # hair / beard
    if direction == 3:
        d.rectangle([ox + 11, hy, ox + 20, hy + 7], fill=hair)
    else:
        d.rectangle([ox + 11, hy, ox + 20, hy + 2], fill=hair)
        if direction == 1:
            d.rectangle([ox + 18, hy, ox + 20, hy + 6], fill=hair)
        elif direction == 2:
            d.rectangle([ox + 11, hy, ox + 13, hy + 6], fill=hair)
        if c["origin"] == "Elf":
            d.rectangle([ox + 11, hy, ox + 12, hy + 10], fill=hair)
            d.rectangle([ox + 19, hy, ox + 20, hy + 10], fill=hair)
        eye = (30, 24, 20, 255)
        if direction == 0:
            d.point([(ox + 13, hy + 4), (ox + 18, hy + 4)], fill=eye)
        elif direction == 1:
            d.point([(ox + 12, hy + 4)], fill=eye)
        elif direction == 2:
            d.point([(ox + 19, hy + 4)], fill=eye)
        if dwarf and direction != 3:
            d.rectangle([ox + 11, hy + 6, ox + 20, hy + 10], fill=hair)
    if c["origin"] == "Elf" and direction != 3:
        d.point([(ox + 10, hy + 3), (ox + 21, hy + 3)], fill=skin)


for c in chars:
    sheet = Image.new("RGBA", (T * 4, T * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for direction in range(4):
        for frame in range(4):
            draw_char(d, frame * T, direction * T, direction, frame, c)
    save(sheet, f"assets/characters/sprites/{c['id']}.png")
    # portrait: upscale the idle-down frame on a rarity-tinted background
    rar = {"common": "#7d8590", "uncommon": "#4caf50", "rare": "#3d7bd9", "epic": "#9b59d0", "legendary": "#e0a030", "mythic": "#e04a6a"}[c["rarity"]]
    por = Image.new("RGBA", (64, 64), shade(hexrgb(rar), 0.45))
    pd = ImageDraw.Draw(por)
    for r in range(30, 0, -3):
        pd.ellipse([32 - r, 26 - r, 32 + r, 26 + r], fill=shade(hexrgb(rar), 0.45 + (30 - r) / 60))
    head = sheet.crop((4, 0, 28, 24)).resize((48, 48), Image.NEAREST)
    por.alpha_composite(head, (8, 14))
    pd.rectangle([0, 0, 63, 63], outline=hexrgb(rar), width=2)
    save(por, f"assets/characters/portraits/{c['id']}.png")

# ---------------------------------------------------------- tool overlays ----
for name, fn in (
    ("pickaxe", lambda d: (d.line([(4, 28), (22, 10)], fill=hexrgb("#7a532e"), width=3),
                           d.arc([10, 2, 30, 22], 200, 340, fill=hexrgb("#b8bec4"), width=3))),
    ("axe", lambda d: (d.line([(4, 28), (22, 10)], fill=hexrgb("#7a532e"), width=3),
                       d.polygon([(18, 6), (28, 8), (26, 18), (20, 14)], fill=hexrgb("#b8bec4")))),
    ("fishing_rod", lambda d: (d.line([(4, 28), (26, 4)], fill=hexrgb("#8a6239"), width=2),
                               d.line([(26, 4), (30, 20)], fill=(230, 230, 230, 200)))),
):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    fn(ImageDraw.Draw(im))
    save(im, f"assets/equipment/tools/{name}.png")

# ------------------------------------------------------------- skill icons ----
skills = json.loads((ROOT / "data/skills/skills.json").read_text())["skills"]
CAT = {"gathering": "#4f8a3c", "production": "#b5651d", "combat": "#a83232", "utility": "#3d6fb0"}
try:
    font = ImageFont.load_default(size=22)
except TypeError:
    font = ImageFont.load_default()
for s in skills:
    im = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = hexrgb(CAT[s["category"]])
    d.rounded_rectangle([1, 1, 46, 46], 10, fill=shade(col, 0.6), outline=col, width=3)
    label = s["name"][:2]
    bbox = d.textbbox((0, 0), label, font=font)
    d.text(((48 - (bbox[2] - bbox[0])) / 2 - bbox[0], (48 - (bbox[3] - bbox[1])) / 2 - bbox[1]), label, fill=(245, 235, 210, 255), font=font)
    save(im, f"assets/ui/skills/{s['id']}.png")


# ======================================================= Phase 2 content ====
MAT = {"bronze": "#c08a4a", "iron": "#9aa3ab", "oak": "#a0703a", "willow": "#8a9a52", "apprentice": "#a0703a",
       "quartz": "#dfe3f5", "pearl": "#efe8f2", "leather": "#8a5a2b",
       # Phase 3
       "steel": "#7f8a94", "silver": "#d8dde3", "mithril": "#6a8fd0", "adamantite": "#3f8a62", "maple": "#c0884a", "yew": "#6a4a3a",
       "sapphire": "#3a6ad0", "sunstone": "#f0a030", "deepforge": "#c0502a", "heartwood": "#7a3a2a", "explorers": "#c0a060", "trowel": "#9aa3ab"}


def mat_of(item_id):
    for k, v in MAT.items():
        if item_id.startswith(k):
            return hexrgb(v)
    return hexrgb("#9aa3ab")


def draw_item(d, it):
    iid, cat = it["id"], it["category"]
    m = mat_of(iid)
    dark = shade(m, 0.55)
    if cat == "ore":
        ore_icon({"coal_ore": "#2a2a2a", "silver_ore": "#d8dde3", "mithril_ore": "#6a8fd0", "adamantite_ore": "#3f8a62"}.get(iid, "#7a8590"))(d)
    elif cat == "bar":
        d.polygon([(4, 20), (10, 12), (28, 12), (22, 20)], fill=shade(m, 1.2), outline=dark)
        d.polygon([(4, 20), (22, 20), (22, 26), (4, 26)], fill=m, outline=dark)
        d.polygon([(22, 20), (28, 12), (28, 18), (22, 26)], fill=shade(m, 0.8), outline=dark)
    elif cat == "log":
        d.polygon([(4, 20), (22, 6), (28, 12), (10, 26)], fill=shade(m, 0.8))
        d.ellipse([22, 5, 30, 13], fill=shade(m, 1.3), outline=dark)
    elif cat == "plank":
        for i, y in enumerate((8, 15, 22)):
            d.rectangle([4 + i, y, 28 - i, y + 5], fill=shade(m, 1.1 - i * 0.1), outline=dark)
    elif cat in ("fish", "food", "junk"):
        col = {"raw_trout": "#b9a07a", "cooked_minnow": "#c9945a", "cooked_trout": "#b97a3e", "burnt_fish": "#3a3330",
               "baked_potato": "#b98a4a"}.get(iid, "#8fa9b8")
        if "potato" in iid:
            d.ellipse([6, 9, 26, 25], fill=hexrgb(col), outline=shade(hexrgb(col), 0.5))
        else:
            d.ellipse([5, 11, 23, 21], fill=hexrgb(col), outline=shade(hexrgb(col), 0.5))
            d.polygon([(22, 16), (29, 10), (29, 22)], fill=shade(hexrgb(col), 0.8))
    elif cat == "crop":
        d.ellipse([7, 10, 25, 26], fill=hexrgb("#b99a5a"), outline=hexrgb("#6b5530"))
        d.point([(12, 15), (19, 19), (15, 22)], fill=hexrgb("#6b5530"))
    elif cat == "herb":
        col = hexrgb("#4f9a3c" if iid == "guam_leaf" else "#9a5ab0")
        for a in (-1, 0, 1):
            d.ellipse([12 + a * 7, 6 + abs(a) * 4, 20 + a * 7, 22], fill=col, outline=shade(col, 0.5))
        d.line([(16, 30), (16, 12)], fill=hexrgb("#2f5a20"), width=2)
    elif cat == "potion":
        col = hexrgb("#d04a4a" if iid == "healing_potion" else "#4aa0d0")
        d.rectangle([13, 4, 19, 10], fill=hexrgb("#c9a26b"))
        d.ellipse([7, 10, 25, 28], fill=col, outline=hexrgb("#2a2a2a"))
        d.ellipse([10, 13, 15, 18], fill=(255, 255, 255, 140))
    elif cat == "hide":
        d.polygon([(6, 8), (26, 8), (28, 18), (22, 28), (10, 28), (4, 18)], fill=hexrgb("#7a6a5a"), outline=hexrgb("#3a2e22"))
    elif cat == "gem":
        quartz(d)
    else:  # misc: bones, gel, tail, trinket, tooth
        if iid == "bones":
            d.line([(6, 24), (26, 8)], fill=hexrgb("#e8e2cf"), width=4)
            for (x, y) in ((5, 23), (7, 26), (25, 7), (27, 10)):
                d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=hexrgb("#e8e2cf"))
        elif iid == "slime_gel":
            d.ellipse([6, 12, 26, 26], fill=(90, 200, 120, 220), outline=hexrgb("#2a7a4a"))
        elif iid == "rat_tail":
            d.arc([4, 6, 28, 30], 180, 360, fill=hexrgb("#c98a8a"), width=3)
        elif iid == "troll_tooth":
            d.polygon([(12, 4), (22, 6), (18, 28)], fill=hexrgb("#efe6c8"), outline=hexrgb("#8a8270"))
        else:
            d.ellipse([8, 8, 24, 24], fill=hexrgb("#c9a030"), outline=hexrgb("#6a5010"))
            d.rectangle([14, 4, 18, 9], fill=hexrgb("#6a5010"))
    if cat == "equipment":
        slot = it.get("equip_slot", "")
        tool = it.get("tool_skill", "")
        handle = hexrgb("#7a532e")
        if tool == "mining":
            d.line([(4, 28), (22, 10)], fill=handle, width=3)
            d.arc([10, 2, 30, 22], 200, 340, fill=m, width=4)
        elif tool == "woodcutting":
            d.line([(4, 28), (22, 10)], fill=handle, width=3)
            d.polygon([(18, 4), (29, 7), (26, 19), (19, 14)], fill=m, outline=dark)
        elif tool == "fishing":
            d.line([(4, 28), (26, 4)], fill=m, width=3)
            d.line([(26, 4), (30, 22)], fill=(230, 230, 230, 200))
        elif it.get("combat_style") == "melee":
            d.line([(6, 26), (26, 6)], fill=m, width=4)
            d.line([(5, 21), (11, 27)], fill=hexrgb("#6b4a2a"), width=3)
        elif it.get("combat_style") == "ranged":
            d.arc([4, 2, 24, 30], 270, 90, fill=m, width=3)
            d.line([(14, 3), (14, 29)], fill=(230, 230, 230, 220))
        elif it.get("combat_style") == "magic":
            d.line([(8, 28), (22, 6)], fill=m, width=3)
            d.ellipse([18, 2, 28, 12], fill=hexrgb("#a0c0ff"), outline=hexrgb("#4060a0"))
        elif slot == "head":
            d.chord([6, 6, 26, 28], 180, 360, fill=m, outline=dark)
            d.rectangle([6, 16, 26, 20], fill=shade(m, 0.8))
        elif slot == "body":
            d.polygon([(6, 8), (26, 8), (24, 28), (8, 28)], fill=m, outline=dark)
            d.rectangle([2, 8, 6, 18], fill=shade(m, 0.8))
            d.rectangle([26, 8, 30, 18], fill=shade(m, 0.8))
        elif slot == "legs":
            d.rectangle([8, 4, 24, 10], fill=m, outline=dark)
            d.rectangle([8, 10, 14, 28], fill=m, outline=dark)
            d.rectangle([18, 10, 24, 28], fill=m, outline=dark)
        elif slot == "gloves":
            d.rounded_rectangle([8, 8, 24, 26], 4, fill=m, outline=dark)
            d.rectangle([4, 12, 8, 18], fill=m)
        elif slot == "boots":
            d.rectangle([8, 6, 16, 22], fill=m, outline=dark)
            d.rectangle([8, 20, 26, 26], fill=m, outline=dark)
        elif iid == "quartz_ring":
            d.ellipse([7, 10, 25, 28], outline=hexrgb("#c08a4a"), width=3)
            d.polygon([(16, 3), (21, 9), (16, 13), (11, 9)], fill=hexrgb("#dfe3f5"), outline=hexrgb("#7a80a0"))
        elif iid == "pearl_amulet":
            d.arc([6, 2, 26, 22], 0, 180, fill=hexrgb("#9aa3ab"), width=2)
            d.ellipse([11, 17, 21, 27], fill=hexrgb("#efe8f2"), outline=hexrgb("#a89ab0"))
        else:
            d.rounded_rectangle([7, 6, 25, 28], 5, fill=hexrgb("#8a5a2b"), outline=hexrgb("#4a3019"))
            d.rectangle([10, 14, 22, 18], fill=hexrgb("#6b4220"))


for it in json.loads((ROOT / "data/items/items.json").read_text())["items"]:
    path = it["icon"].replace("res://", "")
    if it["id"] in ("copper_ore", "tin_ore", "oak_log", "raw_minnow", "uncut_quartz", "bird_nest", "river_pearl"):
        continue
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    draw_item(ImageDraw.Draw(im), it)
    save(im, path)

# --- resource nodes
save(rock(hexrgb("#6d6460"), hexrgb("#8a5a4a")), "assets/resources/nodes/iron_rock.png")
willow = Image.new("RGBA", (T, 48), (0, 0, 0, 0))
d = ImageDraw.Draw(willow)
d.ellipse([5, 40, 27, 47], fill=(0, 0, 0, 80))
d.rectangle([13, 26, 18, 44], fill=hexrgb("#5a4a32"))
d.ellipse([3, 4, 29, 30], fill=hexrgb("#6a8a3a"))
for x in range(5, 28, 4):
    d.line([(x, 14), (x - 1, 34)], fill=hexrgb("#88aa4a"), width=2)
save(willow, "assets/resources/nodes/willow_tree.png")
for name, berries in (("herb_bush", True), ("herb_bush_picked", False)):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([4, 24, 28, 31], fill=(0, 0, 0, 60))
    d.ellipse([5, 8, 27, 28], fill=hexrgb("#3f7a30" if berries else "#5a6a40"))
    if berries:
        for (x, y) in ((10, 14), (18, 12), (21, 20), (13, 21)):
            d.ellipse([x, y, x + 3, y + 3], fill=hexrgb("#8fd06a"))
    save(im, f"assets/resources/nodes/{name}.png")
for name, crop in (("crop_patch", "#b99a5a"), ("herb_patch", "#9a5ab0"), ("crop_patch_empty", None)):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([2, 6, 30, 30], fill=hexrgb("#5a3f22"))
    for y in (10, 17, 24):
        d.line([(3, y), (29, y)], fill=hexrgb("#43301a"))
    if crop:
        for y in (8, 15, 22):
            for x in (6, 13, 20, 26):
                d.line([(x, y + 4), (x, y)], fill=hexrgb("#4f9a3c"), width=2)
                d.ellipse([x - 2, y - 2, x + 2, y + 1], fill=hexrgb(crop))
    save(im, f"assets/resources/nodes/{name}.png")

# --- enemies (32x32; the troll is 48x48)
def enemy(eid, size, fn):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([size * 0.2, size * 0.82, size * 0.8, size * 0.98], fill=(0, 0, 0, 80))
    fn(d, size)
    save(im, f"assets/enemies/{eid}.png")


def humanoid(col, weapon=None):
    def f(d, s):
        c = hexrgb(col)
        d.rectangle([11, 14, 21, 25], fill=shade(c, 0.8))
        d.rectangle([11, 4, 21, 13], fill=c)
        d.polygon([(9, 6), (11, 8), (11, 4)], fill=c)
        d.polygon([(23, 6), (21, 8), (21, 4)], fill=c)
        d.point([(14, 8), (18, 8)], fill=(250, 220, 60, 255))
        d.rectangle([12, 25, 14, 30], fill=shade(c, 0.5))
        d.rectangle([18, 25, 20, 30], fill=shade(c, 0.5))
        if weapon == "bow":
            d.arc([20, 8, 30, 26], 270, 90, fill=hexrgb("#7a532e"), width=2)
        elif weapon == "axe":
            d.line([(24, 26), (26, 8)], fill=hexrgb("#7a532e"), width=2)
            d.polygon([(25, 6), (31, 9), (29, 15), (26, 12)], fill=hexrgb("#9aa3ab"))
        else:
            d.line([(23, 24), (28, 12)], fill=hexrgb("#9aa3ab"), width=2)
    return f


enemy("slime", T, lambda d, s: (d.chord([5, 10, 27, 30], 180, 360, fill=(90, 200, 120, 230)), d.rectangle([5, 20, 27, 28], fill=(90, 200, 120, 230)),
      d.point([(12, 17), (20, 17)], fill=(20, 40, 20, 255)), d.ellipse([9, 13, 13, 16], fill=(220, 255, 230, 180))))
enemy("giant_rat", T, lambda d, s: (d.ellipse([6, 14, 24, 26], fill=hexrgb("#7a6a60")), d.ellipse([20, 12, 29, 21], fill=hexrgb("#8a7a70")),
      d.point([(26, 15)], fill=(200, 30, 30, 255)), d.arc([0, 12, 12, 30], 90, 270, fill=hexrgb("#c98a8a"), width=2)))
enemy("wolf", T, lambda d, s: (d.ellipse([5, 13, 25, 25], fill=hexrgb("#6a6a72")), d.polygon([(21, 9), (31, 14), (24, 20)], fill=hexrgb("#7a7a84")),
      d.polygon([(22, 9), (24, 4), (26, 10)], fill=hexrgb("#5a5a62")), d.line([(5, 18), (0, 12)], fill=hexrgb("#6a6a72"), width=3),
      d.rectangle([8, 24, 10, 30], fill=hexrgb("#55555c")), d.rectangle([19, 24, 21, 30], fill=hexrgb("#55555c"))))
enemy("goblin", T, humanoid("#6aa04a"))
enemy("goblin_archer", T, humanoid("#5a904a", "bow"))
enemy("goblin_warrior", T, humanoid("#4a7a3a", "axe"))
enemy("forest_troll", 48, lambda d, s: (d.rectangle([14, 18, 34, 38], fill=hexrgb("#5a7a4a")), d.ellipse([15, 4, 33, 22], fill=hexrgb("#6a8a5a")),
      d.point([(20, 12), (28, 12)], fill=(250, 220, 60, 255)), d.rectangle([8, 20, 14, 34], fill=hexrgb("#5a7a4a")), d.rectangle([34, 20, 40, 34], fill=hexrgb("#5a7a4a")),
      d.rectangle([16, 38, 22, 46], fill=hexrgb("#4a6a3a")), d.rectangle([26, 38, 32, 46], fill=hexrgb("#4a6a3a")), d.line([(40, 34), (46, 10)], fill=hexrgb("#6b4a2a"), width=4)))

# --- crafting stations (32x32)
def station(name, fn):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([3, 25, 29, 31], fill=(0, 0, 0, 70))
    fn(d)
    save(im, f"assets/environments/props/{name}.png")


station("furnace", lambda d: (d.rounded_rectangle([5, 6, 27, 29], 4, fill=hexrgb("#7a6a60"), outline=hexrgb("#3a302a")),
        d.chord([11, 14, 21, 30], 180, 360, fill=hexrgb("#f08a30")), d.rectangle([11, 22, 21, 28], fill=hexrgb("#f0b040")), d.rectangle([13, 1, 19, 7], fill=hexrgb("#5a4a40"))))
station("anvil", lambda d: (d.polygon([(4, 10), (28, 10), (24, 16), (8, 16)], fill=hexrgb("#5a5f66"), outline=hexrgb("#2a2d30")),
        d.rectangle([12, 16, 20, 24], fill=hexrgb("#4a4f56")), d.rectangle([8, 24, 24, 28], fill=hexrgb("#5a5f66"))))
station("workbench", lambda d: (d.rectangle([3, 12, 29, 17], fill=hexrgb("#a0703a"), outline=hexrgb("#4a3019")),
        d.rectangle([5, 17, 8, 29], fill=hexrgb("#7a532e")), d.rectangle([24, 17, 27, 29], fill=hexrgb("#7a532e")), d.line([(10, 10), (20, 6)], fill=hexrgb("#9aa3ab"), width=2)))
station("range", lambda d: (d.rectangle([4, 10, 28, 29], fill=hexrgb("#6a5a50"), outline=hexrgb("#2a2420")),
        d.ellipse([8, 6, 16, 12], fill=hexrgb("#3a3a3a")), d.ellipse([17, 6, 25, 12], fill=hexrgb("#3a3a3a")), d.rectangle([9, 18, 23, 26], fill=hexrgb("#f08a30"))))
station("alchemy_table", lambda d: (d.rectangle([3, 14, 29, 18], fill=hexrgb("#6a4a7a"), outline=hexrgb("#2a1a30")),
        d.rectangle([5, 18, 8, 29], fill=hexrgb("#4a3a5a")), d.rectangle([24, 18, 27, 29], fill=hexrgb("#4a3a5a")),
        d.ellipse([7, 5, 15, 14], fill=hexrgb("#d04a4a")), d.ellipse([17, 7, 23, 14], fill=hexrgb("#4aa0d0"))))

# --- buildings: one sprite per building sized to its plot, plus a site sprite
ROOFS = {"town_hall": "#a83232", "bank": "#3d6fb0", "tavern": "#b5651d", "blacksmith": "#4a4f56", "workshop": "#8a6239",
         "academy": "#6a4a9a", "farm": "#c9a030", "housing": "#9a5a3a", "marketplace": "#3a8a5a", "barracks": "#7a3030",
         "guild_hall": "#2a5a8a", "expedition_center": "#5a7a3a",
         "outpost_irondeep": "#5a5f6a", "outpost_whisperwood": "#3a6a4a", "outpost_ashen": "#c08a40"}
region = json.loads((ROOT / "data/regions/world_map.json").read_text())
for plot in region.get("building_plots", []) + region.get("outposts", []):
    bid = plot["building"]
    w, h = plot["rect"][2] * T, plot["rect"][3] * T
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    roof = hexrgb(ROOFS.get(bid, "#8a6239"))
    if bid == "farm":
        d.rectangle([4, 4, w - 5, h - 5], outline=hexrgb("#8a6239"), width=3)
        d.rectangle([w // 2 - 24, 8, w // 2 + 24, 52], fill=hexrgb("#a83232"), outline=hexrgb("#4a1a1a"))
        d.polygon([(w // 2 - 30, 12), (w // 2, -4), (w // 2 + 30, 12)], fill=hexrgb("#7a2020"))
    else:
        wall_top = int(h * 0.4)
        d.rectangle([4, wall_top, w - 5, h - 3], fill=hexrgb("#d8c8a0"), outline=hexrgb("#4a3019"), width=2)
        d.polygon([(0, wall_top + 4), (w // 2, 2), (w - 1, wall_top + 4)], fill=roof, outline=shade(roof, 0.5))
        d.rectangle([w // 2 - 7, h - 22, w // 2 + 7, h - 3], fill=hexrgb("#6b4a2a"))
        for x in range(14, w - 14, 28):
            if abs(x - w // 2) > 16:
                d.rectangle([x - 5, wall_top + 10, x + 5, wall_top + 20], fill=hexrgb("#9fd0ff"), outline=hexrgb("#4a3019"))
    save(im, f"assets/environments/buildings/{bid}.png")
site = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(site)
for x in (8, 54):
    d.rectangle([x, 10, x + 3, 60], fill=hexrgb("#a0703a"))
d.rectangle([8, 10, 57, 13], fill=hexrgb("#a0703a"))
d.line([(8, 60), (57, 13)], fill=hexrgb("#7a532e"), width=2)
d.rectangle([20, 46, 44, 58], fill=hexrgb("#c9a26b"), outline=hexrgb("#6b4a2a"))
save(site, "assets/environments/buildings/construction_site.png")
icon(lambda d: (d.line([(6, 26), (20, 12)], fill=hexrgb("#7a532e"), width=3), d.rectangle([16, 4, 28, 12], fill=hexrgb("#9aa3ab"))), "assets/ui/icons/build.png")
for cid in ("gold", "gems", "recruitment_tokens"):
    col = {"gold": "#e0b030", "gems": "#40c0e0", "recruitment_tokens": "#c060e0"}[cid]
    icon(lambda d, col=col: (d.ellipse([5, 5, 27, 27], fill=hexrgb(col), outline=shade(hexrgb(col), 0.5)), d.ellipse([10, 9, 16, 15], fill=(255, 255, 255, 120))),
         f"assets/ui/icons/{cid}.png")

print("placeholder art generated")


# ======================================================= Phase 3 content ====
# Terrain row 3: gate, dunes, ruin floor, ruin wall, moss, enchanted trees, stone ground.
atlas = Image.open(ROOT / "assets/environments/tiles/greenvale_tiles.png").convert("RGBA")
if atlas.size[1] < T * 4:
    bigger = Image.new("RGBA", (T * 8, T * 4), (0, 0, 0, 0))
    bigger.paste(atlas, (0, 0))
    atlas = bigger
gate = noise_tile(hexrgb("#8a8478"), 0.05)
d = ImageDraw.Draw(gate)
d.rectangle([0, 0, 5, T], fill=hexrgb("#5a5550"))
d.rectangle([T - 6, 0, T, T], fill=hexrgb("#5a5550"))
d.arc([2, -10, 30, 18], 0, 180, fill=hexrgb("#3a3530"), width=3)
put_tile(gate, 0, 3)
dunes = noise_tile(hexrgb("#d8b878"), 0.05, hexrgb("#c09c5a"), 20)
d = ImageDraw.Draw(dunes)
for y in (8, 20):
    d.arc([-8, y - 6, 40, y + 6], 200, 340, fill=hexrgb("#b8955a"))
put_tile(dunes, 1, 3)
ruin = noise_tile(hexrgb("#b8a682"), 0.05)
d = ImageDraw.Draw(ruin)
for y in range(0, T, 10):
    d.line([(0, y), (T, y)], fill=hexrgb("#968660"))
    off = 0 if (y // 10) % 2 == 0 else 8
    for x in range(off, T, 16):
        d.line([(x, y), (x, y + 10)], fill=hexrgb("#968660"))
put_tile(ruin, 2, 3)
wall = noise_tile(hexrgb("#8a7650"), 0.05)
d = ImageDraw.Draw(wall)
for y in range(0, T, 6):
    d.line([(0, y), (T, y)], fill=hexrgb("#5e5034"))
d.rectangle([0, 0, T - 1, T - 1], outline=hexrgb("#4a3e26"))
put_tile(wall, 3, 3)
moss = noise_tile(hexrgb("#4a7a5a"), 0.07, hexrgb("#8ad0a0"), 14)
put_tile(moss, 4, 3)
ench = noise_tile(hexrgb("#2a3a4a"), 0.05)
d = ImageDraw.Draw(ench)
for (cx, cy, r) in [(8, 10, 9), (23, 9, 9), (16, 22, 10), (4, 26, 6), (28, 25, 6)]:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexrgb("#3a2a5a"))
    d.ellipse([cx - r + 3, cy - r + 2, cx, cy - 1], fill=hexrgb("#6a4a9a"))
put_tile(ench, 5, 3)
stone = noise_tile(hexrgb("#7d7974"), 0.07, hexrgb("#5d5954"), 30)
put_tile(stone, 6, 3)
save(atlas, "assets/environments/tiles/greenvale_tiles.png")

# Resource nodes
for name, ore in (("coal_rock", "#1e1e1e"), ("silver_rock", "#e8edf3"), ("gem_rock", "#3a6ad0"), ("mithril_rock", "#6a8fd0"),
                  ("adamantite_rock", "#3f8a62"), ("sunstone_rock", "#f0a030")):
    save(rock(hexrgb("#6d6864"), hexrgb(ore)), f"assets/resources/nodes/{name}.png")
for name, leaf, trunk in (("maple_tree", ["#a0461e", "#c0602a", "#e08a3a"], "#6b4a2a"), ("yew_tree", ["#1e3a2a", "#2a4a34", "#3a5a40"], "#4a3020")):
    im = Image.new("RGBA", (T, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([5, 40, 27, 47], fill=(0, 0, 0, 80))
    d.rectangle([13, 28, 18, 44], fill=hexrgb(trunk))
    for (cx, cy, r, i) in [(16, 18, 13, 0), (10, 14, 8, 1), (21, 12, 8, 1), (15, 8, 7, 2)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hexrgb(leaf[i]))
    save(im, f"assets/resources/nodes/{name}.png")
for name, lit in (("glowcap_mushroom", True), ("glowcap_picked", False)):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([4, 24, 28, 31], fill=(0, 0, 0, 60))
    for (x, h) in ((9, 10), (16, 14), (23, 9)):
        d.rectangle([x - 1, 27 - h, x + 1, 27], fill=hexrgb("#d8d0b8"))
        if lit:
            d.chord([x - 5, 22 - h, x + 5, 32 - h], 180, 360, fill=hexrgb("#60e0d0"))
    save(im, f"assets/resources/nodes/{name}.png")
for name, gold in (("dig_site", False), ("royal_dig_site", True), ("dig_site_done", None)):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([3, 10, 29, 30], fill=hexrgb("#8a6a40"), outline=hexrgb("#5a4020"))
    if gold is not None:
        d.ellipse([9, 15, 23, 25], fill=hexrgb("#6a4a28"))
        d.line([(20, 4), (26, 18)], fill=hexrgb("#7a532e"), width=2)
        d.polygon([(24, 16), (30, 20), (26, 24)], fill=hexrgb("#9aa3ab"))
        if gold:
            d.ellipse([12, 17, 17, 22], fill=hexrgb("#f0c040"))
    save(im, f"assets/resources/nodes/{name}.png")
for name, col in (("outpost_depot", "#5a7a3a"),):
    im = chest.copy()
    save(im, f"assets/environments/props/{name}.png")
im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.polygon([(4, 30), (8, 10), (16, 4), (24, 10), (28, 30)], fill=hexrgb("#2a2420"), outline=hexrgb("#5a5048"))
d.rectangle([11, 16, 21, 30], fill=hexrgb("#0a0806"))
save(im, "assets/environments/props/dungeon_entrance.png")

# Enemies
enemy("cave_bat", T, lambda d, s: (d.polygon([(2, 12), (12, 16), (16, 12), (20, 16), (30, 12), (24, 22), (16, 20), (8, 22)], fill=hexrgb("#4a3a4a")),
      d.point([(14, 15), (18, 15)], fill=(240, 60, 60, 255))))
enemy("rock_golem", 48, lambda d, s: (d.rectangle([12, 14, 36, 38], fill=hexrgb("#7a7470")), d.rectangle([16, 4, 32, 16], fill=hexrgb("#8a8480")),
      d.rectangle([4, 16, 12, 34], fill=hexrgb("#6a6460")), d.rectangle([36, 16, 44, 34], fill=hexrgb("#6a6460")),
      d.point([(20, 9), (28, 9)], fill=(120, 200, 255, 255)), d.rectangle([14, 38, 22, 46], fill=hexrgb("#5a5450")), d.rectangle([26, 38, 34, 46], fill=hexrgb("#5a5450"))))
enemy("stone_troll", 48, lambda d, s: (d.rectangle([14, 18, 34, 38], fill=hexrgb("#6a6a72")), d.ellipse([15, 4, 33, 22], fill=hexrgb("#7a7a82")),
      d.point([(20, 12), (28, 12)], fill=(250, 220, 60, 255)), d.rectangle([8, 20, 14, 34], fill=hexrgb("#6a6a72")), d.rectangle([34, 20, 40, 34], fill=hexrgb("#6a6a72")),
      d.rectangle([16, 38, 22, 46], fill=hexrgb("#5a5a62")), d.rectangle([26, 38, 32, 46], fill=hexrgb("#5a5a62"))))
enemy("enchanted_wolf", T, lambda d, s: (d.ellipse([5, 13, 25, 25], fill=hexrgb("#6a7ab0")), d.polygon([(21, 9), (31, 14), (24, 20)], fill=hexrgb("#8a9ad0")),
      d.polygon([(22, 9), (24, 4), (26, 10)], fill=hexrgb("#5a6aa0")), d.rectangle([8, 24, 10, 30], fill=hexrgb("#4a5a90")), d.rectangle([19, 24, 21, 30], fill=hexrgb("#4a5a90"))))
enemy("forest_spirit", T, lambda d, s: (d.ellipse([8, 4, 24, 20], fill=(150, 240, 200, 200)), d.polygon([(8, 14), (24, 14), (20, 30), (16, 24), (12, 30)], fill=(120, 220, 180, 170)),
      d.point([(13, 11), (19, 11)], fill=(20, 60, 40, 255))))
enemy("corrupted_treant", 48, lambda d, s: (d.rectangle([18, 16, 30, 44], fill=hexrgb("#4a3020")), d.ellipse([6, 0, 42, 24], fill=hexrgb("#3a2a4a")),
      d.line([(18, 26), (6, 18)], fill=hexrgb("#4a3020"), width=4), d.line([(30, 26), (42, 18)], fill=hexrgb("#4a3020"), width=4),
      d.point([(21, 20), (27, 20)], fill=(200, 80, 255, 255))))
enemy("desert_raider", T, humanoid("#c08a5a"))
enemy("sand_wyrm", 48, lambda d, s: (d.arc([4, 10, 44, 46], 180, 360, fill=hexrgb("#c09040"), width=10), d.ellipse([32, 18, 46, 30], fill=hexrgb("#d0a050")),
      d.point([(40, 22)], fill=(200, 30, 30, 255))))
enemy("ancient_guardian", 48, lambda d, s: (d.rectangle([14, 12, 34, 40], fill=hexrgb("#c0a060")), d.rectangle([17, 2, 31, 14], fill=hexrgb("#d0b070")),
      d.point([(21, 7), (27, 7)], fill=(60, 220, 255, 255)), d.line([(36, 40), (40, 6)], fill=hexrgb("#8a6a3a"), width=3),
      d.rectangle([16, 40, 22, 46], fill=hexrgb("#a08050")), d.rectangle([26, 40, 32, 46], fill=hexrgb("#a08050"))))
enemy("treasure_goblin", T, lambda d, s: (humanoid("#e0c040")(d, s), d.ellipse([20, 14, 30, 26], fill=hexrgb("#8a5a2b")), d.ellipse([22, 16, 26, 20], fill=hexrgb("#f0d050"))))
enemy("goblin_chieftain", 48, lambda d, s: (d.rectangle([14, 18, 34, 38], fill=hexrgb("#4a7a3a")), d.ellipse([15, 4, 33, 22], fill=hexrgb("#5a8a4a")),
      d.polygon([(15, 6), (19, 0), (24, 5), (29, 0), (33, 6)], fill=hexrgb("#e0b030")), d.point([(20, 12), (28, 12)], fill=(250, 220, 60, 255)),
      d.line([(38, 36), (44, 8)], fill=hexrgb("#7a532e"), width=3), d.polygon([(42, 6), (48, 10), (44, 18)], fill=hexrgb("#9aa3ab"))))
for boss, body, acc in (("deepforge_colossus", "#7a3a2a", "#f08a30"), ("heartrot_ancient", "#3a2a3a", "#b060f0"), ("sand_king", "#c0a060", "#f0d050")):
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 54, 56, 63], fill=(0, 0, 0, 90))
    d.rectangle([18, 20, 46, 54], fill=hexrgb(body))
    d.ellipse([20, 2, 44, 26], fill=shade(hexrgb(body), 1.2))
    d.rectangle([6, 22, 18, 46], fill=hexrgb(body))
    d.rectangle([46, 22, 58, 46], fill=hexrgb(body))
    d.point([(27, 13), (28, 13), (36, 13), (37, 13)], fill=hexrgb(acc))
    d.rectangle([22, 30, 42, 36], fill=hexrgb(acc))
    save(im, f"assets/enemies/{boss}.png")

# Region / map UI icons
for name, col in (("map", "#3d6fb0"), ("quest", "#c9a030"), ("expedition", "#5a7a3a"), ("bell", "#e0b030"), ("dungeon", "#7a3030")):
    icon(lambda d, col=col: (d.rounded_rectangle([3, 3, 29, 29], 6, fill=shade(hexrgb(col), 0.7), outline=hexrgb(col), width=2)), f"assets/ui/icons/{name}.png")
print("phase 3 placeholder art generated")
