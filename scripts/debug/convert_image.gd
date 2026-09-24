extends SceneTree
## godot --headless -s res://scripts/debug/convert_image.gd -- in.webp out.png : converts and prints size

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	print("SIZE %dx%d alpha=%s" % [img.get_width(), img.get_height(), img.detect_alpha()])
	if a.size() > 1:
		img.save_png(a[1])
	quit()
