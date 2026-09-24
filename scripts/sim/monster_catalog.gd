class_name MonsterCatalog
extends RefCounted
## Model lookup for monsters. To swap a model, change its path here and, if its clips are named
## differently, map our logical animation names to the GLB's clip names in "anims".
## Logical names: idle / move / attack / absorb / eat / hurt / die / spawn / spawn_child / hatch / lay_egg.
## Missing clips fall back to procedural motion (flash, pulse, pop-in, shrink) in MonsterVisual.
##   scale      : uniform scale applied to the GLB
##   fix_colors : use vertex colours as albedo (our procedurally generated GLBs need this)

const MODELS := {
	# モコゴケ / ツボミ / モコバナ: supplied grass & tree models (Mossbound set, 2026-09-24)
	"moss": {"path": "res://assets/models/grass/grass.glb", "scale": 0.37, "fix_colors": false, "anims": {"move": "walk", "absorb": "gather"}},
	"moss_bud": {"path": "res://assets/models/grass/tree.glb", "scale": 0.29, "fix_colors": false, "anims": {}},
	"moss_flower": {"path": "res://assets/models/grass/tree.glb", "scale": 0.37, "fix_colors": false, "anims": {}},
	# grass -> tree transformation, played when モコゴケ roots into a ツボミ
	"evolution": {"path": "res://assets/models/grass/evolution.glb", "scale": 0.37, "fix_colors": false, "anims": {}},
	# ザクザクムシ / 魔王 / cursor: procedurally generated (tools/modelgen)
	"bug_larva": {"path": "res://assets/models/monsters/bug_larva.glb", "scale": 1.05, "fix_colors": true, "anims": {}},
	"bug_pupa": {"path": "res://assets/models/monsters/bug_pupa.glb", "scale": 1.0, "fix_colors": true, "anims": {}},
	"bug_adult": {"path": "res://assets/models/monsters/bug_adult.glb", "scale": 1.15, "fix_colors": true, "anims": {}},
	"maou": {"path": "res://assets/models/monsters/maou.glb", "scale": 1.15, "fix_colors": true, "anims": {}},
	"pickaxe": {"path": "res://assets/models/monsters/pickaxe.glb", "scale": 1.0, "fix_colors": true, "anims": {}},
	# previous generated moss models (kept as alternatives)
	"moss_generated": {"path": "res://assets/models/monsters/moss.glb", "scale": 1.0, "fix_colors": true, "anims": {}},
	"moss_bud_generated": {"path": "res://assets/models/monsters/moss_bud.glb", "scale": 1.0, "fix_colors": true, "anims": {}},
	"moss_flower_generated": {"path": "res://assets/models/monsters/moss_flower.glb", "scale": 1.0, "fix_colors": true, "anims": {}},
}

## Autumn tint curve for the evolution effect (one value per frame at 30 fps).
const EVOLUTION_COLOR_CURVE := "res://assets/models/grass/evolution-color.json"
const EVOLUTION_TIME := 7.0

static var _cache := {}
static var _curve: Array = []


static func scene(key: String) -> PackedScene:
	if not _cache.has(key):
		_cache[key] = load(MODELS[key]["path"])
	return _cache[key]


static func scale_of(key: String) -> float:
	return float(MODELS[key]["scale"])


## Instantiates a monster model wrapped in a ModelActor.
static func make_actor(key: String) -> ModelActor:
	var entry: Dictionary = MODELS[key]
	var a := ModelActor.new()
	a.setup(scene(key), 0.0, 0.0, bool(entry["fix_colors"]), [], (entry["anims"] as Dictionary).duplicate())
	a.scale = Vector3.ONE * scale_of(key)
	return a


static func evolution_curve() -> Array:
	if _curve.is_empty() and FileAccess.file_exists(EVOLUTION_COLOR_CURVE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVOLUTION_COLOR_CURVE))
		if parsed is Array:
			_curve = parsed
	return _curve
