class_name GameCamera
extends Camera3D
## Angled top-down camera (風来のシレン style) that can orbit freely.
##   Pan : WASD / arrows / screen edges / right-drag
##   Orbit: right stick / middle-drag / Q・E (yaw)   Reset: R3 / Home
##   Zoom : mouse wheel

const DEFAULT_PITCH := deg_to_rad(55.0)
const MIN_PITCH := deg_to_rad(28.0)
const MAX_PITCH := deg_to_rad(84.0)
const BASE_DIST := 19.0
const ORBIT_YAW_SPEED := 1.9    # rad/s at full stick
const ORBIT_PITCH_SPEED := 1.1

var focus := Vector3(18, 0, 7)
var zoom := 1.0
var yaw := 0.0
var pitch := DEFAULT_PITCH
var bounds := Rect2(0, -2, 36, 28)
var edge_scroll := true
## Set when the player moves the camera manually (used to cancel hero-follow).
var user_moved := false
var _target_focus := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := DEFAULT_PITCH
var _dragging := false
var _orbiting := false
var _shake := 0.0


func _ready() -> void:
	fov = 35.0
	near = 0.1
	far = 140.0
	_target_focus = focus
	Pad.button_pressed.connect(func(b: int) -> void:
		if b == JOY_BUTTON_RIGHT_STICK:
			reset_angle())
	_apply()


func set_bounds(r: Rect2) -> void:
	bounds = r


func focus_on(p: Vector3, instant: bool = false) -> void:
	_target_focus = Vector3(p.x, 0, p.z)
	if instant:
		focus = _target_focus
		_apply()


func reset_angle() -> void:
	_target_yaw = 0.0
	_target_pitch = DEFAULT_PITCH


## Orbits the camera to an absolute angle (used by tests / scripted shots).
func set_angle(yaw_rad: float, pitch_rad: float, instant: bool = true) -> void:
	_target_yaw = yaw_rad
	_target_pitch = clampf(pitch_rad, MIN_PITCH, MAX_PITCH)
	if instant:
		yaw = _target_yaw
		pitch = _target_pitch
		_apply()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Converts a screen-space direction (x right, y down) to a world XZ direction for the current yaw.
func screen_to_world_dir(s: Vector2) -> Vector2:
	var c := cos(yaw)
	var sn := sin(yaw)
	return Vector2(c * s.x + sn * s.y, -sn * s.x + c * s.y)


## Nearest grid step for a screen direction (one axis at a time).
func screen_to_grid_step(s: Vector2) -> Vector2i:
	var w := screen_to_world_dir(s)
	if absf(w.x) >= absf(w.y):
		return Vector2i(1 if w.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if w.y > 0.0 else -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.45, 1.35)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.45, 1.35)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			var k := 0.018 * zoom
			var w := screen_to_world_dir(Vector2(-mm.relative.x * k, -mm.relative.y * k / sin(pitch)))
			_target_focus += Vector3(w.x, 0, w.y)
			user_moved = true
		elif _orbiting:
			_target_yaw -= mm.relative.x * 0.008
			_target_pitch = clampf(_target_pitch + mm.relative.y * 0.006, MIN_PITCH, MAX_PITCH)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_HOME:
		reset_angle()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_Q):
		_target_yaw += ORBIT_YAW_SPEED * 0.6 * delta
	if Input.is_key_pressed(KEY_E):
		_target_yaw -= ORBIT_YAW_SPEED * 0.6 * delta
	# right stick: seamless orbit
	var rs := Pad.right_stick()
	if rs != Vector2.ZERO:
		_target_yaw -= rs.x * ORBIT_YAW_SPEED * delta
		_target_pitch = clampf(_target_pitch - rs.y * ORBIT_PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if edge_scroll and not Pad.using_pad and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var m := 6.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= size.x and mp.y <= size.y:
			if mp.x < m:
				move.x -= 1
			elif mp.x > size.x - m:
				move.x += 1
			if mp.y < m:
				move.y -= 1
			elif mp.y > size.y - m:
				move.y += 1
	if move != Vector2.ZERO:
		user_moved = true
		var w := screen_to_world_dir(move.normalized())
		_target_focus += Vector3(w.x, 0, w.y) * 10.0 * zoom * delta
	_target_focus.x = clampf(_target_focus.x, bounds.position.x, bounds.end.x)
	_target_focus.z = clampf(_target_focus.z, bounds.position.y, bounds.end.y)
	var k := clampf(delta * 10.0, 0.0, 1.0)
	focus = focus.lerp(_target_focus, k)
	yaw = lerp_angle(yaw, _target_yaw, k)
	pitch = lerpf(pitch, _target_pitch, k)
	_shake = maxf(0.0, _shake - delta * 2.5)
	_apply()


func _apply() -> void:
	var dist := BASE_DIST * zoom
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
	position = focus + offset + jitter
	look_at(focus + jitter * 0.5, Vector3.UP)
