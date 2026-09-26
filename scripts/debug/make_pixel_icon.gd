extends SceneTree
## Turns pixel art on a white or transparent background into a crisp square UI icon: near-white becomes
## transparent, the art is cropped to its bounds, centred on a square canvas and downscaled
## with alpha snapped, keeping the original colours.
##   godot --headless -s res://scripts/debug/make_pixel_icon.gd -- in.webp out.png size

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
			if c.a < 0.5 or minf(c.r, minf(c.g, c.b)) > 0.86:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	var crop := img.get_region(Rect2i(lo, hi - lo + Vector2i.ONE))
	var side := maxi(crop.get_width(), crop.get_height())
	var sq := Image.create(side, side, false, Image.FORMAT_RGBA8)
	sq.fill(Color(0, 0, 0, 0))
	sq.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((side - crop.get_width()) / 2, (side - crop.get_height()) / 2))
	var s := int(a[2])
	sq.resize(s, s, Image.INTERPOLATE_LANCZOS)
	for y in s:
		for x in s:
			var c := sq.get_pixel(x, y)
			if c.a < 0.5:
				sq.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				sq.set_pixel(x, y, Color(c.r / c.a if c.a < 1.0 else c.r, c.g / c.a if c.a < 1.0 else c.g, c.b / c.a if c.a < 1.0 else c.b, 1.0).clamp())
	sq.save_png(a[1])
	print("saved ", a[1], " from crop ", crop.get_size())
	quit()
