class_name VoxelBuilder
extends RefCounted
## Voxel-art modelling kit (a GDScript port of the voxel-inn generator).
## Unit voxels live on an integer grid (x right, y up, z towards the camera); "details" are
## freely sized boxes for trims, props and foliage. `commit()` meshes everything with
## hidden-face culling. Every block carries a palette kind plus one of VARS brightness
## variants; the town_voxel shader adds the 8x8 texel noise and the darker block border.
##
## Layer y = 0 is the ground layer: those blocks are flattened to a thin slab so paths and
## patios sit flush on the town ground.

# [sRGB hex, brightness jitter, emission]
const PAL := {
	"grass": [0x6fa03c, .07], "grassDark": [0x5a8a30, .07], "grassLight": [0x86b44a, .07],
	"dirt": [0x7b4f2e, .08], "dirtDark": [0x5f3b22, .08],
	"stone": [0x8e8e93, .07], "stoneDark": [0x6f6f76, .07], "stoneLight": [0xa6a4a0, .06],
	"cobble": [0x7f7b77, .08], "moss": [0x6e7d48, .08],
	"castle": [0xa9a8a6, .06], "castleDark": [0x8a8989, .06], "castleLight": [0xbdbbb5, .05],
	"sand": [0xcdb68a, .05], "sandDark": [0xb89f74, .05],
	"plaster": [0xe9d7ae, .04], "plasterDark": [0xd9c49a, .04],
	"wood": [0x5b3a21, .07], "woodDark": [0x44291a, .06], "plank": [0x7a4d2b, .07], "plankDark": [0x5e3a20, .06],
	"shutter": [0x6a4326, .06], "log": [0x5e3d24, .08],
	"roof": [0xa9472d, .06], "roofLight": [0xbc5a39, .06], "roofDark": [0x7f3322, .06],
	"blue": [0x3b56a6, .06], "blueLight": [0x4a68b8, .06], "blueDark": [0x2c407e, .06],
	"slate": [0x46506a, .06], "slateLight": [0x55607c, .06], "slateDark": [0x363e54, .06],
	"leaf": [0x5c8c34, .08], "leafLight": [0x78a843, .08], "leafDark": [0x416b28, .08],
	"pine": [0x3f6b3a, .08], "pineDark": [0x2f5530, .08], "pineLight": [0x4f7f44, .08],
	"door": [0x94603a, .05], "doorDark": [0x7a4c2c, .05],
	"metal": [0x2f2f33, .04], "steel": [0xb9bec6, .05], "steelDark": [0x7d828c, .05], "steelLight": [0xdfe3e8, .03],
	"leather": [0x7a4a2a, .05], "gold": [0xe0b43c, .04], "bronze": [0xb07a2e, .05],
	"sign": [0x6b4526, .04], "signIcon": [0xefe3c6, .02], "barrel": [0x86552e, .06], "crate": [0x9a6c3a, .07],
	"cloth": [0xb3302a, .05], "clothDark": [0x8c2420, .05], "shieldBlue": [0x2f58b0, .05], "shieldRed": [0xb8342c, .05],
	"coal": [0x2a2a2e, .06], "hay": [0xd9b85a, .07], "carrot": [0xe07a26, .05], "water": [0x4a7fbf, .05],
	"flowerW": [0xf6f2e6, .03], "flowerY": [0xf2d04a, .04], "flowerP": [0xe58fb0, .04], "flowerB": [0x8fa6ee, .04],
	"rock": [0x7d8590, .07], "rockDark": [0x646b76, .07], "snow": [0xeef2f6, .03],
	"shadow": [0x1c1612, .02],
	"clay": [0x8c5a3c, .07], "clayDark": [0x6e4430, .07], "root": [0x5a3a22, .06],
	"glass": [0xf2a24a, .08, 0.9], "lamp": [0xffc15e, .03, 2.2], "fire": [0xff7a1e, .06, 2.6],
	"stainB": [0x3e6ee8, .06, 0.9], "stainR": [0xe0403a, .06, 0.9], "stainY": [0xf2c440, .06, 0.9], "stainG": [0x52c060, .06, 0.9],
}
const VARS := 8

static var _kind_ids := {}
static var _kind_names: Array[String] = []
static var _colors: Array[Color] = []        # linear colour per kind * VARS + variant
static var _emit: PackedFloat32Array = []    # per kind

var rng := RandomNumberGenerator.new()
var vox := {}            # key -> kind * VARS + variant
var details: Array = []  # [Vector3 centre, Vector3 size, int code]
## world-unit size of one voxel and the voxel-space point that maps to the mesh origin
var scale := 0.22
var origin := Vector3.ZERO
## thickness (in voxels) of the flattened ground layer y = 0
var ground_slab := 0.3
## skip faces pointing down for blocks at or below this layer (they sit on the ground)
var floor_y := 1


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value
	if _kind_names.is_empty():
		_init_palette()


static func _init_palette() -> void:
	for k in PAL:
		var p: Array = PAL[k]
		_kind_ids[k] = _kind_names.size()
		_kind_names.append(k)
		var base := Color.hex((int(p[0]) << 8) | 0xff).srgb_to_linear()
		for vi in VARS:
			var f := 1.0 + (float(vi) / (VARS - 1) * 2.0 - 1.0) * float(p[1])
			_colors.append(Color(base.r * f, base.g * f, base.b * f))
		_emit.append(float(p[2]) if p.size() > 2 else 0.0)


# ------------------------------------------------------------------ basics
func rnd() -> float:
	return rng.randf()


func pick(a: Array) -> Variant:
	return a[rng.randi() % a.size()]


static func key(x: int, y: int, z: int) -> int:
	return ((x + 256) * 1024 + (y + 256)) * 1024 + (z + 256)


func _code(k: Variant) -> int:
	if k is Array:
		k = pick(k)
	return int(_kind_ids[k]) * VARS + rng.randi() % VARS


func put(x: int, y: int, z: int, k: Variant) -> void:
	vox[key(x, y, z)] = _code(k)


func erase(x: int, y: int, z: int) -> void:
	vox.erase(key(x, y, z))


func has_v(x: int, y: int, z: int) -> bool:
	return vox.has(key(x, y, z))


func kind_at(x: int, y: int, z: int) -> String:
	var c: Variant = vox.get(key(x, y, z))
	return "" if c == null else _kind_names[int(c) / VARS]


func fill(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, k: Variant) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				put(x, y, z, k)


func clear(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				erase(x, y, z)


## small, freely-sized decoration box
func det(x: float, y: float, z: float, sx: float, sy: float, sz: float, k: Variant) -> void:
	details.append([Vector3(x, y, z), Vector3(sx, sy, sz), _code(k)])


# ------------------------------------------------------------------ facade helpers
# f = {axis: "x"|"z", c: wall coordinate, out: +1/-1 outward}; u runs along the wall
static func face(axis: String, c: int, out: int) -> Dictionary:
	return {"axis": axis, "c": c, "out": out}


func fset(f: Dictionary, u: int, y: int, k: Variant, off: int = 0) -> void:
	var w: int = f.c + f.out * off
	if f.axis == "z":
		put(u, y, w, k)
	else:
		put(w, y, u, k)


func fdel(f: Dictionary, u: int, y: int, off: int = 0) -> void:
	var w: int = f.c + f.out * off
	if f.axis == "z":
		erase(u, y, w)
	else:
		erase(w, y, u)


func fxyz(f: Dictionary, u: float, y: float, off: float = 0.0) -> Vector3:
	var w: float = f.c + f.out * off
	return Vector3(u, y, w) if f.axis == "z" else Vector3(w, y, u)


## detail box in facade coordinates: su along the wall, sw through it
func fdet(f: Dictionary, u: float, y: float, off: float, su: float, sy: float, sw: float, k: Variant) -> void:
	var w: float = f.c + f.out * off
	if f.axis == "z":
		det(u, y, w, su, sy, sw, k)
	else:
		det(w, y, u, sw, sy, su, k)


func roof_k(y: int, set_: Array = ["roof", "roofLight", "roofDark"]) -> String:
	if rnd() < 0.12:
		return set_[2]
	return set_[0] if y % 2 else set_[1]


func plants_box(x0: float, x1: float, z0: float, z1: float, top: float, n: int) -> void:
	for i in n:
		var s := 0.28 + rnd() * 0.2
		det(x0 + rnd() * (x1 - x0), top + s / 2 + rnd() * 0.15, z0 + rnd() * (z1 - z0), s, s, s, ["leaf", "leafLight", "leafDark"])
	for i in int(n * 0.5):
		det(x0 + rnd() * (x1 - x0), top + 0.42 + rnd() * 0.15, z0 + rnd() * (z1 - z0), 0.18, 0.18, 0.18, ["flowerW", "flowerW", "flowerY", "flowerP"])


## recessed window with frame, mullions, optional shutters and flower box
func window_at(f: Dictionary, u0: int, y0: int, w: int, h: int, shutters := false, box := false, pane: Variant = "glass") -> void:
	for u in range(u0, u0 + w):
		for y in range(y0, y0 + h):
			fdel(f, u, y, 0)
			fset(f, u, y, pane, -1)
	var uc := u0 + (w - 1) / 2.0
	var yc := y0 + (h - 1) / 2.0
	var w2 := w + 0.3
	var h2 := h + 0.3
	fdet(f, uc, y0 + h - 0.5, 0.55, w2, 0.24, 0.3, "woodDark")
	fdet(f, uc, y0 - 0.5, 0.6, w2 + 0.2, 0.3, 0.45, "wood")
	fdet(f, u0 - 0.5, yc, 0.55, 0.24, h2, 0.3, "woodDark")
	fdet(f, u0 + w - 0.5, yc, 0.55, 0.24, h2, 0.3, "woodDark")
	if w >= 2:
		fdet(f, uc, yc, -0.45, 0.16, h, 0.12, "woodDark")
	if h >= 2:
		fdet(f, uc, yc, -0.45, w, 0.16, 0.12, "woodDark")
	if shutters:
		for su in [u0 - 1 + 0.02, u0 + w - 0.02]:
			fdet(f, su, yc, 0.6, 0.86, h, 0.16, "shutter")
			for dy in [-h / 2.0 + 0.35, h / 2.0 - 0.35]:
				fdet(f, su, yc + dy, 0.7, 0.9, 0.14, 0.08, "woodDark")
	if box:
		for u in range(u0, u0 + w):
			fset(f, u, y0 - 1, "plank", 1)
		var a := fxyz(f, u0, y0 - 1, 1)
		var b := fxyz(f, u0 + w - 1, y0 - 1, 1)
		plants_box(minf(a.x, b.x) - 0.45, maxf(a.x, b.x) + 0.45, minf(a.z, b.z) - 0.4, maxf(a.z, b.z) + 0.4, a.y + 0.5, w * 6)


## tall window with a pointed (stepped) arch, filled with stained glass
func arch_window(f: Dictionary, u0: int, y0: int, w: int, h: int, frame: Variant = "stoneLight", pane: Variant = null) -> void:
	var glass: Variant = pane if pane != null else ["stainB", "stainB", "stainY", "stainR", "stainG"]
	for u in range(u0, u0 + w):
		for y in range(y0, y0 + h):
			fdel(f, u, y, 0)
			fset(f, u, y, glass, -1)
	# the arch top narrows one step
	if w >= 2:
		for u in range(u0 + 1, u0 + w - 1):
			fdel(f, u, y0 + h, 0)
			fset(f, u, y0 + h, glass, -1)
	for y in range(y0 - 1, y0 + h + 1):
		fset(f, u0 - 1, y, frame, 0)
		fset(f, u0 + w, y, frame, 0)
	for u in range(u0, u0 + w):
		fset(f, u, y0 - 1, frame, 0)
	var uc := u0 + (w - 1) / 2.0
	fdet(f, uc, y0 + h + 0.5, 0.2, maxf(w - 1.6, 0.6), 0.4, 0.4, frame)
	fdet(f, uc, y0 - 0.6, 0.6, w + 1.2, 0.25, 0.4, frame)
	if h >= 3:
		fdet(f, uc, y0 + (h - 1) / 2.0, -0.45, w, 0.14, 0.1, "metal")
	if w >= 2:
		fdet(f, uc, y0 + (h - 1) / 2.0, -0.45, 0.14, h, 0.1, "metal")


# ------------------------------------------------------------------ props
var lamp_spots: Array[Vector3] = []


func lantern(x: float, y: float, z: float) -> void:
	det(x, y + 0.4, z, 0.64, 0.14, 0.64, "metal")
	det(x, y + 0.53, z, 0.3, 0.12, 0.3, "metal")
	det(x, y, z, 0.46, 0.62, 0.46, "lamp")
	det(x, y - 0.37, z, 0.58, 0.12, 0.58, "metal")
	for dx in [-0.25, 0.25]:
		for dz in [-0.25, 0.25]:
			det(x + dx, y, z + dz, 0.08, 0.64, 0.08, "metal")
	lamp_spots.append(Vector3(x, y, z))


func lamp_post(x: int, z: int, h: int, base_y: int = 1) -> void:
	for y in range(base_y, base_y + h):
		put(x, y, z, "wood")
	lantern(x, base_y + h - 1 + 0.95, z)


func barrel(x: int, z: int, h: int = 2, base_y: int = 1) -> void:
	for y in range(base_y, base_y + h):
		put(x, y, z, "barrel")
		det(x, y - 0.3, z, 1.04, 0.1, 1.04, "metal")
		det(x, y + 0.3, z, 1.04, 0.1, 1.04, "metal")


func crate(x: int, y: int, z: int) -> void:
	put(x, y, z, "crate")
	det(x, y + 0.46, z, 1.06, 0.14, 1.06, "plank")
	det(x, y - 0.46, z, 1.06, 0.14, 1.06, "plank")
	det(x, y, z, 1.06, 1.06, 0.14, "plank")
	det(x, y, z, 0.14, 1.06, 1.06, "plank")


func bush(cx: float, cz: float, r: float, base_y: int = 1) -> void:
	for x in range(floori(cx - r), ceili(cx + r) + 1):
		for y in range(base_y, base_y + ceili(r * 1.2)):
			for z in range(floori(cz - r), ceili(cz + r) + 1):
				var d := Vector3(x - cx, (y - base_y + 0.4) * 1.1, z - cz).length()
				if d < r - rnd() * 0.7 and not has_v(x, y, z):
					put(x, y, z, "leafLight" if y >= base_y + 1 and rnd() < 0.5 else pick(["leaf", "leaf", "leafDark"]))


func rock(cx: float, cz: float, r: float, base_y: int = 1) -> void:
	for x in range(floori(cx - r), ceili(cx + r) + 1):
		for y in range(base_y, base_y + ceili(r)):
			for z in range(floori(cz - r), ceili(cz + r) + 1):
				var d := Vector3(x - cx, (y - base_y + 0.4) * 1.3, z - cz).length()
				if d < r - rnd() * 0.6 and not has_v(x, y, z):
					put(x, y, z, "moss" if y > base_y and rnd() < 0.25 else pick(["stone", "stoneDark", "stoneLight", "rock"]))


func tree(tx: int, tz: int, trunk_h: int, r: float, base_y: int = 1) -> void:
	fill(tx, tx + 1, base_y, base_y + trunk_h - 1, tz, tz + 1, "log")
	put(tx + 2, base_y + trunk_h - 2, tz + 1, "log")
	put(tx - 1, base_y + trunk_h - 1, tz, "log")
	var top := base_y + trunk_h - 1
	var c := Vector3(tx + 0.5, top + r * 0.7, tz + 0.5)
	for x in range(floori(c.x - r), ceili(c.x + r) + 1):
		for y in range(floori(c.y - r), ceili(c.y + r) + 1):
			for z in range(floori(c.z - r), ceili(c.z + r) + 1):
				var dy := y - c.y
				var d := Vector3(x - c.x, dy * 1.15, z - c.z).length()
				if d < r - rnd() * 0.9 and not has_v(x, y, z) and y > top - 2:
					var k: String
					if dy > 1.2:
						k = pick(["leafLight", "leafLight", "leaf"])
					elif dy < -1.2:
						k = pick(["leafDark", "leafDark", "leaf"])
					else:
						k = pick(["leaf", "leaf", "leafLight", "leafDark"])
					put(x, y, z, k)


func pine(tx: int, tz: int, h: int, r: float, base_y: int = 1) -> void:
	var trunk := maxi(2, h / 5)
	for y in range(base_y, base_y + trunk + 1):
		put(tx, y, tz, "log")
	var y0 := base_y + trunk
	for y in range(y0, base_y + h):
		var t := float(y - y0) / float(h - trunk)
		# stepped tiers: every 3 rows the radius jumps back out a little
		var rr := r * (1.0 - t) * (0.8 + 0.2 * float((y - y0) % 3 == 0)) + 0.3
		for x in range(floori(tx - rr), ceili(tx + rr) + 1):
			for z in range(floori(tz - rr), ceili(tz + rr) + 1):
				if Vector2(x - tx, z - tz).length() <= rr - rnd() * 0.4:
					put(x, y, z, "pineLight" if (y - y0) % 3 == 0 and rnd() < 0.5 else pick(["pine", "pine", "pineDark"]))
	put(tx, base_y + h, tz, "pine")


## a pixel picture on both faces of a sign board lying in the xy plane (rows top to bottom,
## one char per pixel); the back is mirrored so it reads from behind too
func pixel_art(center: Vector3, rows: Array, colors: Dictionary, px: float, off: float) -> void:
	var nr := rows.size()
	var nc := 0
	for r in rows:
		nc = maxi(nc, (r as String).length())
	for r in nr:
		var row: String = rows[r]
		for c in row.length():
			if not colors.has(row[c]):
				continue
			var du := -(nc * px) / 2.0 + px / 2.0 + c * px
			var dy := (nr * px) / 2.0 - px / 2.0 - r * px
			det(center.x + du, center.y + dy, center.z + off, px, px, 0.1, colors[row[c]])
			det(center.x - du, center.y + dy, center.z - off, px, px, 0.1, colors[row[c]])


# ------------------------------------------------------------------ meshing
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _col := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _idx := PackedInt32Array()


func _quad(c: Vector3, n: Vector3, half: Vector3, code: int) -> void:
	var v := Vector3(0, 0, 1) if absf(n.y) > 0.5 else Vector3.UP
	var u := v.cross(n)
	var hu := u * (absf(u.x) * half.x + absf(u.y) * half.y + absf(u.z) * half.z)
	var hv := v * (absf(v.x) * half.x + absf(v.y) * half.y + absf(v.z) * half.z)
	var fc := c + n * (absf(n.x) * half.x + absf(n.y) * half.y + absf(n.z) * half.z)
	var base := _pos.size()
	var kind := code / VARS
	var colr: Color = _colors[code]
	var extra := Vector2(float((code % VARS) % 4), _emit[kind])
	var corners := [fc - hu - hv, fc + hu - hv, fc + hu + hv, fc - hu + hv]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in 4:
		_pos.append((corners[i] - origin) * scale)
		_nrm.append(n)
		_col.append(colr)
		_uv.append(uvs[i])
		_uv2.append(extra)
	# Godot treats clockwise as the front face
	_idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


func commit() -> ArrayMesh:
	_pos.clear(); _nrm.clear(); _col.clear(); _uv.clear(); _uv2.clear(); _idx.clear()
	for k in vox:
		var z: int = (k % 1024) - 256
		var y: int = ((k / 1024) % 1024) - 256
		var x: int = (k / 1048576) - 256
		var code: int = vox[k]
		var c := Vector3(x, y, z)
		var half := Vector3(0.5, 0.5, 0.5)
		if y == 0:
			c.y = 0.5 - ground_slab * 0.5
			half.y = ground_slab * 0.5
		for d in DIRS:
			if d.y < 0 and y <= floor_y:
				continue
			if vox.has(key(x + d.x, y + d.y, z + d.z)):
				continue
			_quad(c, Vector3(d), half, code)
	for dd in details:
		var p: Vector3 = dd[0]
		var s: Vector3 = dd[1]
		for d in DIRS:
			if d.y < 0 and p.y - s.y * 0.5 <= 0.51:
				continue
			_quad(p, Vector3(d), s * 0.5, dd[2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	if _pos.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## voxel-space bounds of all blocks and details: [min, max]
func bounds() -> AABB:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for k in vox:
		var p := Vector3((k / 1048576) - 256, ((k / 1024) % 1024) - 256, (k % 1024) - 256)
		lo = lo.min(p - Vector3.ONE * 0.5)
		hi = hi.max(p + Vector3.ONE * 0.5)
	for dd in details:
		lo = lo.min(dd[0] - dd[1] * 0.5)
		hi = hi.max(dd[0] + dd[1] * 0.5)
	return AABB(lo, hi - lo)


static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/town_voxel.gdshader")
	return _material
