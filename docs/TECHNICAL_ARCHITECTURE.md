# Worldbound: Technical Architecture

## 1. Overview

```
+---------------------------------------------------------------------------+
| Presentation (Nodes)                                                      |
|  Main.tscn -> WorldView (ChunkRenderer, ResourceNodeViews, CharacterViews,|
|               WorldCamera, FloatingTextPool, DayNight)                    |
|            -> HUD (CharacterBar, CharacterPanel, modal panels, toasts)    |
|  Reads state every frame, listens to events, sends commands only.        |
+------------------------------^-----------------------+--------------------+
                               | event_emitted / reads | assign / cancel
+------------------------------+-----------------------v--------------------+
| Game autoload: fixed-step clock (0.1 s), session, autosave, pause/resume |
+------------------------------^-----------------------+--------------------+
                               |                       |
+------------------------------+-----------------------v--------------------+
| Simulation (RefCounted, no Nodes) - SimulationWorld                       |
|  WorldGrid - GridPathfinder - ResourceNodeState[] - EnemyState[] - Adventurer[]|
|  ActivityEngine + handlers (gathering, crafting, combat, construction)    |
|  Inventory - SkillSet - StatBlock/AccountEffects - Wallet - TownState     |
|  RecruitmentState (dev-only rolls) - EquipmentService - item ledger       |
|  seeded RNG - to_dict()/from_dict()                                       |
+------------------------------^-----------------------+--------------------+
                               |                       |
+------------------------------+------------+   +------v--------------------+
| DataRegistry (res://data/*.json)          |   | GameBackend (interface)   |
| validated on load, read-only at runtime   |   |  LocalGameBackend  [P1]   |
+-------------------------------------------+   |  NakamaGameBackend [P4]   |
                                                |  OfflineProgressionProvider|
                                                +---------------------------+
```

### Principles (from the master spec, and how they are met)

| Requirement | Implementation |
|---|---|
| Separate rendering from simulation | `SimulationWorld` and everything it owns are `RefCounted` with no Node, scene or rendering code. Views read state and interpolate positions |
| Separate persistent state from presentation state | Only `to_dict()` data is persisted. Selection, camera, animation phase and tweens live in Nodes and the `Game` presentation fields |
| Data-driven balance | Skills, the XP curve, items, nodes, activities, characters, terrain, the map and tunables are all JSON under `data/`. Nothing about balance is hard-coded in gameplay scripts (the level-speed constants are the one exception, documented in BALANCE.md and scheduled to move into data) |
| Never trust the client | Still single-player with local authority. All mutations go through `SimulationWorld`'s command API (`assign_activity`, `cancel_assignment`, `start_route`, `equip`, `unequip`, `repair`, `upgrade_equipment`, `sell_item`, `start_construction`, `recruit`, `star_up`, `choose_specialization`, `respec`), each returning "" or a reason, which is the shape a server needs. Gacha rolls are explicitly dev-only on the client. See section 6 |
| No per-frame pathfinding for everyone | Paths are computed only on the PATHFINDING state, cached, and limited to N requests per tick |
| Many characters | The simulation cost is per event (gather, step), not per frame. Off-screen characters skip animation. Chunks and floating text are pooled |
| Modular | One responsibility per script, about 40 scripts, no file over about 400 lines |

## 2. Simulation model

### Fixed-step clock

`Game._process` accumulates real time multiplied by `time_scale` and calls
`world.step(0.1)` as many times as needed, capped to avoid a spiral of death. `step(dt)` does
three things:

1. Resets the per-tick pathfinding budget (`pathfinding_requests_per_tick`, default 4).
2. Ticks only **depleted** resource nodes, which advances their respawn timers.
3. Calls `ActivityEngine.tick(character, dt)` for each character, in a stable order.

### Time-budget state handlers

`ActivityEngine.tick` repeatedly runs the handler for the current state. **Each handler returns
the time it did not use** (for example, a character arriving mid-tick carries the remaining time
into PERFORMING_ACTIVITY). A 1 s step therefore produces the same outcome as ten 0.1 s steps.
`test_coarse_offline_steps_match_fine_live_steps` checks this. It is what allows the offline
simulator to reuse the live rules exactly and still run quickly.

A safety cap (`max_state_steps_per_tick`) and a "no progress means stop" check prevent infinite
loops inside a tick.

### Determinism

The world owns a seeded `RandomNumberGenerator`. Its seed and state are saved, and characters
always tick in `character_order`. Reloading a save and continuing gives identical results
(`test_save_load_round_trip_preserves_everything`). That is a prerequisite for server-side
re-simulation and anti-cheat verification.

### Exploit safety (no duplication)

- `Inventory.add` returns exactly how many units were accepted, and `remove` is all-or-nothing.
- During a gather, the node **charge is consumed first**, and items are only granted when the
  charge was real and space exists. If there is no room, nothing is consumed or granted.
- Deposits use `transfer_all_to`, which moves only what fits and keeps the rest.
- The item ledger records every unit that enters the world (`item_sources`: gathering, loot,
  crafting output) and every unit that leaves it (`item_sinks`: crafting input, food eaten,
  construction, upgrades, NPC sales). The tests assert `storage + bags + equipped + armory ==
  sources − sinks` continuously, across save/load, offline simulation and every Phase 2 system.
- Crafting removes inputs before adding outputs and never creates an output that cannot fit.
  Loot that does not fit is never created. Currency changes go through `Wallet`, which is
  all-or-nothing and rejects negative amounts.
- Loaded saves are sanitised: node charges are clamped, orphan reservations are dropped,
  assignment values are clamped, and bag capacity comes from data rather than from the save.

### Activity handlers and stats (Phase 2)

`ActivityEngine` owns the shared state machine and delegates per-type behaviour to stateless
`ActivityHandler` subclasses (see SYSTEMS.md). Combat resolves swings on exact event times
(`min(next player swing, next enemy swing)`), so results do not depend on the step size
(`test_combat_independent_of_step_size`).

Every gameplay number a character uses comes from `Adventurer.stat(family, skill)`: a cached
`StatBlock` folding affinities, passive, traits, specializations, stars and equipment, merged with
the account-wide `AccountEffects` block (buildings; later relics, pets, guild perks, ascension).
`AccountEffects.current()` rebuilds only when a source's `version` changes, and each character
re-folds only when its own sources or the account version change; individual lookups are memoised.

## 3. Pathfinding

`GridPathfinder` wraps Godot's native `AStarGrid2D`:

- 8-directional movement with `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`, so there is no corner cutting.
- Octile heuristic. Point weights are `move_cost / min_move_cost`, normalised so the cheapest
  terrain costs 1.0. Without this, roads (cost 0.6) would make the heuristic inadmissible and A*
  would ignore them. This was found and fixed by `test_prefers_roads`.
- Two caches: point-to-point and point-to-adjacent-of-object. Both are bounded at 512 entries and
  are dropped when `WorldGrid.version` changes (any walkability change). Cached paths are returned
  as copies.
- `find_path_to_adjacent(from, target)` finds a standing tile next to a blocking object (rock,
  tree, fishing spot or chest). It tries candidates nearest first and prefers orthogonal ones.
- Unreachable goals return `PathResult.unreachable()`. The engine handles these with cooldowns,
  retries and a stuck limit.

**Chunked navigation [P3]:** Phase 1 uses one AStarGrid2D for the whole 64x48 region. For large
regions, the plan is hierarchical pathfinding: an A* over a chunk-portal graph (64x64 chunks), then
local A* inside the chunks along the route. `WorldGrid` already exposes `chunk_of()` and
`chunk_count()`, and `cells_changed` updates individual cells incrementally. Regional transitions
become portal edges between region grids.

## 4. Rendering

- **ChunkRenderer** creates one `TileMapLayer` per 16x16 chunk (configurable) for the chunks that
  overlap the camera view plus a one-chunk margin. Chunks that leave the view are cleared and
  pooled. The TileSet is built from `terrain.json` plus the atlas PNG, including water animation
  frames.
- **Entities** are y-sorted. CharacterViews interpolate toward the simulation's sub-tile position
  with exponential smoothing, and snap on teleport.
- **Visibility management**: every 0.25 s, characters outside the camera rect (plus margin) are
  hidden and skip animation, particles and floating text. The simulation continues unaffected.
- **Object pooling**: floating text uses a 40-label pool, and terrain chunks are pooled.
- **Day/night**: a `CanvasModulate` gradient driven by `sim_time` (one in-game day is 24 real
  minutes).

## 5. Persistence and offline progression

- `SaveService` writes `user://worldbound_save.json` atomically (temp file, then rename). Saves are
  versioned (`save_version`) and the world has its own `format`.
- `Game` autosaves every 30 s, on quit or back, and on `NOTIFICATION_APPLICATION_PAUSED`. When the
  app is backgrounded on mobile, the live clock is frozen. On resume, the elapsed time goes to the
  offline provider exactly once.
- `OfflineProgressionProvider` is the interface. `LocalOfflineSimulator` clamps elapsed time to
  [0, cap] and ignores anything under 60 s. It snapshots the world, advances it in 1 s steps with
  chatty events suppressed (`world.quiet`), snapshots again, and builds an `OfflineReport` from the
  difference plus the rare-find and interruption events. Because the report is a diff of real
  state, it cannot over-report.
- **Server replacement [P4]**: a `ServerOfflineProvider` asks the Offline Simulation Service, which
  runs the same rules from the last authoritative timestamp, and applies the returned state. The
  client clock is never trusted. `TimeSource` is the seam for that.

## 6. Backend and multiplayer architecture (planned, P4)

`GameBackend` is the only boundary between gameplay and persistence or authority:

```
load_world(registry) -> {world, saved_at_unix}
save_world(world)
now_unix()
get_offline_provider()
```

Phase 4 adds `NakamaGameBackend`.

| Service | Responsibility | Tech |
|---|---|---|
| Authentication | Device, Apple and Google login, sessions | Nakama |
| Player / Character | Profile, roster, ownership | Authoritative Go/TS service + PostgreSQL |
| Activity Engine + Offline Simulation | Runs `SimulationWorld` rules server-side, periodically and on login | Headless Godot or a port of the rules (see below) |
| Inventory / Economy / Crafting | Items, currency, recipes, sinks | Service + PostgreSQL (transactions) |
| Recruitment | Gacha rolls, pity per banner, history | Service + PostgreSQL. **Never client-side** |
| Marketplace / Trading | Listings, escrow, fees, price history | Service + PostgreSQL + Redis cache |
| World / Events | Shared town state, world events, community projects | Service + Redis (live) + PostgreSQL |
| Guild / Social / Chat | Guilds, friends, DMs | Nakama social + storage |
| Notification | Push for rare finds, completed jobs and full bags | Nakama + FCM/APNs |

**Command model.** The client sends *intents* such as "assign Brom to mine_copper with these
rules". The server validates ownership, levels and destinations, which is the same
`validate_assignment` logic, and returns authoritative state. The client keeps simulating locally
for presentation, and reconciles whenever authoritative snapshots arrive.

**Rules on the server.** The simulation is deliberately pure GDScript with no Node dependencies, so
it can run in a headless Godot server build (`godot --headless`) as the Activity and Offline
service. The alternative is to port it to Go/TypeScript and keep both in sync using the
deterministic test vectors from `tests/simulation`. **This is an open decision for Phase 4** (see
the roadmap).

## 7. Asset pipeline

- All art lives at its **final path** with its **final dimensions**. Placeholders are generated by
  `tools/generate_placeholder_art.py`, and artists overwrite the files with no code changes.
- Data files reference art by path: `portrait`, `sprite`, `icon`, node `sprite` and
  `depleted_sprite`. Terrain references atlas coordinates.
- Standards:
  - Tiles are 32x32 in the `assets/environments/tiles/greenvale_tiles.png` atlas, 8 columns. Water
    animation frames are on row 2.
  - Character sheets are 128x128: 4 frames by 4 directions (down, left, right, up) of 32x32, with
    the feet at y≈28. Frame 0 is idle. Future gather, combat and cast animations will be extra rows
    with named animations in `CharacterView._build_frames`.
  - Portraits are 64x64. Item icons are 32x32. Skill icons are 48x48. Nodes are 32x32, and trees
    are 32x48.
  - Pixel-art filtering is nearest-neighbour, set project-wide.
- Tool overlays for the gather animations are in `assets/equipment/tools/`.

## 8. Coding conventions

- **GDScript 4, static typing everywhere** (`var x: int`, `-> void`). `:=` is used only when the
  type can be inferred.
- Files are `snake_case.gd`. Classes are `PascalCase` with `class_name` for reusable types. Scenes
  are `PascalCase.tscn`.
- Data IDs are `snake_case` strings (`copper_ore`, `mine_copper`, `brom_stonefist`). IDs are stable
  forever because saves and servers reference them.
- Constants are `UPPER_SNAKE`, signals are past tense (`event_emitted`, `selection_changed`), and
  private members start with `_`.
- Simulation classes are `RefCounted`, own no Nodes, and use no `randf()` globals. They use
  `world.rng` so results stay deterministic.
- Only `ActivityEngine` changes `Adventurer.state`, and it always goes through
  `CharacterStates.can_transition`.
- UI never mutates simulation state directly. It calls `SimulationWorld` command methods.
- Each script starts with a `##` doc comment saying what it owns.
- New behaviour needs tests. `tools/run_tests.sh` must pass with no printed errors before merging.

## 9. Performance notes and measured numbers

These were measured on the development container (Godot 4.3 editor binary, which runs GDScript
slower than export templates):

| Scenario | Time |
|---|---|
| 148-test suite | ~19 s (about 2 s of it is the 10^6-roll chi-square test) |
| 8 h offline, 3 working characters (`test_eight_hour_simulation_is_fast_enough`) | ~3.4 s (was 2.7 s in Phase 1; stat lookups now go through StatBlock) |
| One gather cycle (check, perform, grant, events) | ~60-100 µs |
| Cached path lookup | ~4 µs |

**Known scaling limit:** offline time grows linearly with characters × hours. That is fine for 3
characters, but 50 characters over 8 h would take tens of seconds on a phone. The planned fixes,
in order:

1. Move offline simulation to the server (P4).
2. Add steady-state cycle extrapolation: when a character's loop is unchanged for N trips, compute
   the remaining whole cycles analytically and simulate only the remainder.
3. Profile on device with release export templates.

## 10. Mobile export

Not committed yet, because export presets contain signing data.

- **Android**: install the Android build template, add a preset with a package name such as
  `com.<studio>.worldbound` and a keystore, and use orientation portrait (already set) and
  `rendering/textures/vram_compression/import_etc2_astc=true`.
- **iOS**: requires macOS with Xcode, a bundle ID and a team ID.
- Touch is the primary input. Mouse is emulated as touch on desktop.
  `NOTIFICATION_APPLICATION_PAUSED/RESUMED` drive save and offline handling.
