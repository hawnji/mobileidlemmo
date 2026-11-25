extends WbTestCase
## Phase 4 client rules that need no server: how server answers change the
## local world (wallet cache, server pulls, escrow debits, deliveries, cloud
## vs local choice, guild / event effects).


func test_server_wallet_keeps_local_changes_made_while_a_request_was_out() -> void:
	var w := new_world()
	w.wallet.set_balance_from_server("gems", 100)
	var sent := OnlineSync.premium_snapshot(w)
	w.wallet.earn("gems", 7, "milestone")  # earned while the upload was in flight
	OnlineSync.apply_server_wallet(w, {"gems": 150, "recruitment_tokens": 3, "event_tokens": 0}, sent)
	assert_eq(w.wallet.get_balance("gems"), 157)
	assert_eq(w.wallet.get_balance("recruitment_tokens"), 3)


func test_server_balance_does_not_count_as_earned_or_spent() -> void:
	var w := new_world()
	var earned := int(w.wallet.totals_earned.get("gems", 0))
	var spent := int(w.wallet.totals_spent.get("gems", 0))
	w.wallet.set_balance_from_server("gems", 9999)
	w.wallet.set_balance_from_server("gems", 1)
	assert_eq(int(w.wallet.totals_earned.get("gems", 0)), earned, "the server already counted it")
	assert_eq(int(w.wallet.totals_spent.get("gems", 0)), spent)
	assert_eq(w.wallet.get_balance("gems"), 1)


func test_server_pull_adds_characters_without_a_local_spend() -> void:
	var w := new_world()
	var spent := int(w.wallet.totals_spent.get("gems", 0))
	var new_id := ""
	for cid in registry().characters:
		if not w.characters.has(cid) and String(registry().characters[cid].get("rarity", "")) != "":
			new_id = cid
			break
	var dup: String = w.character_order[0]
	var res := OnlineSync.apply_recruit(w, {"results": [
		{"character_id": new_id, "rarity": "rare", "banner": "standard"},
		{"character_id": dup, "rarity": "common", "banner": "standard"}],
		"wallet": {"gems": 40}, "pity": {"epic": 4, "legendary": 4}, "total": 12})
	assert_true(w.characters.has(new_id), "new character joined")
	assert_true(res[0].new)
	assert_gt(int(w.fragments.get(dup, 0)), 0, "duplicate became fragments")
	assert_eq(w.wallet.get_balance("gems"), 40)
	assert_eq(int(w.wallet.totals_spent.get("gems", 0)), spent, "server charged it, not the client")
	assert_eq(int(w.recruitment.pity_counters("standard").get("epic", 0)), 4, "banner screen shows server pity")


func test_escrow_debit_removes_items_and_keeps_the_item_ledger_balanced() -> void:
	var w := new_world()
	w.storage.add("iron_ore", 50)
	w.record_source("iron_ore", 50, "test")
	assert_eq(OnlineSync.apply_debit(w, "iron_ore", 20, 7, "market_list"), "")
	assert_eq(w.storage.get_quantity("iron_ore"), 30)
	assert_eq(w.server_ledger_seq, 7)
	assert_eq(w.held_totals(), w.ledger_totals(), "conservation still holds")
	assert_ne(OnlineSync.apply_debit(w, "iron_ore", 999, 8, "market_list"), "", "cannot escrow more than held")
	assert_eq(w.server_ledger_seq, 7, "a failed debit does not advance the sequence")


func test_gold_debit_and_sequence_never_goes_backwards() -> void:
	var w := new_world()
	w.wallet.earn("gold", 5000, "test")
	var before := w.wallet.get_balance("gold")
	assert_eq(OnlineSync.apply_debit(w, "gold", 1200, 12, "guild_donation"), "")
	assert_eq(w.wallet.get_balance("gold"), before - 1200)
	OnlineSync.apply_debit(w, "gold", 10, 3, "late answer")
	assert_eq(w.server_ledger_seq, 12)


func test_deliveries_go_to_storage_and_wallet_and_overflow_to_mail() -> void:
	var w := new_world()
	w.storage.max_units = w.storage.total_units() + 5
	var gold := w.wallet.get_balance("gold")
	var got := OnlineSync.apply_deliveries(w, {"items": {"gold": 950, "tin_ore": 8, "not_an_item": 3}, "ledger_seq": 21})
	assert_eq(w.wallet.get_balance("gold"), gold + 950)
	assert_eq(w.storage.get_quantity("tin_ore") + int(w.mailbox.get("tin_ore", 0)), 8)
	assert_eq(int(w.mailbox.get("tin_ore", 0)), 3, "full storage overflows to the mailbox")
	assert_false(got.has("not_an_item"), "unknown items are ignored")
	assert_eq(w.server_ledger_seq, 21)
	assert_eq(w.held_totals(), w.ledger_totals())


func test_ledger_sequence_survives_save_and_load() -> void:
	var w := new_world()
	w.server_ledger_seq = 42
	var w2 := SimulationWorld.from_dict(registry(), JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_eq(w2.server_ledger_seq, 42)


func test_cloud_save_is_chosen_when_it_is_further_along() -> void:
	var w := new_world()
	w.sim_time = 500.0
	var cloud := {"found": true, "saved_at": 2000.0, "save": {"world": {"sim_time": 900.0}}}
	assert_true(OnlineSync.prefer_cloud(w, 1000.0, cloud))
	cloud.save.world.sim_time = 100.0
	assert_false(OnlineSync.prefer_cloud(w, 1000.0, cloud), "local is further along")
	assert_false(OnlineSync.prefer_cloud(w, 1000.0, {"found": false}))
	assert_true(OnlineSync.prefer_cloud(null, 0.0, cloud), "new device takes the cloud save")


func test_guild_perks_and_world_events_boost_every_character() -> void:
	var w := new_world()
	var ch: Adventurer = w.characters[w.character_order[0]]
	var base := ch.stat_block().get_stat("xp", "mining")
	var fx := OnlineSync.Effects.new(registry())
	w.account.extra_sources.append(fx)
	fx.set_sources(registry(), {"xp.all": 1.05}, [{"id": "weekend_bounty", "effects": {"xp.all": 1.1}}])
	ch.invalidate_stats()
	assert_almost(ch.stat_block().get_stat("xp", "mining"), base * 1.05 * 1.1, 0.0001)
	var v := fx.version
	fx.set_sources(registry(), {"xp.all": 1.05}, [{"id": "weekend_bounty", "effects": {"xp.all": 1.1}}])
	assert_eq(fx.version, v, "unchanged sources do not invalidate stats")


func test_server_data_matches_the_shipped_config() -> void:
	assert_gt(WbServerData.guild_levels().size(), 1)
	assert_almost(WbServerData.market_fee(), 0.05)
	assert_eq(WbServerData.describe_effects({"xp.all": 1.03}), "+3% XP")
	assert_true(WbServerData.is_tradeable(registry(), "iron_ore"))
	assert_false(WbServerData.is_tradeable(registry(), "no_such_item"))


func test_online_settings_round_trip() -> void:
	var path := OnlineService.SETTINGS_PATH
	var backup := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	OnlineService.save_settings("http://example.invalid:7350", "k", "tester")
	assert_eq(OnlineService.load_settings().url, "http://example.invalid:7350")
	var id := OnlineService.device_id()
	assert_eq(OnlineService.device_id(), id, "device id is stable")
	OnlineService.clear_settings()
	assert_true(OnlineService.load_settings().is_empty(), "cleared settings mean offline")
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
