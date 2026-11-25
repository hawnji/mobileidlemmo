class_name ActivityHandler
extends RefCounted
## What a character does for one activity type. Handlers are stateless: all
## state lives on the Adventurer, its Assignment and the world, so a handler
## can be shared by every character and the loop survives save/load.

const S := CharacterStates.State
const TP := Adventurer.TravelPurpose
const EPS := 0.000001


## Extra validation when the assignment is created. "" = ok.
func validate(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment, _act: Dictionary) -> String:
	return ""


## CHECKING_CONDITIONS: choose the next state.
func decide(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment, _act: Dictionary) -> void:
	pass


## Arrived at a TO_NODE / TO_TARGET destination.
func on_arrive(e: ActivityEngine, ch: Adventurer) -> void:
	e.set_state(ch, S.CHECKING_CONDITIONS)


## PERFORMING_ACTIVITY or COMBAT. Returns unused time.
func perform(e: ActivityEngine, ch: Adventurer, t: float) -> float:
	e.set_state(ch, S.CHECKING_CONDITIONS)
	return t


## The item whose deposits count towards UNTIL_QUANTITY.
func primary_item(_e: ActivityEngine, _asg: Assignment) -> String:
	return ""


## Whether deposits (rather than kills or crafts) advance the target.
func counts_deposits() -> bool:
	return true


## Items to keep in the bag when depositing (e.g. combat food).
func keep_on_deposit(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment) -> Dictionary:
	return {}


## SINGLE_TRIP: is the trip over once the bag has been deposited?
func single_trip_done(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment) -> bool:
	return true


func after_deposit(e: ActivityEngine, ch: Adventurer, asg: Assignment) -> void:
	e.set_state(ch, S.CHECKING_CONDITIONS, "Resuming %s" % e.registry.activities[asg.activity_id].get("name", ""))


func wants_restock(_e: ActivityEngine, _ch: Adventurer, _asg: Assignment) -> bool:
	return false


## RESTOCKING finished its timer: take supplies from storage.
func restock(e: ActivityEngine, ch: Adventurer, _asg: Assignment) -> void:
	e.set_state(ch, S.CHECKING_CONDITIONS)
