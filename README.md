# Worldbound

A 2D open-world idle MMORPG for Android and iOS, built with Godot 4.x and GDScript.
You collect adventurers, give them jobs, and they travel the world on their own to mine, chop,
fish, fight and craft, and they keep working while you are offline. Automation is the
gameplay, not a shortcut around it.

**Current status: Phase 2 (RPG progression) complete, on top of the Phase 1 prototype.** See
[docs/DEVELOPMENT_ROADMAP.md](docs/DEVELOPMENT_ROADMAP.md) for what is done, the known gaps and
what comes next.

![Phase 2 screenshots](docs/screenshots/phase2_overview.png)

<details><summary>Phase 1 screenshots</summary>

![Phase 1 screenshots](docs/screenshots/overview.png)
</details>

## What works today

- Greenvale, a 64x48 tile starter region: a village with a storage chest, the Oakwood Forest, the
  Greenvale Mine and the Greenvale River, with walkable and blocked terrain, roads and a bridge.
- Three starter characters, each with their own data, portrait, sprite sheet, skills and bag size:
  - Brom Stonefist (Legendary dwarven miner)
  - Sylvara Moonleaf (Mythic elven ranger who specialises in woodcutting)
  - Tamsin Reed (Common general adventurer)
- Four gathering activities: Mine Copper, Mine Tin, Chop Oak and Fish Minnows.
- An autonomous activity engine with a 14-state machine. Characters pick a free node, path to it
  with A*, gather, gain XP, return to storage when their bag reaches the threshold you set,
  deposit, and resume, all without player input.
- Automation rules: return at 50%, 75% or a full bag; repeat forever, stop after N deposited,
  or make one trip.
- The full 24-skill system with a RuneScape-style XP curve. Mining, Woodcutting and Fishing are
  playable in this phase.
- Character bags, shared village storage (with search and sort), rare drops and level-ups.
- Offline progression: an 8 hour cap and a detailed "While you were away" report. The same
  deterministic simulation runs online and offline.
- Mobile UI: character roster, character panel, assignment builder with XP/hour estimates,
  bag, skills, storage, offline report, toasts and bottom navigation.
- Chunk-based terrain rendering, pooled floating text, a day/night tint, and animated water,
  tools and particles.
- Saves locally with atomic writes. Saves on autosave, on quit and when the app is backgrounded
  on mobile.
- 148 automated tests plus a headless boot smoke test.

### Added in Phase 2
- **23 adventurers** across six rarities (3 starters, 18 recruitable, 1 quest, 1 exploration),
  each with affinities, a passive, three traits unlocked at character levels 10/30/60, star
  ranks and specializations (chosen at skill level 30).
- **Currencies**: gold, gems, recruitment tokens, festival tokens (plus guild coins, ascension
  points and relic dust reserved for later phases), with an atomic transaction log.
- **Recruitment**: two banners with published base and effective rates, per-banner pity
  (rare in 10, epic in 50, legendary in 100, mythic in 200), a featured character, 10-pull
  discount, duplicates into fragments, and star-up. Local rolls are dev-only; the server will
  own them in Phase 4.
- **Crafting**: 34 recipes at 5 stations (furnace, anvil, workbench, cooking range, alchemy
  table). Characters restock materials from storage, craft, deposit, and wait when materials run
  out. Preserve, double-craft and burn chances.
- **Equipment**: 9 slots, 27 items (tools, weapons, armour, accessories), requirements,
  durability, breaking, repair with gold, upgrades to +5 gated by the Blacksmith.
- **Combat**: 7 enemy types in 4 hunting grounds with rare variants (Champion to Legendary),
  melee/ranged/magic styles, food and healing thresholds, retreat rules, injury and resting,
  loot, gold and XP for attack/strength/ranged/magic/defense/hunting.
- **Town**: 12 buildings with 5 levels, construction projects worked by the Construct activity,
  worker capacity, storage slots, tavern tokens, and account-wide bonuses.
- **Gathering expansion**: iron, willow, trout, herbs, potatoes and marrentill.
- **Route builder**: chain steps (for example mine copper, mine tin, smelt bronze) and loop
  them; save routes as templates.
- **NPC shop**: sell from storage, lock and favourite items.
- An item conservation ledger (sources minus sinks) that the tests check across every system.

## Running the game

1. Install **Godot 4.3** or newer (the standard build, not .NET).
2. Open `project.godot` in the editor and press **Play** (F5). The game is laid out for portrait
   720x1280, and the desktop window can be resized.
3. Tap or click a character card at the bottom, then **Assign**. Pick a category (Gather, Craft,
   Fight, Build), an activity (and a recipe for crafting), set the automation rules and press
   **Start assignment**. Repeat for the other characters.
4. **Recruit** pulls new adventurers with your 10 starting tokens. **Town** starts construction
   projects; assign heroes to *Construct Buildings* to finish them. **Storage** sells items and
   equips gear on the selected hero. **Gear** on the character panel repairs and upgrades.
5. Drag to pan and pinch or scroll to zoom. **Follow** locks the camera onto the selected character.
6. The top bar's **x1** button changes simulation speed (x1, x5, x20) so you can watch whole loops
   quickly. **Dev** has "simulate time away" buttons for testing offline progression, plus Save and
   Reset.

## Running the tests

```bash
tools/run_tests.sh                 # all tests + headless boot smoke test
tools/run_tests.sh --filter=mining # only tests whose name or file matches
GODOT=/path/to/godot tools/run_tests.sh
```

The run fails if any test fails **or** if any script or engine error is printed. Tests live in
`tests/unit`, `tests/integration` and `tests/simulation` and use a small dependency-free framework
in `tests/framework`.

Other tools:

```bash
python3 tools/generate_greenvale_map.py      # regenerate + validate the starter map
python3 tools/generate_placeholder_art.py    # regenerate placeholder art
godot --headless --path . -s res://tools/balance_report.gd   # gathering, combat and crafting rates
godot --headless --path . -s res://tools/gacha_report.gd     # base and effective gacha rates
xvfb-run godot --path . --rendering-method gl_compatibility \
  -s res://tools/capture_screenshots.gd -- --out=/tmp/shots  # visual smoke test + screenshots
```

## Project layout

```
project.godot          Godot project (main scene: scenes/main/Main.tscn, autoload: Game)
data/                  All balance and content as JSON (skills, items, nodes, activities, characters, map, config)
scripts/core/          Game autoload, DataRegistry, SimulationWorld, StatBlock, AccountEffects, time source
scripts/activities/    ActivityEngine (state machine driver), Assignment, ActivityEstimator,
                       handlers/ (gathering, crafting, combat, construction)
scripts/characters/    Adventurer (runtime state), CharacterStates, CharacterView
scripts/pathfinding/   GridPathfinder (A* on AStarGrid2D, cached), PathResult
scripts/world/         WorldGrid, ResourceNodeState, chunk renderer, camera, views, day/night
scripts/skills/        XpTable, SkillSet
scripts/inventory/     Inventory (bags and storage)
scripts/progression/   Offline progression interface, local simulator, offline report
scripts/combat/        EnemyState, CombatRules
scripts/economy/       Wallet
scripts/equipment/     EquipmentService (equip, wear, repair, upgrade)
scripts/recruitment/   RecruitmentState (rolls, pity, effective rates)
scripts/town/          TownState (buildings, construction projects)
scripts/multiplayer/   GameBackend interface + LocalGameBackend (Nakama backend goes here)
scripts/save/          SaveService
scripts/ui/            HUD, panels, theme, pooled floating text
scenes/                Main, WorldView, HUD scenes
assets/                Placeholder art at final-art paths (see asset pipeline in docs)
tests/                 Unit, integration and simulation tests + runner
tools/                 Map/art generators, test runner script, balance report, screenshot capture
docs/                  Design, architecture, roadmap, systems, data schema, balance, changelog
```

Folders for later phases (quests and others) already exist and each has a README describing what
goes there.

## Documentation

| Document | Contents |
|---|---|
| [GAME_DESIGN.md](docs/GAME_DESIGN.md) | Vision, pillars, core loop, world, characters, all planned systems |
| [TECHNICAL_ARCHITECTURE.md](docs/TECHNICAL_ARCHITECTURE.md) | Layers, simulation model, backend plan, asset pipeline, coding conventions |
| [DEVELOPMENT_ROADMAP.md](docs/DEVELOPMENT_ROADMAP.md) | Phases 1-5, the running implementation checklist |
| [SYSTEMS.md](docs/SYSTEMS.md) | How each implemented system works and how to test it |
| [DATA_SCHEMA.md](docs/DATA_SCHEMA.md) | Every data file's schema, the save format, planned server entities |
| [BALANCE.md](docs/BALANCE.md) | XP curve, gathering rates, offline caps, planned gacha rates |
| [CHANGELOG.md](docs/CHANGELOG.md) | Version history |

## Platform notes

The project uses the Mobile renderer, portrait orientation and touch input, with mouse input
emulated as touch on desktop. Android and iOS export presets are not committed yet, because they
need your signing keys and bundle IDs. See "Mobile export" in
[TECHNICAL_ARCHITECTURE.md](docs/TECHNICAL_ARCHITECTURE.md#mobile-export).
