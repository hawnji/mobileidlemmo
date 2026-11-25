extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/test_runner.gd [-- --filter=name]
## Discovers tests/{unit,integration,simulation}/test_*.gd, runs every test_*
## method and exits with code 1 if anything failed.

const SUITES := ["res://tests/unit", "res://tests/integration", "res://tests/simulation"]


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var files: Array[String] = []
	for dir in SUITES:
		_collect(dir, files)
	# Client tests against a live Nakama server (server/run_tests.sh sets this).
	if not OS.get_environment("WB_NAKAMA_URL").is_empty():
		_collect("res://tests/online", files)
	files.sort()
	var total := 0
	var failed := 0
	var assertions := 0
	var start := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			print("  [LOAD ERROR] %s" % path)
			failed += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var n := String(m.name)
			if n.begins_with("test_") and not methods.has(n):
				methods.append(n)
		print("%s (%d tests)" % [path.trim_prefix("res://tests/"), methods.size()])
		for method in methods:
			if not filter.is_empty() and not (method.contains(filter) or path.contains(filter)):
				continue
			total += 1
			var t0 := Time.get_ticks_usec()
			var inst: WbTestCase = script.new()
			inst.before_each()
			inst.call(method)
			inst.after_each()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			assertions += inst._assertions
			if inst._failures.is_empty() and inst._assertions > 0:
				print("  PASS  %s (%.0f ms)" % [method, ms])
			else:
				failed += 1
				if inst._assertions == 0:
					inst._failures.append("no assertions ran (did the test crash?)")
				print("  FAIL  %s" % method)
				for f in inst._failures:
					print("        - %s" % f)
	print("")
	print("%d tests, %d failed, %d assertions, %.1f s" % [total, failed, assertions, (Time.get_ticks_msec() - start) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		_collect(dir_path.path_join(d), out)
