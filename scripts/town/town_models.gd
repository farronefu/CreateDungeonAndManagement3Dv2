class_name TownModels
extends RefCounted
## Voxel-art models for the heroes' town. Each building is authored in its own voxel space
## (x right, y up, z towards the camera = the building front, ground layer y = 0) and meshed
## by VoxelBuilder. `mesh(name)` returns the mesh with its origin at the centre of the front
## edge on the ground, so the town can line the buildings up along the road.
##
## Everything is generated at start-up (about 0.5 s for the whole town) and cached for the
## session.

const VOX := 0.22                 # world size of one building voxel (a door is ~0.9 tall)
const TREE_VOX := 0.3
const MOUNTAIN_VOX := 3.0
const BUILDINGS := ["castle", "house", "armor_shop", "weapon_shop", "church", "inn"]
const TREES := ["tree_a", "tree_b", "tree_c", "pine_a", "pine_b", "pine_c"]
const ALL := BUILDINGS + TREES + ["mountains"]

const STONE := ["stone", "stone", "stone", "stoneDark", "stoneLight", "cobble"]
const PATH := ["cobble", "cobble", "stone", "stoneDark", "stoneLight", "moss"]
const PLASTER := ["plaster", "plaster", "plaster", "plasterDark"]
const CASTLE := ["castle", "castle", "castle", "castleDark", "castleLight"]
const SANDSTONE := ["sand", "sand", "sand", "sandDark", "stoneLight"]
const RED := ["roof", "roofLight", "roofDark"]
const BLUE := ["blue", "blueLight", "blueDark"]

static var _cache := {}


static func F(axis: String, c: int, out: int) -> Dictionary:
	return VoxelBuilder.face(axis, c, out)


## mesh + size info: {mesh, width, depth, height} (world units)
static func get_model(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var m := build(name)
	var aabb := m.get_aabb()
	var info := {"mesh": m, "width": aabb.size.x, "depth": aabb.size.z, "height": aabb.size.y, "aabb": aabb}
	_cache[name] = info
	return info


static func build(name: String) -> ArrayMesh:
	var b: VoxelBuilder = Callable(TownModels, name).call()
	if name.begins_with("tree") or name.begins_with("pine"):
		# trees stand on their trunk (a 2x2 trunk for broadleaf trees, 1x1 for pines)
		b.scale = TREE_VOX
		b.origin = Vector3(0.5, 0.5, 0.5) if name.begins_with("tree") else Vector3(0, 0.5, 0)
		return b.commit()
	if name == "mountains":
		b.scale = MOUNTAIN_VOX
		b.origin = Vector3(0, 0.5, 0)
		return b.commit()
	b.scale = VOX
	var bb := b.bounds()
	b.origin = Vector3(bb.position.x + bb.size.x * 0.5, 0.5, bb.end.z)
	return b.commit()


# ================================================================== INN
## Faithful port of voxel-inn.html (the reference supplied with the request), minus its
## floating island base and the big trees (the town ground and forest provide those).
static func inn() -> VoxelBuilder:
	var b := VoxelBuilder.new(20260925)
	# path & patio
	for z in range(25, 32):
		var cx := 15 + roundi(sin((z - 25) / 3.2) * 1.3)
		for x in range(cx - 2, cx + 3):
			if (x == cx - 2 or x == cx + 2) and b.rnd() < 0.35:
				continue
			b.put(x, 0, z, PATH)
	for x in range(18, 32):
		for z in range(22, 28):
			var edge := x == 18 or x == 31 or z == 22 or z == 27
			if edge and b.rnd() < 0.4:
				continue
			b.put(x, 0, z, PATH)

	# ---- east wing (built first; the main block overwrites where they meet)
	b.fill(21, 29, 1, 5, 12, 21, STONE)
	for y in range(1, 6):
		b.put(29, y, 21, "wood"); b.put(29, y, 12, "wood")
	b.fill(21, 30, 6, 6, 11, 20, "wood")
	b.fill(22, 30, 7, 10, 11, 19, PLASTER)
	b.fill(22, 30, 11, 11, 11, 19, "wood")
	for y in range(7, 11):
		b.put(30, y, 19, "wood"); b.put(26, y, 11, "wood"); b.put(30, y, 11, "wood")
		for z in [11, 15, 19]:
			b.put(30, y, z, "wood")
	for k in range(0, 7):
		var y := 11 + k
		var zl := 9 + k
		var zr := 21 - k
		for x in range(21, 33):
			if k > 0 and x <= 30:
				for z in range(zl + 1, zr):
					b.put(x, y, z, PLASTER)
			b.put(x, y, zl, b.roof_k(y)); b.put(x, y, zr, b.roof_k(y))
			if not b.has_v(x, y - 1, zl): b.put(x, y - 1, zl, "roofDark")
			if not b.has_v(x, y - 1, zr): b.put(x, y - 1, zr, "roofDark")
		if zl + 1 < zr - 1:
			b.put(31, y, zl + 1, "wood"); b.put(31, y, zr - 1, "wood")
	for x in range(21, 33):
		b.put(x, 18, 15, "roofDark")
	b.window_at(F("x", 30, 1), 14, 12, 3, 2)
	b.window_at(F("z", 19, 1), 25, 8, 3, 2)
	b.window_at(F("x", 30, 1), 14, 8, 3, 2, true)
	b.window_at(F("z", 21, 1), 24, 2, 3, 3, true, true)
	b.window_at(F("z", 12, -1), 24, 2, 3, 3, true)
	# balcony
	b.fill(22, 30, 6, 6, 20, 22, "plank")
	for x in range(22, 31):
		if x % 2 == 0:
			b.put(x, 7, 22, "wood")
		b.put(x, 8, 22, "wood")
	b.put(30, 7, 20, "wood"); b.put(30, 8, 20, "wood"); b.put(30, 8, 21, "wood")
	for x in [25, 29]:
		b.put(x, 5, 22, "woodDark")
	b.plants_box(22.6, 29.4, 21.7, 22.3, 8.5, 22)
	# lean-to shed with barrels & firewood
	for z in range(13, 22):
		b.put(30, 5, z, b.roof_k(5)); b.put(31, 5, z, b.roof_k(5)); b.put(32, 4, z, b.roof_k(4)); b.put(33, 4, z, b.roof_k(4)); b.put(31, 4, z, "roofDark")
	for y in range(1, 4):
		b.put(33, y, 13, "wood"); b.put(33, y, 21, "wood")
	b.barrel(31, 15); b.barrel(31, 17)
	for z in range(18, 21):
		for y in range(1, 3):
			b.put(31, y, z, "log" if (y + z) % 2 else "plank")
	b.crate(32, 1, 19)
	# patio props
	b.barrel(27, 23); b.crate(28, 1, 23); b.crate(29, 1, 23); b.crate(29, 1, 24); b.crate(28, 2, 23)

	# ---- main block: stone ground floor
	b.fill(9, 20, 1, 5, 10, 22, STONE)
	for x in range(9, 21):
		b.put(x, 1, 22, "stoneDark"); b.put(x, 1, 10, "stoneDark")
	for z in range(10, 23):
		b.put(9, 1, z, "stoneDark")
	for y in range(1, 6):
		b.put(9, y, 22, "wood"); b.put(20, y, 22, "wood"); b.put(9, y, 10, "wood"); b.put(20, y, 10, "wood")
	# door
	for y in range(1, 6):
		b.put(13, y, 22, "wood"); b.put(17, y, 22, "wood")
	for x in range(14, 17):
		for y in range(2, 6):
			b.put(x, y, 22, "doorDark" if x == 15 else "door")
		b.put(x, 1, 22, "stoneLight")
	_door_hardware(b, 15, 22)
	b.fill(12, 18, 1, 1, 23, 24, ["stoneLight", "stone", "stone"])
	b.put(12, 2, 24, "stoneDark"); b.put(18, 2, 24, "stoneDark")
	b.plants_box(11.6, 12.4, 23.6, 24.4, 2.5, 9); b.plants_box(17.6, 18.4, 23.6, 24.4, 2.5, 9)
	b.window_at(F("x", 9, -1), 15, 2, 3, 3, true, true)
	b.window_at(F("z", 10, -1), 14, 2, 3, 3, true)

	# ---- main block: timber-framed upper floor
	b.fill(8, 22, 6, 6, 9, 23, "wood")
	b.fill(8, 22, 7, 11, 9, 23, PLASTER)
	b.fill(8, 22, 12, 12, 9, 23, "wood")
	for y in range(7, 12):
		for x in [8, 15, 22]:
			b.put(x, y, 23, "wood"); b.put(x, y, 9, "wood")
		for z in [9, 16, 23]:
			b.put(8, y, z, "wood"); b.put(22, y, z, "wood")
	for x in [9, 13, 17, 20]:
		b.put(x, 5, 23, "woodDark")
	for z in [10, 16, 22]:
		b.put(8, 5, z, "woodDark")
	# porch awning
	for x in range(9, 22):
		b.put(x, 6, 24, b.roof_k(6))
	b.window_at(F("z", 23, 1), 10, 8, 3, 3, true, true)
	b.window_at(F("z", 23, 1), 17, 8, 3, 3, true, true)
	b.window_at(F("x", 8, -1), 11, 8, 3, 3, true)
	b.window_at(F("x", 8, -1), 18, 8, 3, 3, true)
	b.window_at(F("x", 22, 1), 21, 8, 1, 3)
	b.window_at(F("z", 9, -1), 10, 8, 3, 3, true)
	b.window_at(F("z", 9, -1), 17, 8, 3, 3, true)

	# ---- main roof (ridge runs front-to-back)
	_gable_z(b, 12, 6, 24, 9, 8, 24, 9, 23, PLASTER, RED)
	for y in range(13, 17):
		b.put(11, y, 23, "wood"); b.put(19, y, 23, "wood"); b.put(11, y, 9, "wood"); b.put(19, y, 9, "wood")
	for x in range(12, 19):
		b.put(x, 17, 23, "wood"); b.put(x, 17, 9, "wood")
	b.window_at(F("z", 23, 1), 14, 14, 3, 3)
	b.window_at(F("z", 9, -1), 14, 14, 3, 3)

	# ---- dormer on the west slope
	b.fill(8, 13, 14, 17, 14, 18, PLASTER)
	for y in range(14, 18):
		b.put(8, y, 14, "wood"); b.put(8, y, 18, "wood")
	for k in range(0, 4):
		var y := 18 + k
		var zl := 13 + k
		var zr := 19 - k
		for x in range(7, 15):
			if x >= 8:
				for z in range(zl + 1, zr):
					b.put(x, y, z, PLASTER)
			b.put(x, y, zl, b.roof_k(y)); b.put(x, y, zr, b.roof_k(y))
			if not b.has_v(x, y - 1, zl): b.put(x, y - 1, zl, "roofDark")
			if not b.has_v(x, y - 1, zr): b.put(x, y - 1, zr, "roofDark")
	b.window_at(F("x", 8, -1), 15, 15, 3, 2, false, true)

	# ---- chimney
	b.fill(17, 19, 12, 23, 12, 14, STONE)
	b.fill(17, 19, 24, 24, 12, 14, "stoneDark")

	# ---- hanging inn sign
	b.fill(2, 7, 11, 11, 23, 23, "wood")
	b.put(7, 10, 23, "woodDark")
	for x in [3, 5]:
		b.det(x, 10.25, 23, 0.14, 0.5, 0.14, "metal"); b.det(x, 9.85, 23, 0.22, 0.22, 0.22, "metal")
	b.fill(2, 6, 7, 9, 23, 23, "sign")
	b.det(4, 8, 23, 5.1, 3.1, 0.6, "woodDark")
	b.pixel_art(Vector3(4, 8, 23), [
		"###.#..#.#..#",
		".#..##.#.##.#",
		".#..#.##.#.##",
		".#..#..#.#..#",
		"###.#..#.#..#"], {"#": "signIcon"}, 0.3, 0.52)

	# ---- lanterns
	b.lantern(12, 3.4, 23.05); b.det(12, 4.15, 22.75, 0.12, 0.12, 0.5, "metal")
	b.lantern(18, 3.4, 23.05); b.det(18, 4.15, 22.75, 0.12, 0.12, 0.5, "metal")
	b.lamp_post(11, 31, 3); b.lamp_post(33, 26, 3)

	# ---- fence
	for x in [2, 5, 8]:
		b.put(x, 1, 31, "wood"); b.put(x, 2, 31, "wood")
	b.det(5, 1.15, 31, 6, 0.22, 0.24, "plank"); b.det(5, 1.9, 31, 6, 0.22, 0.24, "plank")
	for z in [25, 28]:
		b.put(2, 1, z, "wood"); b.put(2, 2, z, "wood")
	b.det(2, 1.15, 28, 0.24, 0.22, 6, "plank"); b.det(2, 1.9, 28, 0.24, 0.22, 6, "plank")

	# ---- bench & cart wheel
	_bench(b, 20, 25.4)
	_wheel(b, 22.3, 1.85, 22.2, 1.2)

	# ---- greenery
	for q in [[2, 23, 1.8], [8, 26, 1.4], [24, 29, 1.6], [31, 29, 1.8], [7, 20, 1.2], [4, 16, 1.6]]:
		b.bush(q[0], q[1], q[2])
	return b


# ================================================================== HOUSE
## Two-storey timber-framed cottage with a porch, a dormer, a log shed and a vegetable garden.
static func house() -> VoxelBuilder:
	var b := VoxelBuilder.new(7101)
	# path from the door to the road
	for z in range(19, 28):
		var cx := 9 + roundi(sin((z - 19) / 3.0) * 1.0)
		for x in range(cx - 1, cx + 2):
			b.put(x, 0, z, PATH)
		if b.rnd() < 0.5:
			b.put(cx + (2 if b.rnd() < 0.5 else -2), 0, z, PATH)

	# ---- ground floor: stone plinth, plaster, timber posts
	b.fill(6, 18, 1, 2, 8, 18, STONE)
	b.fill(6, 18, 3, 5, 8, 18, PLASTER)
	for y in range(1, 6):
		for p in [[6, 18], [18, 18], [6, 8], [18, 8], [7, 18], [11, 18]]:
			b.put(p[0], y, p[1], "wood")
	for x in range(8, 11):
		for y in range(2, 6):
			b.put(x, y, 18, "doorDark" if x == 9 else "door")
		b.put(x, 1, 18, "stoneLight")
	_door_hardware(b, 9, 18)
	b.fill(8, 10, 1, 1, 19, 19, ["stoneLight", "stone"])
	b.window_at(F("z", 18, 1), 13, 2, 3, 3, true, true)
	b.window_at(F("x", 18, 1), 11, 2, 3, 3, true)
	b.window_at(F("x", 6, -1), 11, 2, 3, 3, true)

	# ---- porch roof over the door on two posts
	for x in range(6, 13):
		b.put(x, 6, 20, b.roof_k(6)); b.put(x, 5, 21, b.roof_k(5))
	for y in range(1, 5):
		b.put(6, y, 21, "wood"); b.put(12, y, 21, "wood")
	b.lantern(12, 3.4, 19.05); b.det(12, 4.15, 18.75, 0.12, 0.12, 0.5, "metal")

	# ---- jettied upper floor
	b.fill(5, 19, 6, 6, 7, 19, "wood")
	b.fill(5, 19, 7, 10, 7, 19, PLASTER)
	b.fill(5, 19, 11, 11, 7, 19, "wood")
	for y in range(7, 11):
		for x in [5, 12, 19]:
			b.put(x, y, 19, "wood"); b.put(x, y, 7, "wood")
		for z in [7, 13, 19]:
			b.put(5, y, z, "wood"); b.put(19, y, z, "wood")
	b.window_at(F("z", 19, 1), 8, 8, 3, 2, true, true)
	b.window_at(F("z", 19, 1), 14, 8, 3, 2, true, true)
	b.window_at(F("x", 19, 1), 15, 8, 3, 2, true)
	b.window_at(F("x", 5, -1), 9, 8, 3, 2, true)

	# ---- roof (ridge front-to-back) with a framed gable
	_gable_z(b, 12, 3, 21, 9, 6, 20, 7, 19, PLASTER, RED)
	for y in range(13, 17):
		b.put(9, y, 19, "wood"); b.put(15, y, 19, "wood")
	for x in range(10, 15):
		b.put(x, 17, 19, "wood")
	b.window_at(F("z", 19, 1), 11, 14, 3, 2, true)

	# ---- dormer on the east slope
	b.fill(13, 17, 14, 16, 11, 15, PLASTER)
	for y in range(14, 17):
		b.put(17, y, 11, "wood"); b.put(17, y, 15, "wood")
	for k in range(0, 4):
		var y := 17 + k
		var zl := 10 + k
		var zr := 16 - k
		for x in range(12, 19):
			if x <= 17:
				for z in range(zl + 1, zr):
					b.put(x, y, z, PLASTER)
			b.put(x, y, zl, b.roof_k(y)); b.put(x, y, zr, b.roof_k(y))
			if not b.has_v(x, y - 1, zl): b.put(x, y - 1, zl, "roofDark")
			if not b.has_v(x, y - 1, zr): b.put(x, y - 1, zr, "roofDark")
	b.window_at(F("x", 17, 1), 12, 14, 3, 2, false, true)

	# ---- chimney
	b.fill(7, 9, 12, 23, 10, 12, STONE)
	b.fill(7, 9, 24, 24, 10, 12, "stoneDark")

	# ---- log shed on the east wall
	for z in range(9, 16):
		b.put(19, 5, z, b.roof_k(5)); b.put(20, 5, z, b.roof_k(5)); b.put(21, 4, z, b.roof_k(4)); b.put(22, 4, z, b.roof_k(4)); b.put(20, 4, z, "roofDark")
	for y in range(1, 4):
		b.put(22, y, 9, "wood"); b.put(22, y, 15, "wood")
	for z in range(10, 15):
		for y in range(1, 4):
			for x in [19, 20]:
				b.put(x, y, z, "log" if (y + z + x) % 2 else "plank")
	b.crate(21, 1, 14)

	# ---- vegetable garden with a fence
	for x in range(22, 30):
		for z in range(17, 25):
			b.put(x, 0, z, "dirtDark" if z % 3 == 0 else "dirt")
	for x in range(22, 30):
		for z in [18, 21, 24]:
			if b.rnd() < 0.6:
				b.det(x, 0.72, z, 0.3, 0.4, 0.3, "carrot")
				b.det(x, 1.08, z, 0.46, 0.4, 0.46, ["leafLight", "leaf"])
			else:
				b.det(x, 0.78, z, 0.62, 0.55, 0.62, ["leaf", "leafLight"])
	for i in 26:
		var hx := 22.0 + b.rnd() * 7.6
		b.det(hx, 1.2, 16.4 + b.rnd() * 0.8, 0.2, 1.3 + b.rnd() * 0.3, 0.2, "hay")
	_fence(b, [Vector2i(21, 25), Vector2i(25, 25), Vector2i(30, 25), Vector2i(30, 20), Vector2i(30, 16)])
	b.barrel(20, 21)

	# ---- yard: bench, bushes, lamp, flowers
	_bench(b, 2.5, 22.4)
	b.lamp_post(4, 26, 3)
	for q in [[3, 17, 1.6], [15, 22, 1.2], [13, 25, 1.1], [18, 26, 1.3]]:
		b.bush(q[0], q[1], q[2])
	b.plants_box(6.6, 7.4, 19.6, 20.4, 0.6, 6)
	return b


# ================================================================== ARMOR SHOP
## Timber-framed shop with a lit display of helmets and breastplates, a hanging helmet sign
## and an open porch with two armour stands and shields.
static func armor_shop() -> VoxelBuilder:
	var b := VoxelBuilder.new(7202)
	# ---- porch wing (built first; the main block overwrites where they meet)
	b.fill(19, 28, 1, 1, 11, 19, "plank")
	b.fill(19, 28, 1, 8, 10, 10, STONE)
	b.fill(28, 28, 1, 8, 10, 14, STONE)
	for y in range(2, 7):
		b.put(28, y, 19, "wood"); b.put(24, y, 19, "wood")
	_lean_to(b, 19, 29, 9, 21, 9, RED)
	_armor_stand(b, 21.5, 1.5, 15.0)
	_armor_stand(b, 25.5, 1.5, 15.0)
	_shield(b, 20.6, 5.2, 10.62, "shieldBlue")
	_shield(b, 23.5, 5.6, 10.62, "shieldRed")
	_shield(b, 26.4, 5.2, 10.62, "shieldBlue")
	# table of boots and gauntlets in front
	b.det(25, 1.9, 21.6, 3.4, 0.2, 1.3, "plank")
	for x in [23.6, 26.4]:
		for z in [21.1, 22.1]:
			b.det(x, 1.2, z, 0.2, 1.3, 0.2, "woodDark")
	for x in [24.0, 24.6]:
		b.det(x, 2.25, 21.6, 0.36, 0.5, 0.7, "leather"); b.det(x, 2.1, 21.95, 0.36, 0.2, 0.2, "leather")
	for x in [25.6, 26.3]:
		b.det(x, 2.15, 21.6, 0.4, 0.3, 0.55, "steel")
	b.lantern(24, 6.0, 19.8)

	# ---- main block ground floor
	b.fill(4, 18, 1, 5, 8, 18, STONE)
	for x in range(4, 19):
		b.put(x, 1, 18, "stoneDark")
	for y in range(1, 6):
		for x in [4, 8, 9, 17, 18]:
			b.put(x, y, 18, "wood")
	for x in range(5, 8):
		for y in range(2, 6):
			b.put(x, y, 18, "doorDark" if x == 6 else "door")
		b.put(x, 1, 18, "stoneLight")
	_door_hardware(b, 6, 18)
	b.fill(5, 7, 1, 1, 19, 19, ["stoneLight", "stone"])
	# lit display window with helmets and breastplates
	_display(b, 10, 16, 18)
	for i in 3:
		var x := 10.9 + i * 2.1
		_helmet(b, x, 3.35, 16.95)
		_cuirass(b, x, 2.1, 17.1)
	b.lantern(3, 3.4, 19.05)

	# ---- jettied upper floor
	b.fill(3, 19, 6, 6, 7, 19, "wood")
	b.fill(3, 19, 7, 11, 7, 19, PLASTER)
	b.fill(3, 19, 12, 12, 7, 19, "wood")
	for y in range(7, 12):
		for x in [3, 11, 19]:
			b.put(x, y, 19, "wood"); b.put(x, y, 7, "wood")
		for z in [7, 13, 19]:
			b.put(3, y, z, "wood"); b.put(19, y, z, "wood")
	# braces
	for i in 3:
		b.put(4 + i, 7 + i, 19, "wood"); b.put(18 - i, 7 + i, 19, "wood")
	b.window_at(F("z", 19, 1), 6, 8, 3, 3, true, true)
	b.window_at(F("z", 19, 1), 13, 8, 3, 3, true, true)
	b.window_at(F("x", 19, 1), 12, 8, 3, 3, true)
	# awning over the display
	for x in range(9, 18):
		b.put(x, 6, 20, b.roof_k(6)); b.put(x, 5, 21, b.roof_k(5))

	# ---- roof
	_gable_z(b, 13, 1, 21, 10, 6, 20, 7, 19, PLASTER, RED)
	for y in range(14, 18):
		b.put(8, y, 19, "wood"); b.put(14, y, 19, "wood")
	for x in range(9, 14):
		b.put(x, 18, 19, "wood")
	b.window_at(F("z", 19, 1), 10, 15, 3, 2, true, true)
	b.fill(15, 17, 13, 25, 10, 12, STONE)
	b.fill(15, 17, 26, 26, 10, 12, "stoneDark")

	# ---- hanging sign: helmet and shield
	_sign(b, 3, 19, [
		"..sss.....bbbbb",
		".sssss....bbybb",
		"sssssss...byyyb",
		"skkkkks...bbybb",
		"sssksss...bbybb",
		"ss.k.ss....byb.",
		"............b.."], {"s": "steelLight", "k": "metal", "b": "shieldBlue", "y": "gold"})

	# ---- yard
	for z in range(20, 27):
		for x in range(5, 8):
			b.put(x, 0, z, PATH)
		if b.rnd() < 0.5:
			b.put(4 if b.rnd() < 0.5 else 8, 0, z, PATH)
	for x in range(9, 29):
		for z in range(20, 24):
			if b.rnd() < 0.8 and not (x >= 23 and z >= 21):
				b.put(x, 0, z, PATH)
	b.crate(1, 1, 16); b.crate(1, 1, 17); b.crate(1, 2, 16)
	b.barrel(2, 20)
	b.lamp_post(10, 26, 3)
	for q in [[0, 22, 1.4], [14, 25, 1.2], [20, 25, 1.5], [29, 23, 1.4]]:
		b.bush(q[0], q[1], q[2])
	return b


# ================================================================== WEAPON SHOP
## Shop with a lit wall of swords and axes, a weapon rack outside, a crossed-swords sign and a
## forge under a lean-to: glowing hearth, anvil, quench barrel, coal and ingots, tall chimney.
static func weapon_shop() -> VoxelBuilder:
	var b := VoxelBuilder.new(7303)
	# ---- forge wing (first; main block overwrites the seam)
	b.fill(19, 28, 0, 0, 11, 20, ["stone", "cobble", "stoneDark"])
	_lean_to(b, 19, 29, 8, 21, 9, RED)
	for y in range(1, 6):
		b.put(28, y, 20, "wood")
	b.fill(22, 27, 1, 4, 9, 12, STONE)
	b.clear(23, 26, 2, 3, 12, 12)
	b.fill(23, 26, 1, 1, 11, 12, "coal")
	for x in range(23, 27):
		b.put(x, 2, 11, "fire")
	b.det(24.5, 2.5, 11.9, 3.2, 0.7, 0.5, "fire")
	b.det(24.5, 2.95, 11.7, 1.8, 0.5, 0.4, "lamp")
	b.fill(22, 27, 5, 6, 9, 12, "stoneDark")
	b.fill(23, 26, 7, 28, 9, 11, STONE)
	b.fill(23, 26, 29, 29, 9, 11, "stoneDark")
	# anvil with a hammer
	b.det(22.5, 1.15, 16, 0.6, 0.7, 0.5, "metal")
	b.det(22.5, 0.65, 16, 1.0, 0.3, 0.8, "metal")
	b.det(22.5, 1.68, 16, 1.5, 0.35, 0.6, "metal")
	b.det(23.45, 1.68, 16, 0.5, 0.2, 0.3, "metal")
	b.det(22.3, 1.93, 16, 0.2, 0.15, 0.8, "plank")
	b.det(22.3, 1.96, 16.45, 0.34, 0.26, 0.26, "steelDark")
	# quench barrel, coal crate, ingots
	b.barrel(27, 16)
	b.det(27, 2.46, 16, 0.8, 0.05, 0.8, "water")
	b.crate(26, 1, 18)
	for i in 7:
		b.det(25.7 + b.rnd() * 0.6, 1.62, 17.7 + b.rnd() * 0.6, 0.32, 0.26, 0.32, "coal")
	b.crate(20, 1, 18)
	for i in 3:
		b.det(20, 1.62 + i * 0.2, 18, 0.7 - i * 0.12, 0.2, 0.34, "steel")
	# tongs and hammers on the hearth side
	for i in 3:
		b.det(21.45, 3.2, 10.6 + i * 0.5, 0.1, 1.0, 0.12, "metal")

	# ---- main block ground floor
	b.fill(4, 18, 1, 5, 8, 18, PLASTER)
	b.fill(4, 18, 1, 1, 8, 18, STONE)
	for y in range(1, 6):
		for x in [4, 18]:
			b.put(x, y, 18, STONE); b.put(x, y, 8, STONE)
		b.put(8, y, 18, "wood"); b.put(17, y, 18, "wood")
	for x in range(5, 8):
		for y in range(2, 6):
			b.put(x, y, 18, "doorDark" if x == 6 else "door")
		b.put(x, 1, 18, "stoneLight")
	_door_hardware(b, 6, 18)
	b.fill(5, 7, 1, 1, 19, 19, ["stoneLight", "stone"])
	_display(b, 9, 16, 18, false)
	for i in 5:
		var x := 9.6 + i * 1.45
		if i == 3:
			_axe(b, x, 1.85, 16.62)
		else:
			_sword(b, x, 1.85, 16.62)
	b.window_at(F("x", 18, 1), 11, 2, 3, 3, true)
	b.lantern(3, 3.4, 19.05)

	# ---- upper floor
	b.fill(3, 19, 6, 6, 7, 19, "wood")
	b.fill(3, 19, 7, 11, 7, 19, PLASTER)
	b.fill(3, 19, 12, 12, 7, 19, "wood")
	for y in range(7, 12):
		for x in [3, 11, 19]:
			b.put(x, y, 19, "wood"); b.put(x, y, 7, "wood")
		for z in [7, 13, 19]:
			b.put(3, y, z, "wood"); b.put(19, y, z, "wood")
	b.window_at(F("z", 19, 1), 6, 8, 3, 3, true, true)
	b.window_at(F("z", 19, 1), 14, 8, 3, 3, true, true)
	for x in range(8, 18):
		b.put(x, 6, 20, b.roof_k(6))

	# ---- roof
	_gable_z(b, 13, 1, 21, 10, 6, 20, 7, 19, PLASTER, RED)
	for y in range(14, 18):
		b.put(8, y, 19, "wood"); b.put(14, y, 19, "wood")
	for x in range(9, 14):
		b.put(x, 18, 19, "wood")
	b.window_at(F("z", 19, 1), 10, 15, 3, 2, true, true)

	# ---- crossed swords sign
	_sign(b, 3, 19, [
		"l.......l",
		".l.....l.",
		"..l...l..",
		"...l.l...",
		"....l....",
		"...l.l...",
		".gg...gg.",
		"hg.....gh",
		"h.......h"], {"l": "steelLight", "g": "gold", "h": "leather"})

	# ---- weapon rack in front of the forge
	b.det(16.5, 1.5, 21.2, 0.25, 2.0, 0.25, "wood"); b.det(21.5, 1.5, 21.2, 0.25, 2.0, 0.25, "wood")
	b.det(19, 2.35, 21.2, 5.3, 0.2, 0.25, "plank"); b.det(19, 1.1, 21.2, 5.3, 0.2, 0.25, "plank")
	_sword(b, 17.4, 1.0, 21.45)
	_sword(b, 18.2, 1.0, 21.45)
	_spear(b, 19.0, 0.6, 21.45)
	_spear(b, 19.7, 0.6, 21.45)
	_axe(b, 20.6, 0.9, 21.45)

	# ---- yard
	for z in range(20, 27):
		for x in range(5, 8):
			b.put(x, 0, z, PATH)
		if b.rnd() < 0.5:
			b.put(4 if b.rnd() < 0.5 else 8, 0, z, PATH)
	for x in range(9, 29):
		for z in range(20, 23):
			if b.rnd() < 0.75:
				b.put(x, 0, z, PATH)
	b.barrel(1, 17); b.barrel(2, 19)
	b.lamp_post(10, 25, 3)
	for q in [[1, 23, 1.5], [13, 24, 1.3], [25, 24, 1.6], [30, 17, 1.4]]:
		b.bush(q[0], q[1], q[2])
	return b


# ================================================================== CHURCH
## Sandstone church with a blue roof, buttresses, stained-glass windows, a rose window over a
## pointed door and a bell tower with a bronze bell and a golden cross.
static func church() -> VoxelBuilder:
	var b := VoxelBuilder.new(7404)
	# ---- nave
	b.fill(8, 24, 1, 10, 0, 22, SANDSTONE)
	for x in range(8, 25):
		b.put(x, 1, 22, "stoneDark"); b.put(x, 1, 0, "stoneDark")
	for z in range(0, 23):
		b.put(8, 1, z, "stoneDark"); b.put(24, 1, z, "stoneDark")
	for y in range(1, 11):
		for p in [[8, 22], [24, 22], [8, 0], [24, 0]]:
			b.put(p[0], y, p[1], "stone")
	# buttresses
	for z in [2, 7, 12, 17]:
		b.fill(25, 26, 1, 4, z, z, STONE); b.fill(25, 25, 5, 8, z, z, STONE); b.put(26, 5, z, "stoneDark")
		b.fill(6, 7, 1, 4, z, z, STONE); b.fill(7, 7, 5, 8, z, z, STONE); b.put(6, 5, z, "stoneDark")
	for z in [4, 9, 14, 19]:
		b.arch_window(F("x", 24, 1), z, 3, 2, 4)
		b.arch_window(F("x", 8, -1), z, 3, 2, 4)
	# nave roof with the gable filled in sandstone
	_gable_z(b, 11, 6, 26, 10, -1, 23, 0, 22, SANDSTONE, BLUE)
	# stone cross on the front gable and a small one at the back
	for q in [[16, 22, 22], [16, 23, 22], [16, 24, 22], [15, 23, 22], [17, 23, 22], [16, 22, 0], [16, 23, 0], [15, 23, 0], [17, 23, 0]]:
		b.put(q[0], q[1], q[2], "stoneLight")

	# ---- front: pointed double door, steps, rose window
	b.fill(12, 20, 1, 1, 23, 24, ["stoneLight", "stone", "stone"])
	for x in range(14, 19):
		b.put(x, 1, 22, "stoneLight")
		for y in range(2, 7):
			b.put(x, y, 22, "doorDark" if x == 16 else "door")
	for x in range(15, 18):
		b.put(x, 7, 22, "door")
	b.put(16, 8, 22, "doorDark")
	for y in range(1, 8):
		b.put(13, y, 23, "stoneLight"); b.put(19, y, 23, "stoneLight")
	for q in [[14, 7], [18, 7], [14, 8], [18, 8], [15, 8], [17, 8], [15, 9], [17, 9], [16, 9], [16, 10]]:
		b.put(q[0], q[1], 23, "stoneLight")
	for x in [15.5, 16.5]:
		b.det(x, 4, 22.56, 0.26, 0.26, 0.1, "metal")
	for y in [3.0, 5.4]:
		b.det(16, y, 22.55, 4.8, 0.14, 0.08, "metal")
	# rose window
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var r := Vector2(dx, dy).length()
			var x := 16 + dx
			var y := 15 + dy
			if r <= 2.6:
				b.erase(x, y, 22)
				var k := "stainB"
				if r < 0.8:
					k = "stainR"
				elif dx == 0 or dy == 0:
					k = "stainY"
				elif absi(dx) == absi(dy):
					k = "stainR"
				b.put(x, y, 21, k)
			elif r <= 3.6:
				b.put(x, y, 23, "stoneLight")
	b.lantern(12, 4.4, 23.05); b.lantern(20, 4.4, 23.05)

	# ---- bell tower
	var TS := ["stone", "stone", "stoneLight", "stoneDark", "sand"]
	b.fill(1, 7, 1, 22, 15, 23, TS)
	for y in [9, 16]:
		for x in range(0, 9):
			b.put(x, y, 24, "wood")
		for z in range(14, 25):
			b.put(0, y, z, "wood")
	# belfry: hollow with openings on three sides
	b.clear(2, 6, 17, 20, 16, 22)
	b.clear(3, 5, 17, 20, 23, 23)
	b.clear(1, 1, 18, 20, 17, 21)
	b.clear(7, 7, 18, 20, 17, 21)
	b.det(4, 19.4, 19.5, 1.6, 1.4, 1.6, "bronze")
	b.det(4, 20.2, 19.5, 1.0, 0.5, 1.0, "bronze")
	b.det(4, 18.7, 19.5, 2.0, 0.3, 2.0, "gold")
	b.det(4, 18.4, 19.5, 0.3, 0.4, 0.3, "gold")
	b.det(4, 20.75, 19.5, 5, 0.3, 0.3, "wood")
	b.arch_window(F("z", 23, 1), 4, 5, 1, 3)
	b.arch_window(F("z", 23, 1), 3, 11, 3, 3)
	for x in range(0, 9):
		for z in range(14, 25):
			if x == 0 or x == 8 or z == 14 or z == 24:
				b.put(x, 22, z, "stoneDark")
	for k in range(0, 9):
		var r := 4 - k / 2
		b.fill(4 - r, 4 + r, 23 + k, 23 + k, 19 - r, 19 + r, b.roof_k(23 + k, BLUE))
	for y in range(31, 36):
		b.put(4, y, 19, "gold")
	b.put(3, 34, 19, "gold"); b.put(5, 34, 19, "gold")

	# ---- churchyard: low wall with lamp pillars, path, benches, flowers
	for x in range(0, 31):
		for z in range(23, 31):
			if (z >= 25 and x >= 12 and x <= 20) or (z >= 23 and z <= 26 and x >= 10 and x <= 22):
				b.put(x, 0, z, PATH)
	for x in range(0, 31):
		if x < 11 or x > 21:
			b.put(x, 1, 30, STONE)
			if x % 3 == 0:
				b.put(x, 2, 30, "stoneLight")
	for p in [10, 22]:
		b.fill(p, p, 1, 3, 30, 30, "stoneLight")
		b.lantern(p, 3.95, 30)
	for z in range(24, 30):
		b.put(0, 1, z, STONE); b.put(30, 1, z, STONE)
	_bench(b, 4.5, 26.4)
	_bench(b, 26.5, 26.4)
	for q in [[2, 28, 1.3], [8, 28, 1.2], [24, 28, 1.3], [29, 20, 1.6], [28, 10, 1.5], [9, 25, 1.0]]:
		b.bush(q[0], q[1], q[2])
	b.plants_box(10.6, 11.4, 23.6, 24.4, 1.5, 6)
	b.plants_box(20.6, 21.4, 23.6, 24.4, 1.5, 6)
	return b


# ================================================================== CASTLE
## The king's castle: curtain wall with crenellations and banners, a gatehouse with a raised
## portcullis, four round towers with blue cone roofs and a keep with a tall main tower.
static func castle() -> VoxelBuilder:
	var b := VoxelBuilder.new(7505)
	# ---- keep
	b.fill(16, 43, 1, 22, 6, 22, CASTLE)
	_ring(b, 15, 44, 5, 23, 23, "castleDark")
	_crenel(b, 15, 44, 5, 23, 24)
	for k in range(0, 10):
		b.fill(17 + k, 42 - k, 24 + k, 24 + k, 7 + k, 21 - k, b.roof_k(24 + k, BLUE))
	for x in [19, 24, 34, 39]:
		b.arch_window(F("z", 22, 1), x, 8, 2, 3, "castleLight", "glass")
		b.arch_window(F("z", 22, 1), x, 15, 2, 3, "castleLight", "glass")
	# main tower
	b.fill(26, 33, 1, 40, 8, 15, CASTLE)
	_ring(b, 25, 34, 7, 16, 41, "castleDark")
	for k in range(0, 10):
		var o := 1 - k / 2
		b.fill(26 - o, 33 + o, 42 + k, 42 + k, 8 - o, 15 + o, b.roof_k(42 + k, BLUE))
	b.arch_window(F("z", 15, 1), 29, 35, 2, 3, "castleLight", "glass")
	b.arch_window(F("z", 15, 1), 29, 28, 2, 2, "castleLight", "glass")
	_flag(b, 29.5, 52, 11.5)

	# ---- towers
	_round_tower(b, 10, 9, 4.5, 26)
	_round_tower(b, 49, 9, 4.5, 26)
	_round_tower(b, 6, 32, 5.0, 20)
	_round_tower(b, 53, 32, 5.0, 20)

	# ---- curtain walls
	b.fill(6, 53, 1, 12, 31, 33, CASTLE)
	b.fill(5, 7, 1, 12, 9, 32, CASTLE)
	b.fill(52, 54, 1, 12, 9, 32, CASTLE)
	b.fill(10, 49, 1, 12, 7, 8, CASTLE)
	for x in range(6, 54):
		if x % 2 == 0:
			b.put(x, 13, 33, CASTLE)
		b.put(x, 12, 34, "castleDark")
	for z in range(9, 33):
		if z % 2 == 0:
			b.put(5, 13, z, CASTLE); b.put(54, 13, z, CASTLE)
	# courtyard
	for x in range(8, 52):
		for z in range(23, 31):
			b.put(x, 0, z, PATH)
	# banners on the wall
	for x in [13, 19, 40, 46]:
		_banner(b, x, 8.0, 33.6, 2.0, 4.5)

	# ---- gatehouse
	b.fill(24, 35, 1, 17, 30, 36, CASTLE)
	_crenel(b, 24, 35, 30, 36, 18)
	for p in [23, 35]:
		b.fill(p, p + 1, 1, 20, 35, 37, CASTLE)
		for k in range(0, 3):
			b.fill(p - 1 + k / 2, p + 2 - k / 2, 21 + k, 21 + k, 34 + k / 2, 38 - k / 2, b.roof_k(21 + k, BLUE))
		b.put(p, 24, 36, "gold"); b.put(p + 1, 24, 36, "gold")
	b.clear(27, 32, 1, 7, 33, 37)
	b.clear(28, 31, 8, 8, 33, 37)
	b.clear(29, 30, 9, 9, 33, 37)
	b.fill(27, 32, 1, 9, 32, 32, "shadow")
	for x in range(27, 33):
		b.det(x, 7.2, 36.6, 0.2, 3.6, 0.2, "metal")
	for y in [6.0, 7.6]:
		b.det(29.5, y, 36.6, 6, 0.2, 0.2, "metal")
	for x in [27.2, 31.8]:
		b.det(x, 4.0, 34.0, 0.3, 6.5, 2.8, "doorDark")
	_banner(b, 29.5, 13.2, 36.6, 3.0, 4.6)
	b.lantern(26, 5.0, 37.05); b.lantern(33, 5.0, 37.05)

	# ---- plaza and path in front of the gate
	for x in range(22, 38):
		for z in range(37, 44):
			if z < 42 or (x >= 26 and x <= 33):
				if not ((x == 22 or x == 37) and b.rnd() < 0.4):
					b.put(x, 0, z, PATH)
	b.lamp_post(23, 42, 3); b.lamp_post(36, 42, 3)
	# moss creeping up the walls
	for k in b.vox.keys():
		var y: int = ((k / 1024) % 1024) - 256
		if y >= 1 and y <= 2 and b.rnd() < 0.18 and b.kind_at((k / 1048576) - 256, y, (k % 1024) - 256).begins_with("castle"):
			b.vox[k] = int(VoxelBuilder._kind_ids["moss"]) * VoxelBuilder.VARS + b.rng.randi() % VoxelBuilder.VARS
	for q in [[3, 38, 1.6], [12, 36, 1.4], [18, 36, 1.3], [41, 36, 1.3], [47, 36, 1.4], [56, 38, 1.6]]:
		b.bush(q[0], q[1], q[2])
	return b


# ================================================================== TREES
static func tree_a() -> VoxelBuilder:
	var b := VoxelBuilder.new(801)
	b.tree(0, 0, 5, 3.8)
	return b


static func tree_b() -> VoxelBuilder:
	var b := VoxelBuilder.new(802)
	b.tree(0, 0, 6, 4.4)
	return b


static func tree_c() -> VoxelBuilder:
	var b := VoxelBuilder.new(803)
	b.tree(0, 0, 4, 3.2)
	return b


static func pine_a() -> VoxelBuilder:
	var b := VoxelBuilder.new(811)
	b.pine(0, 0, 14, 3.8)
	return b


static func pine_b() -> VoxelBuilder:
	var b := VoxelBuilder.new(812)
	b.pine(0, 0, 17, 4.3)
	return b


static func pine_c() -> VoxelBuilder:
	var b := VoxelBuilder.new(813)
	b.pine(0, 0, 11, 3.2)
	return b


# ================================================================== MOUNTAINS
## Distant range as a heightfield of big voxels (MOUNTAIN_VOX): forested foothills, bare rock,
## snow caps. Built in world coordinates (origin = world origin on the ground).
static func mountains() -> VoxelBuilder:
	var b := VoxelBuilder.new(9001)
	b.floor_y = 99
	var peaks := []
	for i in 24:
		var ph := b.rng.randf_range(7.0, 17.0)
		peaks.append([b.rng.randf_range(-50.0, 72.0), b.rng.randf_range(-54.0, -27.0), ph, ph * b.rng.randf_range(0.95, 1.35)])
	for x in range(-52, 74):
		for z in range(-57, -15):
			var h := 0.0
			var top := 0.0
			for p in peaks:
				var d := Vector2(x - p[0], z - p[1]).length()
				var v: float = p[2] * (1.0 - d / p[3])
				if v > h:
					h = v
					top = p[2]
			# rolling foothills towards the forest
			h = maxf(h, 1.2 + 0.9 * sin(x * 0.61) * cos(z * 0.83) + (-16.0 - z) * 0.05)
			var hi := int(h + b.rnd() * 0.6)
			for y in range(1, hi + 1):
				var k: Variant
				if top >= 9.0 and y >= maxi(8, hi - 2) and y >= int(top * 0.66):
					k = "snow"
				elif y <= 2:
					k = ["pine", "pineDark", "pine", "leafDark"]
				else:
					k = ["rock", "rock", "rockDark", "stoneDark"]
				b.put(x, y, z, k)
	return b


# ================================================================== shared parts
## front-to-back gable roof: layers y0.., eaves at xl0/xr0, running z0..z1; the gable ends
## between gz0..gz1 are filled with `fill_k`
static func _gable_z(b: VoxelBuilder, y0: int, xl0: int, xr0: int, steps: int, z0: int, z1: int, gz0: int, gz1: int, fill_k: Variant, roof: Array) -> void:
	for k in range(0, steps + 1):
		var y := y0 + k
		var xl := xl0 + k
		var xr := xr0 - k
		if xl > xr:
			break
		for z in range(z0, z1 + 1):
			if k > 0 and z >= gz0 and z <= gz1:
				for x in range(xl + 1, xr):
					b.put(x, y, z, fill_k)
			b.put(xl, y, z, b.roof_k(y, roof)); b.put(xr, y, z, b.roof_k(y, roof))
			if not b.has_v(xl, y - 1, z): b.put(xl, y - 1, z, roof[2])
			if not b.has_v(xr, y - 1, z): b.put(xr, y - 1, z, roof[2])
	var top := y0 + steps + 1
	var cx := (xl0 + xr0) / 2
	for z in range(z0, z1 + 1):
		b.put(cx, top, z, roof[2])
		if (xl0 + xr0) % 2:
			b.put(cx + 1, top, z, roof[2])


## lean-to roof sloping towards +z from height y_top
static func _lean_to(b: VoxelBuilder, x0: int, x1: int, z0: int, z1: int, y_top: int, roof: Array) -> void:
	for z in range(z0, z1 + 1):
		var y := y_top - (z - z0) / 4
		for x in range(x0, x1 + 1):
			b.put(x, y, z, b.roof_k(y, roof))


static func _door_hardware(b: VoxelBuilder, cx: float, wall_z: int) -> void:
	var fz := wall_z + 0.56
	for y in [2.4, 4.6]:
		b.det(cx, y, fz, 2.9, 0.16, 0.1, "metal")
	b.det(cx + 1.15, 3.4, fz + 0.04, 0.14, 0.36, 0.14, "metal")
	for q in [[0, 0.18, 0.36, 0.08], [0, -0.18, 0.36, 0.08], [-0.16, 0, 0.08, 0.36], [0.16, 0, 0.08, 0.36]]:
		b.det(cx + q[0], 3.9 + q[1], fz + 0.04, q[2], q[3], 0.08, "metal")
	b.det(cx, 5.6, fz + 0.06, 5.2, 0.3, 0.36, "woodDark")


## recessed, lit shop display between x0..x1 on the front wall at wall_z
static func _display(b: VoxelBuilder, x0: int, x1: int, wall_z: int, shelf := true) -> void:
	b.clear(x0, x1, 2, 4, wall_z - 1, wall_z)
	b.fill(x0, x1, 2, 4, wall_z - 2, wall_z - 2, "plank")
	b.fill(x0, x1, 1, 1, wall_z - 1, wall_z, "plankDark")
	for x in range(x0 - 1, x1 + 2):
		b.put(x, 5, wall_z, "wood")
	if shelf:
		b.det((x0 + x1) / 2.0, 2.9, wall_z - 0.9, x1 - x0 + 1, 0.14, 1.2, "plank")
	b.det((x0 + x1) / 2.0, 4.42, wall_z - 1.2, x1 - x0 + 0.6, 0.12, 0.3, "lamp")
	b.det((x0 + x1) / 2.0, 1.6, wall_z + 0.62, x1 - x0 + 1.6, 0.25, 0.3, "wood")


static func _helmet(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y, z, 0.72, 0.62, 0.72, "steel")
	b.det(x, y + 0.36, z, 0.5, 0.14, 0.5, "steelLight")
	b.det(x, y - 0.02, z + 0.37, 0.5, 0.1, 0.04, "metal")
	b.det(x, y + 0.5, z, 0.12, 0.2, 0.5, "cloth")


static func _cuirass(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y, z, 0.9, 0.9, 0.5, "steel")
	b.det(x, y + 0.1, z + 0.26, 0.5, 0.5, 0.04, "steelLight")
	for sx in [-0.5, 0.5]:
		b.det(x + sx, y + 0.35, z, 0.25, 0.25, 0.5, "steelDark")


static func _armor_stand(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y + 0.1, z, 1.3, 0.2, 1.1, "plankDark")
	for sx in [-0.25, 0.25]:
		b.det(x + sx, y + 0.85, z, 0.4, 1.3, 0.45, "steelDark")
		b.det(x + sx, y + 0.55, z + 0.03, 0.46, 0.45, 0.47, "steel")
		b.det(x + sx * 3.2, y + 1.95, z, 0.34, 0.9, 0.4, "steel")
		b.det(x + sx * 3.2, y + 2.55, z, 0.5, 0.4, 0.9, "steelDark")
	b.det(x, y + 1.55, z, 1.3, 0.22, 0.85, "leather")
	b.det(x, y + 2.15, z, 1.3, 1.2, 0.8, "steel")
	b.det(x, y + 2.25, z + 0.41, 0.8, 0.8, 0.06, "steelLight")
	b.det(x, y + 3.2, z, 0.8, 0.8, 0.8, "steel")
	b.det(x, y + 3.2, z + 0.41, 0.6, 0.12, 0.05, "metal")
	b.det(x, y + 3.72, z, 0.2, 0.3, 0.7, "cloth")


static func _shield(b: VoxelBuilder, x: float, y: float, z: float, col: String) -> void:
	b.det(x, y, z, 1.3, 1.5, 0.16, col)
	b.det(x, y - 0.95, z, 0.8, 0.4, 0.16, col)
	b.det(x, y - 1.25, z, 0.35, 0.25, 0.16, col)
	b.det(x, y - 0.2, z + 0.1, 0.24, 1.8, 0.06, "steelLight")
	b.det(x, y + 0.2, z + 0.1, 1.1, 0.24, 0.06, "steelLight")


static func _sword(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y + 1.35, z, 0.22, 1.9, 0.08, "steelLight")
	b.det(x, y + 0.35, z, 0.8, 0.16, 0.16, "bronze")
	b.det(x, y + 0.05, z, 0.16, 0.45, 0.16, "leather")
	b.det(x, y - 0.25, z, 0.24, 0.2, 0.2, "bronze")


static func _axe(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y + 1.1, z, 0.18, 2.6, 0.18, "plank")
	for sx in [-0.35, 0.35]:
		b.det(x + sx, y + 2.0, z, 0.55, 0.8, 0.1, "steel")
		b.det(x + sx * 1.8, y + 2.0, z, 0.12, 1.0, 0.1, "steelLight")


static func _spear(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y + 1.6, z, 0.14, 3.2, 0.14, "plank")
	b.det(x, y + 3.45, z, 0.24, 0.5, 0.12, "steelLight")
	b.det(x, y + 3.1, z, 0.34, 0.12, 0.16, "metal")


static func _bench(b: VoxelBuilder, x: float, z: float) -> void:
	b.det(x, 1.0, z, 2.8, 0.2, 0.8, "plank")
	b.det(x, 1.55, z - 0.45, 2.8, 0.6, 0.16, "plank")
	for sx in [-1.2, 1.2]:
		b.det(x + sx, 0.75, z, 0.22, 0.5, 0.7, "woodDark")


static func _wheel(b: VoxelBuilder, cx: float, cy: float, cz: float, r: float) -> void:
	for a in 28:
		var t := a / 28.0 * TAU
		b.det(cx + cos(t) * r, cy + sin(t) * r, cz, 0.3, 0.3, 0.22, "wood")
	for s in 6:
		var t := s / 6.0 * TAU + 0.3
		var rr := 0.3
		while rr < r:
			b.det(cx + cos(t) * rr, cy + sin(t) * rr, cz, 0.14, 0.14, 0.14, "plank")
			rr += 0.22
	b.det(cx, cy, cz, 0.42, 0.42, 0.3, "metal")


## fence posts at the given corners with two rails between consecutive posts
static func _fence(b: VoxelBuilder, posts: Array) -> void:
	for i in posts.size():
		var p: Vector2i = posts[i]
		b.put(p.x, 1, p.y, "wood"); b.put(p.x, 2, p.y, "wood")
		if i == 0:
			continue
		var q: Vector2i = posts[i - 1]
		var c := Vector2(p + q) * 0.5
		var len := Vector2(p - q).length()
		for y in [1.15, 1.9]:
			if p.y == q.y:
				b.det(c.x, y, c.y, len, 0.22, 0.24, "plank")
			else:
				b.det(c.x, y, c.y, 0.24, 0.22, len, "plank")


## hanging sign: bracket out of the wall at x_wall (towards -x) on the facade line z
static func _sign(b: VoxelBuilder, x_wall: int, z: int, rows: Array, colors: Dictionary) -> void:
	b.fill(x_wall - 5, x_wall - 1, 11, 11, z, z, "wood")
	b.put(x_wall - 1, 10, z, "woodDark")
	for x in [x_wall - 4, x_wall - 2]:
		b.det(x, 10.25, z, 0.14, 0.5, 0.14, "metal"); b.det(x, 9.85, z, 0.22, 0.22, 0.22, "metal")
	b.fill(x_wall - 5, x_wall - 1, 7, 9, z, z, "sign")
	b.det(x_wall - 3, 8, z, 5.1, 3.1, 0.6, "woodDark")
	var nc := 0
	for r in rows:
		nc = maxi(nc, (r as String).length())
	b.pixel_art(Vector3(x_wall - 3, 8, z), rows, colors, minf(0.36, 4.6 / nc), 0.52)


static func _banner(b: VoxelBuilder, x: float, y: float, z: float, w: float, h: float) -> void:
	b.det(x, y + h * 0.5 + 0.15, z + 0.1, w + 0.6, 0.2, 0.2, "wood")
	b.det(x, y, z, w, h, 0.1, "cloth")
	b.det(x - w * 0.3, y - h * 0.5 - 0.2, z, w * 0.4, 0.4, 0.1, "cloth")
	b.det(x + w * 0.3, y - h * 0.5 - 0.2, z, w * 0.4, 0.4, 0.1, "cloth")
	b.det(x, y + h * 0.1, z + 0.07, w * 0.45, w * 0.45, 0.05, "gold")
	b.det(x, y + h * 0.1, z + 0.1, w * 0.18, w * 0.6, 0.05, "clothDark")


static func _flag(b: VoxelBuilder, x: float, y: float, z: float) -> void:
	b.det(x, y + 2.0, z, 0.22, 4.0, 0.22, "wood")
	b.det(x + 1.2, y + 3.3, z, 2.2, 1.3, 0.14, "cloth")
	b.det(x + 1.0, y + 3.3, z + 0.08, 0.6, 0.6, 0.05, "gold")


static func _ring(b: VoxelBuilder, x0: int, x1: int, z0: int, z1: int, y: int, k: Variant) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if x == x0 or x == x1 or z == z0 or z == z1:
				b.put(x, y, z, k)


static func _crenel(b: VoxelBuilder, x0: int, x1: int, z0: int, z1: int, y: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if (x == x0 or x == x1 or z == z0 or z == z1) and (x + z) % 2 == 0:
				b.put(x, y, z, CASTLE)


static func _round_tower(b: VoxelBuilder, cx: int, cz: int, r: float, h: int) -> void:
	var ri := ceili(r + 1.5)
	for x in range(cx - ri, cx + ri + 1):
		for z in range(cz - ri, cz + ri + 1):
			var d := Vector2(x - cx, z - cz).length()
			if d <= r:
				for y in range(1, h + 1):
					b.put(x, y, z, CASTLE)
			if d <= r + 1.0:
				b.put(x, h + 1, z, "castleDark")
	# arrow slits facing the front
	var fz := cz + int(floor(r))
	for y in [8, 14]:
		if h > y + 2:
			b.erase(cx, y, fz); b.erase(cx, y + 1, fz)
			b.put(cx, y, fz - 1, "glass"); b.put(cx, y + 1, fz - 1, "glass")
	# cone roof
	var roof_h := int(r * 2.4)
	var top := h + 2
	for k in range(0, roof_h):
		var rr := (r + 1.2) * (1.0 - float(k) / roof_h)
		for x in range(cx - ri, cx + ri + 1):
			for z in range(cz - ri, cz + ri + 1):
				if Vector2(x - cx, z - cz).length() <= rr:
					b.put(x, top + k, z, b.roof_k(top + k, BLUE))
	_flag(b, cx, top + roof_h, cz)
