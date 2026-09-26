class_name UiTheme
extends RefCounted
## Shared look for all UI: pixel-art windows (hard outline, cream bevel, dark inner edge, warm
## translucent fill) drawn from tiny generated textures scaled up with nearest filtering, and the
## bundled pixel font DotGothic16 (SIL OFL) rendered without anti-aliasing.

const INK := Color(0.1, 0.075, 0.06, 0.86)          # panel fill
const INK_SOLID := Color(0.1, 0.075, 0.06, 0.97)
const EDGE := Color(0.95, 0.82, 0.56)               # bevel highlight
const GOLD := Color(0.98, 0.8, 0.42)
const GOLD_DARK := Color(0.52, 0.38, 0.18)
const TEXT := Color(1, 1, 1)
const TEXT_DIM := Color(0.86, 0.86, 0.86)
const HP := Color(0.55, 0.86, 0.38)
const MP := Color(0.42, 0.72, 1.0)
const WARN := Color(1.0, 0.46, 0.34)
const NAVY := INK
const NAVY_LIGHT := INK_SOLID

const PIXEL_FONT := "res://assets/fonts/DotGothic16-Regular.ttf"
const PX := 3            # screen pixels per logical frame pixel
const OUTLINE := Color(0.05, 0.035, 0.03)

static var _font: FontFile
static var _theme: Theme
static var _boxes := {}


## DotGothic16 is drawn on a 16px grid; sizes snap to 16 / 24 / 32 / 48 / 64 … to keep the dots even.
static func px(size: int) -> int:
	if size <= 19:
		return 16
	if size <= 27:
		return 24
	if size <= 39:
		return 32
	if size <= 55:
		return 48
	return int(round(size / 16.0)) * 16


static func _pixel_font() -> FontFile:
	if _font == null:
		_font = load(PIXEL_FONT) as FontFile
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.generate_mipmaps = false
		_font.multichannel_signed_distance_field = false
	return _font


## Body text (pixel font; there is a single weight).
static func font(_bold: bool = false) -> Font:
	return _pixel_font()


## Headings / numbers (same pixel font — kept for call-site compatibility).
static func serif(_weight: int = 800) -> Font:
	return _pixel_font()


# ------------------------------------------------------------------ pixel frames
## 12x12 logical frame: transparent chamfered corners, 1px outline, 1px bevel highlight,
## 1px inner edge, then the fill. Scaled by PX with nearest filtering.
static func _frame_texture(fill: Color, light: Color, inner: Color, draw_fill: bool = true) -> ImageTexture:
	var n := 12
	var img := Image.create(n * PX, n * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var ex := mini(x, n - 1 - x)
			var ey := mini(y, n - 1 - y)
			var e := mini(ex, ey)
			var c := Color(0, 0, 0, 0)
			if ex == 0 and ey == 0:
				c = Color(0, 0, 0, 0)                 # chamfered corner
			elif e == 0:
				c = OUTLINE
			elif e == 1:
				c = light
			elif e == 2:
				c = inner
			elif draw_fill:
				c = fill
			if c.a > 0.0:
				img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), c)
	return ImageTexture.create_from_image(img)


static func _pixel_box(fill: Color, light: Color, inner: Color, margin_x: int = 14, margin_y: int = 8, draw_fill: bool = true) -> StyleBoxTexture:
	var key := "%s|%s|%s|%d|%d|%s" % [fill, light, inner, margin_x, margin_y, draw_fill]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxTexture.new()
	sb.texture = _frame_texture(fill, light, inner, draw_fill)
	var m := 3 * PX
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y
	sb.draw_center = draw_fill
	_boxes[key] = sb
	return sb


## Window panel. `border` tints the bevel highlight (defaults to warm cream).
static func panel(bg: Color = INK, border: Color = EDGE, _radius: int = 0, _border_w: int = 0) -> StyleBoxTexture:
	return _pixel_box(bg, Color(border, 1.0), Color(border.darkened(0.55), 1.0))


## Translucent black window with a dark pixel frame (top-left status).
static func dark_panel() -> StyleBoxTexture:
	return _pixel_box(Color(0, 0, 0, 0.6), Color(0.32, 0.32, 0.32), Color(0.12, 0.12, 0.12), 18, 12)


## dark_panel's frame with chip padding (speed controls next to the status window).
static func dark_chip() -> StyleBoxTexture:
	return _pixel_box(Color(0, 0, 0, 0.6), Color(0.32, 0.32, 0.32), Color(0.12, 0.12, 0.12), 14, 4)


## Small pill / chip window (same frame, tighter padding).
static func chip(bg: Color = INK, border: Color = EDGE) -> StyleBoxTexture:
	return _pixel_box(bg, Color(border, 1.0), Color(border.darkened(0.55), 1.0), 14, 4)


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.05, 0.03, 0.02, 0.9))
	t.set_constant("outline_size", "Label", 4)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	var normal := _pixel_box(Color(0.24, 0.16, 0.09, 0.96), Color(0.9, 0.74, 0.46), Color(0.42, 0.28, 0.14), 20, 6)
	var hover := _pixel_box(Color(0.36, 0.24, 0.12, 0.98), Color(1.0, 0.9, 0.62), Color(0.55, 0.38, 0.18), 20, 6)
	var pressed := _pixel_box(Color(0.5, 0.33, 0.14, 1.0), Color(0.55, 0.38, 0.18), Color(1.0, 0.9, 0.62), 20, 6)
	var disabled := _pixel_box(Color(0.14, 0.13, 0.12, 0.85), Color(0.42, 0.4, 0.37), Color(0.25, 0.24, 0.22), 20, 6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	# focus: a bright pixel frame drawn around the button (gamepad)
	var focus := _pixel_box(Color(0, 0, 0, 0), Color(1.0, 0.95, 0.5), Color(1.0, 0.95, 0.5, 0.0), 20, 6, false)
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", font())
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	t.set_color("font_outline_color", "Button", Color(0.05, 0.03, 0.02))
	t.set_constant("outline_size", "Button", 4)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	var sep := StyleBoxLine.new()
	sep.color = Color(EDGE, 0.45)
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font("bold_font", "RichTextLabel", font())
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)
	t.set_color("font_outline_color", "RichTextLabel", Color(0.05, 0.03, 0.02, 0.9))
	t.set_constant("outline_size", "RichTextLabel", 3)
	_theme = t
	return t


static func label(text: String, size: int = 24, color: Color = TEXT, _bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	return l


## Heading / number label (pixel font, bigger sizes).
static func heading(text: String, size: int = 24, color: Color = TEXT, _weight: int = 800) -> Label:
	return label(text, size, color)
