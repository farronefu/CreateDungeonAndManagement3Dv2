class_name DungeonView
extends Node3D
## Renders the DungeonGrid as individual rounded soil blocks with gaps between them
## (勇者のくせになまいきだ style). Each block's look follows its nutrient stage
## (Balance.soil_stage): ① bare → ② a few plants → ③ lush → ④ starting to wither → ⑤ withered,
## with 3D leaf clumps, grass tufts, hanging vines and embedded pebbles as instanced decor.
## Also the packed-dirt floor and the 3D surface world. No torches are placed (not even initially).

const OUTER_SIDE := 20     # undiggable rock beyond the grid, so the camera never sees the void
const OUTER_BOTTOM := 16
const HALF := Vector3(0.485, 0.44, 0.485)   # a thin ~0.03 gap between neighbours

var grid: DungeonGrid
var block_mat: ShaderMaterial
var surface: SurfaceWorld

var _mms: Array[MultiMesh] = []
var _slot := {}  # Vector2i -> [multimesh, index]
var _seed := {}
var _anim := {}  # Vector2i -> time left (crumble)
var _hover := Vector2i(-999, -999)
var _hover_amt := 0.0
var _decor_dirty := true
var _decor_timer := 0.0
var _clumps: Array[MultiMeshInstance3D] = []
var _vines: MultiMeshInstance3D
var _tufts: MultiMeshInstance3D
var _pebbles: MultiMeshInstance3D
var _floor_rocks: MultiMeshInstance3D
var _floor_shrooms: MultiMeshInstance3D
var _floor_props := {}
var _rng := RandomNumberGenerator.new()

# leaf / straw palettes (sRGB)
const GREEN := [Color(0.46, 0.72, 0.3), Color(0.36, 0.62, 0.26), Color(0.52, 0.76, 0.36)]
const YELLOW := [Color(0.9, 0.76, 0.36), Color(0.82, 0.66, 0.3), Color(0.94, 0.82, 0.46)]


func setup(g: DungeonGrid) -> void:
	grid = g
	_rng.seed = 12345
	grid.cell_dug.connect(_on_cell_dug)
	grid.nutrient_changed.connect(_on_nutrient_changed)
	_build_materials()
	_build_blocks()
	_build_floor()
	_build_decor_layers()
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c):
				_add_floor_props(c)
	_rebuild_decor()
	surface = SurfaceWorld.new()
	add_child(surface)
	surface.build(grid, block_mat)


func _build_materials() -> void:
	block_mat = ShaderMaterial.new()
	block_mat.shader = load("res://shaders/block.gdshader")
	block_mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	block_mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	block_mat.set_shader_parameter("block_height", HALF.y * 2.0)
	block_mat.set_shader_parameter("depth_rows", float(grid.h))


# ------------------------------------------------------------------ blocks
func _variant_of(c: Vector2i) -> int:
	return absi(c.x * 73856093 ^ c.y * 19349663) % 3


func _build_blocks() -> void:
	# 3 shape variants x (detailed inner grid, cheap outer rock ring) + row 0, which is not
	# drawn as blocks: SurfaceWorld builds it as a stone rampart with the gate
	var lists: Array = [[], [], [], [], [], [], []]
	for y in range(0, grid.h + OUTER_BOTTOM):
		for x in range(-OUTER_SIDE, grid.w + OUTER_SIDE):
			var c := Vector2i(x, y)
			if y == 0:
				lists[6].append(c)
			else:
				lists[_variant_of(c) + (0 if grid.in_bounds(c) else 3)].append(c)
	for i in 6:
		var outer := i >= 3
		var mesh := ProcGen.rounded_box(HALF, 0.085, 200 + (i % 3) * 31, 0.012, 0.03, 0 if outer else 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		var cells: Array = lists[i]
		mm.instance_count = cells.size()
		_mms.append(mm)
		for k in cells.size():
			var c: Vector2i = cells[k]
			_slot[c] = [mm, k]
			_seed[c] = _rng.randf()
			_write_instance(c)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = block_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if outer else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.layers = RenderLayers.DUNGEON
		add_child(mmi)


func _kind_of(c: Vector2i) -> float:
	if not grid.in_bounds(c) or grid.get_type(c) == DungeonGrid.BEDROCK:
		return 1.0
	return 0.0


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
	var sd: float = _seed.get(c, 0.5)
	if s <= 0.0:
		mm.set_instance_transform(sv[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(c.x + 0.5, -5, c.y + 0.5)))
	else:
		# hand-placed feel: a slight twist and height variation; crumbling blocks sink and shrink
		var basis := Basis(Vector3.UP, (sd - 0.5) * 0.08).scaled(Vector3(lerpf(0.6, 1.0, s), s * (0.97 + sd * 0.06), lerpf(0.6, 1.0, s)))
		mm.set_instance_transform(sv[1], Transform3D(basis, Vector3(c.x + 0.5, HALF.y * s, c.y + 0.5)))
	var hover := _hover_amt if c == _hover else 0.0
	var n := grid.get_nutrient(c) if grid.in_bounds(c) else 0
	mm.set_instance_custom_data(sv[1], Color(float(n) / 16.0, sd, hover, _kind_of(c)))


func _on_cell_dug(c: Vector2i) -> void:
	_anim[c] = 0.22
	_decor_dirty = true
	if not _floor_props.has(c):
		_add_floor_props(c)


func _on_nutrient_changed(c: Vector2i) -> void:
	_write_instance(c)
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


# ------------------------------------------------------------------ decor
func _build_decor_layers() -> void:
	var plant := ProcGen.plant_material()
	for i in 3:
		_clumps.append(_mmi(ProcGen.leaf_clump_mesh(31 + i * 7), plant, true))
	_vines = _mmi(ProcGen.vine_chain_mesh(5), plant, true)
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_texture = ProcGen.grass_texture(true)
	grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_mat.alpha_scissor_threshold = 0.4
	grass_mat.cull_mode = BaseMaterial3D.CULL_BACK
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.vertex_color_is_srgb = true
	grass_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	grass_mat.roughness = 1.0
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tufts = _mmi(ProcGen.tuft_mesh(0.26, 0.22), grass_mat, true)
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.vertex_color_is_srgb = true
	stone.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	stone.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	stone.roughness = 1.0
	_pebbles = _mmi(ProcGen.rock_mesh(9), stone, true)
	_floor_rocks = _mmi(ProcGen.rock_mesh(4), stone, true)
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
	if r.randf() < 0.06:
		var s2 := r.randf_range(0.6, 1.0)
		var p2 := Vector3(c.x + 0.5 + r.randf_range(0.15, 0.35) * (1 if r.randf() < 0.5 else -1), 0.0, c.y + r.randf_range(0.2, 0.8))
		props.append(["shroom", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s2), p2)])
	_floor_props[c] = props


func _pick(arr: Array, r: RandomNumberGenerator) -> Color:
	return arr[r.randi() % arr.size()]


## Point on the rounded top of a block (the mesh domes up slightly toward the middle).
func _top_point(c: Vector2i, r: RandomNumberGenerator, spread: float = 0.3) -> Vector3:
	var o := Vector2(r.randf_range(-spread, spread), r.randf_range(-spread, spread))
	var dome := 0.035 * (1.0 - clampf(o.length() / 0.45, 0.0, 1.0))
	return Vector3(c.x + 0.5 + o.x, HALF.y * 2.0 + dome - 0.01, c.y + 0.5 + o.y)


func _stage_color(stage: int, r: RandomNumberGenerator) -> Color:
	match stage:
		1, 2:
			return _pick(GREEN, r)
		3:
			return _pick(GREEN, r) if r.randf() < 0.5 else _pick(YELLOW, r)
	return _pick(YELLOW, r)


func _rebuild_decor() -> void:
	_decor_dirty = false
	var clump_x: Array = [[], [], []]
	var clump_c: Array = [[], [], []]
	var vine_x: Array = []
	var vine_c: Array = []
	var tuft_x: Array = []
	var tuft_c: Array = []
	var peb_x: Array = []
	var peb_c: Array = []
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c) or _anim.has(c):
				continue
			var r := RandomNumberGenerator.new()
			r.seed = hash(c) * 31 + 7
			if grid.get_type(c) == DungeonGrid.BEDROCK:
				continue
			var stage := Balance.soil_stage(grid.get_nutrient(c))
			# leaves and grass on top
			var clumps: int = [0, 0, 6, 6, 6][stage]
			var tufts: int = [0, 2, 1, 1, 2][stage]
			for i in clumps:
				var v := r.randi() % 3
				var s := r.randf_range(0.85, 1.25)
				clump_x[v].append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), _top_point(c, r, 0.27)))
				clump_c[v].append(_stage_color(stage, r))
			for i in tufts:
				tuft_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * r.randf_range(0.8, 1.2)), _top_point(c, r)))
				tuft_c.append(_stage_color(stage, r))
			# vines hang over edges that face a passage
			var per_side: int = [0, 1, 2, 2, 2][stage]
			for d in DungeonGrid.DIRS:
				if not grid.is_floor(c + d):
					continue
				for i in per_side:
					if stage == 1 and r.randf() < 0.5:
						continue
					var nrm := Vector3(d.x, 0, d.y)
					var side := Vector3(-d.y, 0, d.x)
					var pos := Vector3(c.x + 0.5, HALF.y * 2.0 - 0.03, c.y + 0.5) + nrm * (HALF.x + 0.012) + side * r.randf_range(-0.3, 0.3)
					var basis := Basis.looking_at(-nrm, Vector3.UP).scaled(Vector3(1, r.randf_range(0.55, 1.1) * (0.6 if stage == 1 else 1.0), 1))
					vine_x.append(Transform3D(basis, pos))
					vine_c.append(_stage_color(stage, r))
			# pebbles pressed into the clay (one on top of bare soil, the rest on the sides)
			var peb: int = [3, 2, 1, 1, 2][stage]
			for i in peb:
				var p: Vector3
				if stage == 0 and i == 0:
					p = _top_point(c, r, 0.25) - Vector3(0, 0.02, 0)
				else:
					var d2: Vector2i = DungeonGrid.DIRS[r.randi() % 4]
					var n2 := Vector3(d2.x, 0, d2.y)
					p = Vector3(c.x + 0.5, r.randf_range(0.18, 0.62), c.y + 0.5) + n2 * (HALF.x - 0.005) + Vector3(-d2.y, 0, d2.x) * r.randf_range(-0.3, 0.3)
				var ps := r.randf_range(0.11, 0.15)
				peb_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(ps, ps * 0.8, ps)), p))
				peb_c.append(Color(0.5, 0.49, 0.5).darkened(r.randf() * 0.15))
	for v in 3:
		_fill(_clumps[v].multimesh, clump_x[v], clump_c[v])
	_fill(_vines.multimesh, vine_x, vine_c)
	_fill(_tufts.multimesh, tuft_x, tuft_c)
	_fill(_pebbles.multimesh, peb_x, peb_c)
	var rock_x: Array = []
	var rock_c: Array = []
	var shroom_x: Array = []
	for c in _floor_props:
		for pr in _floor_props[c]:
			if pr[0] == "rock":
				rock_x.append(pr[1])
				rock_c.append(Color(0.5, 0.46, 0.42))
			else:
				shroom_x.append(pr[1])
	_fill(_floor_rocks.multimesh, rock_x, rock_c)
	_fill(_floor_shrooms.multimesh, shroom_x, [])


func _fill(mm: MultiMesh, xs: Array, cs: Array) -> void:
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors and i < cs.size():
			mm.set_instance_color(i, cs[i])
