class_name DungeonView
extends Node3D
## Renders approved six-face voxel blocks with nutrient-selected embedded atlases.
## Chunk MultiMeshes keep updates cheap; floor props and the surface world remain separate.

const OUTER_SIDE := 20     # undiggable rock beyond the grid, so the camera never sees the void
const OUTER_BOTTOM := 16
const HALF := Vector3(0.4925, 0.44, 0.4925) # a thin ~0.015 gap between neighbours
const CHUNK := 10
const DECOR_INTERVAL := 0.25   # seconds between decor rebuilds of dirty chunks

var grid: DungeonGrid
var block_mat: ShaderMaterial
var surface: SurfaceWorld

var _slot := {}  # Vector2i -> [multimesh, index]
var _nutrient_of := {}  # last solid block color; retained during crumble
var _seed := {}
var _anim := {}  # Vector2i -> time left (crumble)
var _egg_anim := {}  # crumbling cells that were egg blocks (they keep the egg look while they sink)
var _hover := Vector2i(-999, -999)
var _hover_amt := 0.0
var _rng := RandomNumberGenerator.new()
var _chunks := {}          # Vector2i -> Chunk
var _dirty := {}           # chunk keys whose decor needs a rebuild
var _decor_timer := 0.0
var _floor_rocks: MultiMeshInstance3D
var _floor_shrooms: MultiMeshInstance3D
var _floor_props := {}
var _floor_dirty := false


class Chunk:
	var node: Node3D
	var cells: Array[Vector2i] = []   # cells inside the grid (these carry decor)
	var decor := {}                   # layer -> MultiMesh


func setup(g: DungeonGrid) -> void:
	grid = g
	_rng.seed = 12345
	grid.cell_dug.connect(_on_cell_dug)
	grid.nutrient_changed.connect(_on_nutrient_changed)
	_build_materials()
	_build_decor_resources()
	_build_blocks()
	_build_floor()
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c):
				_add_floor_props(c)
	for k in _chunks:
		_rebuild_chunk_decor(k)
	_rebuild_floor_props()
	surface = SurfaceWorld.new()
	add_child(surface)
	surface.build(grid, block_mat)


func _build_materials() -> void:
	block_mat = VoxelBlockCatalog.material()

# ------------------------------------------------------------------ chunks & blocks
func _chunk_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / CHUNK), floori(float(c.y) / CHUNK))


func _get_chunk(k: Vector2i) -> Chunk:
	if not _chunks.has(k):
		var ch := Chunk.new()
		ch.node = Node3D.new()
		ch.node.name = "Chunk_%d_%d" % [k.x, k.y]
		add_child(ch.node)
		_chunks[k] = ch
	return _chunks[k]


func _build_blocks() -> void:
	# All approved stages have byte-identical geometry and UVs. Share the mesh.
	var block_mesh := VoxelBlockCatalog.mesh()
	var lists := {}   # chunk -> mesh index -> cells
	for y in range(1, grid.h + OUTER_BOTTOM):
		for x in range(-OUTER_SIDE, grid.w + OUTER_SIDE):
			var c := Vector2i(x, y)
			var k := _chunk_of(c)
			var ch := _get_chunk(k)
			if grid.in_bounds(c):
				ch.cells.append(c)
			var i := 0 if grid.in_bounds(c) else 1
			if not lists.has(k):
				lists[k] = {}
			if not lists[k].has(i):
				lists[k][i] = []
			lists[k][i].append(c)
	for k in lists:
		var ch: Chunk = _chunks[k]
		for i in lists[k]:
			var cells: Array = lists[k][i]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = block_mesh
			mm.instance_count = cells.size()
			for n in cells.size():
				var c: Vector2i = cells[n]
				_slot[c] = [mm, n]
				_seed[c] = _rng.randf()
				_write_instance(c)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = block_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if i == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.layers = RenderLayers.DUNGEON
			ch.node.add_child(mmi)


func _kind_of(c: Vector2i) -> float:
	if not grid.in_bounds(c) or grid.get_type(c) == DungeonGrid.BEDROCK:
		return 1.0
	if grid.is_egg(c) or _egg_anim.has(c):
		return 0.5
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
		# Quarter turns preserve the authored 0.03 m gap; crumbling still sinks and shrinks.
		var basis := Basis(Vector3.UP, floorf(sd * 4.0) * PI * 0.5).scaled(Vector3(lerpf(0.6, 1.0, s), s, lerpf(0.6, 1.0, s)))
		mm.set_instance_transform(sv[1], Transform3D(basis, Vector3(c.x + 0.5, HALF.y * s, c.y + 0.5)))
	var hover := _hover_amt if c == _hover else 0.0
	var n := grid.get_nutrient(c) if grid.in_bounds(c) else 0
	if _anim.has(c):
		n = _nutrient_of.get(c, n)
	elif solid:
		_nutrient_of[c] = n
	else:
		_nutrient_of.erase(c)
	mm.set_instance_custom_data(sv[1], Color(minf(float(n), 16.0) / 16.0, sd, hover, _kind_of(c)))


func _on_cell_dug(c: Vector2i) -> void:
	_anim[c] = 0.22
	if grid.last_dug_egg:
		_egg_anim[c] = true
	# the dug block loses its decor, and its neighbours grow vines over the new edge
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_dirty[_chunk_of(c + d)] = true
	if not _floor_props.has(c):
		_add_floor_props(c)
		_floor_dirty = true


func _on_nutrient_changed(c: Vector2i) -> void:
	_write_instance(c)
	# decor only changes when the soil crosses into another stage
	var stage := Balance.soil_stage(grid.get_nutrient(c))
	if int(_stage_of.get(c, -1)) != stage:
		_dirty[_chunk_of(c)] = true


func set_hover(c: Vector2i, amount: float) -> void:
	if c == _hover and is_equal_approx(amount, _hover_amt):
		return
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
				_egg_anim.erase(c)
				_dirty[_chunk_of(c)] = true
			_write_instance(c)
	_decor_timer -= delta
	if _decor_timer <= 0.0 and (not _dirty.is_empty() or _floor_dirty):
		_decor_timer = DECOR_INTERVAL
		for k in _dirty.keys():
			if _chunks.has(k):
				_rebuild_chunk_decor(k)
		_dirty.clear()
		if _floor_dirty:
			_rebuild_floor_props()


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
func _build_decor_resources() -> void:
	# Authored voxel blocks have no extra leaves, tufts, vines or embedded pebbles.
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.vertex_color_is_srgb = true
	stone.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	stone.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	stone.roughness = 1.0
	_floor_rocks = _mmi(ProcGen.rock_mesh(4), stone, true, self)
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("e8dcc0")
	stem.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("d9a441")
	cap.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	cap.emission_enabled = true
	cap.emission = Color("ffb84a")
	cap.emission_energy_multiplier = 0.9
	_floor_shrooms = _mmi(ProcGen.mushroom_mesh(stem, cap), null, false, self)


func _mmi(mesh: Mesh, mat: Material, colors: bool, parent: Node) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	# decor is small: it does not need to cast shadows
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


var _stage_of := {}   # Vector2i -> soil stage the decor was last built for


## Keep stage tracking/debug rebuild hooks; the block texture updates immediately.
func _rebuild_chunk_decor(k: Vector2i) -> void:
	var ch: Chunk = _chunks[k]
	for c in ch.cells:
		if grid.is_block(c) and not _anim.has(c):
			_stage_of[c] = Balance.soil_stage(grid.get_nutrient(c))
		else:
			_stage_of.erase(c)


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


func _rebuild_floor_props() -> void:
	_floor_dirty = false
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


## Full rebuild of every chunk's decor (debug / timing only; the game rebuilds dirty chunks).
func _rebuild_decor() -> void:
	for k in _chunks:
		_rebuild_chunk_decor(k)
	_rebuild_floor_props()


func _fill(mm: MultiMesh, xs: Array, cs: Array) -> void:
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		if mm.use_colors and i < cs.size():
			mm.set_instance_color(i, cs[i])
