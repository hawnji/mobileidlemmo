# Changelog

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
