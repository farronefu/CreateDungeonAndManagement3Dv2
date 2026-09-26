class_name ProcGen
extends RefCounted
## Procedural meshes & textures for the dungeon dressing (no external art needed).

static var _noise_a: NoiseTexture2D
static var _noise_b: NoiseTexture2D


static func noise_a() -> NoiseTexture2D:
	if _noise_a == null:
		_noise_a = _make_noise(1, 0.012, 5)
	return _noise_a


static func noise_b() -> NoiseTexture2D:
	if _noise_b == null:
		_noise_b = _make_noise(7, 0.035, 3)
	return _noise_b


static func _make_noise(seed_value: int, freq: float, octaves: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = octaves
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = fn
	return nt


## Rounded, slightly lumpy box centred at the origin. Denser vertices on the bevels.
## detail: 1 = normal (~770 tris), 0 = cheap (~300 tris, for far-away filler rock).
static func rounded_box(half: Vector3, radius: float, seed_value: int, lump: float = 0.012, dome: float = 0.02, detail: int = 1) -> ArrayMesh:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = 3.2
	var axis_coords := func(h: float) -> PackedFloat32Array:
		var r := radius
		if detail <= 0:
			return PackedFloat32Array([-h, -h + r * 0.5, -h + r, h - r, h - r * 0.5, h])
		return PackedFloat32Array([-h, -h + r * 0.25, -h + r * 0.6, -h + r, 0.0, h - r, h - r * 0.6, h - r * 0.25, h])
	var cx: PackedFloat32Array = axis_coords.call(half.x)
	var cy: PackedFloat32Array = axis_coords.call(half.y)
	var cz: PackedFloat32Array = axis_coords.call(half.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := half - Vector3.ONE * radius
	var shape := func(p: Vector3) -> Vector3:
		var q := p.clamp(-inner, inner)
		var n := p - q
		if n.length_squared() < 1e-10:
			n = p.normalized()
		n = n.normalized()
		var out := q + n * radius
		var d := fn.get_noise_3dv(out * 1.0) * lump
		if n.y > 0.5:
			d += dome * (1.0 - clampf(Vector2(out.x / half.x, out.z / half.z).length(), 0.0, 1.0)) * n.y
		return out + n * d
	# faces: (axis u, axis v, normal axis, sign)
	var faces := [
		[0, 2, 1, 1.0], [0, 2, 1, -1.0],
		[0, 1, 2, 1.0], [0, 1, 2, -1.0],
		[2, 1, 0, 1.0], [2, 1, 0, -1.0],
	]
	var coords := [cx, cy, cz]
	var halves := [half.x, half.y, half.z]
	for f in faces:
		var au: int = f[0]
		var av: int = f[1]
		var an: int = f[2]
		var sg: float = f[3]
		var cu: PackedFloat32Array = coords[au]
		var cv: PackedFloat32Array = coords[av]
		var grid_pts: Array = []
		for i in cu.size():
			var row: Array = []
			for j in cv.size():
				var p := Vector3.ZERO
				p[au] = cu[i]
				p[av] = cv[j]
				p[an] = halves[an] * sg
				row.append(shape.call(p))
			grid_pts.append(row)
		for i in cu.size() - 1:
			for j in cv.size() - 1:
				var a: Vector3 = grid_pts[i][j]
				var b: Vector3 = grid_pts[i + 1][j]
				var c: Vector3 = grid_pts[i + 1][j + 1]
				var d: Vector3 = grid_pts[i][j + 1]
				# orient triangles so they face outwards
				var nrm := (b - a).cross(c - a)
				var outward := Vector3.ZERO
				outward[an] = sg
				if nrm.dot(outward) > 0.0:
					for v in [a, c, b, a, d, c]:
						st.add_vertex(v)
				else:
					for v in [a, b, c, a, c, d]:
						st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ textures
static func grass_texture(neutral: bool = false) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 22:
		var x0 := rng.randf_range(10, 54)
		var height := rng.randf_range(24, 60)
		var lean := rng.randf_range(-14, 14)
		var base_w := rng.randf_range(2.0, 3.6)
		var col := Color.from_hsv(rng.randf_range(0.22, 0.3), rng.randf_range(0.55, 0.8), rng.randf_range(0.45, 0.8))
		if neutral:
			col = Color.from_hsv(0.2, 0.05, rng.randf_range(0.92, 1.0))
		for s in int(height):
			var t := s / height
			var x := x0 + lean * t * t
			var y := 63 - s
			var wdt := base_w * (1.0 - t)
			for dx in range(int(floor(x - wdt)), int(ceil(x + wdt)) + 1):
				if dx >= 0 and dx < 64 and y >= 0:
					var c := col.lerp(Color(0.85, 0.95, 0.5) if not neutral else Color(1, 1, 1), t * 0.5).darkened((0.25 if not neutral else 0.08) * (1.0 - t))
					img.set_pixel(dx, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _leaf(img: Image, cx: float, cy: float, side: int, rng: RandomNumberGenerator) -> void:
	var base := Color.from_hsv(rng.randf_range(0.24, 0.3), 0.7, rng.randf_range(0.45, 0.7))
	for yy in range(-4, 5):
		for xx in range(-6, 7):
			var e := (xx * xx) / 36.0 + (yy * yy) / 12.0
			if e <= 1.0:
				var c := base.lightened(0.25 * (1.0 - e)) if yy < 0 else base.darkened(0.15)
				if e > 0.75:
					c = base.darkened(0.45)
				_px(img, int(cx + xx), int(cy + yy + xx * 0.25 * side), c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


# ------------------------------------------------------------------ small props
## Crossed quads for grass tufts (bottom at y = 0).
static func tuft_mesh(width: float = 0.34, height: float = 0.24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var dx := Vector3(cos(a), 0, sin(a)) * width * 0.5
		var p0 := -dx
		var p1 := dx
		var up := Vector3(0, height, 0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0 + up)
		# reversed copy: with back-face culling each side keeps its upward normal (no dark backs)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0 + up)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
	return st.commit()


static func rock_mesh(seed_value: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.7
	sm.radial_segments = 9
	sm.rings = 5
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = 2.0
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + fn.get_noise_3dv(v) * 0.35)
		if verts[i].y < 0.0:
			verts[i].y *= 0.3
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()


## Two-surface mushroom (stem, cap) sized ~0.2 tall.
static func mushroom_mesh(stem_mat: Material, cap_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.025
	stem.bottom_radius = 0.035
	stem.height = 0.14
	stem.radial_segments = 8
	var cap := SphereMesh.new()
	cap.radius = 0.075
	cap.height = 0.075
	cap.is_hemisphere = true
	cap.radial_segments = 10
	cap.rings = 4
	_add_prim(mesh, stem, Transform3D(Basis(), Vector3(0, 0.07, 0)), stem_mat)
	_add_prim(mesh, cap, Transform3D(Basis(), Vector3(0, 0.125, 0)), cap_mat)
	return mesh


static func _add_prim(mesh: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (xf.basis * norms[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# ------------------------------------------------------------------ plant meshes (tinted per instance)
## One leaf: a folded diamond from `base` along `dir`, broadening toward `side`. White-ish so the
## MultiMesh instance colour decides green / yellow.
static func _leaf3d(k: MeshKit, base: Vector3, dir: Vector3, side: Vector3, up: Vector3, length: float, width: float, shade: float) -> void:
	# rounded leaf: an elliptical outline fanned from the mid-rib, slightly cupped
	var ref := base - up * 0.3
	var seg := 4
	var rib: Array[Vector3] = []
	var lft: Array[Vector3] = []
	var rgt: Array[Vector3] = []
	for i in seg + 1:
		var t := float(i) / seg
		var w := width * sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)) * (1.0 - 0.25 * t)
		var p := base + dir * length * t + up * (sin(PI * t) * width * 0.25)
		rib.append(p)
		lft.append(p - side * w + up * w * 0.28)
		rgt.append(p + side * w + up * w * 0.28)
	var c1 := Color(shade, shade, shade)
	var c2 := Color(shade * 0.84, shade * 0.84, shade * 0.84)
	for i in seg:
		k.quad(rib[i], lft[i], lft[i + 1], rib[i + 1], c1, ref)
		k.quad(rib[i], rib[i + 1], rgt[i + 1], rgt[i], c2, ref)


## Rosette of leaves sitting on a block top (bottom at y = 0), ~0.3 wide.
static func leaf_clump_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var k := MeshKit.new()
	var n := 12
	for i in n:
		var ring := 0.02 if i < 7 else 0.07
		var a := TAU * i / (7 if i < 7 else 5) + rng.randf_range(-0.25, 0.25) + (0.4 if i >= 7 else 0.0)
		var out := Vector3(cos(a), 0, sin(a))
		var lift := rng.randf_range(0.5, 1.1)
		var dir := (out + Vector3(0, lift, 0)).normalized()
		var side := Vector3(-sin(a), 0, cos(a))
		var up := dir.cross(side).normalized()
		if up.y < 0:
			up = -up
		_leaf3d(k, out * ring + Vector3(0, 0.02 if i >= 7 else 0.0, 0), dir, side, up, rng.randf_range(0.11, 0.15), rng.randf_range(0.065, 0.08), rng.randf_range(0.85, 1.0))
	# a couple of upright centre leaves
	for i in 2:
		var a2 := rng.randf() * TAU
		var d2 := Vector3(cos(a2) * 0.3, 1.0, sin(a2) * 0.3).normalized()
		var s2 := Vector3(-sin(a2), 0, cos(a2))
		_leaf3d(k, Vector3.ZERO, d2, s2, d2.cross(s2).normalized(), 0.14, 0.04, 1.0)
	return k.commit()


## Vine hanging from y = 0 down the face it is placed on (faces +Z), with alternating leaves.
static func vine_chain_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var k := MeshKit.new()
	var y := 0.0
	var x := 0.0
	var i := 0
	var length := 0.55
	while y > -length:
		var ny := y - 0.07
		var nx := x + rng.randf_range(-0.02, 0.02)
		k.quad(Vector3(x - 0.008, y, 0.01), Vector3(x + 0.008, y, 0.01), Vector3(nx + 0.008, ny, 0.01), Vector3(nx - 0.008, ny, 0.01), Color(0.7, 0.7, 0.7), Vector3(x, y, -1))
		var sx := 1.0 if i % 2 == 0 else -1.0
		var base := Vector3(nx, ny + 0.02, 0.012)
		var dir := Vector3(sx * 0.8, -0.45, 0.35).normalized()
		_leaf3d(k, base, dir, Vector3(0, 0.3, 1).cross(dir).normalized(), Vector3(0, 0.2, 1).normalized(), 0.075 * (1.0 - float(i) * 0.05), 0.03, rng.randf_range(0.85, 1.0))
		x = nx
		y = ny
		i += 1
	return k.commit()


## Material shared by all plant decor: toon, double sided, tinted by instance colour.
static func plant_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	return m
