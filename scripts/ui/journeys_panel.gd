class_name JourneysPanel
extends ModalPanel
## Expeditions, dungeons and live world events in one screen. A shared team
## picker at the top chooses who goes; each expedition or dungeon shows
## whether that team qualifies and its odds before starting.

var world: SimulationWorld
var _tab := "expeditions"
var _team: Array = []
var _supplies := true
var _msg: Label
var _accum := 0.0
var _tiers := {}  # dungeon_id -> chosen mythic tier (Phase 5)


func setup(p_world: SimulationWorld, tab := "expeditions") -> void:
	world = p_world
	_tab = tab
	refresh()


func _process(delta: float) -> void:
	if world == null:
		return
	_accum += delta
	var live_fight := _tab == "dungeons" and not world.dungeon_runs.is_empty()
	var every := 1.0 if live_fight else 5.0
	if _accum >= every:
		_accum = 0.0
		if live_fight or (_tab == "expeditions" and not world.expeditions.active.is_empty()) or _tab == "events":
			refresh(true)


func refresh(keep_msg := false) -> void:
	var old := _msg.text if keep_msg and _msg else ""
	clear_body()
	set_title({"expeditions": "Expeditions", "dungeons": "Dungeons", "events": "World Events"}[_tab])
	var tabs := HBoxContainer.new()
	for spec in [["Expeditions", "expeditions"], ["Dungeons", "dungeons"], ["Events", "events"]]:
		var b := UiTheme.button(spec[0], 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = _tab == spec[1]
		var key: String = spec[1]
		b.pressed.connect(func() -> void:
			_tab = key
			refresh())
		tabs.add_child(b)
	body.add_child(tabs)
	_msg = UiTheme.label(old, 18, UiTheme.BAD)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_msg)
	match _tab:
		"expeditions":
			_team_picker()
			_expeditions()
		"dungeons":
			_team_picker()
			_dungeons()
		"events":
			_events()
	wrap_labels(body)


func _team_objects() -> Array:
	var out := []
	for cid in _team:
		if world.characters.has(cid):
			out.append(world.characters[cid])
	return out


func _team_picker() -> void:
	body.add_child(UiTheme.label("Team (%d selected)" % _team.size(), 18, UiTheme.ACCENT))
	var flow := HFlowContainer.new()
	for cid in world.character_order:
		var ch: Adventurer = world.characters[cid]
		var free := ch.state != CharacterStates.State.AWAY and ch.state != CharacterStates.State.INJURED
		if not free:
			_team.erase(cid)
		var b := UiTheme.button("%s  P%d" % [ch.display_name.split(" ")[0], int(ExpeditionState.member_power(ch))], 15)
		b.toggle_mode = true
		b.button_pressed = _team.has(cid)
		b.disabled = not free
		b.tooltip_text = CharacterStates.label_of(ch.state)
		b.pressed.connect(func() -> void:
			if _team.has(cid):
				_team.erase(cid)
			else:
				_team.append(cid)
			refresh())
		flow.add_child(b)
	body.add_child(flow)
	body.add_child(UiTheme.label("Team power %d" % int(ExpeditionState.team_power(_team_objects())), 15, UiTheme.TEXT_DIM))
	body.add_child(HSeparator.new())


# ------------------------------------------------------------ expeditions ----

func _expeditions() -> void:
	var reg := world.registry
	var ex := world.expeditions
	body.add_child(UiTheme.label("Slots %d / %d%s" % [ex.active.size(), ex.slots(world),
		"  (build the Expedition Center)" if ex.slots(world) == 0 else ""], 17))
	for run in ex.active:
		var x: Dictionary = reg.expeditions[run.expedition_id]
		var left := maxf(float(run.ends_at) - world.sim_time, 0.0)
		var names := []
		for cid in run.team:
			names.append(world.characters[cid].display_name.split(" ")[0] if world.characters.has(cid) else cid)
		body.add_child(UiTheme.label("%s: %s left  (%s)" % [x.name, OfflineReport.format_duration(left), ", ".join(names)], 17, UiTheme.GOOD))
		var bar := UiTheme.bar(UiTheme.GOOD, 8)
		bar.value = 1.0 - left / maxf(float(run.ends_at) - float(run.started), 1.0)
		body.add_child(bar)
	var sup := CheckButton.new()
	sup.text = "Take supplies (food from storage, +success)"
	sup.button_pressed = _supplies
	sup.toggled.connect(func(on: bool) -> void: _supplies = on)
	body.add_child(sup)
	var team := _team_objects()
	for xid in reg.expeditions:
		var x: Dictionary = reg.expeditions[xid]
		var open := world.is_region_unlocked(String(x.region))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.add_child(UiTheme.label(String(x.name), 21, UiTheme.TEXT if open else UiTheme.TEXT_DIM))
		var d := UiTheme.label(String(x.get("description", "")), 14, UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
		box.add_child(UiTheme.label("%s  |  team of %d  |  %s  |  recommended power %d  |  food %d" % [reg.region_name(String(x.region)),
			int(x.team_size), OfflineReport.format_duration(float(x.duration_seconds)), int(x.get("recommended_power", 0)),
			ExpeditionState.supplies_needed(x)], 14))
		var reqs := []
		for req in x.get("requirements", []):
			reqs.append(Objectives.describe(reg, req))
		if not reqs.is_empty():
			var rl := UiTheme.label("Requires: " + ", ".join(reqs), 14)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(rl)
		if team.size() == int(x.team_size):
			var missing := ExpeditionState.missing_requirements(reg, x, team)
			if missing.is_empty():
				box.add_child(UiTheme.label("Success chance with this team: %d%%" % roundi(ex.success_chance(world, x, team, _supplies) * 100.0), 15, UiTheme.GOOD))
			else:
				box.add_child(UiTheme.label("Team lacks: " + ", ".join(missing), 15, UiTheme.BAD))
		var b := UiTheme.button("Send team", 17)
		b.disabled = not open or team.size() != int(x.team_size)
		b.pressed.connect(func() -> void:
			var e := world.start_expedition(xid, _team.duplicate(), _supplies)
			if e.is_empty():
				_team.clear()
			refresh()
			_msg.text = e)
		box.add_child(b)
		box.add_child(HSeparator.new())
		body.add_child(box)
	if not ex.history.is_empty():
		body.add_child(UiTheme.label("Recent results", 21, UiTheme.ACCENT))
		for h in ex.history.slice(0, 5):
			var txt := "%s: %s (%d%% chance)" % [h.name, "success" if h.success else "failed", roundi(float(h.chance) * 100.0)]
			if not h.story.is_empty():
				txt += "\n  " + "\n  ".join(h.story)
			var hl := UiTheme.label(txt, 14, UiTheme.GOOD if h.success else UiTheme.BAD)
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(hl)


# ------------------------------------------------------------ dungeons ----

func _dungeons() -> void:
	var reg := world.registry
	for run in world.dungeon_runs:
		_run_card(run)
	for did in reg.dungeons:
		var d: Dictionary = reg.dungeons[did]
		var open := world.is_region_unlocked(String(d.region))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.add_child(UiTheme.label(String(d.name), 21, UiTheme.TEXT if open else UiTheme.TEXT_DIM))
		var desc := UiTheme.label(String(d.get("description", "")), 14, UiTheme.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
		var boss := String(reg.enemies.get(d.get("boss", ""), {}).get("name", "?"))
		box.add_child(UiTheme.label("%s  |  party %d-%d  |  %d floors + %s  |  recommended power %d  |  limit %s" % [reg.region_name(String(d.region)),
			int(d.party_min), int(d.party_max), d.get("floors", []).size(), boss, int(d.get("recommended_power", 0)),
			OfflineReport.format_duration(float(d.get("time_limit_seconds", 900)))], 14))
		var rec: Dictionary = world.dungeon_records.get(did, {})
		if not rec.is_empty():
			box.add_child(UiTheme.label("Cleared %d times, best %s" % [int(rec.clears), OfflineReport.format_duration(float(rec.best_time))], 14, UiTheme.GOOD))
		else:
			box.add_child(UiTheme.label("First clear: %s" % QuestsPanel.describe_rewards(reg, d.get("first_clear", {})), 14, UiTheme.ACCENT))
		box.add_child(UiTheme.label("Food: up to %d per member is taken from storage; leftovers come back." % int(d.get("food_per_member", 10)), 13, UiTheme.TEXT_DIM))
		var max_tier := world.endgame.max_unlocked_tier(world, did)
		var tier := clampi(int(_tiers.get(did, 0)), 0, max_tier)
		if max_tier > 0:
			var trow := HBoxContainer.new()
			var minus := UiTheme.button("-", 18)
			minus.custom_minimum_size = Vector2(56, 48)
			minus.disabled = tier <= 0
			minus.pressed.connect(func() -> void:
				_tiers[did] = tier - 1
				refresh())
			trow.add_child(minus)
			var best := int(world.endgame.mythic_records.get(did, 0))
			var tl := UiTheme.label("Normal" if tier == 0 else "Mythic tier %d" % tier, 18, UiTheme.rarity_color("mythic") if tier > 0 else UiTheme.TEXT)
			tl.custom_minimum_size = Vector2(170, 0)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			trow.add_child(tl)
			var plus := UiTheme.button("+", 18)
			plus.custom_minimum_size = Vector2(56, 48)
			plus.disabled = tier >= max_tier
			plus.pressed.connect(func() -> void:
				_tiers[did] = tier + 1
				refresh())
			trow.add_child(plus)
			trow.add_child(UiTheme.label("  best tier %d" % best, 14, UiTheme.TEXT_DIM))
			box.add_child(trow)
			if tier > 0:
				var cfg := reg.dungeon_mythic
				var names := []
				for a in world.endgame.affixes_for(tier):
					names.append(String(a.name))
				box.add_child(UiTheme.label("Enemies +%d%% health, +%d%% damage. Rewards x%s, %d relic dust, %d%% relic chance.%s" % [
					int(float(cfg.get("enemy_health_per_tier", 0.25)) * tier * 100), int(float(cfg.get("enemy_damage_per_tier", 0.12)) * tier * 100),
					String.num(1.0 + float(cfg.get("reward_mult_per_tier", 0.25)) * tier, 2), int(cfg.get("relic_dust_per_tier", 15)) * tier,
					int(minf(float(cfg.get("relic_chance_per_tier", 0.04)) * tier, float(cfg.get("relic_chance_max", 0.4))) * 100),
					"  Affixes: %s." % ", ".join(names) if not names.is_empty() else ""], 14, UiTheme.rarity_color("mythic")))
		var b := UiTheme.button("Enter with team" if tier == 0 else "Enter tier %d with team" % tier, 17)
		b.disabled = not open or _team.size() < int(d.party_min) or _team.size() > int(d.party_max)
		b.pressed.connect(func() -> void:
			var e := world.start_dungeon(did, _team.duplicate(), tier)
			if e.is_empty():
				_team.clear()
			refresh()
			_msg.text = e)
		box.add_child(b)
		box.add_child(HSeparator.new())
		body.add_child(box)


func _run_card(run: DungeonRun) -> void:
	body.add_child(UiTheme.label("%s%s  -  %s  (%s)" % [run.def.get("name", run.dungeon_id), "  (mythic %d)" % run.tier if run.tier > 0 else "",
		run.stage_label(), OfflineReport.format_duration(run.elapsed)], 20, UiTheme.GOOD))
	var boss := run.boss_foe()
	if not boss.is_empty() and boss.enemy.is_alive():
		body.add_child(UiTheme.label("%s%s" % [boss.enemy.display_name(), "  ENRAGED" if run.enraged else ""], 16, UiTheme.BAD))
		var bb := UiTheme.bar(UiTheme.BAD, 10)
		bb.value = boss.enemy.health / maxf(boss.enemy.max_health, 1.0)
		body.add_child(bb)
	for m in run.party:
		var ch: Adventurer = world.characters.get(m.id)
		if ch == null:
			continue
		var row := HBoxContainer.new()
		var l := UiTheme.label(ch.display_name.split(" ")[0], 15, UiTheme.TEXT if not m.down else UiTheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(140, 0)
		row.add_child(l)
		var hb := UiTheme.bar(UiTheme.GOOD, 10)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.value = float(m.hp) / maxf(ch.max_health(), 1.0)
		row.add_child(hb)
		body.add_child(row)
	var log_l := UiTheme.label("\n".join(run.log_lines.slice(maxi(run.log_lines.size() - 6, 0))), 14, UiTheme.TEXT_DIM)
	log_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(log_l)
	body.add_child(HSeparator.new())


# ------------------------------------------------------------ events ----

func _events() -> void:
	var reg := world.registry
	if world.encounters.active.is_empty():
		body.add_child(UiTheme.label("Nothing unusual right now. Treasure goblins, merchants, bountiful harvests and wandering heroes appear at random in unlocked regions.", 17, UiTheme.TEXT_DIM))
	for enc in world.encounters.active:
		var loc: Dictionary = world.locations.get(enc.location, {})
		body.add_child(UiTheme.label(String(enc.name), 21, UiTheme.rarity_color("epic")))
		body.add_child(UiTheme.label("%s, %s  |  %s left" % [loc.get("name", enc.location), reg.region_name(String(enc.region)),
			OfflineReport.format_duration(maxf(float(enc.ends_at) - world.sim_time, 0.0))], 15))
		match String(enc.kind):
			"bonus_location":
				body.add_child(UiTheme.label("Yields x%.1f here" % float(enc.yield_mult), 15, UiTheme.GOOD))
			"surge":
				body.add_child(UiTheme.label("Monsters respawn faster and drop x%.1f gold" % float(enc.gold_mult), 15, UiTheme.GOOD))
			"hero":
				body.add_child(UiTheme.label("%s waits here and joins the first hero to come close." % reg.characters.get(enc.character_id, {}).get("name", "?"), 15, UiTheme.GOOD))
			"spawn_enemy":
				body.add_child(UiTheme.label("Hunt it before it escapes.", 15, UiTheme.GOOD))
			"merchant":
				for s in enc.stock:
					var row := HBoxContainer.new()
					var price := []
					for c in s.price:
						price.append("%d %s" % [int(s.price[c]), String(c).replace("_", " ")])
					var l := UiTheme.label("%s  -  %s  (%d left)" % [reg.get_item_name(String(s.item)), ", ".join(price), int(s.qty)], 15)
					l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					row.add_child(l)
					var b := UiTheme.button("Buy", 16)
					b.disabled = int(s.qty) <= 0
					var uid := int(enc.uid)
					var item := String(s.item)
					b.pressed.connect(func() -> void:
						var e := world.buy_from_merchant(uid, item, 1)
						refresh()
						_msg.text = e)
					row.add_child(b)
					body.add_child(row)
		body.add_child(HSeparator.new())


## Long single-line labels would widen the card past the screen on phones.
static func wrap_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label and c.get_parent() is VBoxContainer:
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrap_labels(c)
