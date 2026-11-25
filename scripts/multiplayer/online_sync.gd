class_name OnlineSync
extends RefCounted
## Applies server answers to the local world. Pure functions on the world,
## so they are tested without a server (tests/unit/test_online_sync.gd).
##
## Contract with the server (server/nakama/src):
## - Premium currencies (PREMIUM) live in the Nakama wallet. The client keeps
##   a cache; the server credits what the simulation earned (capped) when a
##   save upload is accepted, and debits server-side spends (recruitment).
## - Market listings and guild donations are debits recorded as ledger ops
##   with a sequence number; purchases, sales and returns are deliveries
##   (credits). The save carries `server_ledger_seq` = the last op applied
##   locally, so the server knows which ops a save already reflects.

const PREMIUM := ["gems", "recruitment_tokens", "event_tokens"]


## Premium balances = server wallet + whatever changed locally since the
## snapshot `sent` (balances at the moment the request was sent). Pass an
## empty `sent` to take the server values as they are.
static func apply_server_wallet(world: SimulationWorld, server_wallet: Dictionary, sent: Dictionary = {}) -> void:
	for c in PREMIUM:
		if not server_wallet.has(c):
			continue
		var drift := 0
		if sent.has(c):
			drift = world.wallet.get_balance(c) - int(sent[c])
		world.wallet.set_balance_from_server(c, int(server_wallet[c]) + drift)


static func premium_snapshot(world: SimulationWorld) -> Dictionary:
	var out := {}
	for c in PREMIUM:
		out[c] = world.wallet.get_balance(c)
	return out


## A pull the server rolled and paid for: add the characters, sync the wallet.
static func apply_recruit(world: SimulationWorld, resp: Dictionary) -> Array:
	var results: Array = []
	for r in resp.get("results", []):
		results.append({"character_id": String(r.get("character_id", "")), "rarity": String(r.get("rarity", "")),
			"banner": String(r.get("banner", ""))})
	world.apply_recruit_results(results)
	apply_server_wallet(world, resp.get("wallet", {}))
	# Mirror the server's pity so the banner screen shows the real counters.
	var banner := String(results[0].banner) if not results.is_empty() else ""
	if not banner.is_empty() and resp.get("pity") is Dictionary:
		var counters := {}
		for r in resp.pity:
			counters[String(r)] = int(resp.pity[r])
		world.recruitment.pity[banner] = counters
		world.recruitment.total_pulls[banner] = int(resp.get("total", world.recruitment.total_pulls.get(banner, 0)))
	return results


## Removes what the server just escrowed (a listing or a donation).
## Returns "" or an error if the world no longer holds it.
static func apply_debit(world: SimulationWorld, item: String, qty: int, seq: int, reason: String) -> String:
	if item == "gold":
		if not world.wallet.spend("gold", qty, reason):
			return "Not enough gold"
	else:
		if world.storage.get_quantity(item) < qty:
			return "Not enough %s in storage" % world.registry.get_item_name(item)
		world.storage.remove(item, qty)
		world.record_sink(item, qty, reason)
	world.server_ledger_seq = maxi(world.server_ledger_seq, seq)
	return ""


## Claimed deliveries: {items: {id: qty}, ledger_seq}. Gold goes to the
## wallet, items to storage (overflow to the mailbox).
static func apply_deliveries(world: SimulationWorld, resp: Dictionary) -> Dictionary:
	var items: Dictionary = resp.get("items", {})
	var got := {}
	for it in items:
		var qty := int(items[it])
		if qty <= 0:
			continue
		if String(it) == "gold":
			world.wallet.earn("gold", qty, "market")
		elif world.registry.items.has(it):
			world.record_source(String(it), qty, "market")
			world._store_or_mail(String(it), qty)
		else:
			continue
		got[String(it)] = qty
	if int(resp.get("ledger_seq", 0)) > 0:
		world.server_ledger_seq = maxi(world.server_ledger_seq, int(resp.ledger_seq))
	return got


## Which save to keep on start-up: the cloud one when it is further along.
static func prefer_cloud(local_world: SimulationWorld, local_saved_at: float, cloud: Dictionary) -> bool:
	if not cloud.get("found", false):
		return false
	if local_world == null:
		return true
	var cw: Dictionary = cloud.get("save", {}).get("world", {})
	var cloud_sim := float(cw.get("sim_time", 0.0))
	if absf(cloud_sim - local_world.sim_time) > 1.0:
		return cloud_sim > local_world.sim_time
	return float(cloud.get("saved_at", 0.0)) > local_saved_at


## Guild perks and active world events as one account-wide effect source.
class Effects:
	extends RefCounted
	var effects: StatBlock
	var version := 0
	var _key := ""

	func _init(registry: DataRegistry) -> void:
		effects = registry.new_stat_block()

	func set_sources(registry: DataRegistry, guild_perks: Dictionary, events: Array) -> void:
		var key := JSON.stringify([guild_perks, events.map(func(e): return e.get("id", ""))])
		if key == _key:
			return
		_key = key
		var sb := registry.new_stat_block()
		sb.apply(guild_perks)
		for e in events:
			sb.apply(e.get("effects", {}))
		effects = sb
		version += 1
