extends SceneTree
## Builds the in-game hero icon: downscales the source art and snaps alpha so edges stay crisp.
##   godot --headless -s res://scripts/debug/img_info.gd -- in.png out.png size

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGBA8)
	var s := int(a[2])
	img.resize(s, s, Image.INTERPOLATE_LANCZOS)
	for y in s:
		for x in s:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if c.a >= 0.45 else 0.0))
	img.save_png(a[1])
	print("saved ", a[1])
	quit()
