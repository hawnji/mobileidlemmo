# Worldbound: Balance

Every number here comes from `data/`, except the two level-speed constants noted below. To change
balance, edit the JSON and run `tools/run_tests.sh` and
`godot --headless --path . -s res://tools/balance_report.gd`.

## XP curve

The formula (`data/skills/xp_curve.json`, `skill_curve`) is RuneScape-style:

```
points(L) = Σ_{l=1}^{L-1} floor(l + 300 · 2^(l/7))
xp(L)     = floor(points(L) / 4)
```

| Level | XP | Level | XP |
|---|---|---|---|
| 2 | 83 | 50 | 101,333 |
| 5 | 388 | 60 | 273,742 |
| 10 | **1,154** | 70 | 737,627 |
| 15 | 2,411 | 80 | 1,986,068 |
| 20 | 4,470 | 85 | 3,258,594 |
| 25 | 7,842 | 90 | 5,346,332 |
| 30 | 13,363 | 92 | 6,517,253 (half of 99) |
| 40 | 37,224 | 99 | **13,034,431** |

The maximum XP per skill is 200,000,000 (headroom for mastery).

### Validation against the master spec

The spec lists "illustrative" cumulative targets. Level 10 (1,154) and level 99 (13,034,431)
match the formula **exactly**. The spec's values for levels 20 to 90 (9,303, 37,224, 110,117,
275,673, 652,725, 1,503,188, 3,479,914 and 8,077,247) **do not**, and no single smooth exponential
can produce them together with the level-99 anchor. Growth from 80 to 90 in the spec is ×2.32 per
10 levels, but 90 to 99 is only ×1.61 over 9 levels. That kink would make the last 9 levels feel
fast after a long grind.

**Decision:** use the formula, which keeps both spec anchors exactly and grows smoothly at about
×1.105 per level. If the intended feel is "the middle levels are slower", the right control is
the **XP per action at each resource tier**, not the curve. This is flagged for review and can be
changed in data without code changes.

### Character level curve
The same formula with `base 120`, `divisor 9` and a maximum of 100. Characters earn 25% of skill
XP as character XP.

## Gathering (tier 1, Phase 1)

| Node | Skill | Req | Gather (s) | XP | Yield | Rare drop | Charges | Respawn (s) |
|---|---|---|---|---|---|---|---|---|
| Copper Rock | Mining | 1 | 5.0 | 17.5 | 1 copper ore | Uncut Quartz 0.2% | 4 | 10 |
| Tin Rock | Mining | 1 | 5.0 | 17.5 | 1 tin ore | Uncut Quartz 0.2% | 4 | 10 |
| Oak Tree | Woodcutting | 1 | 6.0 | 25.0 | 1 oak log | Bird Nest 0.2% | 5 | 15 |
| Minnow Spot | Fishing | 1 | 6.0 | 10.0 | 1 raw minnow | River Pearl 0.1% | 8 | 12 |

The speed multiplier is `stat("gather_speed", skill) × (1 + min(0.005 × (level − req), 0.40))`,
where the stat folds affinities, passive, traits, specializations, stars, tools and buildings
(see "Stat system" below). The constants `LEVEL_SPEED_PER_LEVEL` and `LEVEL_SPEED_CAP` are still in
`scripts/characters/adventurer.gd` (moving them to config was not done in Phase 2).

### Nodes added in Phase 2
| Node | Skill | Req | Gather (s) | XP | Yield |
|---|---|---|---|---|---|
| Iron Rock | Mining | 15 | 6.0 | 35.0 | iron ore |
| Willow Tree | Woodcutting | 15 | 7.0 | 45.0 | willow log |
| Trout Spot | Fishing | 20 | 7.0 | 50.0 | raw trout |
| Herb Bush | Foraging | 1 | 5.0 | 15.0 | guam leaf |
| Potato Patch | Farming | 1 | 6.0 | 14.0 | potato |
| Marrentill Patch | Farming | 12 | 8.0 | 40.0 | marrentill |

Tier 2 gives 2 to 5 times the XP per action of tier 1, which addresses the Phase 1 observation
that progress stalled around level 40 with only tier 1 content.

## Stat system

`data/config/stats.json` lists every stat family and whether it multiplies (`mul`, default 1) or
adds (`add`, default 0). Keys are `family.skill`, `family.all` or a bare family. Sources: character
affinities, passive, traits, specializations, stars (`progression.star_effects_per_star` applied
`stars − 1` times), equipment (skipped when broken; each upgrade level adds 10% of the item's
bonus) and account effects (buildings now; relics, pets and guild perks later).

## Combat

Formulas (`scripts/combat/combat_rules.gd`, tunables in `game_config.json` → `combat`):

```
player hit chance = clamp(0.55 + (offense_level + accuracy − enemy_defense) × 0.02, 0.15, 0.95)
player max hit    = floor((1 + power_level × 0.18 + weapon_power) × damage × weakness[style])
enemy hit chance  = clamp(0.50 + (enemy_accuracy − (defense_level + armor/2)) × 0.02, 0.05, 0.90)
enemy damage      = randi(0, max_hit) − floor(armor / 10)
XP                = 4 per damage dealt (melee splits attack/strength), 1.5 defense per damage taken,
                    hunting 2 × enemy level × variant multiplier per kill
```

Variants multiply health, accuracy, defense and max hit by `stat_multiplier`, and XP, gold and loot
rolls by their own multipliers. Chances: Champion 3%, Elite 1.5%, Ancient 0.4%, Corrupted 0.2%,
Legendary 0.05%.

### Measured (1 h simulated, starters with default rules and 200 cooked minnows in storage)
| Character | Hunting ground | Kills | Gold | Knock-outs | Levels after 1 h | Estimated risk |
|---|---|---|---|---|---|---|
| Brom | East Meadows | 157 | 491 | 0 | attack 16, def 9, hunting 8 | Low |
| Brom | Goblin Camp | 86 | 906 | 0 | attack 16, def 13, hunting 9 | High |
| Sylvara | East Meadows | 261 | 720 | 0 | ranged 27, def 6, hunting 12 | Low |
| Sylvara | Goblin Camp | 151 | 1,724 | 0 | ranged 28, def 12, hunting 15 | Medium |
| Tamsin | Wolf Den | 39 | 150* | 0 | attack 13, def 13, hunting 7 | Deadly |
| any starter | Forest Troll | 0 | 100* | 0 | defense rises only | Deadly |

\* milestone rewards only (wolves drop no gold; nobody can damage the troll yet). The retreat rule
keeps fresh characters alive: they eat, then go home to rest instead of being knocked out. The
troll is meant as a goal for geared, level 20+ fighters.

## Crafting

| Character | Recipe | Crafts in 1 h (unlimited materials) | Level after 1 h |
|---|---|---|---|
| Brom | Bronze Bar | 974 | smithing 8 → 24 |
| Sylvara | Oak Plank | 1,233 | crafting 1 → 22 |
| Tamsin | Cooked Minnow | 1,437 | cooking 1 → 30 |

**Observation:** with unlimited materials, tier 1 crafting levels faster than gathering. In real
play, crafting is limited by gathered materials (a bronze bar needs one copper and one tin, which
take about 10 s of mining), so the effective rate is far lower. If playtests find it too fast,
raise `seconds` on tier 1 recipes.

Cooking burn chance: `base_chance × (1 − (level − req) / (stop_level − req))`, 0 at `stop_level`.
Preserve chance keeps the inputs; double-craft doubles the outputs; both come from stats (traits,
specializations, Workshop).

## Equipment
| Rule | Value |
|---|---|
| Durability loss | 1 per gather (matching tool), 1 per attack (weapon), 1 per hit taken (random armour piece) |
| Repair cost | missing points × tier × 0.25 gold × (1 − Blacksmith discount) |
| Upgrade cost | level × 100 gold + level × 2 bars (bronze for tier 1, iron for tier 2) |
| Upgrade bonus | +10% of the item's stat bonus per level, max +5, capped by Blacksmith level |

## Town
Building effects are the values of the **current** level (not cumulative). Worker capacity =
4 + Town Hall + Housing bonuses. The Tavern makes `token_rate` recruitment tokens per hour.
Every 10 levels in any skill pays 1 recruitment token and 50 gold.

## Offline

| Setting | Value |
|---|---|
| Base cap | 8 h |
| Planned upgrades | 12 h, 24 h (relics, Celestial Hourglass) |
| Minimum absence | 60 s |
| Simulation step | 1 s |

## Gacha (implemented)

| Rarity | Base rate | Effective rate incl. pity (10^6 simulated pulls) | Hard pity |
|---|---|---|---|
| Common | 45.0% | 43.85% | |
| Uncommon | 30.0% | 29.21% | |
| Rare | 17.0% | 18.27% | Rare or better within 10 pulls |
| Epic | 6.0% | 6.04% | Epic or better within 50 |
| Legendary | 1.8% | 2.02% | Legendary or better within 100 |
| Mythic | 0.2% | 0.61% | Mythic within 200 |

Regenerate with `godot --headless --path . -s res://tools/gacha_report.gd`. The Recruit screen
shows the same numbers. Costs: 1 recruitment token or 150 gems per pull, 10 pulls with gems cost
1,350 (10% off). Duplicates give 5/8/10/15/20/25 fragments by rarity; stars cost 10, 20, 40, 80,
120 fragments.

Tests: `test_base_rates_chi_square_one_million_rolls` (chi-square must stay under 20.52, the
99.9% critical value for 5 degrees of freedom), exact pity behaviour (pulls 10/20/30 forced rare,
higher tier wins, lower tiers reset), mythic by pull 200, featured share within ±3%, and pity and
history persisting through save/load.

## World expansion (Phase 3)

Measured with `godot --headless --path . -s res://tools/balance_report.gd` (reference members
have every combat and gathering skill and the character level set to the column level, and wear
the gear tier for it: bronze below 15, iron 15+, mithril 30+, adamantite 45+). Dungeon runs use
the three starters only, so they are one member short of the 4-member maximum.

| Region | Explorer time to 35% / 98% explored (one starter, fresh world) |
|---|---|
| Greenvale | 35m 00s / 1h 48m |

| Reference member (geared) | Level 10 | 20 | 30 | 40 | 50 | 60 |
|---|---|---|---|---|---|---|
| Power | 81 | 166 | 249 | 309 | 400 | 460 |

| Expedition | Recommended power | Chance at level 20 | 40 | 60 |
|---|---|---|---|---|
| Survey the Valley | 45 | 97% | 97% | 97% |
| Goblin Warrens Raid | 160 | 97% | 97% | 97% |
| The Lost Dwarven Vault | 750 | 58% | 92% | 97% |
| The Moonlit Glade | 500 | 58% | 92% | 97% |
| Heart of the Wood | 1050 | 47% | 71% | 97% |
| Guard the Caravan | 560 | 54% | 84% | 97% |
| Survey the Royal Tombs | 1600 | 43% | 64% | 87% |

| Dungeon | Party | Result at level 20 | 40 | 60 |
|---|---|---|---|---|
| Goblin Warren | 3 | cleared 1m 22s | cleared 55s | cleared 34s |
| Deepforge Vault | 4 | failed 7m 14s | cleared 5m 37s | cleared 2m 55s |
| Heartrot Hollow | 4 | failed 6m 27s | failed 7m 07s | cleared 3m 51s |
| Tomb of the Sand King | 4 | failed 6m 54s | failed 8m 31s | cleared 5m 54s |

### Knobs and intent

| Knob | Value | Intent |
|---|---|---|
| `exploration.survey_seconds` | 60 | A first region takes about 2 hours for one explorer; faster with level and gear |
| `exploration.walk_reveal_radius` | 1 | Gatherers reveal their own paths without exploring for free |
| `exploration.xp_per_tile` | 4 | Roughly 5-6k Exploration XP/h, below gathering, plus discovery rewards |
| Region unlock | quest + mining 20, woodcutting 30 or character level 30 + 30-50% of the previous region explored + 500/2000/6000 gold | Each region is a multi-hour goal |
| Expedition success | `0.10 + 0.60 x min(power/recommended, 1.45)`, +8% supplies | About 70% at the recommended power, the 97% cap needs about 1.45x |
| Expedition recommended power | team size x a geared member at the intended level (5, 10, 30, 30, 45, 35, 50) | Odds rise as the team outlevels the content |
| Dungeon bosses | 320 / 1500 / 1900 / 2600 HP, enrage at 3-5 min | Intended at about level 10 / 40 / 50 / 60 with the matching gear |
| Encounters | one roll every 10-25 min, at most 2 active | Something to notice on most sessions without flooding the map |

## Endgame (Phase 5)

Measured with `tools/balance_report.gd`. Reference parties are 4 members: the three starters
plus Elowen, all at the column level. They wear voidsteel gear and shadowbark weapons from
level 70, and starmetal and skywood from level 90. They carry 120 cooked gloom eels.

| Endgame dungeon | Party | Result at level 70 | 85 | 99 |
|---|---|---|---|---|
| The Dread Citadel | 4 | cleared 5m 22s | cleared 4m 18s | cleared 3m 36s |
| Starfall Sanctum | 4 | failed 9m 19s | cleared 6m 42s | cleared 5m 15s |

| Mythic run (party of 4, level 99) | Tier 1 | 3 | 5 | 7 | 10 |
|---|---|---|---|---|---|
| Goblin Warren | cleared 34s | cleared 38s | cleared 49s | cleared 1m 02s | cleared 1m 02s |
| Tomb of the Sand King | cleared 2m 51s | cleared 3m 45s | cleared 5m 18s | cleared 6m 37s | failed 6m 53s |
| The Dread Citadel | cleared 4m 13s | failed 9m 02s | failed 9m 39s | failed 8m 24s | failed 8m 03s |

These runs use no relics, pets, mounts or perks. High tiers of the endgame dungeons are meant to
need them: Warlord's Banner, Void Prism, Warlord perk ranks and a Shadow Cat each add damage.

- **Mastery pace:** Brom (mining 99, voidsteel gear) mining voidstone earns about 65,000
  mastery XP an hour. A mastery level takes about 15 hours, and 20 levels in one skill take
  about 300 hours.
- **Ascension points (first ascension):** a score of 1,000 gives 94 points, 2,500 gives 150,
  4,000 gives 189 and 6,000 gives 232. A full set of perks costs about 1,200 points, so it takes
  several ascensions.

### Endgame knobs and intent

| Knob | Value | Intent |
|---|---|---|
| Endgame monsters | 280-770 HP, max hit 20-34 | The Shadowlands at level 60-90 with voidsteel, the Celestial Isles at 80-99 with starmetal |
| Bosses | Hollow King 3,380 HP; Astral Wyrm 4,440 HP; enrage 5.5 and 6 min | Dread Citadel at about 70+, Starfall Sanctum at about 85+, with 4 heroes |
| `mythic.enemy_health_per_tier` / `enemy_damage_per_tier` | 0.15 / 0.08 | Ten steps; the last ones need the endgame bonuses |
| `mythic.reward_mult_per_tier`, `relic_dust_per_tier`, `relic_chance_per_tier` | 0.25, 15, 4% (max 40%) | A tier 10 clear pays 3.5x, 150 dust and a 40% relic chance |
| `mastery.xp_per_level` | 1,000,000 | About 15 h per level at endgame rates; bonuses are small (+1% speed per level) |
| `pets.xp_share`, `level_xp` | 5%, up to 1,000,000 | Level 5 needs 700k owner XP (about 5-6 h on an endgame hero at about 130k XP/h); level 10 needs 20M (about 150 h) |
| `relics.upgrade_costs` | 60 / 150 / 320 / 640 dust | One relic to level 5 costs 1,170 dust: about 78 tier-1 clears, or 8 tier-10 clears |
| Ascension points | 30 x sqrt(score / 100), at least 5, only growth since the best earlier score | Diminishing returns; repeat ascensions pay for real progress |
| Season bonuses | +5-10% to two stats | Felt, but never required |
