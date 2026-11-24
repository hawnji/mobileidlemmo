extends WbTestCase

const S := CharacterStates.State


func test_gathering_loop_transitions_are_legal() -> void:
	var loop := [S.IDLE, S.ASSIGNED, S.CHECKING_CONDITIONS, S.PATHFINDING, S.TRAVELING,
		S.PERFORMING_ACTIVITY, S.CHECKING_CONDITIONS, S.PATHFINDING, S.RETURNING,
		S.DEPOSITING, S.CHECKING_CONDITIONS, S.WAITING, S.CHECKING_CONDITIONS, S.COMPLETED]
	for i in range(1, loop.size()):
		assert_true(CharacterStates.can_transition(loop[i - 1], loop[i]),
			"%s -> %s" % [CharacterStates.name_of(loop[i - 1]), CharacterStates.name_of(loop[i])])


func test_illegal_transitions_rejected() -> void:
	assert_false(CharacterStates.can_transition(S.IDLE, S.PERFORMING_ACTIVITY))
	assert_false(CharacterStates.can_transition(S.IDLE, S.DEPOSITING))
	assert_false(CharacterStates.can_transition(S.TRAVELING, S.DEPOSITING))
	assert_false(CharacterStates.can_transition(S.PERFORMING_ACTIVITY, S.DEPOSITING))
	assert_false(CharacterStates.can_transition(S.COMPLETED, S.TRAVELING))


func test_every_state_can_be_cancelled_to_idle() -> void:
	for s in S.values():
		assert_true(CharacterStates.can_transition(s, S.IDLE))


func test_all_fourteen_states_exist_with_labels() -> void:
	assert_eq(S.size(), 14)
	for s in S.values():
		assert_ne(CharacterStates.label_of(s), "?")
		assert_eq(CharacterStates.from_name(CharacterStates.name_of(s)), s)
