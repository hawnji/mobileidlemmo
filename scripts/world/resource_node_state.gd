class_name ResourceNodeState
extends RefCounted
## Runtime state of one gatherable node (rock, tree, fishing spot).
## Each node has a number of charges; every successful gather consumes one.
## At zero charges the node is depleted until its respawn timer elapses.
## A node can be reserved by one character at a time so workers spread out
## instead of queueing on the same rock.

var id := ""
var type_id := ""
var tile := Vector2i.ZERO
var max_charges := 1
var charges := 1
var respawn_seconds := 10.0
var respawn_remaining := 0.0
var reserved_by := ""


static func create(p_id: String, p_type: Dictionary, p_tile: Vector2i) -> ResourceNodeState:
	var n := ResourceNodeState.new()
	n.id = p_id
	n.type_id = String(p_type.get("id", ""))
	n.tile = p_tile
	n.max_charges = maxi(int(p_type.get("charges", 1)), 1)
	n.charges = n.max_charges
	n.respawn_seconds = maxf(float(p_type.get("respawn_seconds", 10.0)), 0.1)
	return n


func is_depleted() -> bool:
	return charges <= 0


func is_available_for(character_id: String) -> bool:
	return not is_depleted() and (reserved_by.is_empty() or reserved_by == character_id)


func reserve(character_id: String) -> bool:
	if not is_available_for(character_id):
		return false
	reserved_by = character_id
	return true


func release(character_id: String) -> void:
	if reserved_by == character_id:
		reserved_by = ""


## Consumes one charge. Returns false (and changes nothing) if depleted.
func consume() -> bool:
	if is_depleted():
		return false
	charges -= 1
	if charges == 0:
		respawn_remaining = respawn_seconds
	return true


## Advances the respawn timer. Returns true when the node respawned.
func tick(dt: float) -> bool:
	if not is_depleted():
		return false
	respawn_remaining -= dt
	if respawn_remaining <= 0.0:
		charges = max_charges
		respawn_remaining = 0.0
		return true
	return false


func to_dict() -> Dictionary:
	return {"id": id, "charges": charges, "respawn_remaining": respawn_remaining, "reserved_by": reserved_by}


func load_dict(d: Dictionary) -> void:
	charges = clampi(int(d.get("charges", max_charges)), 0, max_charges)
	respawn_remaining = maxf(float(d.get("respawn_remaining", 0.0)), 0.0)
	reserved_by = String(d.get("reserved_by", ""))
	if charges == 0 and respawn_remaining <= 0.0:
		respawn_remaining = respawn_seconds
