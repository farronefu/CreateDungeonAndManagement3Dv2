class_name StageDefs
extends RefCounted
## Stage table. The dungeon carries over between stages; only the invading heroes change.
## Add entries here to extend towards the planned 10 stages.
##
## build_time: seconds until the heroes arrive.
## heroes: who comes in, in order. Each entry:
##   profile  the HeroProfile resource
##   mult     scales max HP and attack (and adds a little defence), default 1.0
##   hp       max HP before `mult`, replacing the profile's (optional)
##   heal     false = this hero has no MP and never heals (optional, default: the profile's can_heal)

const YUTA := "res://data/heroes/allen.tres"
const VALEN := "res://data/heroes/valen.tres"

const STAGES := [
	# ゆうた alone, weakened: no healing; a big enough crowd of モコチュリ wears him down
	{"name": "はじまりの洞窟", "build_time": 45.0, "heroes": [{"profile": YUTA, "hp": 70, "heal": false}]},
	# ヴァレン: one ザクザクムシ larva is not enough, two are
	{"name": "ふかい洞窟", "build_time": 60.0, "heroes": [{"profile": VALEN}]},
	# both, and ゆうた heals again: scorpions or several scythe bugs are needed
	{"name": "まどろみの巣", "build_time": 75.0, "heroes": [{"profile": YUTA, "heal": true}, {"profile": VALEN, "mult": 1.5}]},
]


static func get_stage(index: int) -> Dictionary:
	if index < STAGES.size():
		return STAGES[index]
	var last: Dictionary = STAGES[STAGES.size() - 1].duplicate(true)
	for h in last["heroes"]:
		h["mult"] = float(h.get("mult", 1.0)) + 0.4 * (index - STAGES.size() + 1)
	last["name"] = "未踏の階層 %d" % (index + 1)
	return last
