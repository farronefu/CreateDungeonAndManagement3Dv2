extends SceneTree
## Writes the 16x16 pixel-art monster icons of the pause screen (assets/ui/icons/<key>.png)
## and a 6x preview sheet (debug_shots/monster_icons.png).
##   godot --headless -s res://scripts/debug/make_monster_icons.gd

const PAL := {
	"k": "1c140c",   # outline
	"y": "e8e23a", "Y": "f8f590", "d": "b4aa1e",   # moss yellows
	"g": "6cc234",   # sprout
	"b": "9a5626", "B": "c87a3c",   # trunk
	"o": "f08a1e", "O": "ffb850", "q": "bc5a10",   # pill bug / bee oranges
	"w": "ffeaa6",   # wings
	"E": "fffbe0",   # bee eyes
	"s": "1f6ae0", "S": "5a9dff", "n": "3a40a0", "c": "a8e0f0", "h": "ffcc20",   # scorpion
	"e": "101018",   # pupils
}

const ICONS := {
	"moss": [
		"......gg.gg.....",
		".......ggg......",
		"........g.......",
		".....kkkkkk.....",
		"...kkyyYYyykk...",
		"..kyyYYYYyyyyk..",
		".kyyYYYyyyyyyyk.",
		".kyyYyyyyyyyyyk.",
		"kyyyyekyyyekyyyk",
		"kyyyyekyyyekyyyk",
		"kyyyyyyyyyyyyyyk",
		".kyyyyyyyyyyyyk.",
		".kyyyyyyyyyyydk.",
		"..kyyyyyyyyddk..",
		"...kkyyyyddkk...",
		".....kkkkkk.....",
	],
	"moss_flower": [
		".....kkkkkk.....",
		"...kkyYYYYykk...",
		"..kyYYYYyyyyyk..",
		".kyYYyyyyyyyydk.",
		".kyyyyyyyyyyydk.",
		"kyyyyyyyyyyyyddk",
		"kyyyyyyyyyyydddk",
		".kyyyyyyyyydddk.",
		"..kkdddddddkkk..",
		"....kkkbbkk.....",
		"......kbBk......",
		"......kbBk......",
		"......kbBk......",
		".....kbbBbk.....",
		"....kbbbBbbk....",
		"....kkkkkkkk....",
	],
	"bug_larva": [
		"................",
		"................",
		".....kkkkkk.....",
		"...kkoOOoookk...",
		"..koOOokoookok..",
		".koOOookoookook.",
		".koOoookoookooqk",
		"koooookooookooqk",
		"koooookooookoqqk",
		"koooookooookoqek",
		"kqoooqkoooqkqqqk",
		".kqqqqkqqqqkqqk.",
		"..kkkkkkkkkkkk..",
		"..k.k..k..k.k...",
		"................",
		"................",
	],
	"bug_adult": [
		".ww..........ww.",
		"wwww........wwww",
		"wwwww.kkkk.wwwww",
		".wwwwkoOOokwwww.",
		"..wwkoOOoookww..",
		"...kooooooook...",
		"..kEEEooooEEEk..",
		"..kEEkooookEEk..",
		"..kooooooooook..",
		"...kkkkkkkkkk...",
		"...kqqqqqqqqk...",
		"....kooooook....",
		"....kkkkkkkk....",
		".....kqqqqk.....",
		"......kook......",
		".......kk.......",
	],
	"scorpion": [
		"......nnn.......",
		".....nn.ss......",
		".........ss.....",
		".ss......ss..ss.",
		"sSSs....ss..sSSs",
		"sSs..ssssss..sSs",
		"sSSsssSSSSsssSSs",
		".sssshesSehssss.",
		"...sshesSehss...",
		"...ssSSSSSSss...",
		"....ssccccss....",
		"....ssccccss....",
		".....ssccss.....",
		"....ssssssss....",
		"...nns....snn...",
		"...nn......nn...",
	],
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/ui/icons")
	var sheet := Image.create(ICONS.size() * 104 + 8, 112, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("14100c"))
	var i := 0
	for key in ICONS:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rows: Array = ICONS[key]
		if rows.size() != 16:
			print("BAD ROW COUNT ", key, " ", rows.size())
		for y in mini(16, rows.size()):
			var row: String = rows[y]
			if row.length() != 16:
				print("BAD ROW ", key, " ", y, " len ", row.length())
			for x in mini(16, row.length()):
				var ch := row[x]
				if PAL.has(ch):
					img.set_pixel(x, y, Color(PAL[ch]))
		img.save_png("res://assets/ui/icons/%s.png" % key)
		var big := img.duplicate() as Image
		big.resize(96, 96, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, 96, 96), Vector2i(8 + i * 104, 8))
		i += 1
	DirAccess.make_dir_recursive_absolute("res://debug_shots")
	sheet.save_png("res://debug_shots/monster_icons.png")
	print("ICONS WRITTEN ", ICONS.size())
	quit()
