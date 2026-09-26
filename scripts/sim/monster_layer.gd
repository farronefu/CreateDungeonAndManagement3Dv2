class_name MonsterLayer
extends Node3D
## Creates / updates / removes the 3D visuals for every monster in the Ecosystem.

var eco: Ecosystem
var fx: Effects
var _visuals := {}  # Monster.id -> MonsterVisual
## how far outside the view (world units) a monster still counts as on screen
const ON_SCREEN_MARGIN := 1.5
## on-screen monsters advance their skeletal animation every this many frames
const ANIM_STEP := 2
var _frame := 0
## monsters born this frame whose visuals are still to be built ([Monster, cause])
var _pending: Array = []
const SPAWNS_PER_FRAME := 4


func setup(e: Ecosystem, effects: Effects) -> void:
	eco = e
	fx = effects
	eco.spawned.connect(_on_spawned)
	eco.died.connect(_on_died)
	eco.evolved.connect(_on_evolved)
	eco.nutrient_flow.connect(_on_flow)
	eco.ate.connect(_on_ate)
	# build every model once up front: the first instance of each pays for loading and for
	# generating its idle clip, which would otherwise hitch the frame the monster first appears
	for key in ["moss", "moss_bud", "moss_flower", "evolution", "bug_larva", "bug_pupa", "bug_adult", "bug_evolution"]:
		MonsterCatalog.make_actor(key).free()
	for m in eco.monsters:
		_on_spawned(m, "load")


func _on_spawned(m: Monster, cause: String) -> void:
	# laid by a scythe bug: pop out exactly at the tip of its tail
	if m.born_from:
		var pv := m.born_from.visual as MonsterVisual
		if pv and pv.actor:
			var tip = pv.actor.bone_world_position("tail_tip")
			if tip != null:
				var cc := DungeonGrid.cell_center(m.cell)
				m.jitter = Vector2(clampf(tip.x - cc.x, -0.45, 0.45), clampf(tip.z - cc.z, -0.45, 0.45))
		m.born_from = null
	# a flower can scatter 20+ children at once: build their visuals a few per frame
	if cause != "load":
		_pending.append([m, cause])
		return
	_create_visual(m, cause)


func _create_visual(m: Monster, cause: String) -> void:
	var v := MonsterVisual.new()
	add_child(v)
	v.setup(m, cause != "load")
	_visuals[m.id] = v
	if cause == "dig" or cause == "birth":
		var col := Color(0.55, 1.0, 0.3) if m.kind == Monster.Kind.MOSS else Color(1.0, 0.6, 0.2)
		fx.sparkle(v.position + Vector3(0, 0.25, 0), col, 10)
		Sfx.play("spawn_moss" if m.kind == Monster.Kind.MOSS else "spawn_bug", v.position)


func _on_died(m: Monster, cause: String) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v == null:
		return
	_visuals.erase(m.id)
	v.die(cause)
	if cause == "killed":
		Sfx.play("monster_die", v.position)
	if cause != "eaten":
		fx.dust(v.position + Vector3(0, 0.15, 0), Color(0.55, 0.75, 0.35, 0.6) if m.kind == Monster.Kind.MOSS else Color(0.6, 0.45, 0.3, 0.6), 0.7)


func _on_evolved(m: Monster) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v:
		if m.kind == Monster.Kind.MOSS and m.stage == Monster.BUD:
			v.play_evolution()
		else:
			v.swap_model()
		fx.ring(v.position, Color(1.0, 0.9, 0.4))
		fx.sparkle(v.position + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.4), 16)
		Sfx.play("evolve", v.position)


func _on_flow(block: Vector2i, m: Monster, into_monster: bool) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v == null:
		return
	var b := DungeonGrid.cell_center(block, Balance.BLOCK_H * 0.6)
	var p := v.position + Vector3(0, 0.25, 0)
	if into_monster:
		fx.motes(b, p, Color(0.55, 1.0, 0.3))
	else:
		fx.motes(p, b, Color(0.9, 0.85, 0.3))


func _on_ate(pred: Monster, prey: Monster) -> void:
	var v: MonsterVisual = _visuals.get(prey.id)
	if v:
		fx.sparkle(v.position + Vector3(0, 0.2, 0), Color(0.6, 0.9, 0.3), 10)
	Sfx.play("eat", v.position if v else Vector3.ZERO)


func visual_of(m: Monster) -> MonsterVisual:
	return _visuals.get(m.id)


## Skeletal animation is the biggest per-frame cost (the supplied models have 100-300 bones),
## so the monsters' animations are stepped by hand: on screen every ANIM_STEP frames (spread
## over the frames so the load stays even), off screen not at all until they come back.
func _process(delta: float) -> void:
	_frame += 1
	var built := 0
	while not _pending.is_empty() and built < SPAWNS_PER_FRAME:
		var p: Array = _pending.pop_front()
		var pm: Monster = p[0]
		if pm.alive:
			_create_visual(pm, p[1])
			built += 1
	var cam := get_viewport().get_camera_3d()
	var planes: Array[Plane] = cam.get_frustum() if cam else []
	for v in _visuals.values():
		var mv := v as MonsterVisual
		mv.sync(delta)
		var on := planes.is_empty() or _in_view(planes, mv.global_position)
		mv.step_animation(delta, on, (_frame + mv.m.id) % ANIM_STEP == 0)


static func _in_view(planes: Array[Plane], p: Vector3) -> bool:
	for pl in planes:
		if pl.distance_to(p) > ON_SCREEN_MARGIN:
			return false
	return true
