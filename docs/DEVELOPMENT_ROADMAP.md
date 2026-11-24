# Worldbound: Development Roadmap and Implementation Checklist

Legend: ✅ done and tested · 🟡 partial or scaffolded · ⬜ not started

## Phase 1: Core playable prototype (complete)

### Prototype completion requirements (master spec section 28)

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Game launches successfully | ✅ | Headless boot smoke test in `tools/run_tests.sh`; rendered under Xvfb by `tools/capture_screenshots.gd` |
| 2 | World is navigable | ✅ | Drag/pinch/wheel camera, chunked terrain; `test_every_node_in_starter_map_is_reachable_from_storage` |
| 3 | Characters can be selected | ✅ | Roster cards, tap in world, Follow |
| 4 | Characters can be assigned activities | ✅ | ActivityPanel; `test_engine_rejects_*`, `test_round_trip` |
| 5 | Characters autonomously pathfind | ✅ | `test_pathfinding.gd`, `test_recovers_when_path_gets_blocked` |
| 6 | Characters gather resources | ✅ | `test_mining_acceptance_loop`, woodcutting, fishing |
| 7 | XP is awarded correctly | ✅ | `test_xp_table.gd`, `test_skill_set.gd`, loop tests |
| 8 | Inventory capacity works | ✅ | `test_inventory.gd`, `bag never exceeded capacity`, `test_return_threshold_respected` |
| 9 | Characters return automatically | ✅ | Loop tests assert RETURNING visited at least twice |
| 10 | Resources deposited correctly | ✅ | Storage assertions, `test_until_quantity_completes_and_stops` (exact count) |
| 11 | Characters resume their assignments | ✅ | Two or more deposit cycles per loop test; still busy at the end |
| 12 | No duplicate resource exploits | ✅ | `test_conservation.gd` (ledger equals holdings, save/load x5, tampered saves), offline no-double-grant |
| 13 | Core systems documented | ✅ | `docs/` |
| 14 | Major functionality has automated tests | ✅ | 72 tests (see SYSTEMS.md) |

**Acceptance criterion:** "A character can be assigned to mining, automatically navigate to the
mine, gather ore, gain experience, return to storage when inventory is full, deposit the ore, and
repeat without continuous player input." This is ✅, verified by
`tests/integration/test_gathering_loop.gd::test_mining_acceptance_loop`.

### Phase 1 feature checklist

- ✅ Godot project, main scene, autoload, folder structure
- ✅ Tile-based world (64x48), village, forest, mine, river, roads, bridge, blocked terrain
- ✅ Camera (pan, zoom, follow, clamped)
- ✅ Character movement with smooth interpolation and 4-direction walk animation
- ✅ A* pathfinding (weighted, cached, budgeted, recovers from blocked paths)
- ✅ Three characters with data, portraits, sprites
- ✅ Mining (copper and tin), woodcutting (oak), fishing (minnows), plus rare drops
- ✅ Inventory (bags) and storage (search, sort, slot limit)
- ✅ Character XP plus 24-skill XP system
- ✅ Activity assignments with automation rules (threshold, repeat, until N, one trip)
- ✅ Automated return to storage, deposit, resume
- ✅ Basic offline simulation behind a swappable interface, plus a report screen
- ✅ UI: world view, character selection, character info, activity selection, assignment status,
  inventory, skills, storage
- ✅ Save/load (atomic, sanitised), autosave, mobile pause/resume handling
- ✅ Placeholder art pipeline at final paths
- ✅ Docs and tests

### Phase 1 known gaps (deliberately deferred, with reasons)

| Gap | Why deferred | What it needs |
|---|---|---|
| Visual route builder and multi-stop routes | Spec phase 1 only requires single-activity assignments. The data hooks (`preferred_node_ids`) exist | Route model (a list of stops), UI editor, engine support for stop sequences (P2) |
| Safety rules (health, supplies, enemies) | No combat, health or consumables yet | Combat and consumables (P2). States are reserved |
| Fog of war, discoveries | Exploration is P3 | Explored-tile bitmap per region, discovery data |
| Chunked/hierarchical navigation | A 64x48 map does not need it | Portal graph across 64x64 chunks (P3) |
| Gacha, pity, currency tests (named in spec rule 5) | Recruitment and currencies are P2 systems; there is nothing to test yet | Implement in P2 with server-authoritative roll service. Test plan in BALANCE.md |
| Crafting-requirement tests | Crafting is P2 | Recipes data + Crafting activity type |
| Android/iOS export presets | Need the owner's signing keys and bundle IDs | See TECHNICAL_ARCHITECTURE.md §10 |
| Audio | Not in the phase 1 scope | Audio bus layout, SFX per activity (P2) |
| Final art | Placeholders by design | Artist pass following the asset standards |
| Offline sim scales linearly with characters | Fine at 3 characters | Server simulation and cycle extrapolation (see architecture §9) |

## Phase 2: RPG progression (next)

Suggested order. Each step keeps the game playable and the tests green.

1. **Data-driven currencies + Economy service interface** (Gold, Gems, Tokens) with transaction
   log and tests (`currency transactions` from spec rule 5).
2. **Recruitment / gacha**: banner data, configurable rates and pity per banner, transparent rates
   UI, duplicate → fragments. Built behind a `RecruitmentService` interface whose local
   implementation is clearly marked dev-only, because final rolls must be server-side.
   Statistical tests for rates (chi-square over 1M rolls) and pity edge cases.
3. **Roster expansion**: character database to ~20, rarity-driven starting skills, traits.
4. **Processing and crafting**: Smithing (copper + tin → bronze bar), recipes data, a "crafting"
   activity type in the engine (travel to workstation, check ingredients, consume, produce).
5. **Equipment**: 9 slots, tools affect gathering speed, durability and repair.
6. **Combat**: enemies data, combat activity, COMBAT, INJURED and RESTING states, healing
   thresholds, loot tables. Greenvale enemies (slimes, rats, wolves, goblins).
7. **Route builder**: multi-stop routes, saved templates, safety rules.
8. **Town buildings**: Bank (storage upgrades), Blacksmith, Workshop, using Construction.
9. **Additional activities**: Cooking, Foraging, Hunting, Farming.

Acceptance: players collect multiple characters, give them different professions, and manage their
independent progression.

## Phase 3: World expansion

Multiple regions with transitions, fog of war, exploration discoveries, dungeons, bosses,
expeditions, regional quests and reputation, outposts, tier 2 to 4 resources, dynamic encounters,
hierarchical navigation.

## Phase 4: Multiplayer

Nakama auth, authoritative services (see TECHNICAL_ARCHITECTURE §6), server offline simulation,
shared towns, player visibility, friends, guilds, trading, marketplace, co-op bosses, world events.

**Decision needed before starting:** run the simulation rules on the server in headless Godot
(reuses this GDScript unchanged), or port them to Go/TypeScript (more conventional ops, but two
implementations to keep in sync).

## Phase 5: Endgame

Mastery, mythic characters, relics, pets, mounts, World Ascension, seasonal events, advanced
dungeons, endgame regions.
