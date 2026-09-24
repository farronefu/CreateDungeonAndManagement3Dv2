extends SceneTree
## godot --headless -s res://scripts/debug/anims.gd -- res://model.glb : lists animation clips

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var inst := (load(path) as PackedScene).instantiate()
		for p in inst.find_children("*", "AnimationPlayer", true, false):
			var ap := p as AnimationPlayer
			for n in ap.get_animation_list():
				print("%s  %s  %.3fs  tracks=%d" % [path.get_file(), n, ap.get_animation(n).length, ap.get_animation(n).get_track_count()])
		inst.free()
	quit()
