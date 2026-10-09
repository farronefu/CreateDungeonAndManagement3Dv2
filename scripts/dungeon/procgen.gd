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


