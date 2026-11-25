class_name SocialPanel
extends ModalPanel
## Online play: account and cloud sync, friends (and their towns), guild
## with chat and donations, the player market, and the shared world (world
## boss, world events, players in your region). Offline, the Account tab
## lets the player enter a server address and go online.

var world: SimulationWorld
var _tab := "account"
var _msg: Label
var _listings: Array = []
var _friends: Array = []
var _groups: Array = []
var _members: Array = []
var _boss: Dictionary = {}
var _visit: Dictionary = {}
var _trade_with := {}  # {id, name} for a private listing
var _chat_box: VBoxContainer
const TABS := [["Account", "account"], ["Friends", "friends"], ["Guild", "guild"], ["Market", "market"], ["World", "world"]]


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("Social")
	var on := _online()
	if on:
		on.social_changed.connect(_on_changed)
		on.synced.connect(func(_r: Dictionary) -> void: _on_changed())
		on.chat_received.connect(_on_chat)
		on.presence_changed.connect(func(_p: Dictionary) -> void:
			if _tab == "world":
				refresh())
	_open_tab(_tab)


func _online() -> OnlineService:
	return Game.online


func _on_changed() -> void:
	if is_inside_tree():
		refresh()


func _on_chat(e: Dictionary) -> void:
	if _tab == "guild" and is_instance_valid(_chat_box):
		_chat_box.add_child(_chat_line(e))


func _open_tab(t: String) -> void:
	_tab = t
	refresh()
	var on := _online()
	if on == null or not on.is_online():
		return
	match t:
		"friends":
			on.run(func() -> Dictionary: return on.client.list_friends(), func(r: Dictionary) -> void:
				_friends = r.data.get("friends", []) if r.ok else []
				refresh())
		"guild":
			on.refresh_social()
			if on.guild.get("in_guild", false):
				var gid := String(on.guild.get("group_id", ""))
				on.run(func() -> Dictionary: return on.client.group_members(gid), func(r: Dictionary) -> void:
					_members = r.data.get("group_users", []) if r.ok else []
					refresh())
			else:
				on.run(func() -> Dictionary: return on.client.list_groups(), func(r: Dictionary) -> void:
					_groups = r.data.get("groups", []) if r.ok else []
					refresh())
		"market":
			_browse()
		"world":
			on.call_rpc("wb_boss_status", {}, func(r: Dictionary) -> void:
				_boss = r.data if r.ok else {}
				refresh())


func refresh() -> void:
	clear_body()
	var tabs := HFlowContainer.new()
	for spec in TABS:
		var b := UiTheme.button(spec[0], 17)
		b.custom_minimum_size = Vector2(118, 52)
		b.toggle_mode = true
		b.button_pressed = _tab == spec[1]
		var key: String = spec[1]
		b.pressed.connect(func() -> void: _open_tab(key))
		tabs.add_child(b)
	body.add_child(tabs)
	_msg = UiTheme.label("", 17, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	var on := _online()
	if _tab == "account":
		_account(on)
	elif on == null or not on.is_online():
		body.add_child(_dim("You are playing offline. Go online from the Account tab to see friends, guilds, the market and the world boss."))
	else:
		match _tab:
			"friends":
				_friends_tab(on)
			"guild":
				_guild_tab(on)
			"market":
				_market_tab(on)
			"world":
				_world_tab(on)
	QuestsPanel.wrap_labels(body)


func _say(text: String, good := false) -> void:
	if is_instance_valid(_msg):
		_msg.text = text
		_msg.add_theme_color_override("font_color", UiTheme.GOOD if good else UiTheme.BAD)


static func _dim(text: String, size := 16) -> Label:
	var l := UiTheme.label(text, size, UiTheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _field(placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 52)
	e.add_theme_font_size_override("font_size", 18)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func _spin(min_v: int, max_v: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = maxi(max_v, min_v)
	s.value = clampi(value, min_v, maxi(max_v, min_v))
	s.custom_minimum_size = Vector2(150, 52)
	s.get_line_edit().add_theme_font_size_override("font_size", 18)
	return s


# ---------------------------------------------------------------- account

func _account(on: OnlineService) -> void:
	if on == null:
		body.add_child(UiTheme.label("Offline", 24, UiTheme.ACCENT))
		body.add_child(_dim("Your progress is saved on this device. Online play adds a cloud save, friends, guilds, the market, world events and the world boss. It needs a Worldbound server (see server/README.md)."))
		var s := OnlineService.load_settings()
		var url := _field("Server address, e.g. http://192.168.1.20:7350", String(s.get("url", "")))
		var key := _field("Server key", String(s.get("server_key", "defaultkey")))
		var name := _field("Player name (optional)", String(s.get("username", "")))
		for f in [url, key, name]:
			body.add_child(f)
		var go := UiTheme.button("Go online", 20)
		go.pressed.connect(func() -> void:
			if not url.text.begins_with("http"):
				_say("Enter an address starting with http:// or https://")
				return
			OnlineService.save_settings(url.text, key.text, name.text.strip_edges())
			Game.save_now()
			close()
			Game.start_session(NakamaGameBackend.new(Game.registry, OnlineService.load_settings())))
		body.add_child(go)
		return
	var state_text := {"online": "Online", "connecting": "Connecting...", "error": "Server unreachable", "offline": "Offline"}
	body.add_child(UiTheme.label("%s  -  %s" % [state_text.get(on.status, on.status), on.client.username], 24,
		UiTheme.GOOD if on.is_online() else UiTheme.BAD))
	if not on.status_message.is_empty():
		body.add_child(_dim(on.status_message))
	body.add_child(_dim("Server %s  |  %s" % [on.client.base_url, on.last_sync_text]))
	body.add_child(_dim("Your device save stays the working copy and syncs to the cloud every minute. The server checks each upload, holds your gems and tokens, and rolls recruitment."))
	var row := HFlowContainer.new()
	var sync := UiTheme.button("Sync now", 18)
	sync.pressed.connect(func() -> void:
		Game.save_now()
		on.upload_now()
		_say("Syncing...", true))
	row.add_child(sync)
	var cloud := UiTheme.button("Load cloud save", 18)
	cloud.pressed.connect(func() -> void:
		on.download_cloud(func(r: Dictionary) -> void:
			if not r.ok or not r.data.get("found", false):
				_say(r.message if not r.ok else "No cloud save yet")
				return
			var w := SimulationWorld.from_dict(Game.registry, r.data.save.world)
			OnlineSync.apply_server_wallet(w, r.data.get("wallet", {}))
			Game.replace_world(w)
			close()))
	row.add_child(cloud)
	var mail := UiTheme.button("Collect deliveries", 18)
	mail.pressed.connect(func() -> void:
		on.claim_deliveries(func(r: Dictionary) -> void:
			if not r.ok:
				_say(r.message)
			elif r.items.is_empty():
				_say("Nothing waiting", true)
			else:
				_say("Collected: " + _describe(r.items), true)))
	row.add_child(mail)
	var off := UiTheme.button("Play offline", 18)
	off.pressed.connect(func() -> void:
		Game.save_now()
		OnlineService.clear_settings()
		close()
		Game.start_session(LocalGameBackend.new(Game.registry)))
	row.add_child(off)
	body.add_child(row)
	if not on.is_online():
		var retry := UiTheme.button("Reconnect", 18)
		retry.pressed.connect(func() -> void:
			Game.save_now()
			close()
			Game.start_session(NakamaGameBackend.new(Game.registry, OnlineService.load_settings())))
		body.add_child(retry)
	body.add_child(_dim("Your player id (share it with friends): %s" % on.client.user_id, 14))


func _describe(items: Dictionary) -> String:
	var parts := []
	for it in items:
		parts.append("%d %s" % [int(items[it]), "gold" if it == "gold" else world.registry.get_item_name(it)])
	return ", ".join(parts)


# ---------------------------------------------------------------- friends

func _friends_tab(on: OnlineService) -> void:
	var add := HBoxContainer.new()
	var who := _field("Player name")
	add.add_child(who)
	var b := UiTheme.button("Add friend", 18)
	b.pressed.connect(func() -> void:
		var n := who.text.strip_edges()
		if n.is_empty():
			return
		on.run(func() -> Dictionary: return on.client.add_friend_by_username(n), func(r: Dictionary) -> void:
			_say("Friend request sent to %s" % n if r.ok else r.message, r.ok)
			if r.ok:
				_open_tab("friends")))
	add.add_child(b)
	body.add_child(add)
	if _friends.is_empty():
		body.add_child(_dim("No friends yet. Add someone by their player name."))
	var states := {0: "Friend", 1: "Request sent", 2: "Wants to be friends", 3: "Blocked"}
	for f in _friends:
		var u: Dictionary = f.get("user", {})
		var st := int(f.get("state", 0))
		var uid := String(u.get("id", ""))
		var uname := String(u.get("username", "?"))
		var row := HFlowContainer.new()
		var l := UiTheme.label("%s  (%s)%s" % [uname, states.get(st, "?"), "  online" if u.get("online", false) else ""], 18,
			UiTheme.GOOD if st == 0 else UiTheme.TEXT)
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		if st == 2:
			var acc := UiTheme.button("Accept", 16)
			acc.pressed.connect(func() -> void:
				on.run(func() -> Dictionary: return on.client.add_friend_by_id(uid), func(_r: Dictionary) -> void: _open_tab("friends")))
			row.add_child(acc)
		if st == 0:
			var visit := UiTheme.button("Visit town", 16)
			visit.pressed.connect(func() -> void:
				on.call_rpc("wb_visit_town", {"user_id": uid}, func(r: Dictionary) -> void:
					_visit = r.data if r.ok else {}
					refresh()
					if not r.ok:
						_say(r.message)))
			row.add_child(visit)
			var trade := UiTheme.button("Trade", 16)
			trade.pressed.connect(func() -> void:
				_trade_with = {"id": uid, "name": uname}
				_open_tab("market"))
			row.add_child(trade)
		var rm := UiTheme.button("Remove", 16)
		rm.pressed.connect(func() -> void:
			on.run(func() -> Dictionary: return on.client.remove_friend_by_id(uid), func(_r: Dictionary) -> void: _open_tab("friends")))
		row.add_child(rm)
		body.add_child(row)
	if not _visit.is_empty():
		body.add_child(HSeparator.new())
		body.add_child(UiTheme.label("%s's town" % _visit.get("username", "?"), 22, UiTheme.ACCENT))
		var bl := []
		var bld: Dictionary = _visit.get("buildings", {})
		for bid in bld:
			if int(bld[bid]) <= 0:
				continue
			bl.append("%s %d" % [world.registry.buildings.get(bid, {}).get("name", bid), int(bld[bid])])
		body.add_child(_dim("Buildings: " + ", ".join(bl)))
		var rl := []
		for r in _visit.get("roster", []):
			rl.append("%s %s" % [world.registry.characters.get(r.id, {}).get("name", r.id), "*".repeat(int(r.get("stars", 1)))])
		body.add_child(_dim("Heroes: " + ", ".join(rl)))
		var regions: Array = _visit.get("regions", [])
		body.add_child(_dim("Regions: " + ", ".join(regions.map(func(x): return world.registry.region_name(String(x))))))


# ---------------------------------------------------------------- guild

func _guild_tab(on: OnlineService) -> void:
	var g := on.guild
	if not g.get("in_guild", false):
		body.add_child(UiTheme.label("Join a guild", 22, UiTheme.ACCENT))
		body.add_child(_dim("Guild members share a chat and level the guild up with gold donations. Each guild level gives every member a bonus."))
		for grp in _groups:
			var row := HBoxContainer.new()
			var l := UiTheme.label("%s  (%d members)" % [grp.get("name", "?"), int(grp.get("edge_count", 0))], 18)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var gid := String(grp.get("id", ""))
			var j := UiTheme.button("Join", 16)
			j.pressed.connect(func() -> void:
				on.run(func() -> Dictionary: return on.client.join_group(gid), func(r: Dictionary) -> void:
					if not r.ok:
						_say(r.message)
					on.refresh_social()
					_open_tab("guild")))
			row.add_child(j)
			body.add_child(row)
		var mk := HBoxContainer.new()
		var gname := _field("New guild name")
		mk.add_child(gname)
		var c := UiTheme.button("Create", 18)
		c.pressed.connect(func() -> void:
			var n := gname.text.strip_edges()
			if n.length() < 3:
				_say("Guild names need at least 3 letters")
				return
			on.run(func() -> Dictionary: return on.client.create_group(n), func(r: Dictionary) -> void:
				if not r.ok:
					_say(r.message)
				on.refresh_social()
				_open_tab("guild")))
		mk.add_child(c)
		body.add_child(mk)
		return
	var levels: Array = WbServerData.guild_levels()
	var lv := int(g.get("level", 1))
	body.add_child(UiTheme.label("%s  -  level %d" % [g.get("name", "Guild"), lv], 24, UiTheme.ACCENT))
	var next := int(levels[lv]) if lv < levels.size() else -1
	body.add_child(_dim("Guild XP %d%s" % [int(g.get("xp", 0)), "" if next < 0 else " / %d" % next]))
	var bar := UiTheme.bar(UiTheme.ACCENT, 10)
	bar.value = 1.0 if next < 0 else float(g.get("xp", 0)) / float(next)
	body.add_child(bar)
	var perks: Dictionary = g.get("perks", {})
	body.add_child(UiTheme.label("Member bonus: %s" % (WbServerData.describe_effects(perks) if not perks.is_empty() else "none yet"), 17, UiTheme.GOOD))
	var don := HFlowContainer.new()
	for amt in [500, 2000, 10000]:
		var b := UiTheme.button("Donate %d gold" % amt, 16)
		b.disabled = world.wallet.get_balance("gold") < amt
		b.pressed.connect(func() -> void:
			on.guild_donate(amt, func(r: Dictionary) -> void:
				refresh()
				_say("Donated %d gold" % amt if r.ok else r.message, r.ok)))
		don.add_child(b)
	body.add_child(don)
	if not _members.is_empty():
		var names := []
		for m in _members:
			var u: Dictionary = m.get("user", {})
			names.append(String(u.get("username", "?")) + (" (online)" if u.get("online", false) else ""))
		body.add_child(_dim("Members: " + ", ".join(names)))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Guild chat", 20, UiTheme.ACCENT))
	_chat_box = VBoxContainer.new()
	for e in on.chat_log.slice(-30):
		_chat_box.add_child(_chat_line(e))
	if on.chat_log.is_empty():
		_chat_box.add_child(_dim("No messages yet." if not on.chat_channel_id.is_empty() else "Connecting to chat..."))
	body.add_child(_chat_box)
	var send := HBoxContainer.new()
	var text := _field("Say something")
	text.max_length = 300
	send.add_child(text)
	var sb := UiTheme.button("Send", 18)
	var do_send := func() -> void:
		on.send_chat(text.text)
		text.text = ""
	sb.pressed.connect(do_send)
	text.text_submitted.connect(func(_t: String) -> void: do_send.call())
	send.add_child(sb)
	body.add_child(send)
	var leave := UiTheme.button("Leave guild", 16)
	leave.pressed.connect(func() -> void:
		var gid := String(g.get("group_id", ""))
		on.run(func() -> Dictionary: return on.client.leave_group(gid), func(_r: Dictionary) -> void:
			on.guild = {"in_guild": false}
			on.chat_channel_id = ""
			on.chat_log.clear()
			on.refresh_social()
			_open_tab("guild")))
	body.add_child(leave)


func _chat_line(e: Dictionary) -> Label:
	var l := UiTheme.label("%s: %s" % [e.get("username", "?"), e.get("text", "")], 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---------------------------------------------------------------- market

func _browse(item := "") -> void:
	var on := _online()
	on.call_rpc("wb_market_browse", {"item": item} if not item.is_empty() else {}, func(r: Dictionary) -> void:
		_listings = r.data.get("listings", []) if r.ok else []
		if not r.ok:
			_say(r.message)
		refresh())


func _market_tab(on: OnlineService) -> void:
	var reg := world.registry
	body.add_child(UiTheme.label("Sell from storage", 20, UiTheme.ACCENT))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 52)
	pick.add_theme_font_size_override("font_size", 18)
	var ids := []
	var stock := world.storage.items()
	for it in stock:
		if WbServerData.is_tradeable(reg, String(it)):
			ids.append(String(it))
	ids.sort()
	for it in ids:
		pick.add_item("%s (%d)" % [reg.get_item_name(it), int(stock[it])])
	body.add_child(pick)
	if ids.is_empty():
		body.add_child(_dim("Nothing tradeable in storage."))
	var row := HFlowContainer.new()
	row.add_child(UiTheme.label("Qty", 16))
	var qty := _spin(1, 9999, 1)
	row.add_child(qty)
	row.add_child(UiTheme.label("Total price", 16))
	var price := _spin(1, 10_000_000, 100)
	row.add_child(price)
	body.add_child(row)
	if not _trade_with.is_empty():
		var tw := HBoxContainer.new()
		var l := UiTheme.label("Private trade: only %s can buy this" % _trade_with.name, 16, UiTheme.ACCENT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tw.add_child(l)
		var x := UiTheme.button("Public", 16)
		x.pressed.connect(func() -> void:
			_trade_with = {}
			refresh())
		tw.add_child(x)
		body.add_child(tw)
	var fee := int(round(float(WbServerData.market_fee()) * 100.0))
	var list := UiTheme.button("List for sale (%d%% fee on sale)" % fee, 18)
	list.disabled = ids.is_empty()
	list.pressed.connect(func() -> void:
		var it: String = ids[pick.selected]
		on.market_list(it, int(qty.value), int(price.value), String(_trade_with.get("id", "")), func(r: Dictionary) -> void:
			_say("Listed %d %s" % [int(qty.value), reg.get_item_name(it)] if r.ok else r.message, r.ok)
			if r.ok:
				_browse()))
	body.add_child(list)
	body.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	var hl := UiTheme.label("For sale", 20, UiTheme.ACCENT)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var rb := UiTheme.button("Refresh", 16)
	rb.pressed.connect(func() -> void: _browse())
	head.add_child(rb)
	body.add_child(head)
	if _listings.is_empty():
		body.add_child(_dim("No listings right now."))
	for l in _listings:
		var mine := String(l.get("seller", "")) == on.client.user_id
		var r2 := HBoxContainer.new()
		var each := float(l.price) / maxf(float(l.qty), 1.0)
		var t := UiTheme.label("%d %s  -  %d gold (%s each)  by %s%s" % [int(l.qty), reg.get_item_name(String(l.item)), int(l.price),
			("%.1f" % each) if each >= 1.0 else ("%.2f" % each),
			"you" if mine else String(l.get("seller_name", "?")), "  (private)" if not String(l.get("buyer", "")).is_empty() else ""], 16)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(t)
		var lid := String(l.id)
		if mine:
			var c := UiTheme.button("Cancel", 16)
			c.pressed.connect(func() -> void:
				on.call_rpc("wb_market_cancel", {"listing_id": lid}, func(r: Dictionary) -> void:
					if r.ok:
						on.claim_deliveries()
					_say("Listing cancelled; items return as a delivery" if r.ok else r.message, r.ok)
					_browse()))
			r2.add_child(c)
		else:
			var b := UiTheme.button("Buy", 16)
			b.disabled = world.wallet.get_balance("gold") < int(l.price)
			b.pressed.connect(func() -> void:
				on.market_buy(lid, func(r: Dictionary) -> void:
					_say("Bought! Items arrive in storage." if r.ok else r.message, r.ok)
					_browse()))
			r2.add_child(b)
		body.add_child(r2)
	body.add_child(_dim("Sales are paid as deliveries. Gold you spend or receive here is settled with the server on your next sync."))


# ---------------------------------------------------------------- world

func _world_tab(on: OnlineService) -> void:
	body.add_child(UiTheme.label("World events", 20, UiTheme.ACCENT))
	if on.events.is_empty():
		body.add_child(_dim("No event is running. Weekend Bounty runs every weekend; Market Day runs daily."))
	for e in on.events:
		var left := int(e.get("ends_at", 0)) - int(Time.get_unix_time_from_system())
		body.add_child(UiTheme.label("%s  -  %s" % [e.get("name", "?"), e.get("description", "")], 17, UiTheme.GOOD))
		if left > 0:
			body.add_child(_dim("Ends in %s" % OfflineReport.format_duration(left)))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("World boss", 20, UiTheme.ACCENT))
	if _boss.is_empty():
		body.add_child(_dim("Loading..."))
	else:
		body.add_child(UiTheme.label("%s  %d / %d HP  (%d fighters)" % [_boss.get("name", "?"), int(_boss.get("hp", 0)), int(_boss.get("max_hp", 1)), int(_boss.get("fighters", 0))], 18))
		var bar := UiTheme.bar(UiTheme.BAD, 14)
		bar.value = float(_boss.get("hp", 0)) / maxf(float(_boss.get("max_hp", 1)), 1.0)
		body.add_child(bar)
		var cd := int(_boss.get("cooldown_remaining", 0))
		var atk := UiTheme.button("Attack with your best heroes" if cd <= 0 else "Heroes recovering (%s)" % OfflineReport.format_duration(cd), 18)
		atk.disabled = cd > 0
		atk.pressed.connect(func() -> void:
			on.call_rpc("wb_boss_attack", {}, func(r: Dictionary) -> void:
				if r.ok:
					_say("Hit for %d damage%s" % [int(r.data.get("damage", 0)), "  -  the boss falls! Rewards arrive as deliveries." if r.data.get("defeated", false) else ""], true)
					if r.data.get("defeated", false):
						on.claim_deliveries()
				else:
					_say(r.message)
				_open_tab("world")))
		body.add_child(atk)
		var top := []
		for t in _boss.get("top", []):
			top.append("%s %d" % [t.get("name", "?"), int(t.get("damage", 0))])
		if not top.is_empty():
			body.add_child(_dim("Top damage: " + ", ".join(top)))
		body.add_child(_dim("Everyone who lands a hit shares the reward when it falls. Damage comes from your synced save's strongest three heroes."))
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Players in %s" % world.registry.region_name(on.region_match_region) if not on.region_match_region.is_empty() else "Players nearby", 20, UiTheme.ACCENT))
	if on.region_players.is_empty():
		body.add_child(_dim("Nobody else is in this region right now. Other players' heroes appear on your map as blue markers."))
	for uid in on.region_players:
		var p: Dictionary = on.region_players[uid]
		var hs: Array = p.get("heroes", [])
		body.add_child(UiTheme.label("%s  -  %d heroes" % [p.get("name", "?"), hs.size()], 17))
