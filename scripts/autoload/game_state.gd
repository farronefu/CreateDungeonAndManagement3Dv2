extends Node
## Persistent run state (survives scene reloads between stages).
## The dungeon (grid + monsters) carries over from stage to stage.

var in_run := false
var stage_index := 0
var seed_value := 0
var evolution_points := 0
var upgrades := {"dig": 0, "moss": 0, "bug": 0}
## Snapshot the next stage starts from ({} = generate a fresh dungeon).
var dungeon_snapshot := {}
## Snapshot taken when the current stage began (used by "retry").
var stage_start_snapshot := {}
## Set by "retry": the reloaded stage starts at the hero's arrival cut-in, not the title.
var restart_stage := false


func new_run() -> void:
	in_run = true
	stage_index = 0
	seed_value = randi() % 100000 + 1
	evolution_points = 0
	upgrades = {"dig": 0, "moss": 0, "bug": 0}
	dungeon_snapshot = {}
	stage_start_snapshot = {}


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func dig_capacity() -> int:
	return Balance.DIG_MAX_BASE + 10 * upgrade_level("dig")


func buy(id: String) -> bool:
	var u: Dictionary = Balance.UPGRADES[id]
	if upgrade_level(id) >= int(u["max"]) or evolution_points < int(u["cost"]):
		return false
	evolution_points -= int(u["cost"])
	upgrades[id] = upgrade_level(id) + 1
	return true
