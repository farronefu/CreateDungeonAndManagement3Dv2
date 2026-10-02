extends SceneTree
## Rendered regression for authored blocks, nutrient updates, picking data, dig and persistence.
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var mesh := VoxelBlockCatalog.mesh()
	check(mesh.get_surface_count() == 1, "One surface")
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 668 * 3, "Approved 668-triangle mesh")
	check(mesh.get_aabb().size.is_equal_approx(Vector3(0.97, 0.88, 0.97)), "Authored dimensions")
	check(VoxelBlockCatalog._textures.size() == 6, "Six embedded atlases")
	for tex in VoxelBlockCatalog._textures:
		check(tex.get_width() == 408 and tex.get_height() == 272, "Atlas dimensions")
	check(VoxelBlockCatalog._textures[3].get_image().get_data() == VoxelBlockCatalog._textures[4].get_image().get_data(), "Both dry stages have identical pixels")
	var g := DungeonGrid.new(10, 10)
	var values := [0, 1, 4, 5, 9, 10, 12, 13]
	var stages := [0, 1, 1, 2, 2, 3, 3, 4]
	for i in values.size():
		g.set_nutrient(Vector2i(i + 1, 2), values[i])
	var rock := Vector2i(0, 2)
	g.types[g.idx(rock)] = DungeonGrid.BEDROCK
	var floor_cell := Vector2i(1, 3)
	g.types[g.idx(floor_cell)] = DungeonGrid.FLOOR
	var v = load("res://scripts/dungeon/dungeon_view.gd").new()
	root.add_child(v)
	v.setup(g)
	for i in values.size():
		var c := Vector2i(i + 1, 2)
		var slot: Array = v._slot[c]
		var mm: MultiMesh = slot[0]
		var custom := mm.get_instance_custom_data(slot[1])
		check(is_equal_approx(custom.r * 16, values[i]) and custom.a == 0.0, "Boundary data %d" % values[i])
		check(Balance.soil_stage(roundi(custom.r * 16)) == stages[i], "Boundary stage %d" % values[i])
		var xf := mm.get_instance_transform(slot[1])
		check(xf.origin.is_equal_approx(Vector3(c.x + 0.5, 0.44, c.y + 0.5)), "Grid center and floor alignment")
		check(xf.basis.get_scale().is_equal_approx(Vector3.ONE), "No height variation")
		check(absf(xf.basis.x.x) < 0.001 or absf(absf(xf.basis.x.x) - 1.0) < 0.001, "Quarter-turn rotations only")
		var box := xf * mesh.get_aabb()
		check(absf(box.size.x - 0.97) < 0.001 and absf(box.position.y) < 0.001, "Exact 0.03 m neighbor gap")
	var mutable := Vector2i(3, 2)
	for n in values:
		g.set_nutrient(mutable, n)
		var slot: Array = v._slot[mutable]
		check(is_equal_approx(slot[0].get_instance_custom_data(slot[1]).r * 16, n), "Immediate stage update %d" % n)
	v.set_hover(mutable, 0.7)
	var selected: Array = v._slot[mutable]
	check(is_equal_approx(selected[0].get_instance_custom_data(selected[1]).b, 0.7), "Hover retained")
	g.set_nutrient(mutable, 5)
	check(is_equal_approx(selected[0].get_instance_custom_data(selected[1]).b, 0.7), "Hover survives nutrient change")
	v.set_hover(rock, 0.5)
	check(selected[0].get_instance_custom_data(selected[1]).b == 0.0, "Old hover cleared")
	var bedrock: Array = v._slot[rock]
	check(bedrock[0].get_instance_custom_data(bedrock[1]).a == 1.0 and not g.can_dig(rock), "Black bedrock still undiggable")
	var outside: Array = v._slot[Vector2i(-1, 2)]
	check(outside[0].get_instance_custom_data(outside[1]).a == 1.0, "Outer bedrock stays separate")
	for ch in v._chunks.values():
		check(ch.decor.is_empty(), "No old tall block decorations")
	var saved := g.to_dict()
	var loaded := DungeonGrid.from_dict(saved)
	check(loaded.to_dict() == saved, "Existing save schema round trip")
	var dig_cell := Vector2i(2, 3)
	g.set_nutrient(dig_cell, 10)
	check(g.can_dig(dig_cell), "Exposed block dig rule unchanged")
	check(g.dig(dig_cell) == 10 and g.is_floor(dig_cell), "Dig returns nutrient and creates floor")
	check(v._anim.has(dig_cell), "Destruction animation starts")
	v._process(0.1)
	var dug: Array = v._slot[dig_cell]
	check(is_equal_approx(dug[0].get_instance_custom_data(dug[1]).r * 16, 10.0), "Crumbling retains original dry texture")
	check(dug[0].get_instance_transform(dug[1]).basis.get_scale().y < 0.6, "Destruction still shrinks")
	v._process(0.2)
	check(not v._anim.has(dig_cell) and dug[0].get_instance_transform(dug[1]).origin.y < -4.0, "Dug block hidden without removing neighboring faces")
	check(g.can_dig(Vector2i(3, 3)), "Newly exposed adjacent face is diggable")
	var fx := Effects.new()
	root.add_child(fx)
	fx.debris(dig_cell, 0.0, 0)
	var chips := fx.get_children().filter(func(node): return node is CPUParticles3D and node.amount == 22)
	check(chips.size() == 1, "Block debris still emitted")
	check(chips[0].color_initial_ramp.get_color(0).is_equal_approx(VoxelBlockCatalog.debris_color(0).darkened(0.15)), "Bare block fragments gray")
	fx.queue_free()
	v.queue_free()
	await process_frame
	print("VOXEL BLOCK PASS failures=", failures)
	quit(1 if failures else 0)


