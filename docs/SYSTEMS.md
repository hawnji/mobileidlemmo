# Worldbound: Systems Reference (Phases 1 to 3)

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
recruiting never changes the world RNG sequence. Offline the pull runs on the device; online
(Phase 4) the server rolls and charges it and the client only adds the results
(`OnlineSync.apply_recruit`).

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

## World map and regions (Phase 3)
**Files:** `data/regions/world_map.json` (generated by `tools/generate_world_map.py`),
`SimulationWorld.region_unlock_gap/unlock_region/_refresh_gates`, `scripts/ui/map_panel.gd`

- One 128x96 map holds four regions. `ExplorationState.region_at(tile)` maps every tile to a region.
- Gate tiles (one on each side of a border) are object-blocked until both regions are unlocked.
- Unlock = all `unlock.conditions` met (see Conditions) + `unlock.cost` paid.
- Nodes, enemies, locations and activities in a locked region are skipped by the engine and
  rejected at assignment time ("Unlock X first").

## Fog of war, exploration and discoveries (Phase 3)
**Files:** `scripts/world/exploration_state.gd`, `handlers/exploration_handler.gd`,
`SimulationWorld.on_character_moved/survey/try_discover`, `scripts/world/fog_overlay.gd`

- One byte per tile; the map is split into 8x8 blocks with a hidden-tile count each, so a reveal
  over an already explored area costs a few block checks (this is the offline hot path).
- Every character reveals `walk_reveal_radius` (1) every 2 tiles it moves. The Explore activity
  walks to the nearest hidden walkable tile and surveys for `survey_seconds` (60 s, divided by the
  Exploration gather-speed multiplier), revealing `reveal_radius` (4 + level/25 + gear).
- Exploration XP = `xp_per_tile` x new walkable tiles. Region progress counts walkable tiles only.
- Discoveries are found when a qualifying character comes within the detect radius; surveys spot
  them from further away. Rewards can reveal secret passages or hidden nodes.

**Tests:** `test_world_expansion` (fog, survey, discovery requirements, secrets).

## Navigation between regions (Phase 3)
**Files:** `scripts/pathfinding/region_navigator.gd`, `ActivityEngine._pathfind`

- `region_route(a, b)`: BFS over open gates. `next_hop(from, goal)` returns DIRECT (same region),
  WALK (to the far side of the next gate), WALK_ADJACENT (to a waystone), TELEPORT (between
  waystones when the walk is over `fast_travel_min_distance`) or NO_ROUTE.
- A* runs per leg, so searches stay inside one region and the path cache keeps working.
- Characters deposit at their region's outpost depot when it is built (`nearest_deposit`); all
  depots feed the same shared storage.

## Outposts (Phase 3)
Buildings with `kind: "outpost"`. Level 1 needs the region unlocked (level `requires[]`). Built
outposts activate their stations, a depot, a waystone and `local_effects` (gather speed, XP) for
activities inside the region (`SimulationWorld.local_multiplier`).

## Quests, reputation and vendors (Phase 3)
**Files:** `scripts/quests/quest_state.gd`, `scripts/progression/objectives.gd`,
`scripts/ui/quests_panel.gd`

- Quests activate when prerequisites are met; counter objectives snapshot a baseline from world
  `counters` at activation, so earlier kills do not count. Claiming consumes `deliver` items and
  grants rewards; contracts go on cooldown.
- Reputation per region with five tiers. Tiers unlock vendor stock, recipes
  (`requires_reputation`) and the reputation character (Hulda Ironbraid at Honored in Irondeep).

## Dungeons and bosses (Phase 3)
**Files:** `scripts/combat/dungeon_run.gd`, `SimulationWorld.start_dungeon/_finish_dungeon`

- The party leaves the map (state AWAY). The run advances in fixed 0.1 s sub-steps: entry, floors
  of enemies, then the boss. Members attack the first living foe, use their active ability
  (guard, strike, multi-strike, strike-all, heal, buff) on its cooldown and eat from the food pool.
- Bosses change phase below health thresholds, use area/special/summon/heal abilities on timers
  and enrage after `enrage_seconds`. Summoned adds give no loot.
- Food comes out of storage at the start; leftovers go back. Loot and gold are created only when
  the run ends; overflow goes to the mailbox. Wiped members return injured.
- The whole fight state is saved, so a run survives save/load and offline time.

**Tests:** `test_adventures` (clear, wipe, size/region checks, phases, save mid-fight).

## Expeditions (Phase 3)
**Files:** `scripts/expeditions/expedition_state.gd`, `scripts/ui/journeys_panel.gd`

- Slots come from the Expedition Center. A team of exactly `team_size` that meets every
  requirement leaves (AWAY). The result is rolled when the timer ends, from an RNG seeded at the
  start, so online, offline and reloaded runs give the same story and rewards.
- Success chance = `base_success + power_weight x min(team power / recommended, 1.5)` (+ supplies),
  clamped to 5% to 97%. Stages the team qualifies for add rewards or reduce risk; events are
  ambushes (power checks), hazards (skill checks) and bonuses. Failure pays 25% and injures half
  the team.

## Dynamic encounters (Phase 3)
**Files:** `scripts/world/encounter_director.gd`, `data/world/encounters.json`

Every 10 to 25 minutes of simulation time (own RNG stream), one of five encounter kinds appears
in a matching location of an unlocked region for a limited time: a treasure goblin (temporary
enemy), a bountiful harvest (yield multiplier), a travelling merchant (limited stock), a monster
surge (faster respawns, more gold) or a wandering hero (joins the first character to come close).

## Notifications and mailbox (Phase 3)
`NotificationCenter` turns important events into inbox entries by category, merging repeats
inside the cooldown. `LocalNotifier` hands entries to a `LocalNotification` engine singleton if a
plugin provides one; otherwise nothing reaches the OS (honest gap). Rewards that do not fit in
storage go to the mailbox (`claim_mailbox`), never destroyed.

## Online play (Phase 4)
**Files:** `scripts/multiplayer/` (`nakama_client.gd`, `nakama_socket.gd`, `online_service.gd`,
`online_sync.gd`, `nakama_game_backend.gd`, `wb_server_data.gd`), `scripts/ui/social_panel.gd`,
`scripts/world/presence_layer.gd`, and the server in `server/` (see server/README.md).

- **Going online.** Social > Account takes a server address, key and player name, saves them to
  `user://online.cfg` and restarts the session on `NakamaGameBackend`. Start-up signs in with a
  per-install device id, loads the cloud save if it is further along than the device save, and
  falls back to the device save if the server is unreachable. Play offline clears the setting.
- **Cloud sync.** Saves upload at most once a minute and right after server-side actions. A
  refused upload (validation or another device) shows a toast and the reason in Social > Account,
  which also has Sync now, Load cloud save and Collect deliveries.
- **Recruitment** online goes through the server; pity counters on the banner screen are the
  server's.
- **Friends**: add by player name, accept, remove, visit their town (buildings, heroes, regions),
  start a private trade.
- **Guild**: browse, join, create, leave; donate gold to level the guild; members get its perks
  (shown as "Member bonus"); realtime guild chat.
- **Market**: list tradeable storage items for a total price (optionally for one friend), browse
  sorted by unit price, buy, cancel. Payments, purchases and returns arrive as deliveries,
  collected automatically every two minutes and after each purchase.
- **World**: active world events with time left, the world boss with shared HP, cooldown and top
  damage, and the players whose heroes share your region. Their heroes appear on the map as blue
  markers with the player's name.
- Speed-up and the developer time skip are off while online (the server only accepts real time).

**Tests:** `tests/unit/test_online_sync.gd` (11, no server: wallet cache, server pulls, escrow,
deliveries, cloud vs local, guild and event effects, settings). With a server running:
`server/run_tests.sh` runs `server/tests/test_server.mjs` (20) and `tests/online/` (9: real save
round trip and public town, honest progress accepted and gems credited, impossible progress and a
fast clock rejected, second-device conflict, a new device starting from the cloud save, server
recruitment, a market sale settling on both saves, guild donations and perks, guild chat and
region presence over the socket).

**Manual test:** start a server (`server/run_local.sh`), go online from Social > Account on two
devices (or a desktop and a phone), add each other as friends, create and join a guild, chat,
list ore on one and buy it on the other, then attack the world boss from both.
`tools/capture_online_screenshots.gd` scripts a second player and captures screens 25 to 31.

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

| SocialPanel | `scripts/ui/social_panel.gd` | Account, Friends, Guild (chat), Market, World (events, boss, players nearby) |
| PresenceLayer | `scripts/world/presence_layer.gd` | Other players' heroes as named blue markers, interpolated |

**Visual test:** `tools/capture_screenshots.gd` renders 24 screenshots of the key screens (requires
a display or Xvfb).

## Test inventory (200 offline tests, plus 29 against a live server)

| Suite | File | Tests | Covers |
|---|---|---|---|
| unit | test_xp_table | 7 | XP curve |
| unit | test_skill_set | 5 | skill XP and levels |
| unit | test_inventory | 7 | bags and storage |
| unit | test_pathfinding | 11 | A*, caching, reachability, gates |
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
| unit | test_online_sync | 11 | Phase 4 client rules without a server |
| integration | test_gathering_loop | 10 | Phase 1 acceptance loop |
| integration | test_crafting_loop | 7 | crafting requirements and loop |
| integration | test_combat_loop | 9 | combat, injury, retreat, variants |
| integration | test_town | 8 | construction, capacity, selling |
| integration | test_routes | 5 | route builder |
| integration | test_backend | 3 | save/offline with a fake clock |
| integration | test_world_expansion | 23 | regions, gates, fog, surveys, discoveries, secrets, navigation, fast travel, outposts, quests, reputation, vendors, mailbox, save v3 |
| integration | test_adventures | 16 | dungeons, bosses, expeditions, encounters, notifications |
| simulation | test_conservation | 6 | item ledger across every system |
| simulation | test_offline_progress | 8 | offline simulation and reports |
| smoke | Main.tscn headless boot (in run_tests.sh) | 1 | scenes, UI, autoload |
| online | tests/online/test_online_client (needs `WB_NAKAMA_URL`) | 9 | Godot client against Nakama |
| server | server/tests/test_server.mjs (Node, needs a server) | 20 | every RPC, validation, races, socket chat and presence, world boss |
