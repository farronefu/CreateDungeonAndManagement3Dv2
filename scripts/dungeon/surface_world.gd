class_name SurfaceWorld
extends Node3D
## The world above the dungeon (z < 0), built from low-poly toon geometry so it matches the
## 3D dungeon: meadow ground (same shader as the soil, so there is no seam), a dirt ramp
## down to the entrance under a mossy rock mound, the heroes' town along a road, a castle, a
## church, forests, a river with a bridge and distant mountains that fade into the sky fog.

const RAMP := 2.4          # length of the ramp from the surface down to the entrance cell
const ROAD_Z := -4.6
const GROUND_Y := Balance.BLOCK_H

var grid: DungeonGrid
var rng := RandomNumberGenerator.new()
var _occupied: Array[Rect2] = []

var _town: MeshKit
var _glow: MeshKit


## Path the hero walks when entering: road -> cave mouth -> down the ramp -> entrance cell.
func entry_path() -> PackedVector3Array:
	var x := grid.entrance.x + 0.5
	return PackedVector3Array([
		Vector3(x - 5.0, GROUND_Y, ROAD_Z),
		Vector3(x, GROUND_Y, ROAD_Z),
		Vector3(x, GROUND_Y, -RAMP - 0.3),
		Vector3(x, GROUND_Y, -RAMP),
		Vector3(x, 0.0, 0.0),
		Vector3(x, 0.0, 0.5),
	])


func build(g: DungeonGrid, block_mat: ShaderMaterial) -> void:
	grid = g
	rng.seed = 424242
	_town = MeshKit.new()
	_glow = MeshKit.new()
	_build_ground(block_mat)
	_build_ramp(block_mat)
	_build_road()
	_build_cave_mound()
	_build_river()
	_build_castle(Vector3(-3.0, GROUND_Y, -15.5))
	_build_church(Vector3(grid.w + 3.5, GROUND_Y, -10.0))
	_build_houses()
	_build_trees()
	_build_fences()
	_build_mountains()
	_emit(_town, _town_material())
	_emit(_glow, _glow_material())
	# torches flanking the cave mouth
	for sx in [-0.25, 1.25]:
		var t := Torch.new()
		t.light_scale = 0.55
		t.position = Vector3(grid.entrance.x + sx, GROUND_Y, -RAMP + 0.35)
		add_child(t)


func _emit(kit: MeshKit, mat: Material) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit()
	mi.material_override = mat
	add_child(mi)


func _town_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _glow_material() -> StandardMaterial3D:
	var m := _town_material()
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.36)
	m.emission_energy_multiplier = 1.6
	return m


func _free(r: Rect2) -> bool:
	for o in _occupied:
		if o.intersects(r):
			return false
	return true


# ------------------------------------------------------------------ ground & ramp
func _build_ground(block_mat: ShaderMaterial) -> void:
	var ex := float(grid.entrance.x)
	var x0 := -float(DungeonView.OUTER_SIDE)
	var x1 := float(grid.w + DungeonView.OUTER_SIDE)
	var z0 := -46.0
	var mat := block_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("custom_override", Color(0, 0.5, 0, 0))
	# three slabs leave a slot for the ramp
	for r in [Rect2(x0, z0, ex - x0, -z0), Rect2(ex + 1.0, z0, x1 - ex - 1.0, -z0), Rect2(ex, z0, 1.0, -z0 - RAMP)]:
		var pm := PlaneMesh.new()
		pm.size = r.size
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(r.position.x + r.size.x * 0.5, GROUND_Y, r.position.y + r.size.y * 0.5)
		add_child(mi)
	# the far plains, fading into fog
	var far := PlaneMesh.new()
	far.size = Vector2(600, 400)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.4, 0.5, 0.27)
	fm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	fm.roughness = 1.0
	var fmi := MeshInstance3D.new()
	fmi.mesh = far
	fmi.material_override = fm
	fmi.position = Vector3(grid.w * 0.5, GROUND_Y - 0.02, z0 - 200 + 0.5)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	# sides of the dungeon rock body, for low camera angles
	for sx in [x0 - 200.0, x1 + 200.0]:
		var side := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(400, 460)
		side.mesh = sp
		side.material_override = fm
		side.position = Vector3(sx, GROUND_Y - 0.02, 0)
		add_child(side)


func _build_ramp(block_mat: ShaderMaterial) -> void:
	var ex := float(grid.entrance.x)
	# sloped packed-dirt path
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/floor.gdshader")
	floor_mat.set_shader_parameter("noise_a", ProcGen.noise_a())
	floor_mat.set_shader_parameter("noise_b", ProcGen.noise_b())
	floor_mat.set_shader_parameter("depth_rows", float(grid.h))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(ex, GROUND_Y, -RAMP)
	var b := Vector3(ex + 1, GROUND_Y, -RAMP)
	var c := Vector3(ex + 1, 0, 0)
	var d := Vector3(ex, 0, 0)
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0:
		n = -n
	# both windings, so the quad shows whichever way the camera looks at it
	for v in [a, b, c, a, c, d, a, c, b, a, d, c]:
		st.set_normal(n)
		st.add_vertex(v)
	var ramp := MeshInstance3D.new()
	ramp.mesh = st.commit()
	ramp.material_override = floor_mat
	add_child(ramp)
	# soil walls either side of the ramp (strata come from the block shader)
	var wall_mat := block_mat.duplicate() as ShaderMaterial
	wall_mat.set_shader_parameter("custom_override", Color(0, 0.5, 0, 0))
	var wk := SurfaceTool.new()
	wk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [[ex, 1.0], [ex + 1.0, -1.0]]:
		var x: float = side[0]
		var nx: float = side[1]
		var p0 := Vector3(x, GROUND_Y, -RAMP)
		var p1 := Vector3(x, GROUND_Y, 0)
		var p2 := Vector3(x, 0, 0)
		for v in [p0, p1, p2, p0, p2, p1]:
			wk.set_normal(Vector3(nx, 0, 0))
			wk.add_vertex(v)
	var walls := MeshInstance3D.new()
	walls.mesh = wk.commit()
	walls.material_override = wall_mat
	add_child(walls)
	_occupied.append(Rect2(ex - 1.5, -RAMP - 2.0, 4.0, RAMP + 2.0))


func _build_road() -> void:
	var x0 := -float(DungeonView.OUTER_SIDE)
	var x1 := float(grid.w + DungeonView.OUTER_SIDE)
	var y := GROUND_Y + 0.012
	var dirt := Color(0.66, 0.54, 0.38)
	var edge := Color(0.55, 0.44, 0.3)
	var x := x0
	while x < x1:
		var w := 1.0
		var wob := sin(x * 0.35) * 0.12
		var z0 := ROAD_Z - 0.6 + wob
		var z1 := ROAD_Z + 0.6 + wob
		_town.quad(Vector3(x, y, z0), Vector3(x + w, y, z0 + 0.03), Vector3(x + w, y, z1 + 0.03), Vector3(x, y, z1), dirt.lerp(edge, rng.randf() * 0.3), Vector3(x, y - 1, z0))
		x += w
	# path from the road to the cave
	var ex := float(grid.entrance.x)
	_town.quad(Vector3(ex + 0.12, y, ROAD_Z), Vector3(ex + 0.88, y, ROAD_Z), Vector3(ex + 0.88, y, -RAMP - 1.1), Vector3(ex + 0.12, y, -RAMP - 1.1), dirt, Vector3(ex, y - 1, ROAD_Z))
	_occupied.append(Rect2(x0, ROAD_Z - 0.9, x1 - x0, 1.8))


## A mossy rock mound straddling the top of the ramp: the path from the road tunnels through it
## and comes out as the ramp down into the dungeon (the side the camera looks at).
func _build_cave_mound() -> void:
	var cx := float(grid.entrance.x) + 0.5
	var zm := -RAMP - 0.35
	var moss := Color(0.4, 0.52, 0.28)
	var stone := Color(0.52, 0.5, 0.46)
	var dark := Color(0.36, 0.35, 0.33)
	var y := GROUND_Y
	# flanks beside the path
	for sx in [-1.0, 1.0]:
		_town.blob(Vector3(cx + sx * 1.25, y + 0.45, zm + 0.25), Vector3(0.8, 0.8, 0.95), rng, moss, stone, 4, 8, 0.18)
		_town.blob(Vector3(cx + sx * 1.1, y + 0.8, zm - 0.55), Vector3(0.75, 0.95, 0.8), rng, moss, stone, 4, 8, 0.18)
		_town.blob(Vector3(cx + sx * 1.9, y + 0.3, zm - 0.1), Vector3(0.55, 0.5, 0.6), rng, moss, stone, 3, 7, 0.2)
	# roof of the tunnel
	_town.blob(Vector3(cx, y + 1.3, zm - 0.1), Vector3(1.15, 0.5, 1.05), rng, moss, dark, 4, 9, 0.12)
	_town.blob(Vector3(cx + 0.2, y + 1.72, zm - 0.35), Vector3(0.7, 0.4, 0.6), rng, moss, stone, 3, 8, 0.15)
	# dark mouths (camera side and road side)
	var black := Color(0.04, 0.03, 0.025)
	for side in [[zm + 0.62, 1.0], [zm - 0.9, -1.0]]:
		var z: float = side[0]
		var ref := Vector3(cx, y + 0.5, z - side[1])
		_town.quad(Vector3(cx - 0.47, y - 0.05, z), Vector3(cx + 0.47, y - 0.05, z), Vector3(cx + 0.4, y + 0.98, z), Vector3(cx - 0.4, y + 0.98, z), black, ref)
		_town.tri(Vector3(cx - 0.4, y + 0.98, z), Vector3(cx + 0.4, y + 0.98, z), Vector3(cx, y + 1.18, z), black, ref)
	# a little signpost
	_town.box(Vector3(cx + 1.0, y + 0.3, zm - 1.35), Vector3(0.05, 0.6, 0.05), Color(0.45, 0.32, 0.2))
	_town.box(Vector3(cx + 1.0, y + 0.55, zm - 1.33), Vector3(0.42, 0.2, 0.04), Color(0.62, 0.46, 0.28))
	_occupied.append(Rect2(cx - 2.6, zm - 1.6, 5.2, 2.2 - zm))


func _build_river() -> void:
	var x := -8.5
	var y := GROUND_Y + 0.008
	var water := Color(0.3, 0.52, 0.72)
	var z := 0.0
	while z > -46.0:
		var wob := sin(z * 0.3) * 0.8
		var wob2 := sin((z - 1.5) * 0.3) * 0.8
		_glow.quad(Vector3(x + wob - 0.7, y, z), Vector3(x + wob + 0.7, y, z), Vector3(x + wob2 + 0.7, y, z - 1.5), Vector3(x + wob2 - 0.7, y, z - 1.5), water, Vector3(x, y - 1, z))
		z -= 1.5
	# bridge
	var bz := ROAD_Z
	var bx := x + sin(bz * 0.3) * 0.8
	var wood := Color(0.52, 0.36, 0.22)
	_town.box(Vector3(bx, GROUND_Y + 0.08, bz), Vector3(2.0, 0.12, 1.3), wood)
	for sz in [-0.6, 0.6]:
		_town.box(Vector3(bx, GROUND_Y + 0.25, bz + sz), Vector3(2.0, 0.06, 0.06), wood.darkened(0.2))
	_occupied.append(Rect2(x - 1.6, -46, 3.2, 46))


# ------------------------------------------------------------------ buildings
const WALLS := [Color(0.93, 0.88, 0.76), Color(0.88, 0.82, 0.7), Color(0.8, 0.74, 0.64), Color(0.9, 0.85, 0.8)]
const ROOFS := [Color(0.72, 0.28, 0.2), Color(0.28, 0.4, 0.66), Color(0.8, 0.5, 0.24), Color(0.36, 0.5, 0.44), Color(0.5, 0.36, 0.28)]
const TIMBER := Color(0.4, 0.27, 0.17)


func _house(base: Vector3, w: float, d: float, facing: float) -> void:
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	var h := rng.randf_range(0.8, 1.0)
	var bs := Basis(Vector3.UP, facing)
	var fwd := bs * Vector3(0, 0, 1)
	var right := bs * Vector3(1, 0, 0)
	_town.box(base + Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, facing)
	# stone plinth
	_town.box(base + Vector3(0, 0.08, 0), Vector3(w + 0.04, 0.16, d + 0.04), Color(0.55, 0.52, 0.48), facing)
	# timber frame on the facade
	var front := base + fwd * (d * 0.5 + 0.005)
	for i in 3:
		var t := -0.5 + i * 0.5
		_town.box(front + right * (t * (w - 0.08)) + Vector3(0, h * 0.5, 0), Vector3(0.06, h, 0.02), TIMBER, facing)
	_town.box(front + Vector3(0, h * 0.62, 0), Vector3(w, 0.05, 0.02), TIMBER, facing)
	# door + lit windows
	_town.box(front + right * (-w * 0.22) + Vector3(0, 0.26, 0.01), Vector3(0.24, 0.48, 0.03), Color(0.35, 0.22, 0.13), facing)
	_glow.box(front + right * (w * 0.2) + Vector3(0, 0.44, 0.012), Vector3(0.2, 0.18, 0.02), Color(1.0, 0.8, 0.45), facing)
	_glow.box(front + right * (w * 0.2) + Vector3(0, 0.8, 0.012), Vector3(0.16, 0.14, 0.02), Color(1.0, 0.8, 0.45), facing)
	# roof along the wide side
	_town.gable(base + Vector3(0, h, 0), w + 0.24, d + 0.3, rng.randf_range(0.55, 0.75), roof, facing)
	if rng.randf() < 0.6:
		_town.box(base + right * (w * 0.28) + Vector3(0, h + 0.5, -0.1), Vector3(0.14, 0.45, 0.14), Color(0.5, 0.4, 0.36), facing)
	# flower box
	if rng.randf() < 0.5:
		for k in 4:
			_town.box(front + right * (w * 0.2 + (k - 1.5) * 0.06) + Vector3(0, 0.3, 0.05), Vector3(0.05, 0.05, 0.05), [Color(0.95, 0.45, 0.5), Color(1, 0.85, 0.35), Color(0.95, 0.95, 0.9)][k % 3], facing)


func _build_houses() -> void:
	var ex := float(grid.entrance.x)
	var rows := [[ROAD_Z - 2.1, 0.0], [ROAD_Z - 5.2, 0.0], [-2.0, PI]]
	for row in rows:
		var z: float = row[0]
		var facing: float = row[1]
		var x := -DungeonView.OUTER_SIDE + 1.5
		while x < grid.w + DungeonView.OUTER_SIDE - 2:
			var w := rng.randf_range(1.3, 1.9)
			var d := rng.randf_range(1.0, 1.3)
			var r := Rect2(x - w * 0.5 - 0.3, z - d * 0.5 - 0.3, w + 0.6, d + 0.6)
			var skip := rng.randf() < (0.35 if row == rows[2] else 0.18)
			if not skip and _free(r) and absf(x - ex) > 3.2:
				_house(Vector3(x, GROUND_Y, z + rng.randf_range(-0.3, 0.3)), w, d, facing)
				_occupied.append(r)
			x += w + rng.randf_range(0.9, 2.2)


func _build_castle(p: Vector3) -> void:
	var stone := Color(0.72, 0.71, 0.7)
	var stone_d := Color(0.6, 0.59, 0.6)
	var roof := Color(0.3, 0.38, 0.62)
	var W := 7.0
	var D := 5.0
	# curtain walls
	for s in [[Vector3(0, 0, D * 0.5), Vector3(W, 1.5, 0.4)], [Vector3(0, 0, -D * 0.5), Vector3(W, 1.5, 0.4)], [Vector3(W * 0.5, 0, 0), Vector3(0.4, 1.5, D)], [Vector3(-W * 0.5, 0, 0), Vector3(0.4, 1.5, D)]]:
		_town.box(p + s[0] + Vector3(0, 0.75, 0), s[1], stone)
		# crenellations
		var span: float = maxf(s[1].x, s[1].z)
		var along := Vector3(1, 0, 0) if s[1].x > s[1].z else Vector3(0, 0, 1)
		var n := int(span / 0.5)
		for i in n:
			if i % 2 == 0:
				_town.box(p + s[0] + along * (-span * 0.5 + 0.25 + i * 0.5) + Vector3(0, 1.62, 0), Vector3(0.25, 0.25, 0.42) if along.x > 0 else Vector3(0.42, 0.25, 0.25), stone_d)
	# towers
	for c in [Vector3(-W, 0, -D), Vector3(W, 0, -D), Vector3(-W, 0, D), Vector3(W, 0, D)]:
		var tp: Vector3 = p + c * 0.5
		_town.cylinder(tp, 0.75, 2.6, stone, 10)
		_town.cone(tp + Vector3(0, 2.6, 0), 0.95, 1.6, roof, 10)
		_glow.box(tp + Vector3(0, 1.9, 0.76), Vector3(0.14, 0.3, 0.02), Color(1.0, 0.8, 0.45))
		_town.box(tp + Vector3(0, 4.5, 0), Vector3(0.04, 0.7, 0.04), Color(0.3, 0.25, 0.2))
		_town.box(tp + Vector3(0.22, 4.7, 0), Vector3(0.4, 0.24, 0.02), Color(0.85, 0.2, 0.18))
	# keep
	_town.box(p + Vector3(0, 1.6, -0.4), Vector3(3.0, 3.2, 2.4), stone_d)
	_town.gable(p + Vector3(0, 3.2, -0.4), 3.3, 2.7, 1.2, roof)
	for i in 3:
		_glow.box(p + Vector3(-0.9 + i * 0.9, 2.3, 0.81), Vector3(0.18, 0.34, 0.02), Color(1.0, 0.8, 0.45))
	# gate
	_town.box(p + Vector3(0, 0.55, D * 0.5 + 0.21), Vector3(1.0, 1.1, 0.04), Color(0.3, 0.2, 0.12))
	_occupied.append(Rect2(p.x - W * 0.5 - 1.2, p.z - D * 0.5 - 1.2, W + 2.4, D + 2.4))


func _build_church(p: Vector3) -> void:
	var wall := Color(0.86, 0.84, 0.8)
	var roof := Color(0.3, 0.38, 0.6)
	_town.box(p + Vector3(0, 0.8, 0), Vector3(2.0, 1.6, 3.2), wall)
	_town.gable(p + Vector3(0, 1.6, 0), 3.5, 2.4, 1.1, roof, PI * 0.5)
	# bell tower in front
	var tp := p + Vector3(0, 0, 1.9)
	_town.box(tp + Vector3(0, 1.5, 0), Vector3(1.0, 3.0, 1.0), wall.darkened(0.05))
	_town.pyramid(tp + Vector3(0, 3.0, 0), 1.2, 1.3, roof)
	_town.box(tp + Vector3(0, 4.55, 0), Vector3(0.06, 0.5, 0.06), Color(0.95, 0.8, 0.3))
	_town.box(tp + Vector3(0, 4.62, 0), Vector3(0.3, 0.06, 0.06), Color(0.95, 0.8, 0.3))
	_glow.box(tp + Vector3(0, 2.3, 0.51), Vector3(0.3, 0.42, 0.02), Color(1.0, 0.85, 0.5))
	_town.box(tp + Vector3(0, 0.4, 0.51), Vector3(0.4, 0.8, 0.02), Color(0.35, 0.22, 0.13))
	_occupied.append(Rect2(p.x - 2.2, p.z - 2.4, 4.4, 5.4))


# ------------------------------------------------------------------ nature
func _tree(p: Vector3, s: float) -> void:
	var trunk := Color(0.42, 0.29, 0.18)
	_town.cylinder(p, 0.09 * s, 0.5 * s, trunk, 6)
	var g := Color(0.28, 0.5, 0.22).lerp(Color(0.4, 0.58, 0.24), rng.randf())
	for i in 3:
		var o := Vector3(rng.randf_range(-0.25, 0.25), 0.7 + i * 0.18, rng.randf_range(-0.25, 0.25)) * s
		_town.blob(p + o, Vector3.ONE * rng.randf_range(0.38, 0.5) * s, rng, g.lightened(0.12), g.darkened(0.25), 3, 7, 0.15)


func _pine(p: Vector3, s: float) -> void:
	_town.cylinder(p, 0.08 * s, 0.35 * s, Color(0.4, 0.28, 0.18), 5)
	var g := Color(0.2, 0.4, 0.26).lerp(Color(0.26, 0.46, 0.28), rng.randf())
	for i in 3:
		_town.cone(p + Vector3(0, (0.3 + i * 0.42) * s, 0), (0.62 - i * 0.16) * s, 0.75 * s, g.lightened(i * 0.05), 7)


func _build_trees() -> void:
	var x0 := -float(DungeonView.OUTER_SIDE)
	var x1 := float(grid.w + DungeonView.OUTER_SIDE)
	# scattered in town
	for i in 90:
		var p := Vector3(rng.randf_range(x0, x1), GROUND_Y, rng.randf_range(-15.0, -0.8))
		var s := rng.randf_range(0.8, 1.2)
		if _free(Rect2(p.x - 0.5, p.z - 0.5, 1.0, 1.0)):
			if rng.randf() < 0.7:
				_tree(p, s)
			else:
				_pine(p, s)
			_occupied.append(Rect2(p.x - 0.4, p.z - 0.4, 0.8, 0.8))
	# forest belt behind the town
	for i in 320:
		var p2 := Vector3(rng.randf_range(x0 - 10, x1 + 10), GROUND_Y, rng.randf_range(-44.0, -17.0))
		if _free(Rect2(p2.x - 0.3, p2.z - 0.3, 0.6, 0.6)):
			var s2 := rng.randf_range(1.0, 1.7)
			if rng.randf() < 0.55:
				_pine(p2, s2)
			else:
				_tree(p2, s2)


func _build_fences() -> void:
	# low fence along the dungeon edge, leaving the cave path open
	var ex := float(grid.entrance.x)
	var wood := Color(0.55, 0.4, 0.25)
	var z := -0.35
	var x := -float(DungeonView.OUTER_SIDE) + 0.5
	while x < grid.w + DungeonView.OUTER_SIDE - 0.5:
		if absf(x + 0.5 - (ex + 0.5)) > 2.6:
			_town.box(Vector3(x, GROUND_Y + 0.18, z), Vector3(0.06, 0.36, 0.06), wood)
			_town.box(Vector3(x + 0.5, GROUND_Y + 0.26, z), Vector3(1.0, 0.05, 0.03), wood.darkened(0.1))
		x += 1.0


func _build_mountains() -> void:
	for i in 26:
		var x := rng.randf_range(-140.0, 180.0)
		var z := rng.randf_range(-150.0, -80.0)
		var h := rng.randf_range(22.0, 48.0)
		var r := h * rng.randf_range(0.9, 1.3)
		var base := Vector3(x, GROUND_Y - 1.0, z)
		var body := Color(0.42, 0.5, 0.58).lerp(Color(0.5, 0.56, 0.62), rng.randf())
		_town.cone(base, r, h, body, 9, 0.2, rng)
		# snow cap
		_town.cone(base + Vector3(0, h * 0.72, 0), r * 0.3, h * 0.28 + 0.2, Color(0.93, 0.95, 0.98), 9)
