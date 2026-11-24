class_name CharacterView
extends Node2D
## Presentation for one Adventurer. Reads simulation state every frame and
## smooths it; never writes to it. Distant (off-screen) characters skip
## animation work entirely - their progress continues in the simulation.

const S := CharacterStates.State
const DIR_ROWS := {Vector2i.DOWN: 0, Vector2i.LEFT: 1, Vector2i.RIGHT: 2, Vector2i.UP: 3}
const TOOL_BY_SKILL := {"mining": "pickaxe", "woodcutting": "axe", "fishing": "fishing_rod"}
const PARTICLE_COLORS := {"mining": Color("b0a090"), "woodcutting": Color("a7773f"), "fishing": Color("9fd0ff")}

var character: Adventurer
var world: SimulationWorld
var tile_px := 32
var on_screen := true
var _sprite: AnimatedSprite2D
var _tool: Sprite2D
var _name: Label
var _bag_bar: ProgressBar
var _selected := false
var _particles: CPUParticles2D
var _work_t := 0.0
var _tools := {}


func setup(p_character: Adventurer, p_world: SimulationWorld) -> void:
	character = p_character
	world = p_world
	tile_px = int(world.registry.get_config("world.tile_size_px", 32))
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames(String(character.definition.get("sprite", "")))
	_sprite.offset = Vector2(0, -12)
	add_child(_sprite)
	_tool = Sprite2D.new()
	_tool.visible = false
	_tool.offset = Vector2(8, -8)
	_tool.scale = Vector2(0.7, 0.7)
	add_child(_tool)
	for skill in TOOL_BY_SKILL:
		_tools[skill] = UiTheme.texture("res://assets/equipment/tools/%s.png" % TOOL_BY_SKILL[skill])
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 8
	_particles.lifetime = 0.5
	_particles.explosiveness = 0.9
	_particles.direction = Vector2(0, -1)
	_particles.spread = 70.0
	_particles.initial_velocity_min = 30.0
	_particles.initial_velocity_max = 60.0
	_particles.gravity = Vector2(0, 160)
	_particles.scale_amount_min = 1.5
	_particles.scale_amount_max = 2.5
	add_child(_particles)
	_name = Label.new()
	_name.text = character.display_name.split(" ")[0]
	_name.add_theme_font_size_override("font_size", 10)
	_name.add_theme_color_override("font_color", UiTheme.rarity_color(character.rarity))
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 3)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.custom_minimum_size = Vector2(80, 0)
	_name.position = Vector2(-40, -44)
	add_child(_name)
	_bag_bar = ProgressBar.new()
	_bag_bar.show_percentage = false
	_bag_bar.max_value = 1.0
	_bag_bar.step = 0.0
	_bag_bar.custom_minimum_size = Vector2(22, 3)
	_bag_bar.size = Vector2(22, 3)
	_bag_bar.position = Vector2(-11, -30)
	_bag_bar.add_theme_stylebox_override("background", UiTheme.box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 1, 0, 0))
	_bag_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT, 1, 0, 0))
	add_child(_bag_bar)
	position = _target_position()


func _build_frames(path: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var tex: Texture2D = UiTheme.texture(path)
	for dir_name in ["down", "left", "right", "up"]:
		var row: int = ["down", "left", "right", "up"].find(dir_name)
		for kind in ["idle", "walk"]:
			var anim: String = "%s_%s" % [kind, dir_name]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 8.0)
			frames.set_animation_loop(anim, true)
			var count := 1 if kind == "idle" else 4
			for f in count:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(f * 32, row * 32, 32, 32)
				frames.add_frame(anim, at)
	return frames


func _target_position() -> Vector2:
	return character.visual_tile_position() * tile_px + Vector2(tile_px, tile_px) * 0.5


func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()


func _process(delta: float) -> void:
	var target := _target_position()
	if position.distance_to(target) > tile_px * 3.0:
		position = target  # teleport (load / reset)
	else:
		position = position.lerp(target, 1.0 - exp(-delta * 14.0))
	if not on_screen:
		return
	var dir := _dir_name(character.facing)
	var moving := character.state == S.TRAVELING or character.state == S.RETURNING
	var anim := ("walk_" if moving else "idle_") + dir
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.speed_scale = character.move_speed_tiles() / 3.5
	_bag_bar.value = character.inventory.fill_ratio()
	if character.state == S.PERFORMING_ACTIVITY and character.assignment:
		var skill := String(world.registry.activities.get(character.assignment.activity_id, {}).get("skill", ""))
		_tool.texture = _tools.get(skill)
		_tool.visible = _tool.texture != null
		_tool.flip_h = character.facing.x < 0
		_work_t += delta
		_tool.rotation = sin(_work_t * 9.0) * 0.6 * (-1.0 if _tool.flip_h else 1.0)
		_tool.position = Vector2(-4 if _tool.flip_h else 4, 0)
		_sprite.position.y = -absf(sin(_work_t * 9.0)) * 1.5
	else:
		_tool.visible = false
		_sprite.position.y = -1.0 if character.state == S.DEPOSITING else 0.0
		_work_t = 0.0


func play_gather_effect(skill: String) -> void:
	if not on_screen:
		return
	_particles.color = PARTICLE_COLORS.get(skill, Color.WHITE)
	_particles.position = Vector2(character.facing) * 14.0 + Vector2(0, -6)
	_particles.restart()


func _dir_name(f: Vector2i) -> String:
	if f.x != 0 and absi(f.x) >= absi(f.y):
		return "right" if f.x > 0 else "left"
	if f.y < 0:
		return "up"
	return "down"


func _draw() -> void:
	if _selected:
		draw_arc(Vector2(0, 2), 12.0, 0, TAU, 24, UiTheme.ACCENT, 2.0)
