class_name CutIn
extends Control
## Full-width dramatic banner: speed lines, a live 3D portrait and a big title.

signal finished

var _band: Control
var _portrait: TextureRect
var _title: Label
var _sub: Label
var _t := 0.0
var _dur := 0.0
var _color := Color(0.8, 0.15, 0.1)
var _active := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.theme()
	_band = Control.new()
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.draw.connect(_draw_band)
	add_child(_band)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_title = UiTheme.label("", 76, Color(1, 1, 1), true)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02))
	add_child(_title)
	_sub = UiTheme.label("", 32, Color(1, 0.92, 0.7), true)
	_sub.add_theme_constant_override("outline_size", 8)
	add_child(_sub)
	visible = false


func play(title: String, subtitle: String, portrait: Texture2D, color: Color, duration: float = 2.8) -> void:
	_title.text = title
	_sub.text = subtitle
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_color = color
	_t = 0.0
	_dur = duration
	_active = true
	visible = true
	Sfx.play("cutin")


func _input(event: InputEvent) -> void:
	# A / Enter / Space skip the cut-in
	if not _active or _t <= 0.4:
		return
	var skip: bool = event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	skip = skip or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_ENTER, KEY_SPACE])
	if skip:
		_t = maxf(_t, _dur - 0.35)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _active and event is InputEventMouseButton and event.pressed and _t > 0.4:
		_t = maxf(_t, _dur - 0.35)


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	var vs := get_viewport_rect().size
	position = Vector2.ZERO
	size = vs
	_band.size = vs
	var cy := vs.y * 0.5
	var intro := clampf(_t / 0.35, 0.0, 1.0)
	var outro := clampf((_t - (_dur - 0.35)) / 0.35, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - intro, 3.0)
	var o := pow(outro, 2.0)
	var ph := 360.0 * vs.y / 1080.0
	_portrait.size = Vector2(ph * 1.25, ph * 1.25)
	_portrait.position = Vector2(lerpf(-ph * 1.4, vs.x * 0.08, e) - o * vs.x * 0.5, cy - ph * 0.72)
	_title.position = Vector2(lerpf(vs.x, vs.x * 0.36, e) + o * vs.x, cy - 70)
	_sub.position = Vector2(lerpf(vs.x * 1.2, vs.x * 0.37, e) + o * vs.x, cy + 28)
	modulate.a = 1.0 - o
	_band.queue_redraw()
	if _t >= _dur:
		_active = false
		visible = false
		finished.emit()


func _draw_band() -> void:
	var vs := get_viewport_rect().size
	var cy := vs.y * 0.5
	var intro := clampf(_t / 0.25, 0.0, 1.0)
	var h := 250.0 * vs.y / 1080.0 * intro
	_band.draw_rect(Rect2(0, 0, vs.x, vs.y), Color(0, 0, 0, 0.35 * intro))
	var skew := 60.0
	var poly := PackedVector2Array([Vector2(0, cy - h * 0.5 + skew * 0.3), Vector2(vs.x, cy - h * 0.5 - skew * 0.3), Vector2(vs.x, cy + h * 0.5 - skew * 0.3), Vector2(0, cy + h * 0.5 + skew * 0.3)])
	_band.draw_colored_polygon(poly, _color.darkened(0.55))
	# speed lines
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var y := cy + rng.randf_range(-h * 0.5, h * 0.5)
		var speed := rng.randf_range(1400, 2600)
		var ln := rng.randf_range(120, 420)
		var x := fposmod(rng.randf() * vs.x - _t * speed, vs.x + ln) - ln
		_band.draw_line(Vector2(x, y), Vector2(x + ln, y), Color(_color.lightened(0.4), 0.35), rng.randf_range(2, 5))
	_band.draw_line(poly[0], poly[1], UiTheme.GOLD, 5)
	_band.draw_line(poly[3], poly[2], UiTheme.GOLD, 5)
