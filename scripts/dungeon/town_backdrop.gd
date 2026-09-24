class_name TownBackdrop
extends RefCounted
## Procedurally painted pixel-art town that sits above the dungeon entrance
## (the heroes' home: houses, castle, market, bridge, river, forest, mountains).

const W := 960
const H := 112

var img: Image
var rng := RandomNumberGenerator.new()

const OUTLINE := Color("2b2a33")


func generate(seed_value: int = 3) -> ImageTexture:
	rng.seed = seed_value
	img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_sky()
	_clouds()
	_mountains(40, Color("8fb4d6"), 0.035, 10.0, 1)
	_mountains(52, Color("6f9fc0"), 0.05, 12.0, 2)
	var cx := W / 2
	var river_x := int(W * 0.74)
	_hill_castle(int(W * 0.92), 44)
	_hill_castle(int(W * 0.08), 48)
	_forest(70, Color("2f6a3a"), Color("3f8a45"), 9)
	_ground(78)
	_river(river_x)
	_bridge(river_x - 36, 78)
	var x := 6
	while x < W - 20:
		if x > cx - 62 and x < cx + 56:
			x = cx + 56
			continue
		if x > river_x - 44 and x < river_x + 46:
			x = river_x + 46
			continue
		var r := rng.randf()
		if r < 0.5:
			x += _house(x, 86 + rng.randi_range(-2, 2)) + rng.randi_range(1, 6)
		elif r < 0.75:
			x += _stall(x, 90) + rng.randi_range(2, 6)
		else:
			x += _tree(x + 6, 88) + 2
	_castle(cx, 80)
	for tx in [cx - 70, cx + 66, int(W * 0.3), int(W * 0.6), 8, W - 10]:
		_tree(tx, 97)
	var tex := ImageTexture.create_from_image(img)
	return tex


# ------------------------------------------------------------ primitives
func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)


func _rect_outlined(x: int, y: int, w: int, h: int, c: Color) -> void:
	_rect(x, y, w, h, OUTLINE)
	_rect(x + 1, y + 1, w - 2, h - 2, c)


func _ellipse(cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for yy in range(-ry, ry + 1):
		for xx in range(-rx, rx + 1):
			if float(xx * xx) / (rx * rx + 0.01) + float(yy * yy) / (ry * ry + 0.01) <= 1.0:
				_px(cx + xx, cy + yy, c)


func _tri_roof(x: int, y_base: int, w: int, h: int, c: Color) -> void:
	# isosceles roof, apex centred
	for row in h:
		var half := int(round((w / 2.0) * float(row + 1) / h))
		var yy := y_base - h + row
		for xx in range(x + w / 2 - half, x + w / 2 + half):
			var shade := c.darkened(0.25) if xx > x + w / 2 else c
			if row % 3 == 2:
				shade = shade.darkened(0.12)
			_px(xx, yy, shade)
		_px(x + w / 2 - half - 1, yy, OUTLINE)
		_px(x + w / 2 + half, yy, OUTLINE)


# ------------------------------------------------------------ scenery
func _sky() -> void:
	for y in H:
		var t := float(y) / 60.0
		var c := Color("7cc0ee").lerp(Color("d6eefa"), clampf(t, 0.0, 1.0))
		for x in W:
			_px(x, y, c)


func _clouds() -> void:
	for i in 9:
		var cx := rng.randi_range(0, W)
		var cy := rng.randi_range(6, 26)
		for k in 5:
			_ellipse(cx + k * 6 - 12, cy - (3 if k % 2 == 1 else 0), rng.randi_range(6, 9), rng.randi_range(3, 5), Color("ffffff"))
		_rect(cx - 16, cy + 2, 32, 2, Color("e2eef7"))


func _mountains(base: int, c: Color, freq: float, amp: float, seed_off: int) -> void:
	var ph := rng.randf() * 10.0
	for x in W:
		var top := base - int(amp * (0.6 * sin(x * freq + ph) + 0.4 * sin(x * freq * 2.7 + ph * 2.0 + seed_off)) + amp)
		for y in range(top, H):
			var cc := c.darkened(0.08) if (x + y) % 7 == 0 else c
			if y < top + 2 and seed_off == 1:
				cc = Color("eef4f8")
			_px(x, y, cc)


func _forest(base: int, dark: Color, light: Color, size: int) -> void:
	var x := -4
	while x < W + 4:
		var s := size + rng.randi_range(-2, 2)
		var top := base - s * 2 + rng.randi_range(-2, 2)
		_ellipse(x, top + s, s, s + 2, dark)
		_ellipse(x - 2, top + s - 2, s - 3, s - 2, light)
		_px(x - 3, top + s - 3, light.lightened(0.25))
		x += s + rng.randi_range(0, 3)
	_rect(0, base, W, 10, dark.darkened(0.2))


func _ground(y0: int) -> void:
	for y in range(y0, H):
		for x in W:
			var c := Color("67a84a") if (x * 7 + y * 3) % 11 != 0 else Color("5b9a40")
			_px(x, y, c)
	# path
	for x in W:
		var yy := 100 + int(sin(x * 0.03) * 2.0)
		for k in 5:
			_px(x, yy + k, Color("c9a86a") if k > 0 and k < 4 else Color("a8884e"))


func _river(x0: int) -> void:
	for y in range(78, H):
		var off := int(sin(y * 0.2) * 2.0) + (y - 78) / 2
		for k in range(-6 - (y - 78) / 3, 7 + (y - 78) / 3):
			var c := Color("3f7fd0") if (k + y) % 5 != 0 else Color("7ab8f0")
			_px(x0 + off + k, y, c)


func _bridge(x0: int, y0: int) -> void:
	_rect(x0, y0 + 6, 70, 5, Color("b8b8c0"))
	_rect(x0, y0 + 6, 70, 1, OUTLINE)
	for k in 5:
		_ellipse(x0 + 8 + k * 14, y0 + 14, 5, 4, Color("3f7fd0"))
	for k in 12:
		_rect(x0 + k * 6, y0 + 3, 2, 3, Color("9a9aa4"))


func _house(x: int, base: int) -> int:
	var w := rng.randi_range(18, 26)
	var h := rng.randi_range(12, 16)
	var walls := [Color("f2e6cc"), Color("e8d8b8"), Color("d8c8b0"), Color("c8b8a0")]
	var roofs := [Color("d0483a"), Color("3a6ad0"), Color("d88a3a"), Color("8a4a8a"), Color("b8402c")]
	var wall: Color = walls[rng.randi() % walls.size()]
	_rect_outlined(x, base - h, w, h, wall)
	# timber frame
	if rng.randf() < 0.5:
		for k in range(x + 4, x + w - 2, 6):
			_rect(k, base - h + 1, 1, h - 2, Color("7a5230"))
	_tri_roof(x - 2, base - h + 1, w + 4, rng.randi_range(8, 11), roofs[rng.randi() % roofs.size()])
	# door + windows
	_rect_outlined(x + w / 2 - 2, base - 7, 5, 7, Color("7a4a26"))
	_rect_outlined(x + 3, base - h + 4, 4, 4, Color("8fd0f0"))
	_rect_outlined(x + w - 7, base - h + 4, 4, 4, Color("8fd0f0"))
	if rng.randf() < 0.4:
		_rect(x + w - 6, base - h - 9, 3, 6, Color("8a6a5a"))
	return w + 4


func _stall(x: int, base: int) -> int:
	var w := rng.randi_range(14, 18)
	var awn := [[Color("e04040"), Color("ffffff")], [Color("3a70d0"), Color("ffffff")], [Color("f0c020"), Color("d06020")]]
	var a: Array = awn[rng.randi() % awn.size()]
	_rect_outlined(x, base - 7, w, 7, Color("a8744a"))
	for k in w:
		_rect(x + k, base - 12, 1, 4, a[(k / 3) % 2])
	_rect(x, base - 13, w, 1, OUTLINE)
	_rect(x + 1, base - 8, 1, 1, OUTLINE)
	# goods
	for k in range(x + 2, x + w - 2, 3):
		_px(k, base - 6, [Color("f05030"), Color("f0d040"), Color("60c040")][rng.randi() % 3])
	return w


func _tree(x: int, base: int) -> int:
	_rect(x - 1, base - 6, 3, 6, Color("6a4428"))
	_ellipse(x, base - 11, 7, 7, Color("2f7a3a"))
	_ellipse(x - 2, base - 13, 4, 4, Color("4a9a4a"))
	return 14


func _castle(cx: int, base: int) -> void:
	var stone := Color("b4b4be")
	var dark := Color("8a8a96")
	# curtain wall
	_rect_outlined(cx - 42, base - 22, 84, 22, stone)
	for k in range(cx - 42, cx + 42, 6):
		_rect(k, base - 26, 4, 4, stone)
		_rect(k, base - 26, 4, 1, OUTLINE)
	# towers
	for tx in [cx - 44, cx - 14, cx + 16, cx + 38]:
		var th := 40 if (tx == cx - 14 or tx == cx + 16) else 32
		_rect_outlined(tx - 6, base - th, 12, th, stone)
		_tri_roof(tx - 8, base - th + 1, 16, 9, Color("c8402c"))
		_rect(tx - 1, base - th + 6, 2, 4, OUTLINE)
		# flag
		_rect(tx, base - th - 16, 1, 7, OUTLINE)
		_rect(tx + 1, base - th - 16, 6, 3, Color("e03030"))
	# keep
	_rect_outlined(cx - 10, base - 46, 20, 30, dark.lightened(0.2))
	_tri_roof(cx - 13, base - 45, 26, 12, Color("3a5ab8"))
	# gate
	_rect_outlined(cx - 7, base - 14, 14, 14, Color("3a2a20"))
	for k in range(cx - 6, cx + 6, 3):
		_rect(k, base - 13, 1, 12, Color("6a5a4a"))
	# stone texture
	for y in range(base - 46, base):
		for x in range(cx - 42, cx + 42):
			if (x * 13 + y * 7) % 23 == 0 and img.get_pixel(x, y).is_equal_approx(stone):
				_px(x, y, dark)


func _hill_castle(cx: int, base: int) -> void:
	_ellipse(cx, base + 14, 40, 18, Color("5f9a50"))
	_rect_outlined(cx - 10, base - 10, 20, 12, Color("a8a8b4"))
	_rect_outlined(cx - 4, base - 20, 8, 12, Color("a8a8b4"))
	_tri_roof(cx - 6, base - 19, 12, 6, Color("c8402c"))


func _trees_front() -> void:
	for x in [4, 180, 300, 470]:
		_tree(x, 96)
