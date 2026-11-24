extends WbTestCase


func test_add_xp_levels_up_and_reports_levels_gained() -> void:
	var s := SkillSet.new(registry().skill_xp_table)
	assert_eq(s.get_level("mining"), 1)
	assert_eq(s.add_xp("mining", 82.0), 0)
	assert_eq(s.add_xp("mining", 1.0), 1)
	assert_eq(s.get_level("mining"), 2)
	assert_eq(s.add_xp("mining", 1154.0), 8, "multiple levels at once")
	assert_eq(s.get_level("mining"), 10)


func test_invalid_xp_is_ignored() -> void:
	var s := SkillSet.new(registry().skill_xp_table)
	assert_eq(s.add_xp("mining", -100.0), 0)
	assert_eq(s.add_xp("mining", 0.0), 0)
	assert_eq(s.add_xp("mining", NAN), 0)
	assert_eq(s.add_xp("mining", INF), 0)
	assert_almost(s.get_xp("mining"), 0.0)


func test_xp_is_capped() -> void:
	var s := SkillSet.new(registry().skill_xp_table)
	s.add_xp("fishing", 1.0e12)
	assert_almost(s.get_xp("fishing"), 200000000.0)
	assert_eq(s.get_level("fishing"), 99)


func test_set_level_and_serialisation() -> void:
	var s := SkillSet.new(registry().skill_xp_table)
	s.set_level("woodcutting", 30)
	assert_eq(s.get_level("woodcutting"), 30)
	var s2 := SkillSet.new(registry().skill_xp_table)
	s2.load_dict(s.to_dict())
	assert_eq(s2.get_level("woodcutting"), 30)
	assert_almost(s2.get_xp("woodcutting"), 13363.0)


func test_skills_are_independent() -> void:
	var s := SkillSet.new(registry().skill_xp_table)
	s.add_xp("mining", 5000)
	assert_eq(s.get_level("woodcutting"), 1)
	assert_gt(s.get_level("mining"), 1)
