# Worldbound: Systems Reference (Phases 1 and 2)

How each implemented system works, where it lives, and how to test it.

---

## Data registry
**Files:** `scripts/core/data_registry.gd`, `scripts/core/json_data.gd`, `data/**`

- Loads all JSON once (`DataRegistry.get_default()`), builds the XP tables and indexes by ID.
- `validate()` checks the cross references: activity to node type and skill, node to item, rare
  drops, character skills and affinities, the 24-skill count, map row widths, unknown terrain
  symbols, and activity destinations. `Game.start_session` reports any problems with `push_error`.
- `get_config("a.b.c", fallback)` reads `data/config/game_config.json`.

**Test:** `tests/unit/test_data_registry.gd`. To try it by hand, break an ID in
`data/activities/activities.json` and run the tests.

## Skills and XP
**Files:** `scripts/skills/xp_table.gd`, `scripts/skills/skill_set.gd`, `data/skills/*.json`

- `XpTable.from_curve(cfg)` precomputes cumulative thresholds. `level_for_xp` is a binary search.
- `SkillSet` stores XP only. Levels are always derived from XP, so they cannot drift apart.
  `add_xp` ignores values that are not positive, NaN or infinite, caps at 200M, and returns the
  number of levels gained.
- XP multipliers are character affinity XP × passive `xp_multiplier.all` × passive
  `xp_multiplier.<skill>`.
- Character XP is 25% of skill XP (`character_progression.character_xp_share`) on a separate
  100-level curve.

**Tests:** `test_xp_table.gd`, `test_skill_set.gd`

## Inventory and storage
**Files:** `scripts/inventory/inventory.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/item_grid.gd`

- A single class serves both uses. Bags have `max_units` (28/24/32 by character). Storage has
  unlimited units and `max_distinct` = 48 item types.
- Atomic API: `can_add`, `add` (returns the amount accepted), `remove` (all or nothing), and
  `transfer_all_to` (moves what fits). It emits `changed`.
- The storage screen has text search (name or category) and sorting by name, quantity or category.

**Tests:** `test_inventory.gd`

## World grid and resource nodes
**Files:** `scripts/world/world_grid.gd`, `scripts/world/resource_node_state.gd`,
`data/regions/*.json`, `data/resources/resource_nodes.json`

- `WorldGrid` stores a terrain index per cell plus an overlay of blocking objects (nodes and the
  chest). It has `version` and `cells_changed` for cache invalidation and incremental updates.
- `ResourceNodeState` tracks charges, the respawn timer and reservations. A node is depleted at 0
  charges and refills fully after `respawn_seconds`. Only depleted nodes are ticked.

**Tests:** `test_resource_node.gd`, `test_waits_when_all_nodes_busy_then_resumes`

## Pathfinding
**Files:** `scripts/pathfinding/grid_pathfinder.gd`, `scripts/pathfinding/path_result.gd`

See TECHNICAL_ARCHITECTURE §3. Key properties: weighted A* (roads preferred), no corner cutting,
reports unreachable goals, path to a tile adjacent to an object, two bounded caches with
invalidation, and a per-tick request budget enforced by `SimulationWorld.take_path_budget()`.

**Tests:** `test_pathfinding.gd` (9 tests, including a check that every node in the real map is
reachable)

## Activity engine and state machine
**Files:** `scripts/activities/activity_engine.gd`, `scripts/characters/character_states.gd`,
`scripts/activities/assignment.gd`, `scripts/characters/adventurer.gd`

Decision logic in `CHECKING_CONDITIONS`, in priority order:

1. If the target quantity is reached, deposit what is carried, then COMPLETED.
2. If the bag fill is at or above the threshold, or the next yield will not fit, or bag plus
   deposited covers the target, return to storage.
3. If the current node is still reserved and available, keep working it (no re-path when
   adjacent).
4. Otherwise pick the best node: preferred IDs first, then the nearest free node that is not
   depleted and not on cooldown. If there is none, WAITING (retry every 2 s).

Gather timing is `gather_seconds / (affinity_speed × (1 + min(0.005 × levels_over_req, 0.4)))`.
Rare drops roll per gather with `chance × passive rare multiplier` and are added only if there is
room.

Events emitted by the world: `assignment_started`, `state_changed`, `item_gathered`, `xp_gained`,
`level_up`, `character_level_up`, `rare_drop`, `node_depleted`, `node_respawned`, `deposited`,
`interrupted`, `assignment_completed`.

**Tests:** `test_state_machine.gd`, `test_assignment.gd`, `tests/integration/test_gathering_loop.gd`
(acceptance loop, woodcutting, fishing, return threshold, until-quantity, one trip, cancel, three
characters on the same activity without sharing nodes, waiting for respawns, re-routing around
new obstacles)

**Manual test:**
1. Run the game and tap Brom.
2. Tap Assign, choose Mine Copper, choose Full, choose Repeat, then Start.
3. Press **x20**. Watch him walk the road north into the mine, swing the pickaxe, and fill his bag
   (the bar above his head and the panel). He walks back to the chest, "Deposited 28" appears, and
   he heads back out.
4. Open Storage to see the ore.

## Activity handlers (Phase 2)
**Files:** `scripts/activities/handlers/*.gd`

The engine runs travel, pathfinding, depositing, restocking, waiting, resting and injury for every
activity, and asks the handler for the activity's `type` what to do at the work site. A handler
implements `validate`, `decide` (the CHECKING_CONDITIONS step), `on_arrive`, `perform`,
`primary_item`, `keep_on_deposit`, `after_deposit`, `wants_restock` and `restock`. Handlers hold no
state, so loops survive save/load.

| Handler | Loop |
|---|---|
| Gathering | Phase 1 loop, plus tool wear, `yield_bonus_chance` and night speed |
| Crafting | inputs in bag → walk to nearest station → craft until out → storage: deposit, RESTOCKING (as many batches as fit) → repeat; WAITING "Waiting for materials" when storage is short |
| Combat | pick enemy (priority, then nearest, skipping engaged ones and those above the level limit) → walk adjacent → COMBAT (event-timed swings) → loot, gold, XP → next; eat below the heal threshold; retreat below the retreat threshold with no food; 0 HP → INJURED (carried home, 60 s) → RESTING to full |
| Construction | walk to the plot's work tile → 3 s work actions add work and Construction XP → project completes → wait for the next project |

**Manual test (combat):** assign Brom to *Clear the East Meadows*, press x20 and follow him: he
walks east, swings at slimes and rats (damage numbers, enemy HP bars), gold appears, and he goes
home when his bag fills.

**Manual test (crafting):** let Brom mine copper and tin for a while, then assign him to *Smelt
Bars → Bronze Bar*. He walks to the chest, takes ore, walks to the furnace and smelts.

## Recruitment (Phase 2)
**Files:** `scripts/recruitment/recruitment_state.gd`, `SimulationWorld.recruit`,
`scripts/ui/recruit_panel.gd`. Rules and rates are in BALANCE.md. Rolls use their own RNG so
recruiting never changes the world RNG sequence. **Local rolls are development-only**; the Phase 4
server owns them.

**Manual test:** tap **Recruit**, then **Recruit x10** (uses the 10 starting tokens). New heroes
appear in the roster bar; the rates list shows pity progress (for example `3 / 10`).

## Equipment (Phase 2)
**Files:** `scripts/equipment/equipment_service.gd`, `scripts/ui/equipment_panel.gd`. Pristine
items live in storage stacks; used or upgraded items keep their identity in the armory. Equipped
and armory items count as held for the item ledger.

**Manual test:** build the Blacksmith, forge a Bronze Pickaxe, open
**Storage**, tap the pickaxe, **Equip on Brom**, then open **Gear** to see durability fall while he
mines.

## Town (Phase 2)
**Files:** `scripts/town/town_state.gd`, `scripts/ui/town_panel.gd`,
`scripts/activities/handlers/construction_handler.gd`, `scripts/world/building_view.gd`.

**Manual test:** saw oak planks, open **Town**, **Build** the Bank, then assign two heroes to
*Construct Buildings*. Scaffolding appears on the plot and turns into the building at 100%;
storage slots go from 48 to 64.

## Economy (Phase 2)
`Wallet` (atomic multi-currency spend, rejects negative and invalid amounts, caps balances,
keeps a 100-entry history). Sources: starting balances, loot gold, NPC sales, milestones, tavern.
Sinks: recruitment, construction, repair, upgrade, respec. Items: `item_sources` and
`item_sinks` in `SimulationWorld`; `held_totals() == ledger_totals()` must always hold.

## Route builder (Phase 2)
`Assignment.route` holds step assignments. When a step completes, the engine starts the next one
(wrapping when `route_loop` is set). Steps must end (Until amount or One trip). Templates are saved
in the world. **Manual test:** in Assign, add *Mine Copper until 20*, *Mine Tin until 20* and
*Smelt Bronze until 20* as steps, tick Loop, then **Start route**.

## Offline progression
**Files:** `scripts/progression/*.gd`, `scripts/multiplayer/*.gd`, `scripts/save/save_service.gd`,
`scripts/core/time_source.gd`, `scripts/ui/offline_report_panel.gd`

See TECHNICAL_ARCHITECTURE §5.

**Tests:** `tests/simulation/test_offline_progress.gd`, `tests/integration/test_backend.gd` (fake
clock: two hours away is applied once, a corrupt save starts fresh, clock rollback grants
nothing)

**Manual test:**
1. Assign all three characters.
2. Open **Dev**, then **Simulate 1 hour away**. Check the report.
3. Try **Simulate 2 days away**: the report shows the 8 h cap.
4. For a real test, close the game, wait at least 1 minute, and reopen it.

## Save system
`SaveService` writes JSON atomically. `SimulationWorld.to_dict()/from_dict()` covers storage,
characters (tile, skills, bag, state, assignment, path, timers, stats), modified nodes, the RNG
seed and state, sim time, and the ledger. Characters added to data after a save join at spawn.

**Tests:** `test_save_load_round_trip_preserves_everything`, `test_repeated_save_load_does_not_duplicate`,
`test_tampered_save_reservations_are_cleared`

## Presentation
| Component | File | Notes |
|---|---|---|
| Main | `scripts/core/main.gd` | Instances WorldView and HUD, starts the session. `--smoke-test` mode |
| WorldView | `scripts/world/world_view.gd` | Builds node, character and label views. Tap to select. Floating-text reactions to events |
| ChunkRenderer | `scripts/world/chunk_renderer.gd` | Pooled TileMapLayer chunks around the camera |
| WorldCamera | `scripts/world/world_camera.gd` | Touch drag, pinch, wheel, follow, clamped |
| CharacterView | `scripts/characters/character_view.gd` | Walk and idle animations, tool swing, particles, bag bar, selection ring |
| ResourceNodeView | `scripts/world/resource_node_view.gd` | Depleted sprite and respawn ring, fishing bob |
| HUD | `scripts/ui/hud.gd` | Top bar (clock, storage, speed, dev), character panel, roster, bottom nav, toasts |
| Panels | `scripts/ui/*_panel.gd` | Activity (with XP/h estimate), Inventory/Storage, Skills, Offline report |

**Visual test:** `tools/capture_screenshots.gd` renders 8 screenshots of the key screens (requires
a display or Xvfb).

## Test inventory (148 tests)

| Suite | File | Tests | Covers |
|---|---|---|---|
| unit | test_xp_table | 7 | XP curve |
| unit | test_skill_set | 5 | skill XP and levels |
| unit | test_inventory | 7 | bags and storage |
| unit | test_pathfinding | 9 | A*, caching, reachability |
| unit | test_state_machine | 4 | legal transitions |
| unit | test_data_registry | 5 | data validation |
| unit | test_resource_node | 3 | charges, reservations |
| unit | test_assignment | 4 | assignment rules |
| unit | test_estimator | 3 | estimates vs simulation |
| unit | test_wallet | 7 | currency transactions |
| unit | test_stat_block | 7 | stat combination |
| unit | test_recruitment | 14 | gacha probabilities (chi-square), pity, costs, fragments, stars |
| unit | test_equipment | 11 | equip, wear, repair, upgrade |
| unit | test_progression | 6 | traits, milestones, specializations |
| integration | test_gathering_loop | 10 | Phase 1 acceptance loop |
| integration | test_crafting_loop | 7 | crafting requirements and loop |
| integration | test_combat_loop | 9 | combat, injury, retreat, variants |
| integration | test_town | 8 | construction, capacity, selling |
| integration | test_routes | 5 | route builder |
| integration | test_backend | 3 | save/offline with a fake clock |
| simulation | test_conservation | 6 | item ledger across every system |
| simulation | test_offline_progress | 8 | offline simulation and reports |
| smoke | Main.tscn headless boot (in run_tests.sh) | 1 | scenes, UI, autoload |
