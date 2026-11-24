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

The speed multiplier is `affinity_speed × (1 + min(0.005 × (level − req), 0.40))`. The constants
`LEVEL_SPEED_PER_LEVEL` and `LEVEL_SPEED_CAP` are in `scripts/characters/adventurer.gd` and are
**scheduled to move to config in P2**.

### Measured rates (1 h simulated from a fresh save, `tools/balance_report.gd`)

| Character | Activity | Est. items/h | Est. XP/h | Simulated items | Skill level after 1 h |
|---|---|---|---|---|---|
| Brom Stonefist | Mine Copper | 855 | 16,471 | 841 | 15 → 33 |
| Brom Stonefist | Chop Oak | 555 | 13,883 | 589 | 1 → 30 |
| Brom Stonefist | Fish Minnows | 567 | 5,672 | 597 | 1 → 22 |
| Sylvara Moonleaf | Mine Copper | 661 | 11,568 | 691 | 1 → 29 |
| Sylvara Moonleaf | Chop Oak | 737 | 21,196 | 746 | 18 → 36 |
| Sylvara Moonleaf | Fish Minnows | 568 | 5,685 | 596 | 1 → 22 |
| Tamsin Reed | Mine Copper | 669 | 12,300 | 699 | 1 → 29 |
| Tamsin Reed | Chop Oak | 563 | 14,791 | 605 | 1 → 31 |
| Tamsin Reed | Fish Minnows | 606 | 6,366 | 638 | 3 → 23 |

The assignment screen's estimate (`ActivityEstimator`) is within ±25% of the simulation, which
`test_estimate_close_to_simulation` checks. It is slightly low because it ignores the speed gained
from levelling during the hour.

### Balance observations to address in Phase 2

- **Early levels come very fast** (1 → 30 in an hour). This is intended for the curve's front
  end, but with only tier-1 content XP/hour stays flat while thresholds grow, so progress stalls
  near 40 to 50. Phase 2 needs tier-2 nodes (iron at level 15, willow at 15, trout at 20) with
  around 2 to 3 times the XP per action to keep the 30 to 60 range moving.
- **Fishing XP is low** (10 XP per catch). Fish become food, which has value once combat exists.
  Fishing XP/h should be revisited against cooking demand.
- **Specialists are about 25 to 45% better** in their field, and generalists are about 5 to 10%
  better outside it. That matches "rarity matters but is not everything".

## Offline

| Setting | Value |
|---|---|
| Base cap | 8 h |
| Planned upgrades | 12 h, 24 h (relics, Celestial Hourglass) |
| Minimum absence | 60 s |
| Simulation step | 1 s |

## Planned gacha (Phase 2, from the master spec)

| Rarity | Rate | Hard pity (configurable, per banner) |
|---|---|---|
| Common | 45% | |
| Uncommon | 30% | |
| Rare | 17% | Rare or better within 10 pulls |
| Epic | 6% | Epic or better within 50 |
| Legendary | 1.8% | Legendary within 100 |
| Mythic | 0.2% | Mythic within 200 |

The planned tests are: a chi-square test of the base rates over 10^6 server-side rolls; exact
pity-counter behaviour (reset only the tier that hit and lower tiers, with counters persisted per
banner); and the effective rates including pity, which are published in-game.
