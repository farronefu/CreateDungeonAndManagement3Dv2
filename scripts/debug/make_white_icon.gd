extends SceneTree
## Turns white pixel art on a black (or transparent) background into a UI icon like the hero icons:
## white where the art is, transparent elsewhere, cropped to the art, centred on a square, `size` px.
##   godot --headless -s res://scripts/debug/make_white_icon.gd -- in.webp out.png size

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var on := c.a >= 0.5 and c.get_luminance() >= 0.5
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if on else 0.0))
			if on:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	var crop := img.get_region(Rect2i(lo, hi - lo + Vector2i.ONE))
	var side := maxi(crop.get_width(), crop.get_height())
	var sq := Image.create(side, side, false, Image.FORMAT_RGBA8)
	sq.fill(Color(1, 1, 1, 0))
	sq.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((side - crop.get_width()) / 2, (side - crop.get_height()) / 2))
	var s := int(a[2])
	sq.resize(s, s, Image.INTERPOLATE_LANCZOS)
	for y in s:
		for x in s:
			sq.set_pixel(x, y, Color(1, 1, 1, 1.0 if sq.get_pixel(x, y).a >= 0.45 else 0.0))
	sq.save_png(a[1])
	print("saved ", a[1])
	quit()
