class_name CharacterStates
extends RefCounted
## The character activity state machine definition. ActivityEngine is the
## only code that changes Adventurer.state, and it always goes through
## can_transition() so illegal jumps are caught (and tested).

enum State {
	IDLE,
	ASSIGNED,
	PATHFINDING,
	TRAVELING,
	PERFORMING_ACTIVITY,
	COMBAT,
	CHECKING_CONDITIONS,
	RETURNING,
	DEPOSITING,
	RESTOCKING,
	RESTING,
	INJURED,
	WAITING,
	COMPLETED,
}

const S := State

## Allowed transitions. Any state may always go to IDLE (cancel / interrupt).
const TRANSITIONS := {
	S.IDLE: [S.ASSIGNED],
	S.ASSIGNED: [S.CHECKING_CONDITIONS],
	S.CHECKING_CONDITIONS: [S.PATHFINDING, S.PERFORMING_ACTIVITY, S.DEPOSITING, S.WAITING, S.COMPLETED, S.COMBAT, S.RESTOCKING, S.RESTING],
	S.PATHFINDING: [S.TRAVELING, S.RETURNING, S.PERFORMING_ACTIVITY, S.DEPOSITING, S.WAITING, S.CHECKING_CONDITIONS, S.COMBAT],
	S.TRAVELING: [S.PERFORMING_ACTIVITY, S.PATHFINDING, S.CHECKING_CONDITIONS, S.COMBAT],
	S.PERFORMING_ACTIVITY: [S.CHECKING_CONDITIONS],
	S.RETURNING: [S.DEPOSITING, S.PATHFINDING, S.CHECKING_CONDITIONS],
	S.DEPOSITING: [S.CHECKING_CONDITIONS, S.COMPLETED, S.WAITING, S.RESTOCKING, S.RESTING],
	S.WAITING: [S.CHECKING_CONDITIONS, S.PATHFINDING],
	S.COMPLETED: [S.ASSIGNED],
	S.COMBAT: [S.CHECKING_CONDITIONS, S.INJURED],
	S.RESTOCKING: [S.CHECKING_CONDITIONS, S.WAITING, S.COMPLETED],
	S.RESTING: [S.CHECKING_CONDITIONS, S.RESTOCKING],
	S.INJURED: [S.RESTING],
}


static func can_transition(from: int, to: int) -> bool:
	if to == S.IDLE:
		return true
	return to in TRANSITIONS.get(from, [])


static func name_of(state: int) -> String:
	return State.keys()[state] if state >= 0 and state < State.size() else "UNKNOWN"


static func from_name(state_name: String) -> int:
	var idx := State.keys().find(state_name)
	return idx if idx >= 0 else S.IDLE


## Player-facing label for UI.
static func label_of(state: int) -> String:
	match state:
		S.IDLE: return "Idle"
		S.ASSIGNED: return "Assigned"
		S.PATHFINDING: return "Planning route"
		S.TRAVELING: return "Travelling"
		S.PERFORMING_ACTIVITY: return "Working"
		S.COMBAT: return "In combat"
		S.CHECKING_CONDITIONS: return "Thinking"
		S.RETURNING: return "Returning to storage"
		S.DEPOSITING: return "Depositing"
		S.RESTOCKING: return "Restocking"
		S.RESTING: return "Resting"
		S.INJURED: return "Recovering from injury"
		S.WAITING: return "Waiting"
		S.COMPLETED: return "Assignment complete"
	return "?"
