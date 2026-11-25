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

## Phase 2 data files

| File | Shape |
|---|---|
| `config/stats.json` | `families: {family: "mul"\|"add"}` |
| `config/game_config.json` | new sections `combat`, `equipment`, `progression`; `simulation.restock_seconds`, `materials_retry_seconds`; `world.day_length_seconds` |
| `items/items.json` | adds `heal` (food), `equip_slot` (`weapon, head, body, legs, gloves, boots, accessory, tool`), `requirements {skill: level}`, `stats {stat key: value}`, `max_durability`, `tool_skill`, `combat_style`, `attack_speed` |
| `recipes/recipes.json` | `recipes[]: {id, name, skill, required_level, station, inputs {item: qty}, outputs {item: qty}, seconds, xp, requires_building? {building: level}, burn? {item, base_chance, stop_level}}` |
| `enemies/enemies.json` | `enemies[]: {id, name, level, health, max_hit, accuracy, defense, attack_speed, weaknesses {style: mult}, loot[] {item, chance, min, max}, gold [min,max], tags, respawn_seconds, sprite}`; `variants[]: {id, name, chance, stat_multiplier, xp_multiplier, loot_rolls, gold_multiplier}` |
| `activities/activities.json` | `type` is `gathering`, `crafting` (`station`), `combat` (`default_destination` = hunting ground) or `construction` |
| `characters/characters.json` | adds `combat_style`, `traits[3]`, `acquisition` (`starter`, `gacha`, `quest`, `exploration`) |
| `characters/traits.json` | `traits[]: {id, name, description, effects}` |
| `characters/specializations.json` | `unlock_skill_level`, `slots_by_character_level {level: slots}`, `respec_cost`, `specializations[]: {id, name, skill, description, effects}` |
| `economy/currencies.json` | `currencies[]: {id, name, description, starting, premium}`, `milestones {skill_level_every, reward}` |
| `recruitment/banners.json` | `rarity_order`, `duplicate_fragments {rarity: n}`, `banners[]: {id, name, description, rates {rarity: p}, pity[] {rarity, guaranteed_on_pull}, costs {currency: per pull}, ten_pull_discount, pool, featured {character_id, share}\|null}` |
| `town/buildings.json` | `base_worker_capacity`, `work_action_seconds`, `xp_per_work_second`, `buildings[]: {id, name, description, max_level, phase, levels[] {level, cost {gold, items}, construction_level, work_seconds, effects}}` |
| `regions/<region>.json` | adds `stations[] {id, type, name, tile}`, `enemy_spawns[] {id, enemy, tile}`, `building_plots[] {building, rect, work_tile}` |

## Phase 3 data files

| File | Shape |
|---|---|
| `config/game_config.json` | `world.map` (map file id), `exploration {base_reveal_radius, reveal_radius_per_levels, walk_reveal_radius, survey_seconds, xp_per_tile, discovery_detect_radius, explore_complete_pct}`, `navigation.fast_travel_min_distance` |
| `regions/world_map.json` | Generated by `tools/generate_world_map.py`. `width, height, rows[]` (one terrain symbol per tile), `spawn_tile`, `storage`, `regions[] {id, name, description, rect [x,y,w,h], unlocked_by_default, unlock {conditions[], cost {gold}}, outpost}`, `gates[] {id, regions [a,b], a, b}` (one tile on each side), `locations[] {id, name, kind, region, rect}`, `resource_nodes[] {id, type, tile, hidden?}`, `stations[] {..., outpost?}`, `enemy_spawns[]`, `building_plots[]`, `outposts[] {building, rect, work_tile, depot_tile, stations[]}`, `dungeon_entrances[] {id, tile}`, `discoveries[] {id, name, kind, region, tile, requires {exploration, specialty?, affinity?}, rewards}`, `secrets[] {id, region, tiles[], reveals_as}` |
| `quests/quests.json` | `check_interval_seconds`, `reputation {regions[], tiers[] {name, points}}`, `quests[] {id, name, description, category main/regional/contract, region?, repeatable?, cooldown_seconds?, prerequisites[], objectives[], rewards}` |
| `economy/vendors.json` | `vendors[] {id, name, region, currency, stock[] {item, price, tier}}` (tier = reputation tier index) |
| `dungeons/dungeons.json` | `dungeons[] {id, name, region, party_min, party_max, recommended_power, entry_seconds, time_limit_seconds, food_per_member, floors[] {enemies[]}, boss, first_clear, clear_rewards}` |
| `expeditions/expeditions.json` | `base_success, power_weight, min_success, max_success, supplies_bonus, failure_reward_fraction, injury_seconds`, `expeditions[] {id, name, region, team_size, duration_seconds, recommended_power, requirements[], stages[] {requires[], reward_mult, risk_mult, extra_items, message}, events[] {kind ambush/hazard/bonus, chance, power_check?, skill_check?, ...}, rewards {currencies, items, xp, fragments}}` |
| `world/encounters.json` | `first_delay_seconds, interval_seconds [min,max], max_active`, `encounters[] {id, name, kind spawn_enemy/bonus_location/merchant/surge/hero, weight, location_kind, duration, message, ...kind fields}` |
| `config/notifications.json` | `cooldown_seconds, max_kept, categories[] {id, name, default_enabled, events[]}` |
| `characters/abilities.json` | `abilities {id: {name, kind guard/strike/multi_strike/strike_all/heal_party/buff_party, cooldown, ...}}`, `by_specialty {specialty: ability_id}`; characters may override with `active_ability` |
| `enemies/enemies.json` | Bosses add `boss {phases[] {below, damage_mult, attack_speed_mult, message}, abilities[] {id, name, kind area/special/summon/heal, every, ...}, enrage_seconds, enrage_damage_mult}`; any enemy may have `currencies` and `tags` |
| `town/buildings.json` | Outposts: `kind: "outpost"`, `region`, levels add `requires[]` (conditions) and `local_effects {gather_speed, xp}` |
| `recipes/recipes.json` | Recipes may add `requires_reputation {region: tier}` |

**Conditions.** Quest objectives and prerequisites, region unlocks, outpost requirements and
expedition requirements all share one shape, evaluated by `scripts/progression/objectives.gd`:
`gather, kill, kill_tag, craft, dungeon, expedition` (counters since the quest started),
`deliver` (consumed on claim), `explored, discover, discover_count, build, skill,
character_level, combat_level, quest, region, reputation`. Phase 5 adds `season {season}`,
`mount {tag?}`, `ascension {count}`, `mythic_tier {tier, dungeon?}` and `mastery {level,
skill?}`.

## Phase 5 data files

| File | Shape |
|---|---|
| `endgame/relics.json` | `base_slots, max_slots, max_level, upgrade_costs[]` (relic dust to go from level N to N+1), `duplicate_dust {rarity: dust}`, `relics[] {id, name, rarity, effects_per_level, description, icon}`. Effects stack per level (`mul` families as powers, `add` families times the level) |
| `endgame/pets.json` | `max_level, xp_share` (fraction of the owner's XP), `level_xp[]` (cumulative pet XP for each level), `pets[] {id, name, rarity, description, effects_per_level, icon}` |
| `endgame/mounts.json` | `mounts[] {id, name, rarity, effects, tags[]` (`"flying"` opens the Celestial Isles)`, description, icon}` |
| `endgame/mastery.json` | `xp_per_level, max_level`, `effects_per_level {skill category: {family: value}}` (applied to `<family>.<skill>`), `milestones[] {level, reward}` |
| `endgame/ascension.json` | `requirements[]` (conditions), `score {per_skill_level, per_mastery_level, per_mythic_tier, per_discovery}`, `points {scale, unit, minimum}` (points = scale x sqrt(score / unit), minus what the best earlier score already paid, at least `minimum`), `first_ascension_rewards`, `perks[] {id, name, max_rank, cost[], effects_per_rank, start_gold_per_rank?, description}` |
| `endgame/seasons.json` | `seasons[] {id, name, months[] (1-12, UTC), effects, description}`; every month belongs to at most one season |
| `dungeons/dungeons.json` | adds `mythic {max_tier, enemy_health_per_tier, enemy_damage_per_tier, reward_mult_per_tier, relic_dust_per_tier, relic_chance_per_tier, relic_chance_max, relic_pool[], affixes[] {id, name, min_tier, description, trash_health_mult?, boss_health_mult?, boss_damage_mult?, enrage_mult?, food_mult?}}` |
| `items/items.json` | Collectibles: `category: "collectible"` with `unlocks {type: pet/mount/relic/character, id}`; using one consumes it |
| `quests/quests.json` | `category: "seasonal"` quests carry `season` and a `season` prerequisite; active ones expire when the season ends |
| `economy/vendors.json` | Stock entries may carry `season` (sold only then); vendors may use any currency (`relic_dust`, `event_tokens`) |
| `regions/terrain.json` | Atlas row 4: `u` blight ground, `v` void (blocked), `l` cloud, `a` starstone, `z` shadow spires (blocked) |

## Save format (`user://worldbound_save.json`)

**Format 4 (Phase 5)** adds `endgame {relics {id: level}, equipped_relics[], pets {id: {level,
xp}}, pet_assign {character: pet}, mounts[], mount_assign {character: mount}, perks {id: rank},
ascensions, best_score, lifetime_points, mythic_records {dungeon: tier}}` to `world`.
Characters add `mastery_xp {skill: xp}`, and dungeon runs add `tier`. The map grew from 96 to
144 rows. Older saves keep their fog for the first 96 rows (`ExplorationState.load_dict` pads
it), and all their coordinates stay valid. The season is not saved: it comes from the device
clock.

**Phase 4** adds `server_ledger_seq` (int, default 0) to `world`: the highest server ledger op
(market escrow, guild donation, delivery) already applied to this save. Older saves load with 0.
The format number stays 3. The same `{save_version, world}` object is what the client uploads to
the server.

**Format 3 (Phase 3)** adds to `world`: `unlocked_regions[]`, `exploration {fog (deflate +
base64, one byte per tile), fog_size, discovered {id: {time, by}}}`, `revealed_secrets`,
`counters`, `mailbox`, `quests {active {id: {baseline, started}}, completed,
cooldowns, reputation}`, `expeditions {active[] {uid, expedition_id, team, started, ends_at,
seed, supplied}, history, completed_total, next_uid}`, `dungeon_runs[]` (full fight state),
`dungeon_records`, `encounters {active[], next_roll_at, next_uid, rng_state}`, `notifications`,
`last_reveal`. Characters add `away, on_waypoint, deposit_tile, target_key`. Format 1 and 2
saves load with Greenvale unlocked and fog lifted around the village.

**Format 2 (Phase 2)** adds to `world`: `wallet {balances, earned, spent}`, `town {levels,
project}`, `recruitment {rng_seed, rng_state, pity, total_pulls, history}`, `fragments`,
`armory[]`, `next_uid`, `token_progress`, `locked_items`, `favorite_items`, `enemies {spawn_id:
{variant, health, respawn_remaining, engaged_by, attack_timer}}`, `route_templates`,
`item_sources`, `item_sinks` (replacing `production_ledger`, which is migrated). Characters add
`health, stars, traits, specializations, equipment, loadouts, target_enemy_id, target_station_id,
target_tile, target_adjacent, attack_timer, injured_remaining`. Assignments add `recipe_id,
enemy_priority, heal_threshold, food_supply, food_item, auto_repair, route, route_index,
route_loop, route_name`.

Format 1 layout (still readable):
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

## Phase 4 data files

`data/server/server_config.json` (read by the server module, and by `WbServerData` on the client
for display):

| Key | Meaning |
|---|---|
| `validation.items_per_character_hour`, `gold_per_character_hour`, `gold_slack` | Maximum gains between two accepted uploads: rate × characters × hours (+ slack) |
| `validation.clock_slack_seconds` | How far the save's sim clock may run ahead of real elapsed time |
| `validation.hours_per_encounter_hero` | One non-recruited gacha hero is allowed per this many hours (wandering-hero encounters) |
| `validation.premium_per_hour {currency: n}` | Cap on premium currency credited from the simulation |
| `validation.max_save_bytes` | Upload size limit |
| `market.fee`, `market.max_listings` | Sale fee (0.05) and listings per player (20) |
| `guild.level_xp[]`, `guild.perks {level: effects}` | Guild XP per level (1 gold donated = 1 XP) and member effects |
| `world_boss.cooldown_seconds`, `gems_reward`, `bosses[] {id, name, hp, rewards {gold, items}}` | World boss rotation |
| `world_events[] {id, name, description, effects, epoch, period, duration}` | Recurring events: active for `duration` seconds of every `period`, counted from `epoch` (unix) |
| `presence.max_per_match`, `presence.empty_seconds_before_close` | Region presence match limits |

`tools/build_server_module.py` embeds this file plus the game data the server needs (banners,
character rarities, item ids and `untradeable` flags, region ids, the character XP table and the
starting wallet from `currencies.json`) as `WB_DATA` in `server/nakama/modules/index.js`.

`user://online.cfg` (client): `[server] url, server_key`, `[account] username, device_id`. An
empty url means offline play.

## Server storage (Nakama, Phase 4)

Nakama keeps accounts, friends, groups, chat history and wallets in its own tables. The module
stores the rest as storage objects (`collection / key`, owner):

| Collection / key | Owner | Read | Value |
|---|---|---|---|
| `saves/main` | player | owner | `{saved_at, summary {sim_time, gold, earned, spent, items, characters}, save}` |
| `profile/init`, `profile/granted` | player | owner | starting wallet granted; `{ids[]}` of characters the server gave |
| `ledger/pending` | player | server | `{seq, ops[] {seq, kind: debit|credit, item, qty}}` |
| `recruitment/state` | player | owner | `{pity {banner: {rarity: n}}, total {banner: n}, history[]}` |
| `town/public` | player | public | `{username, updated, buildings, regions, roster[] {id, stars, xp}}` |
| `market/<id>` | seller | public | `{id, seller, seller_name, item, qty, price, buyer, created}` |
| `market_index/<id>` | system | public | `{seller, item, buyer}` (deleted with a version check when bought) |
| `deliveries/<id>` | player | owner | `{id, items {id: qty}, reason, at}` |
| `guild/<group_id>` | system | public | `{xp, donations {user_id: gold}}` |
| `world_boss/current` | system | public | `{index, id, name, hp, max_hp, spawned, hits {user_id: {name, damage}}, rewards}` |
| `presence/<region>` | system | server | `{match_id}` of the region's live presence match |

## Future relational schema (not built)
When the simulation moves to the server, these entities replace the save blob. Columns are
indicative.
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
