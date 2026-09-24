class_name DungeonView
extends Node3D
## Renders the DungeonGrid as one continuous body of earth: flush soil cubes (MultiMesh) textured
## in world space from a per-cell "field" texture, a packed-dirt floor for dug passages, sparse
## decor, torches, and the 3D surface world above the entrance (SurfaceWorld).

const OUTER_SIDE := 20     # undiggable rock beyond the grid, so the camera never sees the void
const OUTER_BOTTOM := 16

var grid: DungeonGrid
var block_mat: ShaderMaterial
var surface: SurfaceWorld
var torches := {}  # Vector2i -> Torch

var _mm_inner: MultiMesh
var _mm_outer: MultiMesh
var _slot := {}  # Vector2i -> [multimesh, index]
var _seed := {}
var _anim := {}  # Vector2i -> time left (crumble)
var _hover := Vector2i(-999, -999)
var _hover_amt := 0.0
var _field_img: Image
var _field_tex: ImageTexture
var _field_dirty := false
var _decor_dirty := true
var _decor_timer := 0.0
var _tufts: MultiMeshInstance3D
var _floor_rocks: MultiMeshInstance3D
var _floor_shrooms: MultiMeshInstance3D
var _floor_props := {}
var _rng := RandomNumberGenerator.new()


func setup(g: DungeonGrid) -> void:
	grid = g
	_rng.seed = 12345
	grid.cell_dug.connect(_on_cell_dug)
	grid.nutrient_changed.connect(_on_nutrient_changed)
	_build_field()
	_build_materials()
	_build_blocks()
	_build_floor()
	_build_decor_layers()
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c):
				_add_floor_props(c)
	_auto_torches_initial()
	_rebuild_decor()
	surface = SurfaceWorld.new()
	add_child(surface)
	surface.build(grid, block_mat)


# ------------------------------------------------------------------ field texture
func _field_px(c: Vector2i) -> Vector2i:
	return Vector2i(c.x + OUTER_SIDE, c.y)


func _field_color(c: Vector2i) -> Color:
	if not grid.in_bounds(c):
		return Color(0, 1, 0)
	var t := grid.get_type(c)
	if t == DungeonGrid.FLOOR:
		return Color(0, 0, 1)
	if t == DungeonGrid.BEDROCK:
		return Color(0, 0 if c.y == 0 else 1, 0)
	return Color(float(grid.get_nutrient(c)) / 16.0, 0, 0)


func _build_field() -> void:
	var fw := grid.w + OUTER_SIDE * 2
	var fh := grid.h + OUTER_BOTTOM
	_field_img = Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	for y in fh:
		for x in fw:
			var c := Vector2i(x - OUTER_SIDE, y)
			_field_img.set_pixel(x, y, _field_color(c))
	_field_tex = ImageTexture.create_from_image(_field_img)


func _update_field(c: Vector2i) -> void:
	var p := _field_px(c)
	if p.x < 0 or p.y < 0 or p.x >= _field_img.get_width() or p.y >= _field_img.get_height():
		return
	_field_img.set_pixelv(p, _field_color(c))
	_field_dirty = true


func _build_materials() -> void:
	block_mat = ShaderMaterial.new()
	block_mat.shader = load("res://shaders/block.gdshader")
	block_mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	block_mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	block_mat.set_shader_parameter("block_height", Balance.BLOCK_H)
	block_mat.set_shader_parameter("field", _field_tex)
	block_mat.set_shader_parameter("field_origin", Vector2(-OUTER_SIDE, 0))
	block_mat.set_shader_parameter("field_size", Vector2(_field_img.get_width(), _field_img.get_height()))
	block_mat.set_shader_parameter("depth_rows", float(grid.h))


# ------------------------------------------------------------------ blocks
func _build_blocks() -> void:
	var inner: Array[Vector2i] = []
	var outer: Array[Vector2i] = []
	for y in range(0, grid.h + OUTER_BOTTOM):
		for x in range(-OUTER_SIDE, grid.w + OUTER_SIDE):
			var c := Vector2i(x, y)
			if grid.in_bounds(c):
				inner.append(c)
			else:
				outer.append(c)
	var box := BoxMesh.new()
	box.size = Vector3(1.0, Balance.BLOCK_H, 1.0)
	_mm_inner = _make_mm(box, inner, true)
	_mm_outer = _make_mm(box, outer, false)


func _make_mm(mesh: Mesh, cells: Array[Vector2i], shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c := cells[i]
		_slot[c] = [mm, i]
		_seed[c] = _rng.randf()
		_write_instance(c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = block_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _write_instance(c: Vector2i) -> void:
	if not _slot.has(c):
		return
	var sv: Array = _slot[c]
	var mm: MultiMesh = sv[0]
	var solid := not grid.in_bounds(c) or not grid.is_floor(c)
	var s := 1.0
	if _anim.has(c):
		s = maxf(0.001, _anim[c] / 0.22)
	elif not solid:
		s = 0.0
	var h := Balance.BLOCK_H
	if s <= 0.0:
		mm.set_instance_transform(sv[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(c.x + 0.5, -5, c.y + 0.5)))
	else:
		# crumbling blocks sink and shrink a little
		var basis := Basis().scaled(Vector3(lerpf(0.7, 1.0, s), s, lerpf(0.7, 1.0, s)))
		mm.set_instance_transform(sv[1], Transform3D(basis, Vector3(c.x + 0.5, h * 0.5 * s, c.y + 0.5)))
	var hover := _hover_amt if c == _hover else 0.0
	mm.set_instance_custom_data(sv[1], Color(0, _seed.get(c, 0.5), hover, 0))


func _on_cell_dug(c: Vector2i) -> void:
	_anim[c] = 0.22
	_decor_dirty = true
	_update_field(c)
	if not _floor_props.has(c):
		_add_floor_props(c)
	_maybe_torch(c)


func _on_nutrient_changed(c: Vector2i) -> void:
	_update_field(c)
	_decor_dirty = true


func set_hover(c: Vector2i, amount: float) -> void:
	var old := _hover
	_hover = c
	_hover_amt = amount
	if old != c:
		_write_instance(old)
	_write_instance(c)


func _process(delta: float) -> void:
	if not _anim.is_empty():
		for c in _anim.keys():
			_anim[c] -= delta
			if _anim[c] <= 0.0:
				_anim.erase(c)
			_write_instance(c)
	if _field_dirty:
		_field_dirty = false
		_field_tex.update(_field_img)
	_decor_timer -= delta
	if _decor_dirty and _decor_timer <= 0.0:
		_rebuild_decor()
		_decor_timer = 0.4


# ------------------------------------------------------------------ floor
func _build_floor() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(grid.w + OUTER_SIDE * 2, grid.h + OUTER_BOTTOM)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/floor.gdshader")
	mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	mat.set_shader_parameter("depth_rows", float(grid.h))
	mi.material_override = mat
	mi.position = Vector3(grid.w * 0.5, 0.0, (grid.h + OUTER_BOTTOM) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ decor (kept sparse on purpose)
func _build_decor_layers() -> void:
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_texture = ProcGen.grass_texture()
	grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_mat.alpha_scissor_threshold = 0.4
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.vertex_color_is_srgb = true
	grass_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	grass_mat.roughness = 1.0
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tufts = _mmi(ProcGen.tuft_mesh(0.3, 0.2), grass_mat, true)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.vertex_color_is_srgb = true
	rock_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	rock_mat.roughness = 1.0
	_floor_rocks = _mmi(ProcGen.rock_mesh(4), rock_mat, true)
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("e8dcc0")
	stem.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("d9a441")
	cap.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	cap.emission_enabled = true
	cap.emission = Color("ffb84a")
	cap.emission_energy_multiplier = 0.9
	_floor_shrooms = _mmi(ProcGen.mushroom_mesh(stem, cap), null, false)


func _mmi(mesh: Mesh, mat: Material, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	add_child(mmi)
	return mmi


func _add_floor_props(c: Vector2i) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(c) + 77
	var props := []
	if r.randf() < 0.2:
		var s := r.randf_range(0.06, 0.12)
		var p := Vector3(c.x + r.randf_range(0.2, 0.8), 0.0, c.y + r.randf_range(0.2, 0.8))
		props.append(["rock", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), p)])
	if r.randf() < 0.07:
		var s2 := r.randf_range(0.6, 1.0)
		var p2 := Vector3(c.x + r.randf_range(0.15, 0.35) * (1 if r.randf() < 0.5 else -1) + 0.5, 0.0, c.y + r.randf_range(0.2, 0.8))
		props.append(["shroom", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s2), p2)])
	_floor_props[c] = props


func _rebuild_decor() -> void:
	_decor_dirty = false
	var tuft_x: Array[Transform3D] = []
	var tuft_c: Array[Color] = []
	for y in range(1, grid.h):
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c) or _anim.has(c) or grid.get_type(c) != DungeonGrid.BLOCK:
				continue
			var n := grid.get_nutrient(c)
			if n < 10:
				continue
			var r := RandomNumberGenerator.new()
			r.seed = hash(c) * 31 + n
			var count := 2
			for i in count:
				var p := Vector3(c.x + r.randf_range(0.2, 0.8), Balance.BLOCK_H - 0.01, c.y + r.randf_range(0.2, 0.8))
				var s := r.randf_range(0.8, 1.2)
				tuft_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), p))
				tuft_c.append(Color(0.62, 0.78, 0.42) if n < 10 else Color(0.32, 0.62, 0.36))
	_fill(_tufts.multimesh, tuft_x, tuft_c)
	var rock_x: Array[Transform3D] = []
	var rock_c: Array[Color] = []
	var shroom_x: Array[Transform3D] = []
	for c in _floor_props:
		for pr in _floor_props[c]:
			if pr[0] == "rock":
				rock_x.append(pr[1])
				rock_c.append(Color(0.44, 0.39, 0.34))
			else:
				shroom_x.append(pr[1])
	_fill(_floor_rocks.multimesh, rock_x, rock_c)
	_fill(_floor_shrooms.multimesh, shroom_x, [])


func _fill(mm: MultiMesh, xs: Array[Transform3D], cs: Array) -> void:
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors and i < cs.size():
			mm.set_instance_color(i, cs[i])


# ------------------------------------------------------------------ torches
func _auto_torches_initial() -> void:
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c):
				_maybe_torch(c)


func _maybe_torch(c: Vector2i) -> void:
	if not grid.is_floor(c) or c == grid.entrance:
		return
	for t in torches:
		if absi(t.x - c.x) + absi(t.y - c.y) < 5:
			return
	var walls: Array[Vector2i] = []
	for d in DungeonGrid.DIRS:
		if not grid.is_floor(c + d):
			walls.append(d)
	if walls.is_empty():
		return
	var d: Vector2i = walls[0]
	var torch := Torch.new()
	torch.position = Vector3(c.x + 0.5 + d.x * 0.36, 0, c.y + 0.5 + d.y * 0.36)
	add_child(torch)
	torches[c] = torch
