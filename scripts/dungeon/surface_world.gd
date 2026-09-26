class_name SurfaceWorld
extends Node3D
## The world above the dungeon, all voxel art. The dungeon is a deep pit: the heroes' town
## stands on a cliff PIT_DEPTH above it and BACK behind it (the Town node), and static fog
## fills the gap. Up there: tiled grass ground, a cobbled road, a rocky mound the path tunnels
## through, the town lined up behind the road facing the player (castle, house, armour shop |
## cave | weapon shop, church, inn), a dense forest and a voxel mountain range. Steps cut into
## the cliff lead down into the fog; at the bottom of the pit a stone gate with doors opens
## onto the entrance cell, and row 0 of the dungeon is a stone rampart.
## The hero walks descent_path() into the fog during the build phase (the countdown is the
## time it wanders there), then comes out of the gate along entry_path().
## Building/tree models: TownModels. Small things (road, lamps, props, grass tufts, the cave
## mound) are generated here into one voxel mesh because they depend on the dungeon layout.

const RAMP := 2.4          # length of the ramp from the surface down to the entrance cell
const ROAD_Z := -4.6
const PIT_DEPTH := 5.0     # the town ground sits this far above the dungeon block tops
const BACK := 3.5          # ... and this far behind the dungeon edge; the fog fills the gap
const GROUND_Y := Balance.BLOCK_H + PIT_DEPTH
const STEPS := 12          # steps cut into the cliff (one voxel each) before the fog
## fog layers: [height, front edge z, density] - higher layers end further back
const FOG_LAYERS := [[1.3, -0.3, 1.0], [2.2, -0.95, 0.95], [3.1, -1.6, 0.9], [4.0, -2.3, 0.85]]
const VOX := TownModels.VOX
## buildings from the cave outwards on each side; the castle ends up leftmost
const LEFT_ROW := ["armor_shop", "house", "castle"]
const RIGHT_ROW := ["weapon_shop", "church", "inn"]
const BUILDING_GAP := 0.9
const CAVE_CLEAR := 2.9    # free half-width around the cave path
const FOREST_BACK := -46.0

var grid: DungeonGrid
var rng := RandomNumberGenerator.new()
var _occupied: Array[Rect2] = []
var _deco: VoxelBuilder
var _town: Node3D
var _doors: Array[Node3D] = []
var _town_x := Vector2.ZERO    # x extent of the building row


## World-space path from the road through the mound tunnel and down the steps into the fog,
## where the hero disappears.
func descent_path() -> PackedVector3Array:
	var x := grid.entrance.x + 0.5
	var n := roundi(GROUND_Y / VOX)
	var foot := (n - STEPS + 1) * VOX
	return PackedVector3Array([
		Vector3(x - 5.0, GROUND_Y, ROAD_Z - BACK),
		Vector3(x, GROUND_Y, ROAD_Z - BACK),
		Vector3(x, GROUND_Y, (-STEPS + 0.5) * VOX - BACK),
		Vector3(x, foot, -0.5 * VOX - BACK),
		Vector3(x, foot - 0.9, -BACK + 1.0),
	])


## From behind the gate doors to the entrance cell.
func entry_path() -> PackedVector3Array:
	var x := grid.entrance.x + 0.5
	return PackedVector3Array([Vector3(x, 0.0, -0.8), Vector3(x, 0.0, 0.5)])


func build(g: DungeonGrid, _block_mat: ShaderMaterial) -> void:
	grid = g
	rng.seed = 424242
	_town = Node3D.new()
	_town.name = "Town"
	_town.position.z = -BACK
	add_child(_town)
	_deco = VoxelBuilder.new(4242)
	_deco.scale = VOX
	_deco.origin = Vector3(0, 0.5, 0)
	_build_ground()
	_build_cliff()
	_occupied.append(Rect2(grid.entrance.x - 1.5, -RAMP - 2.0, 4.0, RAMP + 2.0))
	_build_road()
	_build_cave_mound()
	_build_buildings()
	_build_props()
	_build_edge()
	_build_forest()
	_build_mountains()
	_scatter_grass()
	var mi := MeshInstance3D.new()
	mi.name = "TownDeco"
	mi.mesh = _deco.commit()
	mi.material_override = VoxelBuilder.material()
	mi.position = Vector3(0, GROUND_Y + 0.012, 0)
	_town.add_child(mi)
	for c in _town.get_children():
		if not c.name.begins_with("Cliff"):
			RenderLayers.apply(c, RenderLayers.SURFACE)
	_build_fog()
	_build_gate()
	_build_top_wall()


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
		_town.add_child(mi)
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
	_town.add_child(fmi)
	# beside the dungeon rock body, for low camera angles
	for sx in [x0 - 200.0, x1 + 200.0]:
		var side := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(400, 460)
		side.mesh = sp
		side.material_override = fm
		side.position = Vector3(sx, GROUND_Y - 0.02, 0)
		_town.add_child(side)


# ------------------------------------------------------------------ cliff
## The town's edge: a voxel cliff of soil strata that turns to dark rock lower down (the fog
## hides the rest), with roots, embedded boulders and a ragged, overhanging grass lip. Steps
## are cut into it from the tunnel down into the fog. Town-local space (the Town node sits
## BACK behind the dungeon); the sunlit grass lip and the dim face are separate meshes.
func _build_cliff() -> void:
	var face := _cliff_builder(777)
	var lip := _cliff_builder(778)
	var n := roundi(GROUND_Y / VOX)
	var ex := float(grid.entrance.x)
	var sx0 := ceili(ex / VOX)
	var sx1 := floori((ex + 1.0) / VOX)
	var x0 := floori(-30.0 / VOX)
	var x1 := ceili((grid.w + 30.0) / VOX)
	for vx in range(x0, x1):
		var wob := int(round(sin(vx * 0.13) * 1.2 + sin(vx * 0.051) * 1.0))
		var near_slot := vx >= sx0 - 3 and vx <= sx1 + 3
		for vy in range(0, n - 1):
			var d := n - 1 - vy
			for vz in range(-STEPS if near_slot else -3, 0):
				var k: Variant
				if d <= 2:
					k = ["dirt", "dirtDark", "dirt"]
				elif d <= 6 + wob:
					k = ["clay", "clayDark", "clay", "dirtDark"]
				elif d <= 10 + wob:
					k = ["stone", "dirtDark", "rockDark", "clayDark"]
				else:
					k = ["rockDark", "stoneDark", "rockDark", "slateDark"]
				face.put(vx, vy, vz, k)
		for vz in range(-STEPS if near_slot else -3, 0):
			lip.put(vx, n - 1, vz, ["grass", "grassDark", "grass"])
		# ragged edge: stretches of the ground crumble forward as overhanging ledges
		var reach := int(clampf(sin(vx * 0.21) * 1.4 + sin(vx * 0.067 + 1.3) * 1.6 + face.rnd() * 1.2, 0.0, 4.0))
		if near_slot:
			reach = 0
		for vz in range(0, reach):
			var thick := 2 + (reach - vz) + face.rng.randi_range(0, 2)
			lip.put(vx, n - 1, vz, ["grass", "grassDark", "grassLight"])
			for vy in range(n - 1 - thick, n - 1):
				face.put(vx, vy, vz, ["dirt", "dirtDark", "clay"])
		if reach == 0 and not near_slot and face.rnd() < 0.5:
			lip.put(vx, n - 1, 0, ["grass", "grassDark"])
		# the rough face below the soil
		for vy in range(n - 16, n - 1):
			if face.has_v(vx, vy, reach) or reach > 0:
				continue
			if face.rnd() < 0.12:
				face.erase(vx, vy, -1)
			elif face.rnd() < 0.05:
				face.put(vx, vy, 0, "dirtDark" if n - 1 - vy < 8 else "rockDark")
		# grass hanging over the edge and roots hanging down the face
		if face.rnd() < 0.3:
			face.det(vx + 0.5, n - 1.75, reach - 0.1, 0.9, 0.5, 0.25, "leafDark")
		if face.rnd() < 0.16:
			var rx := vx + 0.5
			for i in face.rng.randi_range(3, 9):
				rx += face.rng.randf_range(-0.25, 0.25)
				face.det(rx, n - 1.8 - i * 0.55, reach - 0.42, 0.16, 0.6, 0.16, "root")
	for i in 90:
		var cx := face.rng.randi_range(x0, x1)
		var cy := face.rng.randi_range(n - 14, n - 4)
		if cx >= sx0 - 2 and cx <= sx1 + 2:
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 1):
				if face.rnd() < 0.8 and face.has_v(cx + dx, cy + dy, -1):
					face.put(cx + dx, cy + dy, -1, ["stoneLight", "stone"])
	# steps cut into the cliff; they end at the face, where the fog swallows them
	face.clear(sx0, sx1, 0, n + 1, 0, 0)
	for vz in range(-STEPS, 0):
		var top := n - 1 - (vz + STEPS)
		for vx in range(sx0, sx1 + 1):
			for vy in range(top + 1, n + 1):
				face.erase(vx, vy, vz)
				lip.erase(vx, vy, vz)
			face.put(vx, top, vz, ["stoneLight", "stone"])
	for vx in [sx0 - 1, sx1 + 1]:
		for vy in range(n - 14, n):
			face.put(vx, vy, 0, ["wood", "plank"])
		lip.put(vx, n, -1, "wood")
	lip.lantern(sx0 - 1.5, n + 1.2, -1.0)
	lip.lantern(sx1 + 2.5, n + 1.2, -1.0)
	_add_voxel_mesh(_town, face, "CliffFace", RenderLayers.DUNGEON)
	_add_voxel_mesh(_town, lip, "CliffLip", RenderLayers.SURFACE)


func _cliff_builder(seed_value: int) -> VoxelBuilder:
	var b := VoxelBuilder.new(seed_value)
	b.scale = VOX
	b.origin = Vector3(-0.5, -0.5, -0.5)   # voxel (x, y, z) spans [x, x+1) * VOX
	b.ground_slab = 1.0
	b.floor_y = -99
	return b


func _add_voxel_mesh(parent: Node, b: VoxelBuilder, name_: String, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = b.commit()
	mi.material_override = VoxelBuilder.material()
	parent.add_child(mi)
	RenderLayers.apply(mi, layers)
	return mi


## Grass hummocks and stones along the edge, so the ground does not end in a straight line.
func _build_edge() -> void:
	var b := _deco
	var ex := float(grid.entrance.x) + 0.5
	for i in 90:
		var p := Vector2(rng.randf_range(-40.0, grid.w + 40.0), rng.randf_range(-1.8, -0.25))
		if absf(p.x - ex) < 2.4:
			continue
		var r := rng.randf_range(1.4, 3.0)
		if not _free(Rect2(p.x - r * VOX, p.y - r * VOX, r * VOX * 2.0, r * VOX * 2.0)):
			continue
		var cx := _v(p.x)
		var cz := _v(p.y)
		for x in range(cx - 4, cx + 5):
			for z in range(cz - 4, cz + 5):
				var h := int(r - Vector2(x - cx, (z - cz) * 1.4).length() + b.rnd() * 0.7)
				for y in range(1, h + 1):
					b.put(x, y, z, ["grass", "grassDark", "grassLight"] if y == h else ["dirt", "dirtDark"])
		if rng.randf() < 0.3:
			b.rock(cx + 3.0, cz - 1.0, 1.3)


# ------------------------------------------------------------------ fog
## Dark pit floor and the static fog between the cliff and the dungeon: stacked layers (the
## higher, the further back their front edge, so the dungeon stays clear), an upright curtain
## in front of the cliff, and a dense plume where the steps end so they vanish completely.
func _build_fog() -> void:
	var x0 := -40.0
	var x1 := float(grid.w) + 40.0
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.04, 0.04, 0.05)
	floor_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, BACK + 0.5)
	var fl := MeshInstance3D.new()
	fl.name = "PitFloor"
	fl.mesh = pm
	fl.material_override = floor_m
	fl.position = Vector3((x0 + x1) * 0.5, 0.02, -BACK * 0.5 - 0.25)
	add_child(fl)
	var shader := load("res://shaders/pit_fog.gdshader")
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 4
	fn.frequency = 0.012
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = fn
	for i in FOG_LAYERS.size():
		var l: Array = FOG_LAYERS[i]
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("noise_tex", nt)
		m.set_shader_parameter("seed", float(i) * 1.7)
		m.set_shader_parameter("z_front", l[1])
		m.set_shader_parameter("density", l[2])
		m.render_priority = i
		var p := PlaneMesh.new()
		var zb := -BACK - 0.3
		p.size = Vector2(x1 - x0, l[1] - zb)
		_add_fog(p, m, "Fog%d" % i, Vector3((x0 + x1) * 0.5, l[0], (zb + l[1]) * 0.5))
	var cm := ShaderMaterial.new()
	cm.shader = shader
	cm.set_shader_parameter("noise_tex", nt)
	cm.set_shader_parameter("vertical", true)
	cm.set_shader_parameter("seed", 9.0)
	cm.set_shader_parameter("y_bottom", 1.2)
	cm.set_shader_parameter("y_top", GROUND_Y - 0.9)
	# the plume swallows the steps: dense up to a little above where they end
	var step_end := (roundi(GROUND_Y / VOX) - STEPS + 1) * VOX
	cm.set_shader_parameter("plume", Vector3(grid.entrance.x + 0.5, step_end + 2.2, 2.2))
	cm.render_priority = -1
	var q := QuadMesh.new()
	q.size = Vector2(x1 - x0, GROUND_Y)
	_add_fog(q, cm, "FogCurtain", Vector3((x0 + x1) * 0.5, GROUND_Y * 0.5, -BACK + 0.35))


func _add_fog(mesh: Mesh, mat: Material, name_: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)


# ------------------------------------------------------------------ gate & top wall
## Stone gatehouse behind the entrance cell with a two-leaf door. The hero comes out of it
## (open_gate / close_gate); inside, a stair climbs into darkness.
func _build_gate() -> void:
	var ex := float(grid.entrance.x)
	var b := _cliff_builder(555)
	var ox0 := ceili((ex + 0.06) / VOX)
	var ox1 := floori((ex + 0.94) / VOX) - 1
	var gx0 := ox0 - 5
	var gx1 := ox1 + 5
	var S := ["stoneLight", "stone", "stoneLight", "cobble", "stone"]
	b.fill(gx0, gx1, 0, 10, -7, -1, S)
	for vx in range(gx0, gx1 + 1):
		for vy in range(0, 3):
			if b.rnd() < 0.3:
				b.put(vx, vy, -1, "moss")
	for k in range(0, 4):
		b.fill(gx0 + 1 + k * 2, gx1 - 1 - k * 2, 11 + k, 11 + k, -6, -1, S)
	for vx in range(gx0 - 1, gx1 + 2):
		b.put(vx, 10, 0, "stoneDark")
	# the passage: a short landing behind the doors, then a stair up into the dark
	b.clear(ox0, ox1, 0, 6, -7, 0)
	b.clear(ox0 + 1, ox1 - 1, 7, 7, -7, 0)
	b.fill(ox0, ox1, 0, 8, -8, -8, "shadow")
	for s in range(0, 3):
		b.fill(ox0, ox1, 0, s, -5 - s, -5 - s, "stoneDark")
	b.fill(ox0 - 1, ox0 - 1, 0, 7, 0, 0, "stoneLight")
	b.fill(ox1 + 1, ox1 + 1, 0, 7, 0, 0, "stoneLight")
	for vx in range(ox0, ox1 + 1):
		b.put(vx, 8, 0, "stoneLight")
	b.put(ox0, 7, 0, "stoneLight"); b.put(ox1, 7, 0, "stoneLight")
	b.put((ox0 + ox1) / 2, 9, 0, "stoneLight")
	b.lantern(ox0 - 1.5, 5.2, 0.5)
	b.lantern(ox1 + 1.5, 5.2, 0.5)
	for vx in [ox0 - 1.5, ox1 + 1.5]:
		b.det(vx, 5.95, 0.1, 0.12, 0.12, 0.6, "metal")
	_add_voxel_mesh(self, b, "Gate", RenderLayers.DUNGEON | RenderLayers.SURFACE)
	# door leaves hinge on the jambs and swing inwards
	var w := float(ox1 - ox0 + 1)     # opening width in voxels; each leaf covers half
	for side in [-1, 1]:
		# leaf centre (voxel units, relative to its hinge): +w/4 for the left, -w/4 for the right
		var leaf := _cliff_builder(560 + side)
		var cx: float = w / 4.0 * -side - 0.5
		for i in 2:
			var px: float = cx + (i - 0.5) * w / 4.0
			leaf.det(px, 3.0, 0.0, w / 4.0, 7.0, 0.8, "doorDark" if i == 0 else "door")
		for y in [1.0, 4.6]:
			leaf.det(cx, y, 0.45, w / 2.0, 0.2, 0.1, "metal")
		leaf.det(cx + (w / 4.0 - 0.3) * side, 2.8, 0.5, 0.24, 0.24, 0.14, "metal")
		var pivot := Node3D.new()
		pivot.name = "DoorL" if side < 0 else "DoorR"
		pivot.position = Vector3((ox0 if side < 0 else ox1 + 1) * VOX, 0.0, -0.2)
		add_child(pivot)
		_add_voxel_mesh(pivot, leaf, "Leaf", RenderLayers.DUNGEON | RenderLayers.SURFACE)
		_doors.append(pivot)


func open_gate() -> void:
	_swing_doors(deg_to_rad(105.0))
	Sfx.play("door")


func close_gate() -> void:
	_swing_doors(0.0)


func _swing_doors(angle: float) -> void:
	for i in _doors.size():
		var d: Node3D = _doors[i]
		var tw := d.create_tween()
		tw.tween_property(d, "rotation:y", angle * (1.0 if i == 0 else -1.0), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Row 0 of the dungeon (undiggable) as a stone brick rampart with a gap for the entrance.
func _build_top_wall() -> void:
	var b := _cliff_builder(556)
	var ex := float(grid.entrance.x)
	var BR := ["stone", "stoneLight", "stoneDark", "cobble", "stone"]
	for vx in range(floori(-DungeonView.OUTER_SIDE / VOX), ceili((grid.w + DungeonView.OUTER_SIDE) / VOX)):
		var wx := (vx + 0.5) * VOX
		if wx > ex - 0.02 and wx < ex + 1.02:
			continue
		for vy in range(0, 5):
			# bricks two voxels tall, four long, offset every course
			var brick := floori((vx + (vy / 2 % 2) * 2) / 4.0)
			var k: String = BR[absi(hash(Vector2i(brick, vy / 2))) % BR.size()]
			for vz in range(0, 4):
				b.put(vx, vy, vz, k if vy < 4 else "stoneLight")
			if vy < 2 and b.rnd() < 0.18:
				b.put(vx, vy, 3, "moss")
	_add_voxel_mesh(self, b, "TopWall", RenderLayers.DUNGEON)

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
	_town.add_child(mi)
	var aabb: AABB = info.aabb
	_occupied.append(Rect2(cx + aabb.position.x, front + aabb.position.z, aabb.size.x, aabb.size.z))


# ------------------------------------------------------------------ lamps, props
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
		_town.add_child(mmi)


func _build_mountains() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = TownModels.get_model("mountains").mesh
	mi.material_override = VoxelBuilder.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, GROUND_Y - 0.05, 0)
	_town.add_child(mi)


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
