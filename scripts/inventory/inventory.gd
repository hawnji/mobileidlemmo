class_name Inventory
extends RefCounted
## Item container used for character bags and shared storage.
##
## Capacity is expressed two ways, either of which may be unlimited (-1):
##   max_units    total item count (character bags, e.g. 28)
##   max_distinct number of different item ids (storage "slots")
## All mutations are atomic: add() returns exactly how many units were
## accepted, remove() is all-or-nothing, so items can never be duplicated or
## silently lost by this class.

signal changed

const UNLIMITED := -1

var max_units := UNLIMITED
var max_distinct := UNLIMITED
var _items := {}  # item_id -> int
var _total := 0


func _init(p_max_units := UNLIMITED, p_max_distinct := UNLIMITED) -> void:
	max_units = p_max_units
	max_distinct = p_max_distinct


func get_quantity(item_id: String) -> int:
	return int(_items.get(item_id, 0))


func total_units() -> int:
	return _total


func distinct_count() -> int:
	return _items.size()


func is_empty() -> bool:
	return _total == 0


func free_units() -> int:
	if max_units == UNLIMITED:
		return 1 << 40
	return maxi(max_units - _total, 0)


## How many of `qty` would fit right now.
func can_add(item_id: String, qty: int) -> int:
	if qty <= 0 or item_id.is_empty():
		return 0
	if max_distinct != UNLIMITED and not _items.has(item_id) and _items.size() >= max_distinct:
		return 0
	return mini(qty, free_units())


func add(item_id: String, qty: int) -> int:
	var accepted := can_add(item_id, qty)
	if accepted <= 0:
		return 0
	_items[item_id] = get_quantity(item_id) + accepted
	_total += accepted
	changed.emit()
	return accepted


func remove(item_id: String, qty: int) -> bool:
	if qty <= 0 or get_quantity(item_id) < qty:
		return false
	var left := get_quantity(item_id) - qty
	if left == 0:
		_items.erase(item_id)
	else:
		_items[item_id] = left
	_total -= qty
	changed.emit()
	return true


func is_full() -> bool:
	return max_units != UNLIMITED and _total >= max_units


func fill_ratio() -> float:
	if max_units == UNLIMITED or max_units <= 0:
		return 0.0
	return float(_total) / float(max_units)


## Moves everything that fits into `target`. Returns {item_id: moved_qty}.
## Anything that does not fit stays here — nothing is created or destroyed.
func transfer_all_to(target: Inventory) -> Dictionary:
	var moved := {}
	for item_id in _items.keys():
		var qty := get_quantity(item_id)
		var accepted := target.add(item_id, qty)
		if accepted > 0:
			remove(item_id, accepted)
			moved[item_id] = accepted
	return moved


func items() -> Dictionary:
	return _items.duplicate()


func clear() -> void:
	_items.clear()
	_total = 0
	changed.emit()


func to_dict() -> Dictionary:
	return {"max_units": max_units, "max_distinct": max_distinct, "items": _items.duplicate()}


func load_dict(d: Dictionary) -> void:
	max_units = int(d.get("max_units", max_units))
	max_distinct = int(d.get("max_distinct", max_distinct))
	_items.clear()
	_total = 0
	var src: Dictionary = d.get("items", {})
	for k in src:
		var q := int(src[k])
		if q > 0:
			_items[String(k)] = q
			_total += q
	changed.emit()
