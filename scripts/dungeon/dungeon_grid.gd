class_name DungeonGrid
extends RefCounted
## Logical dungeon: cell types, nutrients and path finding. No rendering here.
## Cell (x, y): x grows east, y grows south (away from the entrance). World: X = x + 0.5, Z = y + 0.5.

signal cell_dug(cell: Vector2i)
signal nutrient_changed(cell: Vector2i)

enum { BLOCK, FLOOR, BEDROCK }

const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

var w: int
var h: int
var types := PackedByteArray()
var nutrient := PackedByteArray()
var entrance := Vector2i.ZERO


func _init(width: int = Balance.GRID_W, height: int = Balance.GRID_H) -> void:
	w = width
	h = height
	types.resize(w * h)
	nutrient.resize(w * h)
	entrance = Vector2i(w / 2, 0)


static func cell_center(c: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func get_type(c: Vector2i) -> int:
	return types[idx(c)] if in_bounds(c) else BEDROCK


func is_floor(c: Vector2i) -> bool:
	return in_bounds(c) and types[idx(c)] == FLOOR


func is_block(c: Vector2i) -> bool:
	return in_bounds(c) and types[idx(c)] == BLOCK


func get_nutrient(c: Vector2i) -> int:
	return nutrient[idx(c)] if in_bounds(c) else 0


func set_nutrient(c: Vector2i, v: int) -> void:
	if not in_bounds(c):
		return
	var nv := clampi(v, 0, Balance.MAX_NUTRIENT)
	if nutrient[idx(c)] != nv:
		nutrient[idx(c)] = nv
		nutrient_changed.emit(c)


## Adds (or removes, if negative) nutrient; returns the amount actually applied.
func add_nutrient(c: Vector2i, dv: int) -> int:
	if not is_block(c):
		return 0
	var before := get_nutrient(c)
	set_nutrient(c, before + dv)
	return get_nutrient(c) - before


func has_floor_neighbor(c: Vector2i) -> bool:
	for d in DIRS:
		if is_floor(c + d):
			return true
	return false


func can_dig(c: Vector2i) -> bool:
	return is_block(c) and has_floor_neighbor(c)


## Turns a block into floor. Returns the nutrient it contained.
func dig(c: Vector2i) -> int:
	if not is_block(c):
		return 0
	var n := get_nutrient(c)
	types[idx(c)] = FLOOR
	nutrient[idx(c)] = 0
	cell_dug.emit(c)
	return n


## Floor that is also allowed by `mask` (1 = walkable; an empty mask allows every floor cell).
func walkable(c: Vector2i, mask: PackedByteArray = PackedByteArray()) -> bool:
	return is_floor(c) and (mask.is_empty() or mask[idx(c)] == 1)


func floor_neighbors(c: Vector2i, mask: PackedByteArray = PackedByteArray()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		if walkable(c + d, mask):
			out.append(c + d)
	return out


func block_neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		if is_block(c + d):
			out.append(c + d)
	return out


## Breadth-first distances over floor cells. -1 = unreachable.
func distance_map(from: Vector2i, mask: PackedByteArray = PackedByteArray()) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if not walkable(from, mask):
		return dist
	var queue: Array[Vector2i] = [from]
	dist[idx(from)] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var dc := dist[idx(c)]
		for d in DIRS:
			var n := c + d
			if walkable(n, mask) and dist[idx(n)] < 0:
				dist[idx(n)] = dc + 1
				queue.append(n)
	return dist


## Shortest floor path from `from` to `to`, excluding `from`. Empty if unreachable or same cell.
func find_path(from: Vector2i, to: Vector2i, mask: PackedByteArray = PackedByteArray()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to or not walkable(to, mask):
		return out
	var dist := distance_map(to, mask)
	if dist[idx(from)] < 0:
		return out
	# walk downhill from `from` towards `to`
	var c := from
	var guard := 0
	while c != to and guard < w * h:
		guard += 1
		var best := c
		var bd := dist[idx(c)]
		for d in DIRS:
			var n := c + d
			if walkable(n, mask) and dist[idx(n)] >= 0 and dist[idx(n)] < bd:
				bd = dist[idx(n)]
				best = n
		if best == c:
			break
		c = best
		out.append(c)
	return out


## First step from `from` towards the nearest cell for which pred(cell) is true (BFS order).
func path_to_nearest(from: Vector2i, pred: Callable, max_dist: int = 9999, mask: PackedByteArray = PackedByteArray()) -> Array[Vector2i]:
	var parent := {}
	var queue: Array[Vector2i] = [from]
	parent[from] = from
	var head := 0
	var depth := {from: 0}
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c != from and pred.call(c):
			var path: Array[Vector2i] = []
			var p := c
			while p != from:
				path.push_front(p)
				p = parent[p]
			return path
		if depth[c] >= max_dist:
			continue
		var dirs := DIRS.duplicate()
		dirs.shuffle()
		for d in dirs:
			var n: Vector2i = c + d
			if walkable(n, mask) and not parent.has(n):
				parent[n] = c
				depth[n] = depth[c] + 1
				queue.append(n)
	return []


func total_nutrient() -> int:
	var s := 0
	for v in nutrient:
		s += v
	return s


func floor_count() -> int:
	var s := 0
	for t in types:
		if t == FLOOR:
			s += 1
	return s


# ------------------------------------------------------------------ generation
func generate(seed_value: int) -> void:
	# Soil types are scattered at random (like 勇者のくせになまいきだ): bare soil gives nothing,
	# nutrient soil gives モコチュリ, rich soil gives ザクザクムシ. Deeper = richer.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.18
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var border := x == 0 or x == w - 1 or y == 0 or y == h - 1
			types[idx(c)] = BEDROCK if border else BLOCK
			nutrient[idx(c)] = 0 if border else _roll_soil(rng, float(y) / float(h - 1), noise.get_noise_2d(x, y))
	# the entrance and the starting tunnel
	types[idx(entrance)] = FLOOR
	var carve := func(c: Vector2i) -> void:
		if in_bounds(c) and types[idx(c)] == BLOCK:
			types[idx(c)] = FLOOR
			nutrient[idx(c)] = 0
	for y in range(1, 6):
		carve.call(Vector2i(entrance.x, y))
	for x in range(entrance.x - 5, entrance.x + 4):
		carve.call(Vector2i(x, 5))
	for y in range(3, 8):
		for x in range(entrance.x - 8, entrance.x - 4):
			carve.call(Vector2i(x, y))
	for y in range(6, 9):
		carve.call(Vector2i(entrance.x + 3, y))


## One soil block. depth: 0 (surface) .. 1 (bottom); bias: -1..1 regional noise for gentle clustering.
func _roll_soil(rng: RandomNumberGenerator, depth: float, bias: float) -> int:
	var p_bare := clampf(0.48 - 0.2 * depth - 0.12 * bias, 0.2, 0.7)
	var p_rich := 0.0 if depth < 0.3 else clampf(0.01 + 0.05 * depth + 0.02 * bias, 0.0, 0.08)
	var r := rng.randf()
	if r < p_bare:
		return 0
	if r < p_bare + p_rich:
		return rng.randi_range(Balance.BUG_SPAWN_MIN, 14)
	# nutrient soil: mostly small amounts, larger deeper down
	var n := 1 + int(pow(rng.randf(), 1.7) * 7.0 + depth * 2.0)
	return clampi(n, Balance.MOSS_SPAWN_MIN, Balance.BUG_SPAWN_MIN - 1)


# ------------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {"w": w, "h": h, "types": types.duplicate(), "nutrient": nutrient.duplicate(), "entrance": entrance}


static func from_dict(d: Dictionary) -> DungeonGrid:
	var g := DungeonGrid.new(d["w"], d["h"])
	g.types = (d["types"] as PackedByteArray).duplicate()
	g.nutrient = (d["nutrient"] as PackedByteArray).duplicate()
	g.entrance = d["entrance"]
	return g
