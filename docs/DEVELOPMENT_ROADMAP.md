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

## Phase 2: RPG progression (complete)

Acceptance (spec): players collect multiple characters, give them different professions, and
manage their independent progression. **Met**: 23 characters, recruitment, crafting, combat,
equipment and town loops all run unattended, online and offline, and are covered by tests.

### Phase 2 feature checklist

| Feature | Status | Where | Tests |
|---|---|---|---|
| Data-driven currencies with transaction log | Done | `scripts/economy/wallet.gd`, `data/economy/currencies.json` | `test_wallet` (7) |
| Account-wide and per-character stat system | Done | `stat_block.gd`, `account_effects.gd`, `data/config/stats.json` | `test_stat_block` (7) |
| Recruitment: banners, rates, pity, featured, 10-pull discount | Done (local/dev only) | `recruitment_state.gd`, `data/recruitment/banners.json` | `test_recruitment` (14, incl. chi-square over 10^6 rolls) |
| Effective rates published in-game | Done | Recruit screen, `tools/gacha_report.gd` | `test_effective_rates_include_pity` |
| Duplicates to fragments, star ranks | Done | `SimulationWorld.recruit/star_up` | `test_star_up_uses_fragments` |
| Roster of ~20 characters | Done (23) | `data/characters/characters.json` | `test_data_registry` |
| Traits (unlock at character level 10/30/60) | Done | `data/characters/traits.json`, `sync_traits` | `test_progression` |
| Specializations (skill 30, slots by character level, respec) | Done | `data/characters/specializations.json` | `test_specializations` |
| Processing and crafting (5 stations, 34 recipes) | Done | `handlers/crafting_handler.gd`, `data/recipes/recipes.json` | `test_crafting_loop` (7) |
| Crafting requirements (skill, building, station) | Done | `CraftingHandler.validate` | `test_requirements` |
| Equipment: 9 slots, requirements, durability, repair, upgrade | Done | `equipment_service.gd` | `test_equipment` (11) |
| Combat: enemies, variants, styles, food, retreat, injury, resting, loot | Done | `handlers/combat_handler.gd`, `combat_rules.gd`, `enemy_state.gd` | `test_combat_loop` (9) |
| COMBAT, RESTOCKING, RESTING, INJURED states in use | Done | `character_states.gd` | `test_state_machine`, combat tests |
| Route builder (multi-step, loop, templates) | Done | `Assignment.route`, `SimulationWorld.start_route` | `test_routes` (5) |
| Town buildings (12) and construction projects | Done | `town_state.gd`, `handlers/construction_handler.gd` | `test_town` (8) |
| Worker capacity, storage slots, tavern tokens | Done | `SimulationWorld` | `test_town` |
| Cooking, Foraging, Farming, Hunting, Herblore | Done | activities + recipes data | crafting and combat tests |
| NPC selling, item lock and favourites | Done | `SimulationWorld.sell_item` | `test_sell_items_for_gold_respects_lock` |
| Skill milestones (token + gold every 10 levels) | Done | `on_skill_level_up` | `test_skill_milestones_pay_tokens_and_gold` |
| Item conservation across all sources and sinks | Done | `item_sources/item_sinks` | `test_ledger_holds_across_all_activities` |
| Offline report covers crafting, kills, currencies, buildings | Done | `offline_report.gd` | `test_report_includes_combat_crafting_and_gold` |
| UI: categories, recipes, combat settings, heroes, gear, recruit, town, storage actions, routes | Done | `scripts/ui/*` | screenshots `09` to `16` |
| Save format 2 with migration from Phase 1 saves | Done | `SimulationWorld.from_dict` | save/load tests |

### Phase 2 known gaps (honest list)

| Gap | Why | Plan |
|---|---|---|
| Gacha rolls happen on the device | No server yet. Marked dev-only in code and UI | Phase 4 Recruitment Service owns RNG, pity and history |
| Enemies stand still at spawn points; ranged and magic attack from an adjacent tile | Keeps combat deterministic and cheap | Aggro radius and ranged distance in Phase 3 combat pass |
| Equipment loadouts are stored but have no UI | Time | Loadout save/apply buttons on the Gear screen |
| Character active abilities | Not designed in data yet | Phase 3 (bosses need them) |
| Audio | Out of scope so far | Audio bus layout and SFX per activity |
| Crafting and cooking XP/hour is high at low levels | Tier 1 recipes are quick | Tune `seconds`/`xp` in recipes.json after playtesting (see BALANCE.md) |

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
