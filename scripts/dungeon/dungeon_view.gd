class_name DungeonView
extends Node3D
## Renders the DungeonGrid: soil blocks (MultiMesh, 3 shape variants), floor, moss decor,
## torches, the entrance arch and the pixel-art town backdrop.

const VARIANTS := 3
const HALF := Vector3(0.485, Balance.BLOCK_H * 0.5, 0.485)
# undiggable rock filling the view beyond the grid (so the camera never sees the void)
const OUTER_SIDE := 20
const OUTER_BOTTOM := 16

var grid: DungeonGrid
var block_mat: ShaderMaterial
var _mm: Array[MultiMesh] = []
var _slot := {}  # Vector2i -> [variant, index]
var _seed := {}  # Vector2i -> float
var _anim := {}  # Vector2i -> time left (crumble)
var _hover := Vector2i(-999, -999)
var _hover_amt := 0.0
var _decor_dirty := true
var _decor_timer := 0.0
var _tufts: MultiMeshInstance3D
var _vines: MultiMeshInstance3D
var _floor_rocks: MultiMeshInstance3D
var _floor_shrooms: MultiMeshInstance3D
var _floor_props := {}  # Vector2i -> Array of [kind, Transform3D]
var torches := {}  # Vector2i -> Node3D
var _rng := RandomNumberGenerator.new()


func setup(g: DungeonGrid) -> void:
	grid = g
	_rng.seed = 12345
	grid.cell_dug.connect(_on_cell_dug)
	grid.nutrient_changed.connect(_on_nutrient_changed)
	_build_materials()
	_build_blocks()
	_build_floor()
	_build_decor_layers()
	_build_entrance()
	_build_backdrop()
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c):
				_add_floor_props(c)
	_auto_torches_initial()
	_rebuild_decor()


func _build_materials() -> void:
	block_mat = ShaderMaterial.new()
	block_mat.shader = load("res://shaders/block.gdshader")
	block_mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	block_mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	block_mat.set_shader_parameter("block_height", Balance.BLOCK_H)


# ------------------------------------------------------------------ blocks
func _cells_to_render() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(0, grid.h + OUTER_BOTTOM):
		for x in range(-OUTER_SIDE, grid.w + OUTER_SIDE):
			out.append(Vector2i(x, y))
	return out


func _variant_of(c: Vector2i) -> int:
	return absi(c.x * 73856093 ^ c.y * 19349663) % VARIANTS


func _build_blocks() -> void:
	var cells := _cells_to_render()
	# slots 0..2: diggable grid (detailed, casts shadows); 3..5: filler rock outside the grid (cheap)
	var per_variant: Array = [[], [], [], [], [], []]
	for c in cells:
		per_variant[_variant_of(c) + (0 if grid.in_bounds(c) else VARIANTS)].append(c)
	for v in VARIANTS * 2:
		var outer := v >= VARIANTS
		var mesh := ProcGen.rounded_box(HALF, 0.075, 100 + (v % VARIANTS) * 17, 0.012, 0.02, 0 if outer else 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		var list: Array = per_variant[v]
		mm.instance_count = list.size()
		_mm.append(mm)
		for i in list.size():
			var c: Vector2i = list[i]
			_slot[c] = [v, i]
			_seed[c] = _rng.randf()
			_write_instance(c)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = block_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if outer else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


func _is_solid_visual(c: Vector2i) -> bool:
	if grid.in_bounds(c):
		return not grid.is_floor(c)
	return true


func _block_xform(c: Vector2i, scale: float) -> Transform3D:
	var s: float = _seed.get(c, 0.5)
	var hgt := 1.0 + (s - 0.5) * 0.08
	var basis := Basis(Vector3.UP, (s - 0.5) * 0.06).scaled(Vector3(scale, hgt * scale, scale))
	return Transform3D(basis, Vector3(c.x + 0.5, HALF.y * hgt * scale, c.y + 0.5))


func _custom_of(c: Vector2i) -> Color:
	var s: float = _seed.get(c, 0.5)
	var hover := _hover_amt if c == _hover else 0.0
	if not grid.in_bounds(c):
		# the surface row stays grassy, everything else is bare rock
		return Color(0.55, s, 0.0, 0.0) if c.y == 0 else Color(0.0, s, 0.0, 1.0)
	var t := grid.get_type(c)
	if t == DungeonGrid.BEDROCK:
		# top row is grassy ground at the surface; other borders are bare rock
		return Color(0.55, s, hover, 0.0) if c.y == 0 else Color(0.0, s, hover, 1.0)
	var n := grid.get_nutrient(c)
	return Color(clampf(float(n) / Balance.MAX_NUTRIENT, 0.0, 1.0), s, hover, 0.0)


func _write_instance(c: Vector2i) -> void:
	if not _slot.has(c):
		return
	var sv: Array = _slot[c]
	var mm: MultiMesh = _mm[sv[0]]
	var scale := 1.0
	if _anim.has(c):
		scale = maxf(0.001, _anim[c] / 0.22)
	elif not _is_solid_visual(c):
		scale = 0.0
	if scale <= 0.0:
		mm.set_instance_transform(sv[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(c.x + 0.5, -5, c.y + 0.5)))
	else:
		mm.set_instance_transform(sv[1], _block_xform(c, scale))
	mm.set_instance_custom_data(sv[1], _custom_of(c))


func _on_cell_dug(c: Vector2i) -> void:
	_anim[c] = 0.22
	_decor_dirty = true
	if _floor_props.is_empty() or not _floor_props.has(c):
		_add_floor_props(c)
	_maybe_torch(c)


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
	pm.size = Vector2(grid.w + OUTER_SIDE * 2, grid.h + OUTER_BOTTOM + 2)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/floor.gdshader")
	mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	mi.material_override = mat
	mi.position = Vector3(grid.w * 0.5, 0.0, (grid.h + OUTER_BOTTOM) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ decor
func _build_decor_layers() -> void:
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_texture = ProcGen.grass_texture()
	grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grass_mat.alpha_scissor_threshold = 0.4
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.roughness = 0.9
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tufts = _mmi(ProcGen.tuft_mesh(), grass_mat, true)
	var vine_mat := grass_mat.duplicate() as StandardMaterial3D
	vine_mat.albedo_texture = ProcGen.vine_texture()
	_vines = _mmi(ProcGen.vine_mesh(), vine_mat, true)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.roughness = 0.85
	_floor_rocks = _mmi(ProcGen.rock_mesh(4), rock_mat, true)
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("efe4c8")
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("d8453a")
	cap.roughness = 0.5
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
	if r.randf() < 0.28:
		var s := r.randf_range(0.08, 0.16)
		var p := Vector3(c.x + r.randf_range(0.2, 0.8), 0.0, c.y + r.randf_range(0.2, 0.8))
		props.append(["rock", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), p)])
	if r.randf() < 0.1:
		var s2 := r.randf_range(0.7, 1.3)
		var p2 := Vector3(c.x + r.randf_range(0.2, 0.8), 0.0, c.y + r.randf_range(0.2, 0.8))
		props.append(["shroom", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s2), p2)])
	_floor_props[c] = props


func _rebuild_decor() -> void:
	_decor_dirty = false
	var tuft_x: Array[Transform3D] = []
	var tuft_c: Array[Color] = []
	var vine_x: Array[Transform3D] = []
	var vine_c: Array[Color] = []
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c) or _anim.has(c):
				continue
			var n := grid.get_nutrient(c)
			if y == 0:
				n = 9
			if n < 3:
				continue
			var r := RandomNumberGenerator.new()
			r.seed = hash(c) * 31 + n
			var top := Balance.BLOCK_H * (1.0 + (float(_seed.get(c, 0.5)) - 0.5) * 0.08)
			var count := clampi((n - 3) / 3, 0, 4)
			for i in count:
				var p := Vector3(c.x + r.randf_range(0.15, 0.85), top - 0.01, c.y + r.randf_range(0.15, 0.85))
				var s := r.randf_range(0.7, 1.25) * (0.7 + n / 30.0)
				tuft_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), p))
				tuft_c.append(Color.from_hsv(r.randf_range(0.18, 0.26), 0.35, r.randf_range(1.0, 1.25)))
			if n >= 6:
				for d in DungeonGrid.DIRS:
					if not grid.is_floor(c + d):
						continue
					var vines := 1 if n < 11 else 2
					for k in vines:
						var along := r.randf_range(-0.28, 0.28)
						var normal := Vector3(d.x, 0, d.y)
						var side := Vector3(-d.y, 0, d.x)
						var pos := Vector3(c.x + 0.5, top - 0.02, c.y + 0.5) + normal * (HALF.x + 0.012) + side * along
						var basis := Basis.looking_at(-normal, Vector3.UP).scaled(Vector3(r.randf_range(0.8, 1.2), r.randf_range(0.5, 1.0) * (0.6 + n / 20.0), 1))
						vine_x.append(Transform3D(basis, pos))
						vine_c.append(Color.from_hsv(r.randf_range(0.22, 0.28), 0.4, r.randf_range(0.8, 1.0)))
	_fill(_tufts.multimesh, tuft_x, tuft_c)
	_fill(_vines.multimesh, vine_x, vine_c)
	var rock_x: Array[Transform3D] = []
	var rock_c: Array[Color] = []
	var shroom_x: Array[Transform3D] = []
	for c in _floor_props:
		for pr in _floor_props[c]:
			if pr[0] == "rock":
				rock_x.append(pr[1])
				rock_c.append(Color(0.55, 0.5, 0.46).lightened(randf() * 0.1))
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
	torch.position = Vector3(c.x + 0.5 + d.x * 0.34, 0, c.y + 0.5 + d.y * 0.34)
	add_child(torch)
	torches[c] = torch


# ------------------------------------------------------------------ entrance & town
func _build_entrance() -> void:
	var e := grid.entrance
	var mat := block_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("custom_override", Color(0.55, 0.3, 0.0, 0.35))
	var pillar := ProcGen.rounded_box(Vector3(0.16, 0.7, 0.3), 0.08, 9, 0.02, 0.0)
	var lintel := ProcGen.rounded_box(Vector3(0.62, 0.2, 0.34), 0.1, 10, 0.02, 0.03)
	for sx in [-1, 1]:
		var mi := MeshInstance3D.new()
		mi.mesh = pillar
		mi.material_override = mat
		mi.position = Vector3(e.x + 0.5 + sx * 0.44, 0.7, e.y + 0.2)
		add_child(mi)
	var top := MeshInstance3D.new()
	top.mesh = lintel
	top.material_override = mat
	top.position = Vector3(e.x + 0.5, 1.45, e.y + 0.2)
	add_child(top)
	# dark tunnel mouth behind the arch
	var hole := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 1.3)
	hole.mesh = q
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.03, 0.02, 0.02)
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.material_override = hm
	hole.position = Vector3(e.x + 0.5, 0.65, e.y - 0.05)
	add_child(hole)


## Hand-made backdrop: drop an image here to replace the generated town (see README).
##   town.png          pixel art (nearest filtering)
##   town_painted.png  painted / high resolution art (smooth filtering)
const BACKDROP_PIXEL := "res://assets/backdrop/town.png"
const BACKDROP_PAINTED := "res://assets/backdrop/town_painted.png"


func _build_backdrop() -> void:
	var width := float(grid.w + OUTER_SIDE * 2)
	var tex: Texture2D
	var smooth := false
	if ResourceLoader.exists(BACKDROP_PAINTED):
		tex = load(BACKDROP_PAINTED)
		smooth = true
	elif ResourceLoader.exists(BACKDROP_PIXEL):
		tex = load(BACKDROP_PIXEL)
	else:
		tex = TownBackdrop.new().generate(7, width)
	# the strip always spans the full width; its height follows the image's aspect ratio
	var height := width * float(tex.get_height()) / float(tex.get_width())
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if smooth else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex.has_alpha():
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tilt the painting back so it faces the (55° down) camera; bottom edge sits on the surface
	var tilt := deg_to_rad(-55.0)
	# image centre sits right above the dungeon entrance
	var bottom := Vector3(grid.entrance.x + 0.5, Balance.BLOCK_H + 0.02, -0.02)
	var up := Vector3(0, cos(tilt), sin(tilt))
	mi.rotation.x = tilt
	mi.position = bottom + up * height * 0.5
	add_child(mi)
