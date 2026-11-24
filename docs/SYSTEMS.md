# Worldbound: Systems Reference (Phase 1)

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

## Test inventory (72 tests)

| Suite | File | Tests |
|---|---|---|
| unit | test_xp_table | 7 |
| unit | test_skill_set | 5 |
| unit | test_inventory | 7 |
| unit | test_pathfinding | 9 |
| unit | test_state_machine | 4 |
| unit | test_data_registry | 5 |
| unit | test_resource_node | 3 |
| unit | test_assignment | 4 |
| unit | test_estimator | 3 |
| integration | test_gathering_loop | 10 |
| integration | test_backend | 3 |
| simulation | test_conservation | 5 |
| simulation | test_offline_progress | 7 |
| smoke | Main.tscn headless boot (in run_tests.sh) | 1 |
