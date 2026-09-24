class_name UiTheme
extends RefCounted
## Shared look for all UI: warm dark "lantern glass" panels with a hairline brass edge,
## bundled Noto fonts (serif for headings / numbers, sans for body text).

const INK := Color(0.07, 0.055, 0.045, 0.82)       # panel fill
const INK_SOLID := Color(0.09, 0.07, 0.055, 0.96)
const EDGE := Color(0.82, 0.64, 0.36, 0.55)         # hairline border
const GOLD := Color(0.96, 0.78, 0.42)
const GOLD_DARK := Color(0.52, 0.38, 0.18)
const TEXT := Color(0.97, 0.93, 0.85)
const TEXT_DIM := Color(0.78, 0.72, 0.62)
const HP := Color(0.55, 0.86, 0.38)
const MP := Color(0.42, 0.72, 1.0)
const WARN := Color(1.0, 0.46, 0.34)
# kept for older call sites
const NAVY := INK
const NAVY_LIGHT := INK_SOLID

const SANS_PATH := "res://assets/fonts/NotoSansJP-VF.ttf"
const SERIF_PATH := "res://assets/fonts/NotoSerifJP-VF.ttf"

static var _fonts := {}
static var _theme: Theme


static func _variant(path: String, weight: int) -> Font:
	var key := "%s:%d" % [path, weight]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		var base := load(path) as FontFile
		base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		base.hinting = TextServer.HINTING_LIGHT
		fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		_fonts[key] = fv
	return _fonts[key]


## Body text (Noto Sans JP).
static func font(bold: bool = false) -> Font:
	return _variant(SANS_PATH, 700 if bold else 500)


## Headings, titles and big numbers (Noto Serif JP).
static func serif(weight: int = 800) -> Font:
	return _variant(SERIF_PATH, weight)


static func panel(bg: Color = INK, border: Color = EDGE, radius: int = 8, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


## Pill-shaped glass chip.
static func chip(bg: Color = INK, border: Color = EDGE) -> StyleBoxFlat:
	var sb := panel(bg, border, 22, 1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.05, 0.03, 0.02, 0.85))
	t.set_constant("outline_size", "Label", 5)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "Label", 2)
	var normal := panel(Color(0.16, 0.11, 0.07, 0.92), Color(0.86, 0.66, 0.36, 0.7), 6, 1)
	var hover := panel(Color(0.28, 0.19, 0.1, 0.96), Color(1.0, 0.82, 0.5, 0.95), 6, 1)
	var pressed := panel(Color(0.42, 0.28, 0.12, 1.0), Color(1.0, 0.88, 0.6), 6, 1)
	var disabled := panel(Color(0.12, 0.11, 0.1, 0.75), Color(0.35, 0.32, 0.28, 0.6), 6, 1)
	for sb in [normal, hover, pressed, disabled]:
		sb.shadow_size = 4
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1.0, 0.92, 0.65)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(8)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", serif(700))
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_pressed_color", "Button", Color(1, 0.97, 0.88))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	var sep := StyleBoxLine.new()
	sep.color = Color(EDGE, 0.4)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	_theme = t
	return t


static func label(text: String, size: int = 20, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font(true))
	return l


## Serif label for headings / numbers.
static func heading(text: String, size: int = 24, color: Color = GOLD, weight: int = 800) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", serif(weight))
	return l
