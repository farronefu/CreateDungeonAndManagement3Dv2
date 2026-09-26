class_name MonsterVisual
extends Node3D
## 3D representation of one Monster: interpolates grid movement, faces its heading and
## drives the model's animations from the simulation state. Clips a model does not have
## (e.g. the static tree) are replaced by procedural motion on `_pivot`.

var m: Monster
var actor: ModelActor
var _pivot: Node3D
var _yaw := 0.0
var _dying := false
var _anim_acc := 0.0
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_timer := 0.0
var _last_hp := 0.0
var _proc_tween: Tween
# grass -> tree evolution effect
var _evolving := false
var _evo_t := 0.0
var _evo_mat: ShaderMaterial
## the material replaced by the autumn shader; kept alive so the renderer never sees a freed RID
var _evo_replaced: Material
var _evo_time := 7.0
## the effect keeps playing until the monster has left this model (sim may lag the effect)
var _evo_wait_key := ""

static var _bar_bg_mat: StandardMaterial3D
static var _bar_fg_mat: StandardMaterial3D
static var _autumn_shader: Shader
## game speed (x1/x2/x3): one-shot clips and evolution effects follow the simulation clock
static var time_scale := 1.0


func setup(monster: Monster, animate_in: bool) -> void:
	m = monster
	m.visual = self
	_pivot = Node3D.new()
	add_child(_pivot)
	_yaw = atan2(float(m.dir.x), float(m.dir.y))
	position = _target_pos()
	rotation.y = _yaw
	swap_model(animate_in)
	_make_bar()
	_last_hp = m.hp


func swap_model(animate_in: bool = true) -> void:
	if _evolving:
		return  # the effect swaps to the final model when it ends
	_set_actor(MonsterCatalog.make_actor(m.model_key()))
	if animate_in:
		_play_request("spawn", 0.0)
	else:
		actor.play("idle", 0.0)


func _set_actor(a: ModelActor) -> void:
	if actor:
		# hide now, free a moment later: freeing a model in the frame it was created leaves the
		# renderer with a pending update that points at its (already freed) materials
		var old := actor
		old.visible = false
		old.process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().create_timer(0.2).timeout.connect(old.queue_free)
	actor = a
	_pivot.add_child(actor)


## Plays an evolution effect model once, then swaps to the monster's new model:
##   "evolution"      モコチュリ → ツボミ (grass-to-tree scene with its autumn colour shift)
##   "bug_evolution"  ザクザクムシ サナギ → 成虫 (shell cracks, the scythe bug flies out)
func play_evolution(key: String = "evolution") -> void:
	_evolving = true
	_evo_t = 0.0
	_evo_time = MonsterCatalog.evo_time_of(key)
	_evo_wait_key = m.model_key() if key == "bug_evolution" else ""
	_set_actor(MonsterCatalog.make_actor(key))
	for clip in actor.anim.get_animation_list() if actor.anim else []:
		if clip != "RESET":
			actor.play_once(clip, time_scale)
			break
	var sprout := actor.model.find_child("Sprout_Mesh_01", true, false) as MeshInstance3D
	if sprout:
		_evo_replaced = sprout.get_active_material(0)
		var original := _evo_replaced as BaseMaterial3D
		if original:
			if _autumn_shader == null:
				_autumn_shader = load("res://shaders/autumn.gdshader")
			_evo_mat = ShaderMaterial.new()
			_evo_mat.shader = _autumn_shader
			_evo_mat.set_shader_parameter("color_tex", original.albedo_texture)
			sprout.set_surface_override_material(0, _evo_mat)


func _update_evolution(delta: float) -> void:
	_evo_t += delta * time_scale
	if actor.anim:
		actor.anim.speed_scale = time_scale
	var frac := clampf(_evo_t / _evo_time, 0.0, 1.0)
	var curve := MonsterCatalog.evolution_curve()
	if _evo_mat and not curve.is_empty():
		var idx := frac * (curve.size() - 1)
		var l := int(idx)
		var r := mini(l + 1, curve.size() - 1)
		_evo_mat.set_shader_parameter("autumn", lerpf(float(curve[l]), float(curve[r]), idx - l))
	if frac >= 1.0 and m.model_key() != _evo_wait_key:
		_evolving = false
		_evo_mat = null
		swap_model(false)


func _target_pos() -> Vector3:
	var a := DungeonGrid.cell_center(m.from_cell)
	var b := DungeonGrid.cell_center(m.cell)
	var t := m.move_t
	if m.kind == Monster.Kind.BUG:
		t = smoothstep(0.0, 1.0, t) * 0.4 + t * 0.6
	return a.lerp(b, t) + Vector3(m.jitter.x, 0, m.jitter.y)


## Advances the skeletal animation by hand (MonsterLayer decides when): time piles up and is
## applied in one step; off screen it is dropped, so the pose simply resumes later.
func step_animation(delta: float, on_screen: bool, now: bool) -> void:
	if actor == null or actor.anim == null:
		return
	if actor.anim.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
		actor.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_acc += delta
	if not on_screen:
		_anim_acc = 0.0
	elif now:
		actor.anim.advance(_anim_acc)
		_anim_acc = 0.0


func sync(delta: float) -> void:
	if _dying or actor == null:
		return
	position = _target_pos()
	var target := atan2(float(m.dir.x), float(m.dir.y))
	_yaw = lerp_angle(_yaw, target, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = _yaw
	if _evolving:
		m.anim_request = ""
		_update_evolution(delta)
		_update_bar(delta)
		return
	if m.anim_request != "":
		_play_request(m.anim_request, m.busy)
		m.anim_request = ""
	if m.is_moving() and actor.has_anim("move"):
		actor.play("move", 0.15, _move_speed() * time_scale)
	else:
		actor.play(m.base_anim)
	_last_hp = m.hp
	_update_bar(delta)


## Walk playback rate: one cycle per cell, or matched to the model's stride (capped so legs stay readable).
func _move_speed() -> float:
	var clip_len := actor.anim_length("move")
	var stride := MonsterCatalog.stride_of(m.model_key())
	if stride > 0.0:
		return minf(3.0, clip_len / (stride * m.move_dur))
	return clip_len / maxf(0.05, m.move_dur)


## Plays a one-shot clip timed to the simulation's action length, or a procedural stand-in.
func _play_request(n: String, busy: float) -> void:
	# サナギ → 成虫: the dedicated evolution scene replaces the pupa's own hatch clip
	if n == "hatch" and m.kind == Monster.Kind.BUG and MonsterCatalog.MODELS.has("bug_evolution"):
		play_evolution("bug_evolution")
		return
	if actor.has_anim(n):
		var speed := 1.0
		if busy > 0.05:
			speed = clampf(actor.anim_length(n) / busy, 0.6, 3.0)
		actor.play_once(n, speed * time_scale)
		return
	var d := maxf(busy, 0.35)
	if _proc_tween:
		_proc_tween.kill()
	_pivot.position = Vector3.ZERO
	_pivot.scale = Vector3.ONE
	_proc_tween = create_tween()
	match n:
		"spawn":
			_pivot.scale = Vector3.ONE * 0.01
			_proc_tween.tween_property(_pivot, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"attack":
			_proc_tween.tween_property(_pivot, "position", Vector3(0, 0, -0.08), d * 0.35).set_ease(Tween.EASE_OUT)
			_proc_tween.tween_property(_pivot, "position", Vector3(0, 0.03, 0.2), d * 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_proc_tween.tween_property(_pivot, "position", Vector3.ZERO, d * 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"hurt":
			_proc_tween.tween_property(_pivot, "scale", Vector3(1.12, 0.85, 1.12), 0.08)
			_proc_tween.tween_property(_pivot, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_:
			# absorb / spawn_child / hatch / eat / lay_egg: breathing pulse
			var pulses := 2 if d > 0.8 else 1
			for i in pulses:
				_proc_tween.tween_property(_pivot, "scale", Vector3(1.08, 1.14, 1.08), d / pulses * 0.45).set_trans(Tween.TRANS_SINE)
				_proc_tween.tween_property(_pivot, "scale", Vector3.ONE, d / pulses * 0.55).set_trans(Tween.TRANS_SINE)


func hurt() -> void:
	if actor and not _dying:
		actor.flash(Color(1, 1, 1))
		_bar_timer = 3.0
		if not actor.is_busy() and not _evolving:
			_play_request("hurt", 0.0)


func die(cause: String) -> void:
	_dying = true
	_bar.visible = false
	if _proc_tween:
		_proc_tween.kill()
	var dur := 0.4
	if actor and actor.has_anim("die") and not _evolving:
		dur = actor.play_once("die", 1.6 if cause == "eaten" else 1.0)
		var tw := create_tween()
		tw.tween_interval(dur)
		tw.tween_callback(queue_free)
		return
	# no death clip: short hold, then shrink away (like the supplied grass / tree)
	var tw2 := create_tween()
	tw2.tween_interval(0.1 if cause == "eaten" or cause == "bloom" else 0.35)
	tw2.tween_property(_pivot, "scale", Vector3(1.2, 0.2, 1.2), 0.15)
	tw2.tween_property(_pivot, "scale", Vector3.ONE * 0.001, 0.2)
	tw2.tween_callback(queue_free)


func _make_bar() -> void:
	if _bar_bg_mat == null:
		_bar_bg_mat = StandardMaterial3D.new()
		_bar_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bar_bg_mat.albedo_color = Color(0.08, 0.05, 0.05)
		_bar_bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_bar_bg_mat.billboard_keep_scale = true
		_bar_bg_mat.no_depth_test = true
		_bar_bg_mat.render_priority = 1
		_bar_fg_mat = _bar_bg_mat.duplicate()
		_bar_fg_mat.albedo_color = Color(1.0, 0.35, 0.25)
		_bar_fg_mat.render_priority = 2
	_bar = Node3D.new()
	_bar.position = Vector3(0, 0.62 if m.kind == Monster.Kind.MOSS else 0.55, 0)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.44, 0.07)
	bg.mesh = q
	bg.material_override = _bar_bg_mat
	_bar.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.4, 0.04)
	_bar_fill.mesh = q2
	_bar_fill.material_override = _bar_fg_mat
	_bar.add_child(_bar_fill)
	_bar.visible = false
	add_child(_bar)


func _update_bar(delta: float) -> void:
	if _bar_timer > 0.0:
		_bar_timer -= delta
		_bar.visible = true
		var r := clampf(m.hp / maxf(1.0, m.max_hp), 0.0, 1.0)
		_bar_fill.scale.x = maxf(0.01, r)
		_bar.global_rotation = Vector3.ZERO
	else:
		_bar.visible = false
