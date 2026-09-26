extends Node
## Gamepad state (Xbox layout). Tracks buttons / sticks from input events so gameplay code can
## query them, and remembers whether the player is currently using a pad or the mouse.
##   A: dig / confirm / place 魔王 / skip cut-in (hold + D-pad = dig a tunnel)   B: cancel
##   Y: call the hero (asks first)   RB / LB: faster / slower   Start: pause
##   D-pad / left stick: move the cursor   right stick: look around the cursor
##   RT + right stick: move the camera   LT: jump to the hero   R3: zoom step

signal button_pressed(button: int)
signal mode_changed(using_pad: bool)
## LT / RT pulled past half way (JOY_AXIS_TRIGGER_LEFT / _RIGHT)
signal trigger_pressed(axis: int)

const STICK_DEADZONE := 0.22

var using_pad := false
var _buttons := {}
var _axes := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Godot's default ui_accept has no gamepad binding: make A press focused buttons
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.device = -1
	InputMap.action_add_event("ui_accept", a)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		_buttons[b.button_index] = b.pressed
		_set_pad(true)
		if b.pressed:
			button_pressed.emit(b.button_index)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var was := float(_axes.get(m.axis, 0.0))
		_axes[m.axis] = m.axis_value
		if (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT) and was <= 0.5 and m.axis_value > 0.5:
			trigger_pressed.emit(m.axis)
		if absf(m.axis_value) > 0.4:
			_set_pad(true)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 4.0:
			_set_pad(false)
	elif event is InputEventMouseButton or event is InputEventKey:
		_set_pad(false)


func _set_pad(v: bool) -> void:
	if v != using_pad:
		using_pad = v
		mode_changed.emit(v)


func held(button: int) -> bool:
	return bool(_buttons.get(button, false))


func axis(a: int) -> float:
	var v := float(_axes.get(a, 0.0))
	return 0.0 if absf(v) < STICK_DEADZONE else v


## Right stick with deadzone, x = right, y = down.
func right_stick() -> Vector2:
	return Vector2(axis(JOY_AXIS_RIGHT_X), axis(JOY_AXIS_RIGHT_Y))


## Left stick with deadzone.
func left_stick() -> Vector2:
	return Vector2(axis(JOY_AXIS_LEFT_X), axis(JOY_AXIS_LEFT_Y))


## D-pad as a vector (x right, y down).
func dpad() -> Vector2i:
	var v := Vector2i.ZERO
	if held(JOY_BUTTON_DPAD_LEFT):
		v.x -= 1
	if held(JOY_BUTTON_DPAD_RIGHT):
		v.x += 1
	if held(JOY_BUTTON_DPAD_UP):
		v.y -= 1
	if held(JOY_BUTTON_DPAD_DOWN):
		v.y += 1
	return v
