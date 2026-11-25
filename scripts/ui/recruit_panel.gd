class_name RecruitPanel
extends ModalPanel
## Recruitment banners: published base and effective rates, pity progress,
## 1x / 10x pulls and the results.
##
## Offline the pull runs in SimulationWorld. Online, the server rolls and
## charges it (OnlineService.recruit) and keeps the pity counters.

var world: SimulationWorld
var _banner := "standard"
var _results: Array = []
var _msg: Label
var _busy := false
static var _effective_cache := {}


func setup(p_world: SimulationWorld) -> void:
	world = p_world
	set_title("Recruit")
	refresh()


func refresh() -> void:
	clear_body()
	var reg := world.registry
	var tabs := HBoxContainer.new()
	for bid in reg.banner_order:
		var b := UiTheme.button(String(reg.banners[bid].name), 18)
		b.toggle_mode = true
		b.button_pressed = bid == _banner
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_banner = bid
			_results.clear()
			refresh())
		tabs.add_child(b)
	body.add_child(tabs)
	var banner: Dictionary = reg.banners[_banner]
	var desc := UiTheme.label(String(banner.get("description", "")), 17, UiTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(desc)
	var w := world.wallet
	body.add_child(UiTheme.label("Tokens %d  |  Festival tokens %d  |  Gems %d" % [w.get_balance("recruitment_tokens"), w.get_balance("event_tokens"), w.get_balance("gems")], 19))
	var pulls := HBoxContainer.new()
	for n in [1, 10]:
		var cost := world.recruit_cost(_banner, n)
		var label := "Recruit x%d" % n
		if not cost.is_empty():
			var cur := String(cost.keys()[0])
			label += "\n%d %s" % [int(cost[cur]), reg.currencies.get(cur, {}).get("name", cur)]
		var b := UiTheme.button(label, 20)
		b.custom_minimum_size = Vector2(0, 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = cost.is_empty() or _busy
		b.pressed.connect(func() -> void:
			var online: OnlineService = Game.online
			if online and online.is_online():
				# The server rolls and charges the pull.
				_busy = true
				refresh()
				online.recruit(_banner, n, func(res: Dictionary) -> void:
					_busy = false
					_results = res.results
					refresh()
					_msg.text = res.error)
				return
			var res := world.recruit(_banner, n)
			_results = res.results
			refresh()
			_msg.text = res.error)
		pulls.add_child(b)
	body.add_child(pulls)
	_msg = UiTheme.label("", 18, UiTheme.BAD)
	body.add_child(_msg)
	if not _results.is_empty():
		body.add_child(UiTheme.label("Results", 22, UiTheme.ACCENT))
		var grid := GridContainer.new()
		grid.columns = 2
		for r in _results:
			var ch: Dictionary = reg.characters.get(r.character_id, {})
			var txt := "%s (%s)  %s" % [ch.get("name", "?"), String(r.rarity).capitalize(), "NEW!" if r.get("new", false) else "+%d fragments" % int(r.get("fragments", 0))]
			var l := UiTheme.label(txt, 18, UiTheme.rarity_color(String(r.rarity)))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(l)
		body.add_child(grid)
	body.add_child(HSeparator.new())
	body.add_child(UiTheme.label("Rates", 22, UiTheme.ACCENT))
	if not _effective_cache.has(_banner):
		_effective_cache[_banner] = RecruitmentState.effective_rates(reg, banner, 50000)
	var eff: Dictionary = _effective_cache[_banner]
	var counters := world.recruitment.pity_counters(_banner)
	var pity_by := {}
	for p in banner.get("pity", []):
		pity_by[String(p.rarity)] = int(p.guaranteed_on_pull)
	for rarity in banner.rates:
		var line := "%s  base %.1f%%  effective %.2f%%" % [String(rarity).capitalize(), float(banner.rates[rarity]) * 100.0, float(eff.get(rarity, 0.0)) * 100.0]
		if pity_by.has(rarity):
			line += "  |  guaranteed within %d (%d / %d)" % [pity_by[rarity], int(counters.get(rarity, 0)), pity_by[rarity]]
		body.add_child(UiTheme.label(line, 16, UiTheme.rarity_color(String(rarity))))
	var feat: Variant = banner.get("featured")
	if feat is Dictionary:
		body.add_child(UiTheme.label("Featured: %s (%d%% of %s results)" % [reg.characters[feat.character_id].name, int(float(feat.share) * 100),
			reg.characters[feat.character_id].rarity], 16, UiTheme.ACCENT))
	body.add_child(UiTheme.label("Duplicates become fragments for star upgrades. Pity is kept per banner and never expires.", 15, UiTheme.TEXT_DIM))
	var on: OnlineService = Game.online
	body.add_child(UiTheme.label("Online: the server rolls each pull and keeps your pity." if on and on.is_online()
		else "Offline: pulls are rolled on this device. When you play online, the server rolls them.", 15, UiTheme.TEXT_DIM))
