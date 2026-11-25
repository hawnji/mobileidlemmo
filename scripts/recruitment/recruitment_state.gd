class_name RecruitmentState
extends RefCounted
## Gacha rolls, pity counters and pull history for every banner.
##
## LOCAL / DEVELOPMENT ONLY. In the online build the Recruitment Service on
## the server owns the RNG, the pity counters and the history (see
## docs/TECHNICAL_ARCHITECTURE.md). The client only displays results. The
## same algorithm is used on both sides so this file is the reference
## implementation and is what the probability tests run against.
##
## Pity: every pity tier T has a counter of pulls since the last result of
## rarity >= T. If the next pull is the T counter's `guaranteed_on_pull`-th,
## the result is raised to at least T (the highest such tier wins). After a
## pull of rarity R, counters for tiers <= R reset and the others increase.

var rng := RandomNumberGenerator.new()
var pity := {}  # banner_id -> {rarity: pulls_since}
var total_pulls := {}  # banner_id -> int
var history: Array[Dictionary] = []  # most recent first, capped
const HISTORY_SIZE := 100


static func rarity_rank(registry: DataRegistry, rarity: String) -> int:
	return (registry.recruitment_config.get("rarity_order", []) as Array).find(rarity)


## One roll of the base table, ignoring pity.
func roll_base_rarity(banner: Dictionary) -> String:
	var rates: Dictionary = banner.get("rates", {})
	var r := rng.randf()
	var acc := 0.0
	var last := ""
	for rarity in rates:
		acc += float(rates[rarity])
		last = String(rarity)
		if r < acc:
			return last
	return last


func pity_counters(banner_id: String) -> Dictionary:
	if not pity.has(banner_id):
		pity[banner_id] = {}
	return pity[banner_id]


## Rolls one rarity with pity applied and updates the counters.
func roll_rarity(registry: DataRegistry, banner: Dictionary) -> String:
	var bid := String(banner.get("id", ""))
	var counters := pity_counters(bid)
	var forced := ""
	for p in banner.get("pity", []):
		var tier := String(p.rarity)
		if int(counters.get(tier, 0)) + 1 >= int(p.guaranteed_on_pull):
			if forced.is_empty() or rarity_rank(registry, tier) > rarity_rank(registry, forced):
				forced = tier
	var result := roll_base_rarity(banner)
	if not forced.is_empty() and rarity_rank(registry, result) < rarity_rank(registry, forced):
		result = forced
	for p in banner.get("pity", []):
		var tier := String(p.rarity)
		if rarity_rank(registry, result) >= rarity_rank(registry, tier):
			counters[tier] = 0
		else:
			counters[tier] = int(counters.get(tier, 0)) + 1
	total_pulls[bid] = int(total_pulls.get(bid, 0)) + 1
	return result


func pick_character(registry: DataRegistry, banner: Dictionary, rarity: String) -> String:
	var pool: Array[String] = []
	for cid in registry.characters_by_acquisition("gacha"):
		if String(registry.characters[cid].get("rarity", "")) == rarity:
			pool.append(cid)
	var featured: Variant = banner.get("featured")
	if featured is Dictionary:
		var fid := String(featured.get("character_id", ""))
		if pool.has(fid):
			if rng.randf() < float(featured.get("share", 0.0)) or pool.size() == 1:
				return fid
			pool.erase(fid)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


## Pulls `count` results. Returns [{character_id, rarity}]. Does not charge
## currency or grant characters: SimulationWorld.recruit() does that.
func pull(registry: DataRegistry, banner: Dictionary, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in count:
		var rarity := roll_rarity(registry, banner)
		var cid := pick_character(registry, banner, rarity)
		var res := {"character_id": cid, "rarity": rarity, "banner": String(banner.get("id", ""))}
		out.append(res)
		history.push_front(res)
	if history.size() > HISTORY_SIZE:
		history.resize(HISTORY_SIZE)
	return out


## Long-run share of each rarity including pity, measured by simulating
## `pulls` rolls on a throwaway state with a fixed seed. Published in-game.
static func effective_rates(registry: DataRegistry, banner: Dictionary, pulls := 200000, seed_value := 12345) -> Dictionary:
	var sim := RecruitmentState.new()
	sim.rng.seed = seed_value
	var counts := {}
	for i in pulls:
		var r := sim.roll_rarity(registry, banner)
		counts[r] = int(counts.get(r, 0)) + 1
	var rates := {}
	for rarity in banner.get("rates", {}):
		rates[rarity] = float(counts.get(rarity, 0)) / float(pulls)
	return rates


func to_dict() -> Dictionary:
	return {"rng_seed": str(rng.seed), "rng_state": str(rng.state), "pity": pity.duplicate(true),
		"total_pulls": total_pulls.duplicate(), "history": history.duplicate(true)}


func load_dict(registry: DataRegistry, d: Dictionary) -> void:
	rng.seed = String(d.get("rng_seed", str(rng.seed))).to_int()
	rng.state = String(d.get("rng_state", str(rng.state))).to_int()
	pity = {}
	var p: Variant = d.get("pity", {})
	if p is Dictionary:
		for b in p:
			if registry.banners.has(b) and p[b] is Dictionary:
				var c := {}
				for tier in p[b]:
					c[String(tier)] = maxi(int(p[b][tier]), 0)
				pity[String(b)] = c
	for b in d.get("total_pulls", {}):
		total_pulls[String(b)] = int(d.total_pulls[b])
	history.clear()
	for h in d.get("history", []):
		if h is Dictionary:
			history.append(h)
