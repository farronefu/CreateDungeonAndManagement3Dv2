class_name SurfaceWorld
extends Node3D
## The world above the dungeon (z < 0), all voxel art: tiled grass ground, a cobbled road, a
## rocky mound over the cave mouth, the heroes' town lined up behind the road and facing the
## player (castle, two houses, armour shop | cave | weapon shop, church, inn), a dense forest
## behind it and a voxel mountain range on the horizon. Building/tree models: TownModels.
## Small things (road, fence, lamps, props, grass tufts, the cave mound) are generated here
## into one voxel mesh because they depend on the dungeon layout.

const RAMP := 2.4          # length of the ramp from the surface down to the entrance cell
const ROAD_Z := -4.6
const GROUND_Y := Balance.BLOCK_H
const VOX := TownModels.VOX
## buildings from the cave outwards on each side; the castle ends up leftmost
const LEFT_ROW := ["armor_shop", "house", "house", "castle"]
const RIGHT_ROW := ["weapon_shop", "church", "inn"]
const BUILDING_GAP := 0.9
const CAVE_CLEAR := 2.9    # free half-width around the cave path
const FOREST_BACK := -46.0

var grid: DungeonGrid
var rng := RandomNumberGenerator.new()
var _occupied: Array[Rect2] = []
var _deco: VoxelBuilder
var _town_x := Vector2.ZERO    # x extent of the building row


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
	_deco = VoxelBuilder.new(4242)
	_deco.scale = VOX
	_deco.origin = Vector3(0, 0.5, 0)
	_build_ground()
	_build_ramp(block_mat)
	_build_road()
	_build_cave_mound()
	_build_buildings()
	_build_fence()
	_build_props()
	_build_forest()
	_build_mountains()
	_scatter_grass()
	var mi := MeshInstance3D.new()
	mi.name = "TownDeco"
	mi.mesh = _deco.commit()
	mi.material_override = VoxelBuilder.material()
	mi.position = Vector3(0, GROUND_Y + 0.012, 0)
	add_child(mi)
	RenderLayers.apply(self, RenderLayers.SURFACE)


func _v(w: float) -> int:
	return roundi(w / VOX)


func _free(r: Rect2) -> bool:
	for o in _occupied:
		if o.intersects(r):
			return false
	return true


# ------------------------------------------------------------------ ground & ramp
func _build_ground() -> void:
	var ex := float(grid.entrance.x)
	var x0 := -90.0
	var x1 := float(grid.w) + 90.0
	var z0 := FOREST_BACK - 2.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/town_ground.gdshader")
	# three slabs leave a slot for the ramp
	for r in [Rect2(x0, z0, ex - x0, -z0), Rect2(ex + 1.0, z0, x1 - ex - 1.0, -z0), Rect2(ex, z0, 1.0, -z0 - RAMP)]:
		var pm := PlaneMesh.new()
		pm.size = r.size
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(r.position.x + r.size.x * 0.5, GROUND_Y, r.position.y + r.size.y * 0.5)
		add_child(mi)
	# the far plains under the mountains, fading into fog
	var far := PlaneMesh.new()
	far.size = Vector2(700, 400)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.44, 0.2)
	fm.roughness = 1.0
	var fmi := MeshInstance3D.new()
	fmi.mesh = far
	fmi.material_override = fm
	fmi.position = Vector3(grid.w * 0.5, GROUND_Y - 0.02, z0 - 200 + 0.5)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	# beside the dungeon rock body, for low camera angles
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


# ------------------------------------------------------------------ road & cave
func _build_road() -> void:
	var b := _deco
	for vx in range(_v(-70.0), _v(grid.w + 70.0)):
		var wob := sin(vx * VOX * 0.35) * 0.12
		var za := ceili((ROAD_Z - 0.62 + wob) / VOX)
		var zb := floori((ROAD_Z + 0.62 + wob) / VOX)
		for vz in range(za, zb + 1):
			if (vz == za or vz == zb) and b.rnd() < 0.3:
				continue
			b.put(vx, 0, vz, TownModels.PATH)
	# the path from the road through the mound to the ramp
	var ex := float(grid.entrance.x)
	for vx in range(_v(ex + 0.1), _v(ex + 0.9) + 1):
		for vz in range(_v(ROAD_Z), _v(-RAMP - 0.12) + 1):
			b.put(vx, 0, vz, TownModels.PATH)
	_occupied.append(Rect2(-70.0, ROAD_Z - 0.85, grid.w + 140.0, 1.7))


## A rocky, mossy mound straddling the top of the ramp; the path tunnels through it.
func _build_cave_mound() -> void:
	var b := _deco
	var ex := float(grid.entrance.x)
	var cx := (ex + 0.5) / VOX
	var cz := (-RAMP - 0.95) / VOX
	var rx := 2.5 / VOX
	var rz := 1.1 / VOX
	var ry := 2.1 / VOX
	var tx0 := _v(ex + 0.08)
	var tx1 := _v(ex + 0.92)
	var t_top := int(1.2 / VOX) + 1
	var z_front := _v(-RAMP - 0.12)
	for vx in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
		for vz in range(floori(cz - rz) - 1, z_front + 1):
			var dx := (vx - cx) / rx
			var dz := (vz - cz) / rz
			var q := 1.0 - dx * dx - dz * dz
			if q <= 0.0:
				continue
			var h := int(ry * sqrt(q) * (0.85 + b.rnd() * 0.3)) + 1
			for y in range(1, h + 1):
				var near_tunnel := vx >= tx0 - 1 and vx <= tx1 + 1 and y <= t_top + 1
				if vx >= tx0 and vx <= tx1 and y <= t_top:
					continue
				var k: Variant
				if y >= h - 1 and y > ry * 0.55 and b.rnd() < 0.8:
					k = ["moss", "grassDark", "moss", "grass", "leafDark"]
				elif near_tunnel:
					k = ["stoneDark", "rockDark"]
				else:
					k = ["stone", "stone", "stoneDark", "stoneLight", "rock"]
				b.put(vx, y, vz, k)
	# stone arch framing both mouths of the tunnel
	for vz in [z_front, floori(cz - rz) - 1]:
		for y in range(1, t_top + 2):
			b.put(tx0 - 1, y, vz, ["stoneLight", "stone"]); b.put(tx1 + 1, y, vz, ["stoneLight", "stone"])
		for vx in range(tx0 - 1, tx1 + 2):
			b.put(vx, t_top + 1, vz, "stoneLight")
		b.put(tx0, t_top, vz, "stoneLight"); b.put(tx1, t_top, vz, "stoneLight")
		b.put((tx0 + tx1) / 2, t_top + 2, vz, "stoneLight"); b.put((tx0 + tx1) / 2 + 1, t_top + 2, vz, "stoneLight")
	# boulders at its feet
	for q in [[-2.9, -0.2, 2.2], [2.9, -0.1, 2.0], [-2.2, 0.9, 1.4], [2.4, 1.0, 1.6], [-3.6, -1.0, 1.5]]:
		b.rock(cx + q[0] / VOX, cz + q[1] / VOX, q[2])
	# a moss tuft or two on top
	b.bush(cx + 0.6 / VOX, cz - 0.1 / VOX, 1.6, int(ry * 0.9))
	_occupied.append(Rect2(ex + 0.5 - 3.6, -RAMP - 2.3, 7.2, 2.3))


# ------------------------------------------------------------------ buildings
func _build_buildings() -> void:
	var ex := float(grid.entrance.x)
	var front := ROAD_Z - 0.8
	var x := ex + 0.5 - CAVE_CLEAR
	for n in LEFT_ROW:
		var info := TownModels.get_model(n)
		var w: float = info.width
		_place(info, x - w * 0.5, front)
		x -= w + BUILDING_GAP
	_town_x.x = x + BUILDING_GAP
	x = ex + 0.5 + CAVE_CLEAR
	for n in RIGHT_ROW:
		var info := TownModels.get_model(n)
		var w: float = info.width
		_place(info, x + w * 0.5, front)
		x += w + BUILDING_GAP
	_town_x.y = x - BUILDING_GAP


func _place(info: Dictionary, cx: float, front: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = info.mesh
	mi.material_override = VoxelBuilder.material()
	mi.position = Vector3(cx, GROUND_Y + 0.012, front)
	add_child(mi)
	var aabb: AABB = info.aabb
	_occupied.append(Rect2(cx + aabb.position.x, front + aabb.position.z, aabb.size.x, aabb.size.z))


# ------------------------------------------------------------------ fence, lamps, props
func _build_fence() -> void:
	# low fence along the dungeon edge, leaving the cave path open
	var b := _deco
	var ex := float(grid.entrance.x)
	var vz := _v(-0.42)
	var prev := -99999
	var vx := _v(-60.0)
	while vx <= _v(grid.w + 60.0):
		if absf(vx * VOX - (ex + 0.5)) > 2.5:
			b.put(vx, 1, vz, "wood"); b.put(vx, 2, vz, "wood")
			if vx - prev == 5:
				for y in [1.15, 1.9]:
					b.det((vx + prev) * 0.5, y, vz, 5.0, 0.22, 0.24, "plank")
			prev = vx
		vx += 5
	_occupied.append(Rect2(-60.0, -0.62, grid.w + 120.0, 0.4))


func _build_props() -> void:
	var b := _deco
	var ex := float(grid.entrance.x) + 0.5
	# street lamps on the dungeon side of the road
	var x := ex - 3.6
	while x > -40.0:
		_prop_lamp(x)
		x -= 6.5
	x = ex + 3.6
	while x < grid.w + 40.0:
		_prop_lamp(x)
		x += 6.5
	# signpost by the cave path
	var sx := _v(ex + 1.35)
	var sz := _v(ROAD_Z + 1.05)
	for y in range(1, 6):
		b.put(sx, y, sz, "wood")
	b.det(sx + 1.2, 4.6, sz, 2.6, 0.9, 0.2, "sign")
	b.det(sx + 2.65, 4.6, sz, 0.35, 0.55, 0.2, "sign")
	b.det(sx + 1.1, 4.6, sz + 0.13, 1.6, 0.14, 0.05, "signIcon")
	_occupied.append(Rect2(ex + 1.1, ROAD_Z + 0.8, 0.9, 0.5))
	# a well, a hay cart, barrels and crates in the strip before the fence
	_prop_well(ex - 9.3, -2.3)
	_prop_cart(ex + 8.6, -2.2)
	_prop_stack(ex - 5.2, -1.4)
	_prop_stack(ex + 13.4, -1.6)
	_prop_stack(ex - 17.0, -1.5)
	# bushes, rocks and flower beds wherever there is room
	for i in 60:
		var p := Vector2(rng.randf_range(-40.0, grid.w + 40.0), rng.randf_range(-3.7, -1.0))
		if absf(p.x - ex) < 3.3:
			continue
		var r := Rect2(p.x - 0.6, p.y - 0.6, 1.2, 1.2)
		if not _free(r):
			continue
		var kind := rng.randf()
		if kind < 0.5:
			b.bush(p.x / VOX, p.y / VOX, rng.randf_range(1.8, 2.8))
		elif kind < 0.65:
			b.rock(p.x / VOX, p.y / VOX, rng.randf_range(1.0, 1.6))
		else:
			_flower_bed(p)
		_occupied.append(r)


func _prop_lamp(x: float) -> void:
	var r := Rect2(x - 0.25, ROAD_Z + 0.75, 0.5, 0.5)
	if not _free(r):
		return
	_deco.lamp_post(_v(x), _v(ROAD_Z + 1.0), 4)
	_occupied.append(r)


func _prop_well(x: float, z: float) -> void:
	var b := _deco
	var cx := _v(x)
	var cz := _v(z)
	b.fill(cx - 2, cx + 2, 1, 2, cz - 2, cz + 2, TownModels.STONE)
	b.clear(cx - 1, cx + 1, 1, 2, cz - 1, cz + 1)
	b.det(cx, 1.2, cz, 3.0, 0.1, 3.0, "water")
	for s in [-2, 2]:
		for y in range(3, 7):
			b.put(cx + s, y, cz, "wood")
	for xx in range(cx - 3, cx + 4):
		b.put(xx, 7, cz - 1, b.roof_k(7)); b.put(xx, 7, cz + 1, b.roof_k(7)); b.put(xx, 8, cz, "roofDark")
	b.det(cx, 5.6, cz, 4.0, 0.22, 0.22, "wood")
	b.det(cx, 4.4, cz, 0.08, 2.2, 0.08, "plank")
	b.det(cx, 3.2, cz, 0.7, 0.6, 0.7, "barrel")
	b.det(cx, 3.5, cz, 0.76, 0.1, 0.76, "metal")
	_occupied.append(Rect2(x - 0.8, z - 0.8, 1.6, 1.6))


func _prop_cart(x: float, z: float) -> void:
	var b := _deco
	var cx := x / VOX
	var cz := z / VOX
	b.det(cx, 2.0, cz, 5.0, 0.35, 2.6, "plank")
	for s in [-1.25, 1.25]:
		b.det(cx, 2.45, cz + s, 5.0, 0.6, 0.16, "plankDark")
		TownModels._wheel(b, cx - 0.8, 1.5, cz + s * 1.15, 1.0)
	for i in 3:
		b.det(cx - 3.1, 1.6 + i * 0.01, cz + (i - 1) * 0.5, 2.2, 0.16, 0.16, "wood")
	for xx in range(roundi(cx) - 2, roundi(cx) + 2):
		for zz in range(roundi(cz) - 1, roundi(cz) + 2):
			b.put(xx, 3, zz, "hay")
			if b.rnd() < 0.6:
				b.put(xx, 4, zz, "hay")
	_occupied.append(Rect2(x - 1.0, z - 0.6, 2.0, 1.2))


func _prop_stack(x: float, z: float) -> void:
	var b := _deco
	var cx := _v(x)
	var cz := _v(z)
	b.barrel(cx, cz)
	b.crate(cx + 1, 1, cz)
	b.crate(cx + 1, 1, cz - 1)
	b.crate(cx + 1, 2, cz)
	b.barrel(cx - 1, cz - 1)
	_occupied.append(Rect2(x - 0.5, z - 0.5, 1.0, 0.8))


func _flower_bed(p: Vector2) -> void:
	var b := _deco
	var cols := [["flowerW", "flowerY"], ["flowerP", "flowerW"], ["flowerB", "flowerW"], ["flowerY", "flowerP"]]
	var c: Array = cols[rng.randi() % cols.size()]
	for i in 12:
		var q := p / VOX + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.2, 1.2))
		b.det(q.x, 0.65, q.y, 0.12, 0.3, 0.12, "leafDark")
		b.det(q.x, 0.86, q.y, 0.28, 0.18, 0.28, c)
		b.det(q.x + 0.2, 0.62, q.y + 0.1, 0.3, 0.2, 0.3, ["leaf", "leafLight"])


# ------------------------------------------------------------------ nature
func _build_forest() -> void:
	var lists := {}
	for n in TownModels.TREES:
		lists[n] = []
	var zf := ROAD_Z - 0.8
	var x := -48.0
	while x < grid.w + 48.0:
		var z := zf - 0.5
		while z > FOREST_BACK:
			var far := z < -26.0
			var p := Vector3(x + rng.randf_range(-0.6, 0.6), GROUND_Y + 0.01, z + rng.randf_range(-0.5, 0.5))
			if _free(Rect2(p.x - 0.6, p.z - 0.6, 1.2, 1.2)):
				var n: String = TownModels.TREES[rng.randi() % TownModels.TREES.size()]
				var s := rng.randf_range(0.8, 1.15) * (1.25 if far else 1.0)
				var bs := Basis(Vector3.UP, (rng.randi() % 4) * PI * 0.5).scaled(Vector3.ONE * s)
				lists[n].append(Transform3D(bs, p))
			z -= 2.1 if far else 1.45
		x += 1.65 if z > -26.0 else 1.9
	for n in lists:
		var ts: Array = lists[n]
		if ts.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = TownModels.get_model(n).mesh
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Forest_" + n
		mmi.multimesh = mm
		mmi.material_override = VoxelBuilder.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_mountains() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = TownModels.get_model("mountains").mesh
	mi.material_override = VoxelBuilder.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, GROUND_Y - 0.05, 0)
	add_child(mi)


## grass tufts and little flowers over the free town ground (as in the inn reference)
func _scatter_grass() -> void:
	var b := _deco
	for i in 4200:
		var p := Vector2(rng.randf_range(-45.0, grid.w + 45.0), rng.randf_range(-14.0, -0.7))
		if not _free(Rect2(p.x - 0.08, p.y - 0.08, 0.16, 0.16)):
			continue
		var vx := p.x / VOX
		var vz := p.y / VOX
		if rng.randf() < 0.2:
			b.det(vx, 0.62, vz, 0.1, 0.26, 0.1, "leafDark")
			b.det(vx, 0.8, vz, 0.26, 0.16, 0.26, ["flowerW", "flowerW", "flowerY", "flowerP", "flowerB"])
		else:
			# a tuft of two or three thin blades
			var k: String = ["grassLight", "grass", "leaf", "leafDark"][rng.randi() % 4]
			for j in rng.randi_range(2, 3):
				var h := 0.25 + rng.randf() * 0.4
				b.det(vx + rng.randf_range(-0.14, 0.14), 0.5 + h / 2.0, vz + rng.randf_range(-0.14, 0.14), 0.1, h, 0.1, k)
