class_name DayNight
extends CanvasModulate
## Simple day/night tint driven by simulation time (purely cosmetic).

const DAY_LENGTH_SECONDS := 1440.0  # one in-game day = 24 real minutes

var world: SimulationWorld
var _gradient := Gradient.new()


func _ready() -> void:
	_gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.3, 0.7, 0.8, 0.9, 1.0])
	_gradient.colors = PackedColorArray([
		Color(0.45, 0.5, 0.75), Color(0.55, 0.55, 0.75), Color(1.0, 0.92, 0.85),
		Color(1, 1, 1), Color(1.0, 0.8, 0.65), Color(0.55, 0.52, 0.75), Color(0.45, 0.5, 0.75)])


func _process(_delta: float) -> void:
	if world:
		color = _gradient.sample(world.day_phase())
