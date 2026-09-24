class_name HeroProfile
extends Resource
## Everything that defines one hero. To swap the hero model, point `model_path` at another
## GLB (or .tscn) and set the animation names it uses. No code changes needed.

@export var display_name := "アレン"
@export_multiline var intro_line := "魔王をさらいに来たぞ！"

@export_group("Model")
@export_file("*.glb", "*.gltf", "*.tscn") var model_path := "res://assets/models/hero/hero.glb"
## Height of the model on screen in tiles (1 tile = 1 block).
@export var model_height := 0.85
## Extra yaw if the model does not face +Z.
@export_range(-180.0, 180.0) var model_yaw_offset_deg := 0.0
@export var anim_idle := "idle"
@export var anim_walk := "walk"
@export var anim_attack := "attack"
## Playback speed of the attack clip and when (in clip seconds) the blow lands.
@export var attack_anim_speed := 1.4
@export var attack_hit_time := 0.7
## Walk clip speed at the base move time.
@export var walk_anim_speed := 1.0

@export_group("Stats")
@export var max_hp := 120
@export var max_mp := 30
@export var atk := 8
@export var defense := 1
## Seconds per cell.
@export var move_time := 0.55
@export var carry_move_time := 0.8
@export var attack_interval := 1.15
@export var heal_amount := 35
@export var heal_cost := 6
## Manhattan distance at which the hero notices the demon lord.
@export var sight := 4
