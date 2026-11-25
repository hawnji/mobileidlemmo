extends WbTestCase


func test_data_loads_and_validates_cleanly() -> void:
	var errors := registry().validate()
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_core_content_present() -> void:
	var r := registry()
	assert_eq(r.skill_order.size(), 24)
	assert_eq(r.character_order.size(), 23)
	assert_eq(r.characters_by_acquisition("starter").size(), 3)
	for a in ["mine_copper", "chop_oak", "fish_minnow"]:
		assert_has(r.activities, a)
	assert_has(r.regions, "greenvale_start")


func test_config_lookup() -> void:
	var r := registry()
	assert_eq(int(r.get_config("offline.base_cap_hours")), 8)
	assert_eq(r.get_config("does.not.exist", "fallback"), "fallback")


func test_starter_roles_are_covered() -> void:
	var roles := []
	for cid in registry().character_order:
		roles.append(registry().characters[cid].role)
	assert_has(roles, "mining_specialist")
	assert_has(roles, "woodcutting_specialist")
	assert_has(roles, "generalist")


func test_validation_catches_broken_references() -> void:
	var r := DataRegistry.new()
	r.load_from(DataRegistry.DEFAULT_ROOT)
	r.activities["broken"] = {"id": "broken", "skill": "nope", "node_type": "missing"}
	var errors := r.validate()
	assert_gte(errors.size(), 2)
