extends SceneTree
## Draws ヴァレン's UI icon (his helmet, 16x16 pixel art shown at 64x64) into assets/ui/valen_icon.png.
##   godot --headless -s res://scripts/debug/make_valen_icon.gd

const ART := [
	"....RRRRRRRR....",
	"...RRRRRRRRRR...",
	"..RRRRRRRRRRRR..",
	"..RRRRRRRRRRRR..",
	"..RRRRRRRRRRRR..",
	"..rrrrrrrrrrrr..",
	"..rKKKGGGGKKKr..",
	"..rKKKKGGKKKKr..",
	"..rrKKKGGKKKrr..",
	"..rrrrKGGKrrrr..",
	"..rrrrKGGKrrrr..",
	"..rrrrKGGKrrrr..",
	"..rrrrKGGKrrrr..",
	"..rrrrKGGKrrrr..",
	"...gGGGGGGGGg...",
	"....gggggggg....",
]
const PAL := {
	"R": Color("e62b17"), "r": Color("c21712"), "K": Color("291c1f"), "G": Color("f2b233"), "g": Color("c2781a"),
}


func _init() -> void:
	var s := 4
	var img := Image.create(16 * s, 16 * s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var ch: String = ART[y][x]
			if PAL.has(ch):
				img.fill_rect(Rect2i(x * s, y * s, s, s), PAL[ch])
	img.save_png("res://assets/ui/valen_icon.png")
	print("VALEN ICON saved")
	quit()
