class_name WbTestCase
extends RefCounted
## Minimal dependency-free test base class. Subclass it in tests/**/test_*.gd
## and add methods named test_*. Optional before_each()/after_each().

var _failures: Array[String] = []
var _assertions := 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func _fail(msg: String) -> void:
	_failures.append(msg)


func assert_true(cond: bool, msg := "") -> void:
	_assertions += 1
	if not cond:
		_fail("expected true. " + msg)


func assert_false(cond: bool, msg := "") -> void:
	_assertions += 1
	if cond:
		_fail("expected false. " + msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	_assertions += 1
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		_fail("expected %s (%s) got %s (%s). %s" % [expected, type_string(typeof(expected)), actual, type_string(typeof(actual)), msg])
	elif actual != expected:
		_fail("expected %s got %s. %s" % [expected, actual, msg])


func assert_ne(actual: Variant, other: Variant, msg := "") -> void:
	_assertions += 1
	if actual == other:
		_fail("expected value != %s. %s" % [other, msg])


func assert_almost(actual: float, expected: float, tolerance := 0.0001, msg := "") -> void:
	_assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("expected %f ± %f got %f. %s" % [expected, tolerance, actual, msg])


func assert_gt(actual: float, bound: float, msg := "") -> void:
	_assertions += 1
	if not (actual > bound):
		_fail("expected > %s got %s. %s" % [bound, actual, msg])


func assert_gte(actual: float, bound: float, msg := "") -> void:
	_assertions += 1
	if not (actual >= bound):
		_fail("expected >= %s got %s. %s" % [bound, actual, msg])


func assert_lte(actual: float, bound: float, msg := "") -> void:
	_assertions += 1
	if not (actual <= bound):
		_fail("expected <= %s got %s. %s" % [bound, actual, msg])


func assert_null(v: Variant, msg := "") -> void:
	_assertions += 1
	if v != null:
		_fail("expected null got %s. %s" % [v, msg])


func assert_not_null(v: Variant, msg := "") -> void:
	_assertions += 1
	if v == null:
		_fail("expected non-null. " + msg)


func assert_has(container: Variant, value: Variant, msg := "") -> void:
	_assertions += 1
	if not container.has(value):
		_fail("expected %s to contain %s. %s" % [container, value, msg])


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# --- Shared fixtures -------------------------------------------------------

func registry() -> DataRegistry:
	return DataRegistry.get_default()


func new_world(seed_value := 12345) -> SimulationWorld:
	return SimulationWorld.create_new(registry(), seed_value)


## Builds a tiny world from ASCII rows using the real terrain table.
func grid_from(rows: Array) -> WorldGrid:
	return WorldGrid.from_rows(rows, registry().terrain_by_symbol)


func make_assignment(world: SimulationWorld, character_id: String, activity_id: String) -> Assignment:
	return Assignment.create(character_id, world.registry.activities[activity_id])
