class_name StageDefs
extends RefCounted
## Stage table. The dungeon carries over between stages; only the invading hero changes.
## Add entries here to extend towards the planned 10 stages.

const STAGES := [
	{"name": "はじまりの洞窟", "hero": "res://data/heroes/allen.tres", "hero_mult": 1.0, "build_time": 150.0},
	{"name": "ふかい洞窟", "hero": "res://data/heroes/allen.tres", "hero_mult": 1.4, "build_time": 150.0},
	{"name": "まどろみの巣", "hero": "res://data/heroes/allen.tres", "hero_mult": 1.8, "build_time": 160.0},
]


static func get_stage(index: int) -> Dictionary:
	if index < STAGES.size():
		return STAGES[index]
	var last: Dictionary = STAGES[STAGES.size() - 1].duplicate()
	last["hero_mult"] = float(last["hero_mult"]) + 0.4 * (index - STAGES.size() + 1)
	last["name"] = "未踏の階層 %d" % (index + 1)
	return last
