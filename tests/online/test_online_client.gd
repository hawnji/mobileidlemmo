extends WbTestCase
## Phase 4 client against a live Nakama server running server/nakama.
## Runs only when WB_NAKAMA_URL is set (server/run_tests.sh does that).
## Every test uses fresh accounts, so the suite can run repeatedly.

var _url := OS.get_environment("WB_NAKAMA_URL")
var _key := OS.get_environment("WB_NAKAMA_KEY") if not OS.get_environment("WB_NAKAMA_KEY").is_empty() else "wb-dev-server-key"
var _services: Array = []
static var _run := ""


func before_each() -> void:
	super.before_each()
	if _run.is_empty():
		_run = "%x" % (Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system()))


func after_each() -> void:
	for s in _services:
		s.socket.close()
		s.free()
	_services.clear()
	super.after_each()


## A signed-in player with a new world (nothing synced yet).
func _player(tag: String, setup := Callable()) -> OnlineService:
	var svc := OnlineService.new(_url, _key)
	svc.synchronous = true
	_services.append(svc)
	var boot := svc.connect_blocking("wbtest-%s-%s" % [tag, _run], "%s_%s" % [tag, _run])
	assert_true(svc.is_online(), "signed in as %s: %s" % [tag, svc.status_message])
	assert_eq(int(boot.get("wallet", {}).get("gems", -1)), 300, "starting gems come from the server wallet")
	var w := new_world()
	if setup.is_valid():
		setup.call(w)
	svc.attach_world(w)
	return svc


func _upload(svc: OnlineService) -> Dictionary:
	var out := {}
	var cb := func(r: Dictionary) -> void: out.merge(r)
	svc.synced.connect(cb)
	svc.upload_now()
	svc.synced.disconnect(cb)
	return out


func _give(w: SimulationWorld, item: String, qty: int) -> void:
	w.storage.add(item, qty)
	w.record_source(item, qty, "test")


func _pump(svcs: Array, until: Callable, ms := 5000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		for s in svcs:
			s.socket.poll()
		if until.call():
			return true
		OS.delay_msec(20)
	return false


func _result(fn: Callable) -> Dictionary:
	var out := {}
	fn.call(func(r: Dictionary) -> void: out.merge(r))
	return out


# ------------------------------------------------------------------ saves

func test_a_real_save_uploads_downloads_and_shows_as_a_public_town() -> void:
	var a := _player("saver")
	var r := _upload(a)
	assert_true(r.ok, "first upload: %s" % r.get("message", ""))
	assert_false(a.cloud_version.is_empty())
	var dl := a.client.call_rpc("wb_save_download")
	assert_true(dl.ok and dl.data.found)
	var w2 := SimulationWorld.from_dict(registry(), dl.data.save.world)
	assert_eq(w2.character_order, a.world.character_order)
	assert_eq(w2.storage.items(), a.world.storage.items())
	var b := _player("visitor")
	var town := b.client.call_rpc("wb_visit_town", {"user_id": a.client.user_id})
	assert_true(town.ok, town.message)
	assert_eq(int(town.data.buildings.get("town_hall", 0)), a.world.town.level_of("town_hall"))
	assert_eq(town.data.roster.size(), a.world.character_order.size())


func test_honest_progress_is_accepted_and_earned_gems_are_credited() -> void:
	var a := _player("grinder")
	assert_true(_upload(a).ok)
	for cid in a.world.character_order:
		var act: String = {"brom_stonefist": "mine_copper", "sylvara_moonleaf": "chop_oak"}.get(cid, "fish_minnow")
		a.world.assign_activity(cid, Assignment.create(cid, registry().activities[act]))
	for i in 1500:
		a.world.step(0.1)
	a.world.wallet.earn("gems", 25, "milestone:test")
	var r := _upload(a)
	assert_true(r.ok, "progress accepted: %s" % r.get("message", ""))
	var boot := a.client.call_rpc("wb_bootstrap")
	assert_eq(int(boot.data.wallet.gems), 325, "server credited the earned gems")
	assert_eq(a.world.wallet.get_balance("gems"), 325, "client follows the server wallet")


func test_impossible_progress_is_rejected() -> void:
	var a := _player("cheater")
	assert_true(_upload(a).ok)
	_give(a.world, "iron_bar", 50000)
	var r := _upload(a)
	assert_false(r.ok)
	assert_true(String(r.message).contains("iron_bar"), String(r.message))
	a.world.sim_time += 7200.0
	assert_false(_upload(a).ok, "a clock ahead of real time is refused")


func test_a_second_device_must_load_the_cloud_save_first() -> void:
	var a := _player("twodev")
	assert_true(_upload(a).ok)
	var stale := a.cloud_version
	assert_true(_upload(a).ok)
	a.cloud_version = stale  # as if another device had saved since
	var r := _upload(a)
	assert_false(r.ok)
	assert_true(String(r.message).contains("another device"), String(r.message))


func test_new_device_starts_from_the_cloud_save() -> void:
	var a := _player("roamer")
	for i in 600:
		a.world.step(0.1)
	assert_true(_upload(a).ok)
	var path := "user://test_cloud_device.json"
	var backend := NakamaGameBackend.new(registry(), {"url": _url, "server_key": _key, "device_id": "wbtest-roamer-%s" % _run}, path)
	backend.delete_save()
	backend.service.synchronous = true
	_services.append(backend.service)
	var loaded := backend.load_world(registry())
	assert_eq(String(loaded.get("source", "")), "cloud")
	assert_almost(float(loaded.world.sim_time), a.world.sim_time, 0.01)
	backend.delete_save()


# ------------------------------------------------------------------ economy

func test_server_recruitment_adds_heroes_that_later_saves_may_keep() -> void:
	var a := _player("puller")
	assert_true(_upload(a).ok)
	var before := a.world.character_order.size()
	var res := _result(func(cb: Callable) -> void: a.recruit("standard", 10, cb))
	assert_eq(String(res.get("error", "?")), "")
	assert_eq(res.results.size(), 10)
	assert_eq(a.world.wallet.get_balance("recruitment_tokens"), 0, "ten tokens spent on the server")
	assert_gte(a.world.character_order.size(), before)
	for r0 in res.results:
		assert_true(a.world.characters.has(String(r0.character_id)), "pulled hero is on the roster")
	var r := _upload(a)
	assert_true(r.ok, "granted heroes are accepted: %s" % r.get("message", ""))
	var none := _result(func(cb: Callable) -> void: a.recruit("standard", 10, cb))
	assert_eq(String(none.error), "Not enough tokens or gems")


func test_market_sale_between_two_players_settles_on_both_saves() -> void:
	var seller := _player("seller", func(w: SimulationWorld) -> void: _give(w, "iron_ore", 40))
	var buyer := _player("buyer", func(w: SimulationWorld) -> void: w.wallet.earn("gold", 3000, "test"))
	assert_true(_upload(seller).ok)
	assert_true(_upload(buyer).ok)
	var listed := _result(func(cb: Callable) -> void: seller.market_list("iron_ore", 25, 1000, "", cb))
	assert_true(listed.ok, String(listed.get("message", "")))
	assert_eq(seller.world.storage.get_quantity("iron_ore"), 15, "escrowed items leave storage")
	assert_true(_upload(seller).ok, "seller's save matches the escrow")
	var lid := String(listed.data.listing.id)
	var bought := _result(func(cb: Callable) -> void: buyer.market_buy(lid, cb))
	assert_true(bought.ok, String(bought.get("message", "")))
	assert_eq(buyer.world.storage.get_quantity("iron_ore"), 25, "delivered to the buyer")
	assert_eq(buyer.world.wallet.get_balance("gold"), 200 + 3000 - 1000)
	assert_true(_upload(buyer).ok, "buyer's save with the purchase is accepted")
	var paid := _result(func(cb: Callable) -> void: seller.claim_deliveries(cb))
	assert_eq(int(paid.items.get("gold", 0)), 950, "price minus the 5% fee")
	assert_true(_upload(seller).ok)
	assert_eq(seller.world.held_totals(), seller.world.ledger_totals())
	assert_eq(buyer.world.held_totals(), buyer.world.ledger_totals())


func test_guild_donations_level_the_guild_and_boost_members() -> void:
	var a := _player("founder", func(w: SimulationWorld) -> void: w.wallet.earn("gold", 6000, "test"))
	var b := _player("member")
	assert_true(_upload(a).ok)
	var g := a.client.create_group("Guild %s" % _run)
	assert_true(g.ok, g.message)
	assert_true(b.client.join_group(String(g.data.id)).ok)
	var don := _result(func(cb: Callable) -> void: a.guild_donate(5000, cb))
	assert_true(don.ok, String(don.get("message", "")))
	assert_eq(int(don.data.level), 2)
	assert_true(_upload(a).ok, "save with the donation applied is accepted")
	b.refresh_social()
	assert_eq(int(b.guild.get("level", 0)), 2)
	var ch: Adventurer = b.world.characters[b.world.character_order[0]]
	ch.invalidate_stats()
	assert_gt(ch.stat_block().get_stat("xp", "mining"), 1.0199, "member gets the level-2 XP perk")


# ------------------------------------------------------------------ realtime

func test_guild_chat_and_region_presence_over_the_socket() -> void:
	var a := _player("chat_a")
	var b := _player("chat_b")
	var g := a.client.create_group("Chat %s" % _run)
	assert_true(b.client.join_group(String(g.data.id)).ok)
	assert_true(_pump([a, b], func() -> bool: return a.socket.is_open() and b.socket.is_open()), "sockets open")
	assert_true(_pump([a, b], func() -> bool: return not a.chat_channel_id.is_empty() and not b.chat_channel_id.is_empty()), "joined guild chat")
	a.send_chat("hello from %s" % _run)
	assert_true(_pump([a, b], func() -> bool:
		return b.chat_log.any(func(e): return String(e.text) == "hello from %s" % _run)), "chat reached the other member")
	# Both worlds start in the same region, so they share its match.
	a._update_presence()
	b._update_presence()
	assert_true(_pump([a, b], func() -> bool: return not a.region_match_id.is_empty() and not b.region_match_id.is_empty()))
	assert_eq(a.region_match_id, b.region_match_id)
	var seen := func() -> bool:
		a._update_presence()
		return b.region_players.has(a.client.user_id) and not b.region_players[a.client.user_id].heroes.is_empty()
	assert_true(_pump([a, b], seen, 6000), "b sees a's heroes")
	assert_eq(b.region_players[a.client.user_id].heroes.size(), a.world.character_order.size())
