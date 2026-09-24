class_name MeshKit
extends RefCounted
## Tiny flat-shaded, vertex-coloured mesh builder for low-poly toon props (town, rocks, trees).
## Every triangle is oriented so its normal points away from `ref` (the primitive's centre), so
## the helpers never depend on winding order. Use a material with culling disabled.

var _st := SurfaceTool.new()
var _n := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, ref: Vector3 = Vector3.INF) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	if ref != Vector3.INF and nrm.dot((a + b + c) / 3.0 - ref) < 0.0:
		nrm = -nrm
		var tmp := b
		b = c
		c = tmp
	# Godot treats clockwise triangles as front faces: emit a, c, b so the outward normal matches
	_st.set_color(col)
	_st.set_normal(nrm)
	_st.add_vertex(a)
	_st.set_normal(nrm)
	_st.add_vertex(c)
	_st.set_normal(nrm)
	_st.add_vertex(b)
	_n += 1


## Quad a-b-c-d (counter-clockwise seen from the front).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, ref: Vector3 = Vector3.INF) -> void:
	tri(a, c, b, col, ref)
	tri(a, d, c, col, ref)


func box(center: Vector3, size: Vector3, col: Color, yaw: float = 0.0, top_col: Variant = null) -> void:
	var h := size * 0.5
	var bs := Basis(Vector3.UP, yaw)
	var p := func(x: float, y: float, z: float) -> Vector3: return center + bs * Vector3(x * h.x, y * h.y, z * h.z)
	var tc: Color = top_col if top_col != null else col
	quad(p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), tc, center)
	quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), col, center)
	quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), col, center)
	quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), col, center)
	quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), col, center)


## Gable roof along local X, sitting on y = base. w/d are the footprint incl. overhang.
func gable(center_base: Vector3, w: float, d: float, h: float, col: Color, yaw: float = 0.0) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var p := func(x: float, y: float, z: float) -> Vector3: return center_base + bs * Vector3(x, y, z)
	var hw := w * 0.5
	var hd := d * 0.5
	var t := 0.06
	# two slopes (with a little thickness at the eaves)
	var r := center_base + Vector3(0, -0.3, 0)
	quad(p.call(-hw, 0, hd), p.call(hw, 0, hd), p.call(hw, h, 0), p.call(-hw, h, 0), col, r)
	quad(p.call(hw, 0, -hd), p.call(-hw, 0, -hd), p.call(-hw, h, 0), p.call(hw, h, 0), col.darkened(0.18), r)
	quad(p.call(-hw, -t, hd), p.call(hw, -t, hd), p.call(hw, 0, hd), p.call(-hw, 0, hd), col.darkened(0.35), center_base)
	quad(p.call(hw, -t, -hd), p.call(-hw, -t, -hd), p.call(-hw, 0, -hd), p.call(hw, 0, -hd), col.darkened(0.35), center_base)
	# gable ends
	var wall := col.darkened(0.45)
	var mid := center_base + Vector3(0, h * 0.3, 0)
	tri(p.call(hw * 0.94, 0, hd), p.call(hw * 0.94, 0, -hd), p.call(hw * 0.94, h, 0), wall, mid)
	tri(p.call(-hw * 0.94, 0, -hd), p.call(-hw * 0.94, 0, hd), p.call(-hw * 0.94, h, 0), wall, mid)


func pyramid(center_base: Vector3, w: float, h: float, col: Color) -> void:
	var hw := w * 0.5
	var apex := center_base + Vector3(0, h, 0)
	var c := [Vector3(-hw, 0, hw), Vector3(hw, 0, hw), Vector3(hw, 0, -hw), Vector3(-hw, 0, -hw)]
	for i in 4:
		var a: Vector3 = center_base + c[i]
		var b: Vector3 = center_base + c[(i + 1) % 4]
		tri(a, b, apex, col if i % 2 == 0 else col.darkened(0.15), center_base + Vector3(0, h * 0.25, 0))


func cylinder(base: Vector3, r: float, h: float, col: Color, seg: int = 8, top_col: Variant = null) -> void:
	var tc: Color = top_col if top_col != null else col
	var r0 := base + Vector3(0, h * 0.5, 0)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		quad(base + p1, base + p0, base + p0 + Vector3(0, h, 0), base + p1 + Vector3(0, h, 0), col, r0)
		tri(base + Vector3(0, h, 0), base + p1 + Vector3(0, h, 0), base + p0 + Vector3(0, h, 0), tc, r0)


func cone(base: Vector3, r: float, h: float, col: Color, seg: int = 8, jitter: float = 0.0, rng: RandomNumberGenerator = null) -> void:
	var apex := base + Vector3(0, h, 0)
	var pts: Array[Vector3] = []
	for i in seg:
		var a := TAU * i / seg
		var rr := r * (1.0 + (rng.randf_range(-jitter, jitter) if rng else 0.0))
		pts.append(base + Vector3(cos(a) * rr, 0, sin(a) * rr))
	for i in seg:
		var shade := 0.0 if i < seg / 2 else 0.12
		tri(pts[(i + 1) % seg], pts[i], apex, col.darkened(shade), base + Vector3(0, h * 0.25, 0))


## Lumpy low-poly blob (rocks, foliage). col_fn(normal_y) -> Color lets the top differ from the sides.
func blob(center: Vector3, radius: Vector3, rng: RandomNumberGenerator, col_top: Color, col_side: Color, rings: int = 4, seg: int = 7, lump: float = 0.18) -> void:
	var grid: Array = []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := PI * v
		var row: Array[Vector3] = []
		for j in seg:
			var th := TAU * j / seg + (0.5 if i % 2 == 1 else 0.0) * TAU / seg
			var dir := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := 1.0 + rng.randf_range(-lump, lump) if (i > 0 and i < rings) else 1.0
			row.append(center + dir * radius * k)
		grid.append(row)
	for i in rings:
		for j in seg:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][(j + 1) % seg]
			var c: Vector3 = grid[i + 1][(j + 1) % seg]
			var d: Vector3 = grid[i + 1][j]
			var ny := ((a + b + c + d) * 0.25 - center).normalized().y
			var col := col_side.lerp(col_top, clampf(ny * 1.6, 0.0, 1.0))
			tri(a, c, b, col, center)
			tri(a, d, c, col, center)


func commit() -> ArrayMesh:
	return _st.commit()


func is_empty() -> bool:
	return _n == 0
