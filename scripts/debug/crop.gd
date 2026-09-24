extends SceneTree
## godot --headless -s res://scripts/debug/crop.gd -- in.png out.png x y w h

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	var r := Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	img.get_region(r).save_png(a[1])
	quit()
