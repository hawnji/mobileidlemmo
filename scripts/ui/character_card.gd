class_name CharacterCard
extends Button
## Compact roster card in the bottom character bar.

var character: Adventurer
var registry: DataRegistry
var _state: Label
var _bag: ProgressBar
var _portrait: TextureRect
var _hp: ProgressBar


func setup(p_character: Adventurer, p_registry: DataRegistry) -> void:
	character = p_character
	registry = p_registry
	toggle_mode = true
	custom_minimum_size = Vector2(220, 116)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -8
	h.offset_top = 8
	h.offset_bottom = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_portrait = TextureRect.new()
	_portrait.texture = UiTheme.texture(String(character.definition.get("portrait", "")))
	_portrait.custom_minimum_size = Vector2(64, 64)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := UiTheme.label(character.display_name.split(" ")[0], 20, UiTheme.rarity_color(character.rarity))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	_state = UiTheme.label("", 15, UiTheme.TEXT_DIM)
	_state.clip_text = true
	_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_state)
	_bag = UiTheme.bar(UiTheme.ACCENT, 8)
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_bag)
	_hp = UiTheme.bar(UiTheme.BAD, 6)
	_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hp)
	refresh()


func refresh() -> void:
	_state.text = CharacterStates.label_of(character.state)
	_bag.value = character.inventory.fill_ratio()
	_hp.value = character.health / character.max_health()
