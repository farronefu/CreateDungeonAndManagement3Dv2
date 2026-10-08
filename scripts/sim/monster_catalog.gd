class_name MonsterCatalog
extends RefCounted
## Model lookup for monsters. To swap a model, change its path here and, if its clips are named
## differently, map our logical animation names to the GLB's clip names in "anims".
## Logical names: idle / move / attack / absorb / eat / hurt / die / spawn / spawn_child / hatch / lay_egg.
## Missing clips fall back to procedural motion (flash, pulse, pop-in, shrink) in MonsterVisual.
##   scale      : uniform scale applied to the GLB
##   fix_colors : use vertex colours as albedo (our procedurally generated GLBs need this)
##   stride     : optional, world units one walk cycle covers at this scale (keeps feet from sliding)

const MODELS := {
	# モコチュリ / ツボミ / モコバナ: supplied grass & tree models (Mossbound set, 2026-09-24)
	"moss": {"path": "res://assets/models/final-runtime/MonsterChain-Mokochuri-Voxel-Animated.glb", "scale": 0.37, "fix_colors": false, "anims": {"move": "walk", "absorb": "gather"}},
	"moss_bud": {"path": "res://assets/models/final-runtime/MonsterChain-Tsubomi-Voxel-Animated.glb", "scale": 0.29, "fix_colors": false, "anims": {}},
	"moss_flower": {"path": "res://assets/models/final-runtime/MonsterChain-Mokobana-Voxel-Animated.glb", "scale": 0.37, "fix_colors": false, "anims": {}},
	# grass -> tree transformation, played when モコチュリ roots into a ツボミ
	"evolution": {"path": "res://assets/models/final-runtime/MonsterChain-PlantEvolution-Voxel-Animated.glb", "scale": 0.37, "fix_colors": false, "anims": {}, "evo_time": 7.0},
	# Approved voxel pillbug v2 (2026-10-02): +Y up, +Z forward, ground origin; pupa is curled.
	"bug_larva": {"path": "res://assets/models/pillbug/voxel-pillbug-v2.glb", "scale": 0.31, "fix_colors": true, "stride": 0.095, "loops": ["Idle", "Walk", "CurlIdle"],
		"anims": {"idle": "Idle", "move": "Walk", "attack": "Attack", "eat": "Eat", "spawn": "Spawn", "die": "Death"}},
	"bug_pupa": {"path": "res://assets/models/pillbug/voxel-pillbug-v2.glb", "scale": 0.31, "fix_colors": true,
		"loops": ["Idle", "Walk", "CurlIdle"],
		"anims": {"idle": "CurlIdle", "spawn": "Curl", "hatch": "Uncurl", "die": "Death"}},
	# ザクザクムシ 成虫: supplied flying scythe bug (broad-scythe, 2026-09-25). It hovers; LayEgg has a tail_tip bone
	"bug_adult": {"path": "res://assets/models/final-runtime/MonsterChain-Broad-Scythe-Voxel-Animated.glb", "scale": 0.3, "fix_colors": false,
		"anims": {"move": "Fly", "idle": "Hover", "attack": "Attack", "eat": "Attack", "lay_egg": "LayEgg", "die": "Death"}},
	# pupa -> adult: the curled pill bug cracks open and the scythe bug flies out (3.5 s)
	"bug_evolution": {"path": "res://assets/models/final-runtime/MonsterChain-Bug-Evolution-Voxel-Animated.glb", "scale": 0.38, "fix_colors": false, "vertex_palette": true, "anims": {}, "evo_time": 3.5},
	# サソリ: voxel scorpion (2026-10-08). Attack drives the sting forward over its head, so it doubles as
	# the egg-laying sting into a wall. Death crumbles into grains (fx_Scorpion_Dust, hidden otherwise)
	"scorpion": {"path": "res://assets/models/scorpion/scorpion.glb", "scale": 0.46, "fix_colors": false, "stride": 0.34, "loops": ["Idle", "Walk"],
		"anims": {"idle": "Idle", "move": "Walk", "attack": "Attack", "eat": "Eat", "lay_egg": "Attack", "die": "Death"}},
	# 魔王: supplied caped demon king (2026-09-27): idle / look_around, moving eyes (eye.L / eye.R)
	"maou": {"path": "res://assets/models/final-runtime/MonsterChain-Demon-King-Voxel-Animated.glb", "scale": 0.47, "fix_colors": false, "vertex_palette": true, "anims": {}},
	# the captured 魔王: wrapped in bandages, lying on his back (head +Z), kicking (struggle, loop)
	"maou_wrapped": {"path": "res://assets/models/final-runtime/MonsterChain-Demon-King-Captured-Voxel-Animated.glb", "scale": 0.47, "fix_colors": false, "vertex_palette": true, "anims": {"idle": "struggle"}},
	# dig cursor: supplied hydraulic breaker (2026-09-26, reduced for the game). MetalChisel slides
	# along its local Y out of BreakerBody; the tip is at the model origin, the body is 2.4 tall
	"breaker": {"path": "res://assets/models/final-runtime/MonsterChain-Mining-Breaker-Voxel-Animated.glb", "scale": 0.45, "fix_colors": false, "anims": {}},
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
	if entry.get("vertex_palette", false):
		a.use_authored_vertex_palette()
	# Authored voxel clips declare an exact loop set; Eat and Spawn are one-shots.
	if entry.has("loops") and a.anim:
		for clip in a.anim.get_animation_list():
			a.anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in entry["loops"] else Animation.LOOP_NONE
	a.scale = Vector3.ONE * scale_of(key)
	return a


static func evo_time_of(key: String) -> float:
	return float(MODELS[key].get("evo_time", EVOLUTION_TIME))


static func stride_of(key: String) -> float:
	return float(MODELS[key].get("stride", 0.0))


static func evolution_curve() -> Array:
	if _curve.is_empty() and FileAccess.file_exists(EVOLUTION_COLOR_CURVE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVOLUTION_COLOR_CURVE))
		if parsed is Array:
			_curve = parsed
	return _curve
