# Worldbound: Game Design

Status tags: **[P1]** is implemented in Phase 1. **[P2] to [P5]** marks the phase where a feature
is planned.

## 1. Vision

Worldbound is a 2D top-down open-world idle MMORPG for phones. You collect a growing roster of
adventurers and manage them as a workforce. Each one travels a shared fantasy world on its own
to gather, fight, craft, explore and return home, and keeps going while you are offline.

**Design principle: automation is the gameplay.** Your skill shows in planning routes, matching
characters to jobs, setting automation rules, unlocking regions and building production chains.
It does not show in tapping.

### Pillars

1. **Character collection.** Hundreds of distinct adventurers. Every one of them has a niche, and
   rarity is never the only thing that matters.
2. **Visible automation.** When you look at the world you see your characters walking, mining,
   chopping and fishing. The world feels inhabited.
3. **Deep skilling.** 24 RuneScape-style skills from 1 to 99 plus mastery, connected through a
   production economy.
4. **Long-term progression.** Regions, tiers, settlements, relics and prestige.
5. **Social world.** Shared towns, guilds, trading and co-op bosses, all server-authoritative.

## 2. Core loop

1. Recruit adventurers **[P2]**. In Phase 1 you start with three.
2. Assign them to activities **[P1]**.
3. Set automation rules: return threshold and continuation mode **[P1]**. Safety, consumable and
   multi-stop routes come in **[P2]**.
4. They travel **[P1]**, perform the activity **[P1]**, and earn XP and loot **[P1]**.
5. They manage their bags and return to storage **[P1]**, deposit **[P1]** and resume **[P1]**.
6. You spend resources on crafting, equipment, buildings and upgrades **[P2]**.
7. You unlock regions and discover new characters, activities and resources **[P3]**.

The game runs on three time scales:

- **Active play:** exploring, optimising routes, managing characters, discoveries and multiplayer.
- **Short assignments:** gathering and processing loops lasting minutes. These are in **[P1]**.
- **Long assignments:** expeditions, farming and offline progression lasting hours. Offline
  progression is in **[P1]**.

## 3. World

There are eight planned regions, each with its own environments, resources, enemies and
characters. The full list is in the master spec and summarised here:

| # | Region | Theme | Signature activities | Phase |
|---|---|---|---|---|
| 1 | Greenvale | Forests, rivers, farms, starter village | Copper/tin, oak, fishing, farming, beginner combat | **P1 slice**, rest P2-P3 |
| 2 | Irondeep Mountains | Mines, dwarven holds | Iron/silver/gems, advanced smithing | P3 |
| 3 | Whisperwood | Enchanted forest | Rare wood, herblore, magical foraging | P3 |
| 4 | Ashen Desert | Ruins, tombs | Archaeology, treasure, rare minerals | P3 |
| 5 | Frostfang Peaks | Snow, ice caves | Rare fishing, advanced mining | P3 |
| 6 | Sunken Kingdom | Underwater ruins | Diving, aquatic gathering (needs gear) | P3/P5 |
| 7 | Shadowlands | Corruption, fortresses | High-level combat, dark materials | P5 |
| 8 | Celestial Isles | Floating islands (endgame) | Mythic resources, world bosses | P5 |

### Phase 1 slice of Greenvale [P1]

This is a 64x48 tile map (32 px tiles) with four distinct locations:

- **Greenvale Hollow**: the village, with buildings, a stone plaza and the **Village Storage** chest.
  This is where your characters start.
- **Oakwood Forest** (west, across the river bridge): forest floor that slows walking, dense tree
  clumps you cannot walk through, and 12 oak trees.
- **Greenvale Mine** (north-east, inside the mountains): a cave hall with 6 copper and 3 tin rocks,
  reached by a road.
- **Greenvale River** (runs through the middle): 4 minnow fishing spots along the southern bank.
- Hollow Farms (south): scenery only until Farming arrives in P2.

Roads and the bridge cost less to walk on, so characters prefer them.

Later exploration features include fog of war, discovery points, hidden caves, secret paths,
treasure, environmental puzzles and character-specific discoveries (rangers find trails, rogues
find treasure, mages find magical objects, miners find tunnels). These come in **[P3]**. The world
data format already supports multiple regions and location rectangles.

## 4. Characters

### Phase 1 roster [P1]

| Character | Rarity | Role | Affinities | Passive | Bag |
|---|---|---|---|---|---|
| Brom Stonefist | Legendary | Mining specialist, Tank | Mining +25% speed / +10% XP, Smithing | *Deep Veins*: double rare gem chance | 28 |
| Sylvara Moonleaf | Mythic | Woodcutting specialist, Ranger | Woodcutting +25% / +15%, Exploration | *Forest Sense*: +50% bird nest chance | 24 |
| Tamsin Reed | Common | Generalist, Warrior | Fishing +5% | *Jack of All Trades*: +5% XP in every skill, biggest bag | 32 |

Tamsin shows the rule that rarity is not everything. She has the largest bag, a universal XP
bonus and the fastest movement after Sylvara, so she makes fewer trips on long routes than the
specialists.

### Planned character model [P2]

The full model covers unique ID, portrait, sprite, rarity, origin, backstory, primary and
secondary affinity, combat specialty, starting skills, passive, active ability, base stats,
equipment slots, level (cap 100), XP, star rank (1 to 6 stars from duplicates), personality,
specialization and relationships. Phase 1 data already includes most of the descriptive fields.
See [DATA_SCHEMA.md](DATA_SCHEMA.md).

There are six rarities: Common, Uncommon, Rare, Epic, Legendary and Mythic. Higher rarity means
more starting skills, stronger passives and more specialization potential, but every rarity keeps
a niche.

Traits **[P2]**: Hard Worker, Treasure Seeker, Battle Hardened, Efficient, Pack Mule, Night Owl,
Perfectionist and Adventurous. Specializations **[P2]** are meaningful side-grades, such as Gem
Specialist versus Ore Extractor.

Character level **[P1]**: each character earns 25% of the skill XP they gain as character XP, on
a separate curve capped at level 100.

## 5. Skills

There are 24 skills, each with a maximum level of 99 and mastery after that **[P5]**:

- **Gathering:** Mining **[P1]**, Woodcutting **[P1]**, Fishing **[P1]**, Hunting, Foraging, Farming,
  Archaeology
- **Production:** Smithing, Crafting, Cooking, Herblore, Enchanting, Construction, Tailoring, Alchemy
- **Combat:** Attack, Strength, Defense, Ranged, Magic
- **Utility:** Prayer, Agility, Exploration, Summoning

All 24 exist in data and in the Skills screen. The 21 not yet playable are labelled "Coming in a
later phase". Every skill is planned to feed at least one other system:

```
Mining -> ore -> Smithing -> bars -> Crafting/Smithing -> equipment -> Combat & gathering speed
Woodcutting -> logs -> fuel (Smithing, Cooking), Construction, fletching
Fishing -> raw fish -> Cooking -> food -> Combat sustain
Farming/Foraging -> herbs -> Herblore -> potions
Construction -> buildings -> settlement bonuses
Enchanting -> equipment upgrades
```

## 6. The automation system (the most important system) [P1]

Each character receives an **Assignment** containing the activity, destination, deposit target,
return threshold, continuation mode, target quantity, preferred nodes and safety settings. It then
runs a state machine:

```
IDLE -> ASSIGNED -> CHECKING_CONDITIONS -> PATHFINDING -> TRAVELING -> PERFORMING_ACTIVITY
                         ^                                                 |
                         +------------------- (per gather) ----------------+
CHECKING_CONDITIONS -(bag at threshold)-> PATHFINDING -> RETURNING -> DEPOSITING -> CHECKING_CONDITIONS (resume)
CHECKING_CONDITIONS -(no free node)-> WAITING -> CHECKING_CONDITIONS
CHECKING_CONDITIONS/DEPOSITING -(target reached / one trip)-> COMPLETED
```

COMBAT, RESTOCKING, RESTING and INJURED are already part of the state machine's transition table
for Phase 2.

Key behaviours:

- Characters **reserve** a node so workers spread across rocks and trees instead of queueing.
- Depleted nodes respawn on a timer. A character whose nodes are all busy or depleted waits and
  retries.
- Unreachable nodes go on a cooldown for that character, and it tries another. After 5
  consecutive routing failures the character stops and reports "Stuck" instead of looping forever.
- If terrain changes under a planned path, the character re-plans from where it stands.
- Cancelling keeps the character's bag contents.

Route builder **[P2]**: multi-stop routes (mine copper, then tin, then deposit, then repeat), saved
templates, and safety rules for health, supplies, enemy level, consumables and repairs. The
`Assignment` data already reserves `preferred_node_ids` and `safety`.

## 7. Offline progression [P1]

- Offline progress is capped at 8 hours by default. 12 and 24 hour upgrades are planned for
  **[P2]** through relics and the Celestial Hourglass.
- Offline time is simulated with the **same deterministic rules** as live play, so offline results
  match what would have happened online. They cannot exceed it.
- The report shows time away, the cap, total XP, items added to storage, rare finds, and for each
  character their XP and levels gained, items gathered, trips, interruptions and current state.
- Rolling the clock back grants nothing, and reopening the game immediately does not grant the
  same time twice.

## 8. Later systems (summary)

| System | Phase | Notes |
|---|---|---|
| Recruitment / gacha | P2 | Six rarities. Rates 45/30/17/6/1.8/0.2%. Configurable pity at 10/50/100/200 pulls, tracked per banner. **Results generated server-side only.** Tokens, gems and event currency. Duplicates become fragments for star ranks 1-6. Some characters can only be recruited outside the gacha. |
| Combat | P2 | Automated. Roles are Tank, Warrior, Ranger, Mage, Healer, Assassin and Support. Players set target priority, stance, ability priority, healing and retreat thresholds, and party. Enemy variants: Champion, Elite, Ancient, Corrupted and Legendary. |
| Bosses | P3 | Phases, special attacks, summons, area attacks, weaknesses, enrage, unique loot |
| Equipment | P2 | 9 slots (weapon, head, body, legs, gloves, boots, 2 accessories, tool). Durability, repair, upgrades, quality, comparison, loadouts |
| Crafting and economy | P2 | Resources in tiers 1-7, processing recipes, bank upgrades, item locking and favourites |
| Town and outposts | P2/P3 | 12 buildings. Outposts act as remote storage and fast-travel points for automation |
| Expeditions | P3 | Multi-hour team missions with requirements, risk, events and branching discoveries |
| Quests and reputation | P3 | Main, regional and repeatable contracts. Reputation per region |
| Pets and mounts | P5 | Passive bonuses, travel speed and terrain access |
| Multiplayer | P4 | Shared towns, friends, guilds, trading, marketplace, co-op bosses, world events |
| Dynamic world | P4 | Server-side periodic simulation of shortages, merchants and community projects |
| Relics and World Ascension | P5 | Account-wide bonuses and a prestige system with diminishing returns |
| Daily, weekly and seasonal | P4/P5 | Never mandatory for competitive progression |
| Notifications | P2 | Rare finds, completed jobs and full bags only. No spam for routine gathering |

## 9. Monetisation principles

Monetisation must not be pay-to-win. It focuses on cosmetics (skins, town decorations, pet and
mount skins), optional convenience and optional premium recruitment. Gacha probabilities and pity
are always visible. Maximum-rarity characters are never required for normal progression.
Currencies are Gold, Gems, Recruitment Tokens, Guild Coins, Ascension Points and Relic Dust
**[P2+]**.

## 10. Design decisions made in Phase 1

| Decision | Why |
|---|---|
| Bags hold a number of **units** (e.g. 28 items), not slots | It makes "return at 75%" exact and easy to read. Storage limits the number of **item types** instead (48 to start) |
| Nodes have **charges** and respawn, and one gatherer at a time | It spreads workers out, makes resource availability visible, and prevents an infinite single-node exploit |
| Level gives +0.5% gather speed per level above the requirement, up to +40% | It rewards training without making high levels trivialise low-tier nodes |
| The spec's mid-curve XP targets were replaced with the formula's values | They are not on any single exponential curve. See [BALANCE.md](BALANCE.md#xp-curve) |
| Simulation speed and "simulate time away" are in the build | They are needed to test idle mechanics in minutes. They will be removed or locked to debug builds before release |
| Portrait orientation | One-handed mobile play. The world view has more vertical space, and the roster and nav sit in thumb reach |
