extends SceneTree
## godot --headless -s res://scripts/debug/inspect_model.gd -- res://path/model.glb

func _init() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var inst := (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	_dump(inst, 0)
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var lo := 1e9
		var hi := -1e9
		for i in s.get_bone_count():
			var p := (s.global_transform * s.get_bone_global_rest(i)).origin
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		print("skeleton %s bones %d  bone y range %.3f .. %.3f" % [s.name, s.get_bone_count(), lo, hi])
	quit()


func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is Node3D:
		var t := (n as Node3D).transform
		extra = " pos=%s scale=%s" % [t.origin, t.basis.get_scale()]
	if n is MeshInstance3D:
		extra += " aabb=%s skin=%s" % [(n as MeshInstance3D).get_aabb(), (n as MeshInstance3D).skin != null]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	if depth < 4:
		for c in n.get_children():
			_dump(c, depth + 1)
