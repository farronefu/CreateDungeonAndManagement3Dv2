class_name MonsterVisual
extends Node3D
## 3D representation of one Monster: interpolates grid movement, faces its heading and
## drives the model's animations from the simulation state.

var m: Monster
var actor: ModelActor
var _yaw := 0.0
var _dying := false
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_timer := 0.0
var _last_hp := 0.0

static var _bar_bg_mat: StandardMaterial3D
static var _bar_fg_mat: StandardMaterial3D


func setup(monster: Monster, animate_in: bool) -> void:
	m = monster
	m.visual = self
	_yaw = atan2(float(m.dir.x), float(m.dir.y))
	position = _target_pos()
	rotation.y = _yaw
	swap_model(animate_in)
	_make_bar()
	_last_hp = m.hp


func swap_model(animate_in: bool = true) -> void:
	if actor:
		actor.queue_free()
	actor = MonsterCatalog.make_actor(m.model_key())
	add_child(actor)
	if animate_in and actor.has_anim("spawn"):
		actor.play_once("spawn")
	else:
		actor.play("idle", 0.0)


func _target_pos() -> Vector3:
	var a := DungeonGrid.cell_center(m.from_cell)
	var b := DungeonGrid.cell_center(m.cell)
	var t := m.move_t
	if m.kind == Monster.Kind.BUG:
		t = smoothstep(0.0, 1.0, t) * 0.4 + t * 0.6
	return a.lerp(b, t) + Vector3(m.jitter.x, 0, m.jitter.y)


func sync(delta: float) -> void:
	if _dying or actor == null:
		return
	position = _target_pos()
	var target := atan2(float(m.dir.x), float(m.dir.y))
	_yaw = lerp_angle(_yaw, target, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = _yaw
	if m.anim_request != "":
		actor.play_once(m.anim_request)
		m.anim_request = ""
	if m.is_moving() and actor.has_anim("move"):
		actor.play("move", 0.15, actor.anim_length("move") / maxf(0.05, m.move_dur))
	else:
		actor.play(m.base_anim)
	_last_hp = m.hp
	_update_bar(delta)


func hurt() -> void:
	if actor and not _dying:
		actor.flash(Color(1, 1, 1))
		_bar_timer = 3.0
		if actor.has_anim("hurt") and not actor.is_busy():
			actor.play_once("hurt")


func die(cause: String) -> void:
	_dying = true
	_bar.visible = false
	var dur := 0.4
	if actor and actor.has_anim("die"):
		dur = actor.play_once("die", 1.6 if cause == "eaten" else 1.0)
	elif cause == "bloom":
		dur = 0.3
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(queue_free)


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
