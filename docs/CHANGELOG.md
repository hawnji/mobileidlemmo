# Changelog

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
