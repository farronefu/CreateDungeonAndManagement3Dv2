class_name DigCursor
extends Node3D
## The player's dig cursor (a hydraulic breaker hovering over the cell): highlights the block under the mouse (or the gamepad cursor)
## and emits clicks. Gamepad: D-pad / left stick move (hold to repeat, longer = faster),
## A digs / places the 魔王, holding A while moving digs a whole tunnel.

signal clicked(cell: Vector2i)
signal hovered(cell: Vector2i)

enum Mode { NONE, DIG, PLACE }

var grid: DungeonGrid
var view: DungeonView
var camera: Camera3D
var mode := Mode.NONE
var hover := Vector2i(-999, -999)
## Callable(cell) -> Color : frame colour (alpha 0 hides it)
var validator: Callable
## gamepad cursor
var pad_cell := Vector2i(-1, -1)
const REPEAT_DELAY := 0.2
const REPEAT_INTERVAL := 0.085
const REPEAT_FAST := 0.04
var _rep_dir := Vector2.ZERO
var _rep_timer := 0.0
var _rep_held := 0.0

var _frame: MeshInstance3D
var _frame_mat: StandardMaterial3D
var _pick: Node3D          # breaker, bobs and recoils
var _pick_pivot: Node3D    # follows the hovered cell
var _chisel: Node3D        # MetalChisel: extends downwards to break the block
var _chisel_y := 0.0
var _t := 0.0
var _swinging := false


func _ready() -> void:
	_frame = MeshInstance3D.new()
	_frame.mesh = _frame_mesh()
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_mat.albedo_color = Color(1.0, 0.7, 0.2)
	_frame_mat.emission_enabled = true
	_frame_mat.emission = Color(1.0, 0.6, 0.15)
	_frame_mat.emission_energy_multiplier = 1.6
	_frame_mat.vertex_color_use_as_albedo = true
	_frame_mat.no_depth_test = true
	_frame_mat.render_priority = 5
	_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame.material_override = _frame_mat
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_frame)
	_pick_pivot = Node3D.new()
	add_child(_pick_pivot)
	var pick := MonsterCatalog.make_actor("breaker")
	pick.set_shadows(true)
	_pick = Node3D.new()
	_pick.add_child(pick)
	# turn the 魔 emblem side towards the camera and put the chisel axis over the cell centre
	pick.rotation.y = BREAKER_YAW
	_chisel = pick.model.find_child("MetalChisel", true, false) as Node3D
	if _chisel:
		_chisel_y = _chisel.position.y
		var off := Basis(Vector3.UP, BREAKER_YAW) * Vector3(_chisel.position.x, 0, _chisel.position.z) * pick.scale.x
		pick.position = -off
	_pick_pivot.add_child(_pick)
	Pad.button_pressed.connect(_on_pad_button)
	Pad.mode_changed.connect(func(on: bool) -> void:
		if on:
			_init_pad_cell())


## Four thin L-shaped corner brackets plus a very faint fill (pulses in _process).
func _frame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var o := 0.49
	var t := 0.035   # line thickness
	var l := 0.2     # arm length
	var rects: Array[Rect2] = []
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var cx: float = o * sx
			var cz: float = o * sz
			# horizontal arm and vertical arm of the bracket
			rects.append(Rect2(minf(cx, cx - sx * l), cz - (t if sz > 0 else 0.0), l, t))
			rects.append(Rect2(cx - (t if sx > 0 else 0.0), minf(cz, cz - sz * l), t, l))
	var col := Color(1, 1, 1, 1)
	for r in rects:
		var a := Vector3(r.position.x, 0, r.position.y)
		var b := Vector3(r.end.x, 0, r.position.y)
		var c := Vector3(r.end.x, 0, r.end.y)
		var d := Vector3(r.position.x, 0, r.end.y)
		for v in [a, b, c, a, c, d]:
			st.set_color(col)
			st.add_vertex(v)
	# faint fill
	var fill := Color(1, 1, 1, 0.1)
	var f := o - 0.02
	for v in [Vector3(-f, 0, -f), Vector3(f, 0, -f), Vector3(f, 0, f), Vector3(-f, 0, -f), Vector3(f, 0, f), Vector3(-f, 0, f)]:
		st.set_color(fill)
		st.add_vertex(v)
	return st.commit()


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and grid.in_bounds(hover):
			clicked.emit(hover)


func _init_pad_cell() -> void:
	if grid == null:
		return
	if grid.in_bounds(hover):
		pad_cell = hover
	elif camera is GameCamera:
		pad_cell = DungeonGrid.world_to_cell((camera as GameCamera).focus)
	pad_cell = pad_cell.clamp(Vector2i.ZERO, Vector2i(grid.w - 1, grid.h - 1))


func _on_pad_button(b: int) -> void:
	# the signal still arrives while the game is paused (cursor disabled)
	if mode == Mode.NONE or grid == null or not can_process():
		return
	if not grid.in_bounds(pad_cell):
		_init_pad_cell()
	if b == JOY_BUTTON_A:
		clicked.emit(pad_cell)


## Moves the gamepad cursor one step per repeat tick; returns true if it moved.
func _pad_step(delta: float) -> void:
	var s := Vector2(Pad.dpad())
	var stick := Pad.left_stick()
	var fast := false
	if s == Vector2.ZERO and stick.length() > 0.5:
		# stick: 8-way, full tilt = fast
		s = Vector2(0 if absf(stick.x) < 0.38 else signf(stick.x), 0 if absf(stick.y) < 0.38 else signf(stick.y))
		fast = stick.length() > 0.95
	if s == Vector2.ZERO:
		_rep_dir = Vector2.ZERO
		return
	if s != _rep_dir:
		_rep_dir = s
		_rep_held = 0.0
		_rep_timer = REPEAT_DELAY
		_move_pad(s)
		return
	_rep_held += delta
	_rep_timer -= delta
	if _rep_timer <= 0.0:
		_rep_timer = REPEAT_FAST if (fast or _rep_held > 0.7) else REPEAT_INTERVAL
		_move_pad(s)


func _move_pad(s: Vector2) -> void:
	var cam := camera as GameCamera
	var step := Vector2i.ZERO
	if s.x != 0.0:
		step += cam.screen_to_grid_step(Vector2(s.x, 0)) if cam else Vector2i(int(s.x), 0)
	if s.y != 0.0:
		step += cam.screen_to_grid_step(Vector2(0, s.y)) if cam else Vector2i(0, int(s.y))
	var next := (pad_cell + step).clamp(Vector2i.ZERO, Vector2i(grid.w - 1, grid.h - 1))
	if next == pad_cell:
		return
	pad_cell = next
	# (the camera follows the gliding frame every frame in _process)
	# holding A while moving digs a tunnel
	if mode == Mode.DIG and Pad.held(JOY_BUTTON_A):
		clicked.emit(pad_cell)


const BREAKER_YAW := -PI / 2.0
const BREAKER_TILT := -0.5   # lean (rad) about the chisel tip: the body leans to the upper right
const HOVER := 0.06          # gap between the chisel tip and the block top at rest
const EXTEND := 0.3          # how far the chisel shoots out (model units; 0.3 is hidden inside the body)
const HITS := 3              # hydraulic hammer blows per dig


## Hydraulic hammering: the chisel shoots down into the block a few times, the body recoils.
func swing() -> void:
	if _swinging or _chisel == null:
		return
	_swinging = true
	var tw := create_tween()
	for i in HITS:
		var ext := EXTEND * (1.0 if i == 0 else 0.8)
		tw.tween_property(_chisel, "position:y", _chisel_y - ext, 0.035).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_pick, "position:y", 0.05, 0.035)
		tw.tween_property(_chisel, "position:y", _chisel_y, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_pick, "position:y", 0.0, 0.07)
	tw.tween_callback(func() -> void: _swinging = false)


func _process(delta: float) -> void:
	_t += delta
	if mode == Mode.NONE or camera == null:
		_frame.visible = false
		_pick_pivot.visible = false
		view.set_hover(Vector2i(-999, -999), 0.0)
		return
	var c := mouse_cell()
	if Pad.using_pad:
		if not grid.in_bounds(pad_cell):
			_init_pad_cell()
		_pad_step(delta)
		c = pad_cell
	if c != hover:
		hover = c
		hovered.emit(c)
	var solid := grid.in_bounds(c) and not grid.is_floor(c)
	var y := Balance.BLOCK_H + 0.025 if solid else 0.02
	var col := validator.call(c) as Color if validator.is_valid() else Color(1, 0.7, 0.2)
	var frame_target := Vector3(c.x + 0.5, y, c.y + 0.5)
	# glide between cells (snap after a jump or when the frame reappears)
	if _frame.visible and _frame.position.distance_to(frame_target) < 4.0:
		_frame.position = _frame.position.lerp(frame_target, clampf(delta * 24.0, 0.0, 1.0))
	else:
		_frame.position = frame_target
	_frame.visible = grid.in_bounds(c) and col.a > 0.0
	# gamepad: while the player steers the cursor, the gliding frame pushes the camera along so a
	# held D-pad pans seamlessly (idle cursor never pushes, so hero-follow is left alone)
	var steering := _rep_dir != Vector2.ZERO or _frame.position.distance_to(frame_target) > 0.01
	if Pad.using_pad and steering and camera is GameCamera and grid.in_bounds(c):
		if (camera as GameCamera).keep_in_view(Vector3(_frame.position.x, 0, _frame.position.z)):
			(camera as GameCamera).user_moved = true
	var pulse := 0.75 + 0.25 * sin(_t * 5.0)
	_frame_mat.albedo_color = Color(col.r, col.g, col.b, col.a * pulse)
	# brackets breathe outward slightly
	_frame.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 5.0))
	_frame_mat.emission = Color(col.r, col.g, col.b)
	view.set_hover(c if solid else Vector2i(-999, -999), 0.5 * pulse * col.a)
	_pick_pivot.visible = mode == Mode.DIG and grid.in_bounds(c)
	var target := Vector3(c.x + 0.5, y + HOVER + (0.0 if _swinging else (sin(_t * 3.0) * 0.5 + 0.5) * 0.04), c.y + 0.5)
	_pick_pivot.position = _pick_pivot.position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	_pick_pivot.rotation = Vector3(0.0, 0.0, BREAKER_TILT)


func mouse_cell() -> Vector2i:
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	if absf(d.y) < 1e-4:
		return hover
	# first test the tops of the blocks, then the floor
	var t_top := (Balance.BLOCK_H - o.y) / d.y
	var p_top := o + d * t_top
	var c_top := DungeonGrid.world_to_cell(p_top)
	if grid.in_bounds(c_top) and not grid.is_floor(c_top):
		return c_top
	var t_floor := (0.0 - o.y) / d.y
	return DungeonGrid.world_to_cell(o + d * t_floor)
