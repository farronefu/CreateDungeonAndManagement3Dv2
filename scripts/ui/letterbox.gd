class_name Letterbox
extends Control
## Cinema-scope bars sliding in from the top and bottom of the screen, with a speaker line
## typed out in the bottom bar. Used by the opening scene; A / Enter / Space / click skip it.

const BAR_H := 150.0

var skipped := false
var _top: ColorRect
var _bottom: ColorRect
var _name: Label
var _line: Label
var _active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	_top = _bar(Control.PRESET_TOP_WIDE)
	_bottom = _bar(Control.PRESET_BOTTOM_WIDE)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 120
	box.offset_right = -120
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(box)
	_name = UiTheme.label("", 28, UiTheme.GOLD)
	box.add_child(_name)
	_line = UiTheme.label("", 44, Color(1, 1, 1))
	box.add_child(_line)
	_set_bars(0.0)
	visible = false


func _bar(preset: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	r.set_anchors_preset(preset)
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.offset_left = 0.0
	r.offset_right = 0.0
	return r


## 0 = hidden, 1 = fully in.
func _set_bars(k: float) -> void:
	var h := BAR_H * k
	_top.offset_top = 0.0
	_top.offset_bottom = h
	_bottom.offset_top = -h
	_bottom.offset_bottom = 0.0


func begin() -> void:
	skipped = false
	_active = true
	visible = true
	_name.text = ""
	_line.text = ""
	var tw := create_tween()
	tw.tween_method(_set_bars, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func say(who: String, text: String, seconds: float) -> void:
	_name.text = who
	_line.text = text
	_line.visible_ratio = 0.0
	create_tween().tween_property(_line, "visible_ratio", 1.0, seconds)


func end() -> void:
	_active = false
	_name.text = ""
	_line.text = ""
	var tw := create_tween()
	tw.tween_method(_set_bars, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: visible = false)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var skip := false
	if event is InputEventJoypadButton and event.pressed:
		skip = (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	elif event is InputEventKey and event.pressed and not event.echo:
		skip = (event as InputEventKey).keycode in [KEY_ENTER, KEY_SPACE]
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	if skip:
		skipped = true
		get_viewport().set_input_as_handled()
