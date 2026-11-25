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

## Phase 3: World expansion (complete)

Acceptance (spec): players can progress through several distinct regions with meaningful
exploration and skill requirements. **Met**: four regions on one map, each gated by quests,
skill levels, exploration of the previous region and gold; exploring a region takes hours, not
minutes (Greenvale: about 35 minutes to 35% and 1 h 48 m to 98% for one starter, see
BALANCE.md); every system below runs online and offline and is covered by tests.

### Phase 3 feature checklist

| Feature | Status | Where | Tests |
|---|---|---|---|
| Multiple regions, transitions (gates), unlock requirements and cost | Done (4 regions) | `data/regions/world_map.json`, `SimulationWorld.unlock_region` | `test_world_expansion` (regions, gates) |
| Fog of war, exploration skill, survey activity | Done | `exploration_state.gd`, `handlers/exploration_handler.gd`, `fog_overlay.gd` | fog, survey, explorer tests |
| Discoveries with specialty/affinity requirements, secrets | Done (20 + 2 secrets) | `world_map.json`, `SimulationWorld.try_discover/reveal_secret` | discovery and secret tests |
| Hierarchical navigation and fast travel | Done | `region_navigator.gd`, `ActivityEngine._pathfind` | route, teleport and reachability tests |
| Outposts: depot, stations, waystone, local bonuses | Done (3) | `data/town/buildings.json` (kind outpost) | outpost test |
| Tier 2 to 4 resources and gear | Done | items, nodes, recipes data | registry validation, loops |
| Regional and main quests, contracts, reputation, vendors | Done (37 quests, 4 vendors) | `quest_state.gd`, `data/quests/quests.json`, `data/economy/vendors.json` | quest, reputation, vendor tests |
| Dungeons with bosses (phases, abilities, summons, enrage) | Done (4) | `dungeon_run.gd`, `data/dungeons/dungeons.json` | `test_adventures` (clear, wipe, save mid-fight) |
| Character active abilities | Done, in dungeons only | `data/characters/abilities.json` | dungeon tests |
| Expeditions with requirements, stages, events, deterministic results | Done (7) | `expedition_state.gd` | slot, requirement, determinism tests |
| Dynamic encounters (5 kinds) | Done | `encounter_director.gd`, `data/world/encounters.json` | encounter tests incl. offline |
| Notification categories and inbox | Done (in-game) | `notification_center.gd`, `data/config/notifications.json` | notification tests |
| Mailbox for rewards when storage is full | Done | `SimulationWorld._store_or_mail` | mailbox test |
| Offline report: exploration, discoveries, expeditions, dungeons, quests | Done | `offline_report.gd` | offline suite |
| Save format 3 with migration from format 1 and 2 | Done | `SimulationWorld._load_phase3` | save round-trip tests |
| UI: World Map, Quests and Vendors, Journeys, Notifications, fog overlay | Done | `scripts/ui/*` | screenshots `17` to `24` |

### Phase 3 known gaps (honest list)

| Gap | Why | Plan |
|---|---|---|
| Phone (OS) notifications are not delivered | Godot has no built-in mobile notification API; it needs an Android plugin and an iOS plugin | `LocalNotifier` forwards to a `LocalNotification` singleton when one is installed and already schedules expedition returns on backgrounding; add the plugins at export time |
| Remote push (server to phone) | Needs a backend and Apple/Google credentials | Phase 4 |
| Active abilities are used only in dungeons | Open-world combat stays simple and cheap for offline simulation | Revisit with the Phase 5 combat pass |
| Bosses exist only inside dungeons; no open-world boss | Co-op world bosses belong to multiplayer | Phase 4 |
| Expedition and dungeon results are decided on the device | No server yet | Phase 4 services own rewards |
| One map file holds all regions | Fine at 128x96 (12k tiles) | Split into region chunks if the world grows past ~512x512 |
| Balance is first-pass | Measured with `tools/balance_report.gd`, not playtested | Tune after playtests (BALANCE.md lists the knobs) |
| Art is placeholder | By design | Artist pass |

## Phase 4: Multiplayer (complete, with the gaps below)

Spec: Nakama auth, authoritative services, server offline simulation, shared towns, player
visibility, friends, guilds, trading, marketplace, co-op bosses, world events.

**Decision taken:** the services are a Nakama JavaScript module (server/nakama). The world
simulation stays in GDScript on the device and the server validates each save upload against
per-hour caps. Running the same GDScript headless on the server remains the path to full
authority (see the gaps). Everything below was tested against a real Nakama 3.22 + PostgreSQL 16
(`server/run_tests.sh`: 20 server tests + 9 Godot client tests).

### Phase 4 feature checklist

| Feature | Status | Where |
|---|---|---|
| Nakama device authentication, sessions | Done | `NakamaClient.authenticate_device`, `OnlineService.connect_blocking` |
| Cloud save with versioning (second device must load first) | Done | `wb_save_upload` / `wb_save_download`, `NakamaGameBackend` |
| Save validation (clock, item and gold gains, granted characters, escrow) | Done | `server/nakama/src/10_profile.js` `validateSave` |
| Server-owned premium wallet with capped crediting | Done | `premiumDelta`, `OnlineSync.apply_server_wallet` |
| Server-side recruitment (rolls, pity, featured, cost) | Done | `20_recruit.js`, Recruit screen online path |
| Friends (request, accept, remove) | Done | Nakama friends, Social > Friends |
| Shared towns (visit a friend's town) | Done | `wb_visit_town`, Social > Friends > Visit town |
| Guilds: create, join, leave, members, donations, 5 levels, member perks | Done | Nakama groups + `40_guild.js`, Social > Guild |
| Guild chat (realtime) | Done | Nakama group channel over `NakamaSocket` |
| Marketplace: list, browse, buy, cancel, 5% fee, escrow, race-safe buying | Done | `30_market.js`, Social > Market |
| Direct trading (private listing for one friend) | Done | `buyer` field, Social > Friends > Trade |
| Deliveries (purchases, sales, returns, boss loot) | Done | `wb_claim_deliveries`, `OnlineSync.apply_deliveries` |
| Co-op world boss (shared HP, cooldown, damage from synced heroes, rewards for all fighters) | Done | `50_boss.js`, Social > World |
| World events on the server clock, applied as account effects | Done | `60_world.js`, `OnlineSync.Effects` |
| Player visibility: other players' heroes in your region | Done | `region_presence` match, `PresenceLayer` (blue markers) |
| Offline play keeps working; online is opt-in per device | Done | `LocalGameBackend` fallback, Social > Account |
| Server offline simulation | **Not done** | See gaps |
| Docker deployment | Written, **not run** | `docker-compose.yml` |

### Phase 4 known gaps (honest list)

| Gap | Why | Plan |
|---|---|---|
| The simulation is not server-authoritative; offline progress is computed on the device | A headless-Godot simulation service is a large separate deployment; validation caps were the smallest step that makes cheating bounded | Run `SimulationWorld` in headless Godot behind Nakama (or port it), recompute offline time on the server |
| Expedition, dungeon and quest rewards are decided on the device | Same as above | Move with the simulation service |
| `docker-compose.yml` untested | The build machine had no Docker daemon | Run it once on a machine with Docker |
| No Apple / Google sign-in, push notifications, chat moderation or rate limits | Need store accounts, FCM/APNs keys and a moderation policy | Before a public test |
| Premium currency earned offline before the first sign-in is not carried over | The first upload is a trusted baseline; crediting unverified history would let anyone mint gems | Keep; explain in the first-sign-in screen |
| A crash right after listing an item can let it reappear locally (within the hourly cap) | Escrow is applied to the local save on the next autosave | Server-authoritative inventory with the simulation service |
| Presence shows heroes only in the region where most of your heroes are | Keeps one realtime match per player | Per-region subscriptions if needed |
| Balance of the market fee, boss HP and guild levels is first-pass | No players yet | Tune with telemetry |

## Phase 5: Endgame

Mastery, mythic characters, relics, pets, mounts, World Ascension, seasonal events, advanced
dungeons, endgame regions.
