# Worldbound: Data Schema

All content is JSON under `data/`. Every file has `schema_version`. IDs are stable `snake_case`
strings. `DataRegistry.validate()` enforces the cross references described below.

## data/config/game_config.json
| Key | Type | Meaning |
|---|---|---|
| simulation.tick_seconds | float | Fixed live step (0.1) |
| simulation.max_state_steps_per_tick | int | Safety cap per character per tick |
| simulation.pathfinding_requests_per_tick | int | Path search budget per world step |
| simulation.waiting_retry_seconds | float | WAITING retry delay |
| simulation.unreachable_node_cooldown_seconds | float | Per-character node blacklist duration |
| simulation.max_consecutive_path_failures | int | Then the character stops as "Stuck" |
| simulation.deposit_seconds | float | Time spent at the chest |
| offline.base_cap_hours | number | 8 |
| offline.upgraded_cap_hours | number[] | Planned upgrades [12, 24] |
| offline.simulation_step_seconds | float | Offline step (1.0) |
| offline.minimum_elapsed_seconds | number | Ignore absences shorter than this |
| storage.starting_distinct_item_slots | int | Storage item-type slots |
| character_progression.character_xp_share | float | Share of skill XP that becomes character XP |
| save.autosave_seconds, save.file_path | | |
| world.start_region, chunk_size_tiles, tile_size_px | | |

## data/skills/skills.json
`skills[]`: `{id, name, category: gathering|production|combat|utility, description, icon, implemented_phase: int|null, mastery_enabled}`. Exactly 24.

## data/skills/xp_curve.json
`skill_curve` and `character_curve`: `{max_level, base, divisor, max_xp}`. The formula is in
BALANCE.md.

## data/items/items.json
`items[]`: `{id, name, category, tier, rarity, sell_price, icon, description}`.
Planned for P2: `stackable`, `equip_slot`, `requirements`, `durability`, `stats`.

## data/resources/resource_nodes.json
`node_types[]`:
```json
{"id": "copper_rock", "name": "Copper Rock", "skill": "mining", "required_level": 1,
 "gather_seconds": 5.0, "xp": 17.5,
 "yield": {"item": "copper_ore", "min": 1, "max": 1},
 "rare_drops": [{"item": "uncut_quartz", "chance": 0.002}],
 "charges": 4, "respawn_seconds": 10.0, "blocks_movement": true,
 "sprite": "res://...", "depleted_sprite": "res://..."}
```
Validated: skill exists, items exist, `gather_seconds > 0`, `charges > 0`.

## data/activities/activities.json
`activities[]`: `{id, name, type: "gathering", skill, required_level, node_type, default_destination, animation, description}`.
Validated: node type, skill, and that the destination exists in the start region.
P2 will add the types `crafting` (workstation, recipe), `combat` (enemy table) and `route`.

## data/characters/characters.json
`characters[]`:
| Field | Type | Notes |
|---|---|---|
| id, name, rarity, origin, title, role, combat_specialty | string | rarity ∈ common..mythic |
| primary_affinity, secondary_affinity | string\|null | skill IDs |
| affinities | {skill: {speed, xp}} | multipliers |
| starting_skills | {skill: level} | |
| base_stats | {health, move_speed_tiles, carry_capacity} | carry_capacity is the bag size in units |
| passive | {id, name, description, effects} | effects keys: `xp_multiplier.all`, `xp_multiplier.<skill>`, `rare_drop_multiplier.<skill>` |
| personality, background | string | |
| portrait, sprite | res:// path | |
| palette | {primary, secondary} | placeholder art colours |

Planned for P2: `active_ability`, `traits[]`, `specializations[]`, `star_rank`, `equipment_slots`,
`acquisition` (gacha / quest / exploration).

## data/regions/terrain.json
`terrain[]`: `{symbol, id, walkable, move_cost, atlas: [col,row], animation_frames?, animation_fps?}`.

## data/regions/<region>.json
| Field | Notes |
|---|---|
| id, name, description, width, height | |
| rows | `height` strings of `width` terrain symbols |
| spawn_tile | [x,y] |
| storage | {id, name, tile} |
| locations[] | {id, name, kind, rect: [x,y,w,h]}. Used as assignment destinations |
| resource_nodes[] | {id, type, tile} |

`greenvale_start.json` is generated and validated by `tools/generate_greenvale_map.py`.

## Save format (`user://worldbound_save.json`)
```
{ save_version: 1, saved_at_unix: float,
  world: { format: 1, region_id, sim_time, rng_seed, rng_state,
           storage: {max_units, max_distinct, items},
           character_order: [...],
           characters: { <id>: { tile, facing, skills: {skill: xp}, character_xp,
                                 inventory, state: "STATE_NAME", assignment: {...}|null,
                                 travel_purpose, path, path_index, move_progress,
                                 action_elapsed, target_node_id, wait_remaining,
                                 path_failures, status_message, stats } },
           nodes: { <id>: {charges, respawn_remaining, reserved_by} },   // only modified nodes
           production_ledger: {item: qty} } }
```
States and enums are stored by **name**, so reordering an enum does not corrupt saves.

## Assignment
`{character_id, activity_id, destination_id, deposit_target_id, return_fill_ratio (0.1-1),
continue_mode: REPEAT|UNTIL_QUANTITY|SINGLE_TRIP, target_quantity, preferred_node_ids[],
safety: {return_below_health_ratio, avoid_enemies_above_level}, deposited_primary,
trips_completed, started_at_sim_time}`

## Planned server entities (Phase 4, PostgreSQL)
This maps the spec's entity list onto tables. Columns are indicative.

```sql
player(id uuid pk, account_level int, settings jsonb, created_at, last_sim_at timestamptz)
currency_balance(player_id fk, currency text, amount bigint, pk(player_id,currency))
currency_ledger(id bigserial, player_id, currency, delta bigint, reason text, ref_id, created_at)
character(id uuid pk, owner_id fk player, def_id text, rarity text, level int, xp bigint,
          star_rank int, traits jsonb, state jsonb)
character_skill(character_id fk, skill_id text, xp bigint, pk(character_id, skill_id))
character_equipment(character_id fk, slot text, item_instance_id fk, pk(character_id, slot))
assignment(id uuid pk, character_id fk unique, activity_id text, destination_id text,
           rules jsonb, progress jsonb, started_at)
automation_rule(id, assignment_id fk, conditions jsonb, actions jsonb, ord int)
inventory(owner_type text, owner_id uuid, item_id text, quantity bigint, pk(owner_type, owner_id, item_id))
item_instance(id uuid pk, item_id text, owner_id, durability int, quality int, rolls jsonb)
world_region(id text pk, bounds int4range[], unlock_requirements jsonb)
resource_node_state(region_id, node_id, owner_id, charges int, respawn_at timestamptz)
recruitment(player_id, banner_id, pity jsonb, pulls int, pk(player_id, banner_id))
recruitment_history(id, player_id, banner_id, result_def_id, rarity, rolled_at, server_seed_hash)
guild(id, owner_id, level, data jsonb) ; guild_member(guild_id, player_id, role)
market_listing(id, seller_id, item_id, item_instance_id, quantity, unit_price, created_at, status)
expedition(id, player_id, team uuid[], def_id, started_at, ends_at, outcome jsonb)
building(id, owner_id, type, level, location)
quest_progress(player_id, quest_id, state, progress jsonb)
```
Redis is used for session presence, shared-town live state, marketplace order-book caching and
rate limiting.
