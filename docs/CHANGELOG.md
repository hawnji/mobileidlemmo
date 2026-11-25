# Changelog

## 0.5.0 (2026-11-25): Phase 5, endgame

### Added
- **Endgame regions** on a taller world map (128 x 144):
  - The **Shadowlands** (level 60 to 90): Gloomhold, Wraith Fields, Shadowbark Wood, the
    Voidstone Pits, the Black Marsh, the Knights' Barrow and the Void Rift.
  - The **Celestial Isles** (level 80 to 99): Skyreach, Skywood Grove, the Aether Gardens,
    Starfall Isle, Serpent Reach, Golem Isle and the Sentinel Terrace. The isles need a flying
    mount.
  - Both regions get outposts, 10 discoveries, 5 new terrain tiles and 2 new gates.
- **Content**:
  - voidsteel and starmetal gear; shadowbark and skywood bows, staves and rods;
  - gloom eel and cloud koi;
  - nightshade and aether bloom, with a shadow draught potion;
  - 8 gathering nodes, 6 enemies, the Hollow King and Astral Wyrm bosses;
  - the Dread Citadel and Starfall Sanctum dungeons;
  - 2 expeditions, 4 main quests (09 to 12), 6 regional quests, 4 contracts and 8 seasonal
    contracts;
  - 5 vendors (two stables, the Gloomhold Quartermaster, the Skyreach Archivist and the
    Festival Merchant).
- **Mythic heroes**:
  - Nyx Voidwalker (Dread Citadel sigil);
  - Kaelen Stormforge (Starfall Sanctum sigil);
  - Astraea Skyborn (first World Ascension).
- **Relics** (12):
  - account-wide bonuses in 3 slots, up to 6 with the Relic Attunement perk;
  - levels 1 to 5, upgraded with relic dust;
  - duplicates turn into dust.
- **Pets** (8): each follows one hero and levels (to 10) from 5% of that hero's XP.
- **Mounts** (7): travel speed and other bonuses, one rider each; flying mounts open the
  Celestial Isles.
- **Mastery**: XP earned at level 99 builds mastery levels (to 20) for that skill, with
  milestone rewards at 5, 10 and 20.
- **Mythic dungeon tiers** 1 to 10 for any cleared dungeon:
  - enemy health +15% and damage +8% per tier;
  - affixes Fortified (2), Tyrannical (4), Frenzied (6) and Famished (8);
  - rewards x(1 + 0.25 x tier), relic dust and a relic chance.
- **World Ascension** after the last main quest:
  - resets the world and keeps the legacy;
  - grants ascension points for 9 permanent perks;
  - the first ascension also grants Astraea's sigil and the Celestial Drake.
- **Seasons** from the calendar (Bloomtide, Sunfire Regatta, Harvest Moon, Frostfall): each has
  a bonus, seasonal contracts that pay festival tokens, and seasonal stock.
- **Legacy screen** (10th nav button), a mythic tier picker in Journeys, a **Use** button in
  Storage, and toasts for endgame events.
- **New conditions**: `season`, `mount`, `ascension`, `mythic_tier`, `mastery`.
- **Tests and tools**:
  - `tests/integration/test_endgame.gd` (21 tests, 221 offline tests in total);
  - `tools/capture_endgame_screenshots.gd` and screenshots 32 to 41;
  - endgame tables in `tools/balance_report.gd`.

### Changed
- **Save format 4.** Older saves keep their fog when the map grows.
- **Offline cap** now adds the `offline_cap_hours` stat.
- **The HUD navigation** has two rows of five buttons.

### Not done (see the roadmap)
- **Seasonal festivals** are contracts, a merchant and a bonus. There are no special festival
  maps or events.
- **Server-side checks** do not cover endgame progress (relic levels, mastery, mythic records).

## 0.4.0 (2026-11-25): Phase 4, multiplayer

### Added
- **Server**: a Nakama 3.22 JavaScript module (`server/nakama`) with cloud saves, upload
  validation, a server-owned premium wallet, server-side recruitment, a marketplace with escrow
  and fees, private trades, deliveries, guild progression, a co-op world boss, recurring world
  events and per-region presence matches. `server/run_local.sh`, `server/run_tests.sh`,
  `docker-compose.yml` (not yet run) and `tools/build_server_module.py`.
- **Client**: `NakamaClient` (REST), `NakamaSocket` (realtime), `OnlineService` (requests on
  worker threads, sync cycle, chat, presence), `OnlineSync` (applies server answers),
  `NakamaGameBackend` (cloud save with device-save fallback).
- **Social screen** (new nav button): Account and sync, Friends (add, accept, visit town, trade),
  Guild (join, create, donate, perks, chat), Market (sell, browse, buy, cancel), World (events,
  world boss, players nearby). Other players' heroes appear on the map as blue markers.
- Guild perks and world events apply to every hero as account effects.
- `data/server/server_config.json` with the validation caps, market, guild, boss and event
  settings.
- `server_ledger_seq` in saves.
- 11 new offline tests (200 total), 9 Godot client tests and 20 server tests against a live
  server, `tools/capture_online_screenshots.gd` and screenshots 25 to 31.

### Changed
- Recruitment online is rolled by the server; the banner screen shows the server's pity.
- Speed-up and developer time skips are disabled while online.
- `SimulationWorld.apply_recruit_results` split out of `recruit`; `Wallet.set_balance_from_server`.

### Not done (see the roadmap)
- Server-side simulation and offline progress (the server validates uploads instead).
- Apple / Google sign-in, push notifications, chat moderation, rate limits.

## 0.3.0 (2026-11-25): Phase 3, world expansion

### Added
- One 128x96 world map with four regions (Greenvale, Irondeep Mountains, Whisperwood, Ashen
  Desert), gates, unlock requirements and costs, generated by `tools/generate_world_map.py`.
- Fog of war, the Explore activity with surveys, 20 discoveries with hero requirements and two
  secret passages.
- Hierarchical region navigation with waystone fast travel.
- Three outposts with depots, stations, waystones and local bonuses.
- Quests (8 main, 16 regional, 13 contracts), regional reputation with five tiers, four vendors,
  reputation-gated recipes and a reputation character (Hulda Ironbraid, 24 characters total).
- Four dungeons with boss phases, abilities, summons and enrage; character active abilities.
- Seven expeditions with requirements, stages, events, injuries and deterministic results.
- Dynamic encounters: treasure goblin, bountiful harvest, travelling merchant, monster surge,
  wandering hero.
- Notification inbox with categories; mailbox for rewards that do not fit in storage.
- Tier 2 to 4 resources and gear (coal, gold, mithril, adamantite, gems, maple, yew, new fish
  and herbs, artifacts), 120 items and 72 recipes in total.
- UI: World Map, Quests and Vendors, Journeys (expeditions, dungeons, events), Notifications, a
  soft fog overlay, outposts, depots and dungeon entrances on the map.
- Offline report lists exploration progress, discoveries, expeditions, dungeons, quests ready
  and new characters.
- Balance report tables for exploration pace, expedition odds and dungeon outcomes.
- 41 new tests (189 total).

### Changed
- Save format 3; format 1 and 2 saves migrate with Greenvale unlocked.
- New character state AWAY (15 states).
- Bottom navigation has two rows (World, Heroes, Map, Quests, Journeys, Town, Recruit, Storage);
  the Social placeholder returns with multiplayer.

### Fixed
- A preserve roll on a full bag blocked the craft and was wasted. Restocking now leaves room for
  one batch when the character can preserve or double-craft.
- Characters on an expedition or in a dungeon were reset to Idle when a save loaded.

## 0.2.0 (2026-11-25): Phase 2, RPG progression

### Added
- Currencies (gold, gems, recruitment and festival tokens, plus reserved later-phase currencies)
  with an atomic wallet and transaction log.
- Recruitment banners with pity, featured characters, effective-rate publishing, duplicates to
  fragments and star ranks. Local rolls are clearly marked dev-only.
- 20 new adventurers (23 total), traits, specializations and star effects through a new
  data-driven StatBlock system with account-wide effects.
- Crafting at five stations with 34 recipes, restocking from storage, preserve, double-craft and
  burn chances.
- Equipment with 9 slots, durability, breaking, repair, upgrades and an armory for used items.
- Combat with 7 enemy types, 5 rare variants, food, retreat, injury and resting.
- Town with 12 buildings, construction projects and the Construct activity.
- New gathering: iron, willow, trout, herbs, potatoes, marrentill.
- Route builder with looping and saved templates.
- NPC selling, item lock and favourites, skill milestones, tavern tokens, worker capacity.
- UI: activity categories, recipe and combat options, Heroes, Gear, Recruit, Town and storage
  actions; HP bars, enemy views, building plots, combat floating text.
- Placeholder art for every new item, node, enemy, station, building and character.
- 76 new tests (148 total).

### Changed
- ActivityEngine now delegates to per-type handlers (gathering, crafting, combat, construction).
- The production ledger became a sources/sinks item ledger. Save format 2 (Phase 1 saves are
  migrated on load).
- New worlds start with only the three starter characters.
- The day/night clock, tint and night bonuses share one `day_phase()`.

## 0.1.0 (2026-11-24): Phase 1 prototype

### Added
- Godot 4.3 project with a Mobile renderer, portrait layout, the `Game` autoload, and Main, WorldView and HUD scenes.
- A data-driven content pipeline: 24 skills, the XP curves, 7 items, 4 resource node types, 4 activities, 3 starter characters, 14 terrain types and the Greenvale starter region (64x48), all validated on load.
- A pure-logic simulation (`SimulationWorld`) with a fixed 0.1 s step, deterministic RNG and a production ledger.
- The `ActivityEngine`, which runs the 14-state character state machine and the gathering loop. Characters travel, gather, return at a threshold, deposit and resume. It supports node reservations, respawns, waiting, unreachable-node cooldowns, stuck detection and re-routing.
- Assignment rules: return at 50%, 75% or a full bag; Repeat, Until amount, or One trip.
- A* pathfinding on AStarGrid2D with weighted terrain, roads, no corner cutting, two caches and a per-tick budget.
- Inventory (bags measured in units, storage measured in item-type slots), rare drops, skill XP and levels, and character XP.
- Offline progression behind `OfflineProgressionProvider` (local simulator, 8 h cap) with a "While you were away" report.
- `GameBackend` interface with `LocalGameBackend`. Atomic JSON saves, autosave, and mobile pause/resume handling.
- Chunk-based terrain rendering with pooled TileMapLayers, animated water, character walk and work animations, tool swings, particles, pooled floating text, a day/night tint and a touch camera.
- Mobile HUD: roster cards, character panel, assignment builder with XP/h estimates, bag, skills (all 24), storage with search and sort, toasts, bottom navigation, and dev tools (speed and simulated time away).
- Placeholder art generator at the final asset paths. Map generator with reachability validation.
- 72 automated tests, a headless boot smoke test, a screenshot capture tool and a balance report tool.
- Docs: README, GAME_DESIGN, TECHNICAL_ARCHITECTURE, DEVELOPMENT_ROADMAP, SYSTEMS, DATA_SCHEMA, BALANCE and CHANGELOG.

### Fixed during development
- A* ignored roads because the octile heuristic became inadmissible with move costs below 1. Weights are now normalised.
- An `ActivityEngine` and `SimulationWorld` reference cycle leaked memory. The engine now holds the world weakly.
- Woodcutting "one trip" counted only logs. Bags can also hold rare drops, so the test now checks the total.
