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
atlas = Image.new("RGBA", (T * 8, T * 3), (0, 0, 0, 0))


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
SKIN = {"Dwarf": "#e0a77a", "Elf": "#f0d2b0", "Human": "#d9a982"}
HAIR = {"brom_stonefist": "#b5532a", "sylvara_moonleaf": "#e9e4c8", "tamsin_reed": "#4a3019"}


def draw_char(d, ox, oy, direction, frame, c):
    prim = hexrgb(c["palette"]["primary"])
    sec = hexrgb(c["palette"]["secondary"])
    skin = hexrgb(SKIN.get(c["origin"], "#d9a982"))
    hair = hexrgb(HAIR.get(c["id"], "#4a3019"))
    dwarf = c["origin"] == "Dwarf"
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

print("placeholder art generated")
