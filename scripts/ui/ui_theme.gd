class_name UiTheme
extends RefCounted
## Builds the shared mobile UI theme in code so every panel matches.
## Colours are centralised here; swapping to a designed .tres theme later only
## touches this file.

const BG := Color("1b1f26")
const PANEL := Color("262b34")
const PANEL_LIGHT := Color("323844")
const BORDER := Color("b8954a")
const TEXT := Color("efe6d2")
const TEXT_DIM := Color("a9a294")
const ACCENT := Color("e0b85a")
const GOOD := Color("7cc46a")
const BAD := Color("e0665a")

const RARITY_COLORS := {
	"common": Color("9aa3ad"), "uncommon": Color("5fbf62"), "rare": Color("4a8ff0"),
	"epic": Color("b06ae0"), "legendary": Color("f0a83a"), "mythic": Color("f05a7a"),
}
const CATEGORY_COLORS := {
	"gathering": Color("5fa04a"), "production": Color("c47a2c"), "combat": Color("c04848"), "utility": Color("4a7fc4"),
}


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, TEXT)


static func box(bg: Color, border := BORDER, radius := 12, border_w := 2, pad := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, BORDER.darkened(0.3), 10, 2, 10))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.08), BORDER, 10, 2, 10))
	t.set_stylebox("pressed", "Button", box(BORDER.darkened(0.45), ACCENT, 10, 2, 10))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.2), Color(0.3, 0.3, 0.3), 10, 2, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_stylebox("background", "ProgressBar", box(Color("15181d"), Color("15181d"), 6, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT, 6, 0, 0))
	t.set_stylebox("normal", "LineEdit", box(Color("15181d"), BORDER.darkened(0.4), 8, 2, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 56)  # finger-sized
	return b


static func bar(color := ACCENT, height := 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	p.max_value = 1.0
	p.step = 0.0
	var fill := box(color, color, 6, 0, 0)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)
