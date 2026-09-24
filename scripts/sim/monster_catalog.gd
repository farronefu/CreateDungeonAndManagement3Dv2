class_name MonsterCatalog
extends RefCounted
## Model lookup for monsters. Replace a path here to swap in hand-made models;
## they only need the same animation names (idle / move / attack / hurt / die / spawn ...).

const MODELS := {
	"moss": {"path": "res://assets/models/monsters/moss.glb", "scale": 1.0},
	"moss_bud": {"path": "res://assets/models/monsters/moss_bud.glb", "scale": 1.0},
	"moss_flower": {"path": "res://assets/models/monsters/moss_flower.glb", "scale": 1.0},
	"bug_larva": {"path": "res://assets/models/monsters/bug_larva.glb", "scale": 1.05},
	"bug_pupa": {"path": "res://assets/models/monsters/bug_pupa.glb", "scale": 1.0},
	"bug_adult": {"path": "res://assets/models/monsters/bug_adult.glb", "scale": 1.15},
	"maou": {"path": "res://assets/models/monsters/maou.glb", "scale": 1.15},
	"pickaxe": {"path": "res://assets/models/monsters/pickaxe.glb", "scale": 1.0},
}

static var _cache := {}


static func scene(key: String) -> PackedScene:
	if not _cache.has(key):
		_cache[key] = load(MODELS[key]["path"])
	return _cache[key]


static func scale_of(key: String) -> float:
	return float(MODELS[key]["scale"])


## Instantiates a monster model wrapped in a ModelActor.
static func make_actor(key: String) -> ModelActor:
	var a := ModelActor.new()
	a.setup(scene(key), 0.0, 0.0, true)
	a.scale = Vector3.ONE * scale_of(key)
	return a
