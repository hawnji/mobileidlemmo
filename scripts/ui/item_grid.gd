class_name ItemGrid
extends GridContainer
## Reusable grid of item slots (icon + quantity + name) used by the bag and
## storage screens. Supports a text filter and sort modes.

enum SortMode { NAME, QUANTITY, CATEGORY }

signal item_pressed(item_id: String)

var registry: DataRegistry
var filter_text := ""
var sort_mode := SortMode.NAME
var favorites := {}
var locked := {}


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func show_items(items: Dictionary) -> int:
	for c in get_children():
		c.queue_free()
	var ids: Array = []
	for id in items:
		var item: Dictionary = registry.items.get(id, {})
		var name := String(item.get("name", id))
		if filter_text.is_empty() or name.to_lower().contains(filter_text.to_lower()) or String(item.get("category", "")).contains(filter_text.to_lower()):
			ids.append(id)
	var fav := favorites
	match sort_mode:
		SortMode.NAME:
			ids.sort_custom(func(a, b): return registry.get_item_name(a) < registry.get_item_name(b))
		SortMode.QUANTITY:
			ids.sort_custom(func(a, b): return int(items[a]) > int(items[b]))
		SortMode.CATEGORY:
			ids.sort_custom(func(a, b): return String(registry.items.get(a, {}).get("category", "")) < String(registry.items.get(b, {}).get("category", "")))
	if not fav.is_empty():
		var favs := ids.filter(func(x): return fav.has(x))
		var rest := ids.filter(func(x): return not fav.has(x))
		ids = favs + rest
	for id in ids:
		add_child(_slot(id, int(items[id])))
	return ids.size()


func _slot(item_id: String, qty: int) -> Control:
	var item: Dictionary = registry.items.get(item_id, {})
	var p := PanelContainer.new()
	var rar := UiTheme.rarity_color(String(item.get("rarity", "common")))
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT, rar.darkened(0.2), 10, 2, 6))
	p.custom_minimum_size = Vector2(150, 132)
	p.tooltip_text = String(item.get("description", ""))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var icon := TextureRect.new()
	icon.texture = UiTheme.texture(String(item.get("icon", "")))
	icon.custom_minimum_size = Vector2(56, 56)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(icon)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			item_pressed.emit(item_id))
	var mark := ("* " if favorites.has(item_id) else "") + ("[L] " if locked.has(item_id) else "")
	var q := UiTheme.label(mark + "x%s" % _fmt(qty), 22, UiTheme.ACCENT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var n := UiTheme.label(String(item.get("name", item_id)), 16, UiTheme.TEXT_DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	return p


static func _fmt(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
