extends SceneTree
## Prints base and effective (pity-inclusive) rates for every banner.
##   godot --headless --path . -s res://tools/gacha_report.gd
func _initialize() -> void:
	var reg := DataRegistry.get_default()
	for bid in reg.banner_order:
		var b: Dictionary = reg.banners[bid]
		var eff := RecruitmentState.effective_rates(reg, b, 1000000)
		print("%s" % b.name)
		print("| Rarity | Base | Effective (1M simulated pulls) |")
		print("|---|---|---|")
		for r in b.rates:
			print("| %s | %.2f%% | %.2f%% |" % [String(r).capitalize(), float(b.rates[r]) * 100.0, float(eff[r]) * 100.0])
	quit()
