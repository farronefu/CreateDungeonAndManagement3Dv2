class_name GameCamera
extends Camera3D
## Angled top-down camera (風来のシレン style). WASD / arrows / screen edges / right-drag to pan,
## mouse wheel to zoom.

const PITCH := deg_to_rad(55.0)
const BASE_DIST := 19.0

var focus := Vector3(18, 0, 7)
var zoom := 1.0
var bounds := Rect2(0, -2, 36, 28)
var edge_scroll := true
## Set when the player moves the camera manually (used to cancel hero-follow).
var user_moved := false
var _target_focus := Vector3.ZERO
var _dragging := false
var _shake := 0.0


func _ready() -> void:
	fov = 35.0
	near = 0.1
	far = 120.0
	_target_focus = focus
	_apply()


func set_bounds(r: Rect2) -> void:
	bounds = r


func focus_on(p: Vector3, instant: bool = false) -> void:
	_target_focus = Vector3(p.x, 0, p.z)
	if instant:
		focus = _target_focus
		_apply()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.45, 1.35)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.45, 1.35)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var k := 0.018 * zoom
		user_moved = true
		_target_focus += Vector3(-mm.relative.x * k, 0, -mm.relative.y * k / sin(PITCH))


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
	if edge_scroll and DisplayServer.window_is_focused():
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
		_target_focus += Vector3(move.x, 0, move.y).normalized() * 10.0 * zoom * delta
	_target_focus.x = clampf(_target_focus.x, bounds.position.x, bounds.end.x)
	_target_focus.z = clampf(_target_focus.z, bounds.position.y, bounds.end.y)
	focus = focus.lerp(_target_focus, clampf(delta * 10.0, 0.0, 1.0))
	_shake = maxf(0.0, _shake - delta * 2.5)
	_apply()


func _apply() -> void:
	var dist := BASE_DIST * zoom
	var offset := Vector3(0, sin(PITCH), cos(PITCH)) * dist
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
	position = focus + offset + jitter
	look_at(focus + jitter * 0.5, Vector3.UP)
