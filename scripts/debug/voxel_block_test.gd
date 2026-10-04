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
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 1440 * 3, "Shared 1440-triangle relief shell")
	check(mesh.get_aabb().size.is_equal_approx(Vector3(0.985, 0.88, 0.985)), "Authored dimensions")
	check(VoxelBlockCatalog._textures.size() == 6, "Six embedded atlases")
	for tex in VoxelBlockCatalog._textures:
		check(tex.get_width() == 408 and tex.get_height() == 272, "Atlas dimensions")
	check(VoxelBlockCatalog._textures[3].get_image().get_data() == VoxelBlockCatalog._textures[4].get_image().get_data(), "Both dry stages have identical pixels")
	check_relief(mesh)
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
		check(absf(box.size.x - 0.985) < 0.001 and absf(box.position.y) < 0.001, "Exact 0.015 m neighbor gap")
	# Neighbors keep a thin, positive seam under every fixed quarter-turn rotation.
	for c in v._slot:
		for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
			var neighbor: Vector2i = c+direction
			if not v._slot.has(neighbor): continue
			if g.is_floor(c) or g.is_floor(neighbor): continue
			var slot: Array = v._slot[c]
			var other: Array = v._slot[neighbor]
			var box: AABB = slot[0].get_instance_transform(slot[1])*mesh.get_aabb()
			var next_box: AABB = other[0].get_instance_transform(other[1])*mesh.get_aabb()
			var gap: float = next_box.position.x-box.end.x if direction==Vector2i.RIGHT else next_box.position.z-box.end.z
			check(absf(gap-0.015)<0.0001,"Adjacent envelopes leave 0.015m and cannot overlap")
	var stable_seeds: Dictionary = v._seed.duplicate()
	var mutable := Vector2i(3, 2)
	for n in values:
		g.set_nutrient(mutable, n)
		var slot: Array = v._slot[mutable]
		check(is_equal_approx(slot[0].get_instance_custom_data(slot[1]).r * 16, n), "Immediate stage update %d" % n)
		check(v._seed == stable_seeds,"Nutrient changes preserve all shape seeds")
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
	var reloaded_view = load("res://scripts/dungeon/dungeon_view.gd").new()
	root.add_child(reloaded_view)
	reloaded_view.setup(loaded)
	check(reloaded_view._seed == stable_seeds,"Reload reconstructs identical cell variants and rotations")
	reloaded_view.queue_free()
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




func check_relief(mesh: ArrayMesh) -> void:
	check(mesh == VoxelBlockCatalog.mesh(), "Mesh cached across blocks")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cells: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var descriptors: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var normals := BlockSurfaceMesh.NORMALS
	var box := mesh.get_aabb().grow(0.00001)
	var hashes := {}
	for face in 6:
		for y in 6:
			for x in 6:
				var h := VoxelBlockCatalog.surface_height(face,Vector2i(x,y),0,0.0,true)
				check(h>=BlockSurfaceMesh.DEPTH*0.85 and h<=BlockSurfaceMesh.DEPTH,"Bedrock shallow relief remains inside envelope")
	for face in 6:
		for variant in 4:
			var seed_value := float(variant)/1024.0
			var signature := []
			for nutrient in [0,1,4,5,9,10,12,13,16]:
				var levels := {}
				var maximum := 0.0
				var minimum := 1.0
				for y in BlockSurfaceMesh.GRID:
					for x in BlockSurfaceMesh.GRID:
						var h := VoxelBlockCatalog.surface_height(face,Vector2i(x,y),nutrient,seed_value)
						check(h == VoxelBlockCatalog.surface_height(face,Vector2i(x,y),nutrient,seed_value), "Stable per-cell height")
						levels[roundi(h*100000)] = true
						minimum = minf(minimum,h)
						maximum = maxf(maximum,h)
						if nutrient == 5: signature.append(h)
				check(levels.size() >= 4 and minimum < 0.03 and is_equal_approx(maximum,BlockSurfaceMesh.DEPTH), "Irregular plateaus, pits and exact envelope")
				# Highest protrusions always belong to connected patches, not isolated cubes.
				for y in BlockSurfaceMesh.GRID:
					for x in BlockSurfaceMesh.GRID:
						var cell := Vector2i(x,y)
						if VoxelBlockCatalog.surface_height(face,cell,nutrient,seed_value) < maximum-0.001: continue
						var connected := false
						for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
							var neighbor: Vector2i = cell+d
							if neighbor.x>=0 and neighbor.x<6 and neighbor.y>=0 and neighbor.y<6:
								connected = connected or VoxelBlockCatalog.surface_height(face,neighbor,nutrient,seed_value) >= maximum-0.001
						check(connected,"Peak belongs to a connected plateau")
				if nutrient == 5: hashes[hash(signature)] = true
				# CPU reconstruction checks the actual shared vertex descriptors, including walls.
				for i in vertices.size():
					if int(descriptors[i].x) != face: continue
					var payload: Color = cells[i]
					var a := Vector2(payload.r,payload.g)
					var b := Vector2(payload.b,payload.a)
					var h_a := VoxelBlockCatalog.surface_height(face,Vector2i(floori(a.x*6),floori(a.y*6)),nutrient,seed_value)
					var h_b := 0.0 if b == Vector2.ONE else VoxelBlockCatalog.surface_height(face,Vector2i(floori(b.x*6),floori(b.y*6)),nutrient,seed_value)
					var displaced: Vector3 = vertices[i]+normals[face]*(lerpf(h_a,h_b,descriptors[i].y)-BlockSurfaceMesh.DEPTH)
					check(box.has_point(displaced),"All displaced vertices inside existing bounds")
	print("RELIEF unique signatures=",hashes.size())
	check(hashes.size() == 24,"Four distinct fixed variants on every face")
