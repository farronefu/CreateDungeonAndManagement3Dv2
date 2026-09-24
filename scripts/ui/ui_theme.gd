class_name UiTheme
extends RefCounted
## Shared fonts, colours and style boxes for the HUD (navy panels with gold trim).

const NAVY := Color(0.07, 0.11, 0.2, 0.92)
const NAVY_LIGHT := Color(0.13, 0.19, 0.33, 0.95)
const GOLD := Color(0.93, 0.74, 0.32)
const GOLD_DARK := Color(0.55, 0.4, 0.15)
const TEXT := Color(0.96, 0.95, 0.9)
const HP := Color(0.45, 0.9, 0.35)
const MP := Color(0.35, 0.75, 1.0)
const WARN := Color(1.0, 0.45, 0.35)

static var _fonts := {}
static var _theme: Theme


static func font(bold: bool = false) -> Font:
	var key := "b" if bold else "r"
	if not _fonts.has(key):
		var f := SystemFont.new()
		# Japanese-capable system fonts (a bundled OFL font can replace this for release builds)
		f.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo UI", "Meiryo", "Yu Gothic", "MS Gothic", "Hiragino Sans", "Noto Sans CJK JP", "Noto Sans JP", "sans-serif"])
		f.font_weight = 700 if bold else 500
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_fonts[key] = f
	return _fonts[key]


static func panel(bg: Color = NAVY, border: Color = GOLD, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	var normal := panel(Color(0.2, 0.15, 0.08, 0.95), GOLD, 8, 2)
	var hover := panel(Color(0.36, 0.26, 0.1, 0.98), Color(1.0, 0.85, 0.45), 8, 2)
	var pressed := panel(Color(0.5, 0.36, 0.12, 1.0), Color(1.0, 0.9, 0.5), 8, 2)
	var disabled := panel(Color(0.15, 0.15, 0.17, 0.9), Color(0.4, 0.4, 0.4), 8, 2)
	for sb in [normal, hover, pressed, disabled]:
		sb.shadow_size = 3
		sb.content_margin_left = 18
		sb.content_margin_right = 18
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	_theme = t
	return t


static func label(text: String, size: int = 22, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font(true))
	return l
