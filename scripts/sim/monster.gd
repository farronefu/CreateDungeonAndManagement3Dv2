class_name Monster
extends RefCounted
## Simulation state of one monster. Rendering lives in MonsterVisual.

enum Kind { MOSS, BUG }
# MOSS stages
const MOSS := 0
const BUD := 1
const FLOWER := 2
# BUG stages
const LARVA := 0
const PUPA := 1
const ADULT := 2

var id := 0
var kind := Kind.MOSS
var stage := 0
var cell := Vector2i.ZERO
var from_cell := Vector2i.ZERO
var move_t := 1.0
var move_dur := 1.0
var dir := Vector2i(0, 1)
var hp := 10.0
var max_hp := 10.0
var atk := 1.0
var nutrient := 0
var age := 0.0
## seconds spent in the current stage
var stage_t := 0.0
var timer := 0.0
var meta_timer := 0.0
var cooldown := 0.0
var lay_cooldown := 0.0
## larvae a freshly emerged adult still lays straight away (see Ecosystem._tick_adult)
var birth_lays := 0
var _birth_lay := false
var busy := 0.0
## pending attack on the hero: lands when hit_timer crosses 0
var hit_timer := -1.0
var hit_dmg := 0
var toggle := false
var alive := true
var jitter := Vector2.ZERO
var base_anim := "idle"
## One-shot animation requested by the simulation; consumed by the visual.
var anim_request := ""
var visual: Node3D
## parent that laid this monster (only set at birth, used to place it at the tail tip)
var born_from: Monster


func is_moving() -> bool:
	return move_t < 1.0


func is_prey() -> bool:
	return kind == Kind.MOSS


func model_key() -> String:
	if kind == Kind.MOSS:
		return ["moss", "moss_bud", "moss_flower"][stage]
	return ["bug_larva", "bug_pupa", "bug_adult"][stage]


func display_name() -> String:
	if kind == Kind.MOSS:
		return ["モコチュリ", "モコツボミ", "モコバナ"][stage]
	return ["ザクザクムシ(幼虫)", "ザクザクムシ(サナギ)", "ザクザクムシ(成虫)"][stage]


## Threat order used by the hero when picking a target.
func threat() -> int:
	if kind == Kind.BUG:
		return [5, 3, 8][stage]
	return [2, 1, 1][stage]


func to_dict() -> Dictionary:
	return {"kind": kind, "stage": stage, "cell": cell, "dir": dir, "hp": hp, "max_hp": max_hp, "atk": atk, "nutrient": nutrient, "age": age, "timer": timer, "lay_cooldown": lay_cooldown}


static func from_dict(d: Dictionary) -> Monster:
	var m := Monster.new()
	m.kind = d["kind"]
	m.stage = d["stage"]
	m.cell = d["cell"]
	m.from_cell = m.cell
	m.dir = d["dir"]
	m.hp = d["hp"]
	m.max_hp = d["max_hp"]
	m.atk = d["atk"]
	m.nutrient = d["nutrient"]
	m.age = d["age"]
	m.timer = d["timer"]
	m.lay_cooldown = d["lay_cooldown"]
	return m
