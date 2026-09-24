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
static func grass_texture() -> ImageTexture:
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
		for s in int(height):
			var t := s / height
			var x := x0 + lean * t * t
			var y := 63 - s
			var wdt := base_w * (1.0 - t)
			for dx in range(int(floor(x - wdt)), int(ceil(x + wdt)) + 1):
				if dx >= 0 and dx < 64 and y >= 0:
					var c := col.lerp(Color(0.85, 0.95, 0.5), t * 0.5).darkened(0.25 * (1.0 - t))
					img.set_pixel(dx, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func vine_texture() -> ImageTexture:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for s in 3:
		var x0 := 10.0 + s * 20.0 + rng.randf_range(-4, 4)
		var length := rng.randf_range(60, 124)
		var phase := rng.randf() * TAU
		var y := 0
		while y < length:
			var x := x0 + sin(y * 0.09 + phase) * 5.0
			for dx in range(-1, 2):
				_px(img, int(x) + dx, y, Color(0.2, 0.32, 0.1))
			if y % 9 == 0:
				var side := 1 if (y / 9) % 2 == 0 else -1
				_leaf(img, x + side * 5.0, y + 2.0, side, rng)
			y += 1
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
		var n := Vector3(-sin(a), 0.6, cos(a)).normalized()
		st.set_normal(n)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1 + up)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0 + up)
	return st.commit()


## Vertical quad hanging down from y = 0, facing +Z.
static func vine_mesh(width: float = 0.5, height: float = 0.62) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	var tl := Vector3(-width / 2, 0, 0)
	var tr := Vector3(width / 2, 0, 0)
	var bl := Vector3(-width / 2, -height, 0)
	var br := Vector3(width / 2, -height, 0)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
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
