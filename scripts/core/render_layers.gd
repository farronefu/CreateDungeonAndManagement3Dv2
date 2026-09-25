class_name RenderLayers
extends RefCounted
## Visual layer bits, used to light the three parts of the scene separately:
##   DUNGEON  soil blocks, floor, decor under ground  -> dim light from above (no sun)
##   SURFACE  town, meadow, entrance ramp             -> the sun
##   ACTORS   monsters, hero, 魔王, cursor, effects   -> their own key light (always vivid)

const DUNGEON := 1
const SURFACE := 2
const ACTORS := 4


## Sets the visual layer on every VisualInstance3D under `n` (inclusive).
static func apply(n: Node, bits: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = bits
	for c in n.get_children():
		apply(c, bits)
