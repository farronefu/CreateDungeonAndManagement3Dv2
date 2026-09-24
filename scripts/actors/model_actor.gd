class_name ModelActor
extends Node3D
## Wraps an imported GLB scene: normalises its size, finds the AnimationPlayer and
## provides cross-faded playback plus hit-flash / fade helpers.
## Any GLB that follows the animation naming in HeroProfile / MonsterCatalog can be dropped in.

const LOOPING := ["idle", "move", "walk", "absorb", "eat", "carried", "scared", "cheer"]

var model: Node3D
var anim: AnimationPlayer
var current := ""
## logical animation name -> clip name in the GLB (e.g. {"move": "walk", "absorb": "gather"})
var anim_map := {}
var _meshes: Array[GeometryInstance3D] = []
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _one_shot_until := 0.0
var _clock := 0.0


func setup(packed: PackedScene, target_height: float = 0.0, yaw_offset: float = 0.0, fix_vertex_colors: bool = false, extra_loops: Array = [], clip_map: Dictionary = {}) -> void:
	anim_map = clip_map
	model = packed.instantiate() as Node3D
	add_child(model)
	_collect(model)
	if target_height > 0.0:
		var box := _model_aabb()
		if box.size.y > 0.0001:
			var s := target_height / box.size.y
			model.scale = Vector3.ONE * s
			model.position.y = -box.position.y * s
	model.rotation.y = yaw_offset
	anim = _find_player(model)
	if anim:
		_ensure_idle()
		for n in LOOPING + extra_loops:
			if has_anim(n):
				anim.get_animation(_clip(n)).loop_mode = Animation.LOOP_LINEAR
	for g in _meshes:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if fix_vertex_colors and g is MeshInstance3D:
			var mi := g as MeshInstance3D
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
					if mat:
						mat.vertex_color_use_as_albedo = true
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)


func _clip(n: String) -> String:
	return str(anim_map.get(n, n))


func has_anim(n: String) -> bool:
	return anim != null and anim.has_animation(_clip(n))


func anim_length(n: String) -> float:
	return anim.get_animation(_clip(n)).length if has_anim(n) else 0.0


## Models without an idle clip (e.g. the supplied grass) hold the first key of their walk clip.
func _ensure_idle() -> void:
	if has_anim("idle") or not has_anim("move"):
		return
	var idle := anim.get_animation(_clip("move")).duplicate(true) as Animation
	for track in idle.get_track_count():
		while idle.track_get_key_count(track) > 1:
			idle.track_remove_key(track, idle.track_get_key_count(track) - 1)
	idle.length = 0.1
	var lib := anim.get_animation_library("")
	if lib and not lib.has_animation("idle"):
		lib.add_animation("idle", idle)
	anim_map.erase("idle")


## Plays a looping/base animation. Ignored while a one-shot is still running unless `force`.
func play(n: String, blend: float = 0.18, speed: float = 1.0, force: bool = false) -> void:
	if not has_anim(n):
		return
	if not force and _clock < _one_shot_until:
		return
	if n == current and anim.is_playing():
		anim.speed_scale = speed
		return
	current = n
	anim.play(_clip(n), blend)
	anim.speed_scale = speed


## Plays an animation once; base animations resume after it finishes.
func play_once(n: String, speed: float = 1.0, blend: float = 0.1) -> float:
	if not has_anim(n):
		return 0.0
	current = n
	anim.play(_clip(n), blend)
	anim.seek(0.0, true)
	anim.speed_scale = speed
	var dur := anim_length(n) / maxf(speed, 0.01)
	_one_shot_until = _clock + dur
	return dur


func is_busy() -> bool:
	return _clock < _one_shot_until


func flash(color: Color = Color(1, 0.25, 0.2), time: float = 0.18) -> void:
	_flash_mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
	_flash_t = time
	for g in _meshes:
		g.material_overlay = _flash_mat


func set_fade(alpha: float) -> void:
	for g in _meshes:
		g.transparency = 1.0 - clampf(alpha, 0.0, 1.0)


func set_shadows(on: bool) -> void:
	for g in _meshes:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_clock += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		var a := clampf(_flash_t / 0.18, 0.0, 1.0) * 0.75
		_flash_mat.albedo_color.a = a
		if _flash_t <= 0.0:
			for g in _meshes:
				g.material_overlay = null


func _collect(n: Node) -> void:
	if n is GeometryInstance3D:
		_meshes.append(n)
	for c in n.get_children():
		_collect(c)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p:
			return p
	return null


func _model_aabb() -> AABB:
	var box := AABB()
	var first := true
	for g in _meshes:
		if not (g is MeshInstance3D) or (g as MeshInstance3D).mesh == null:
			continue
		var mi := g as MeshInstance3D
		var xf := _relative_xform(g)
		# Skinned meshes are placed by their bones, not by the node chain: use rest * bind.
		if mi.skin and mi.skin.get_bind_count() > 0:
			var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if sk:
				var bi := mi.skin.get_bind_bone(0)
				if bi < 0:
					bi = sk.find_bone(mi.skin.get_bind_name(0))
				if bi >= 0:
					xf = _relative_xform(sk) * sk.get_bone_global_rest(bi) * mi.skin.get_bind_pose(0)
		var b := xf * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _relative_xform(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != model:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
