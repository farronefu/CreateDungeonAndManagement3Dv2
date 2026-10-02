extends SceneTree
## godot --headless --path PROJECT --script res://scripts/debug/voxel_pillbug_test.gd
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var v := MonsterVisual.new()
	var m := Monster.new()
	m.kind = Monster.Kind.BUG
	root.add_child(v)
	v.setup(m, false)
	var a := v.actor
	var mesh := a.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check((mesh.get_active_material(0) as BaseMaterial3D).vertex_color_use_as_albedo, "Voxel vertex colors enabled")
	m.move_dur = Balance.LARVA_STEP_TIME
	check(is_equal_approx(v._move_speed(), 3.0), "Existing readable walk speed cap retained")
	check(is_equal_approx(Balance.ATTACK_HIT_FRACTION, 0.44), "Eat contact remains at 0.44 seconds")
	var expected := {"Idle": 2.0, "Walk": 0.8, "Attack": 1.5, "Eat": 1.0, "Spawn": 0.45, "Death": 1.5, "Curl": 0.6, "CurlIdle": 1.6, "Uncurl": 0.8, "DeathFallback": 0.7}
	check(a.anim.get_animation_list().size() == 10, "Exactly ten imported clips")
	check(not a.has_anim("hurt") and not a.anim.has_animation("Hit"), "No hit clip")
	for clip in expected:
		check(a.anim.has_animation(clip), "Clip exists: " + clip)
		check(is_equal_approx(a.anim.get_animation(clip).length, expected[clip]), "Clip duration: " + clip)
		var mode := Animation.LOOP_LINEAR if clip in ["Idle", "Walk", "CurlIdle"] else Animation.LOOP_NONE
		check(a.anim.get_animation(clip).loop_mode == mode, "Explicit loop mode: " + clip)
		a.anim.play(clip)
		a.anim.seek(expected[clip] * 0.5, true)
	var box := a.local_aabb()
	print("VOXEL BOUNDS ", box)
	check(absf(box.position.y) < 0.002 and absf(box.size.y - 1.044 * 0.38) < 0.01, "Ground origin and familiar height")
	check(a.model.rotation == Vector3.ZERO, "No extra axis rotation")
	a.play("idle", 0.0, 1.0, true)
	v._play_request("spawn", 0.0)
	check(a.current == "spawn" and v._proc_tween == null, "Spawn uses authored clip without duplicate scale tween")
	v._play_request("attack", Balance.BUG_ATTACK_BUSY)
	check(a.current == "attack" and is_equal_approx(a.anim.speed_scale, 2.5), "Attack lasts 0.6 seconds")
	check(is_equal_approx(Balance.BUG_ATTACK_BUSY * Balance.ATTACK_HIT_FRACTION, 0.264), "Attack contact timing retained")
	v._play_request("eat", 1.0)
	check(a.current == "eat" and is_equal_approx(a.anim.speed_scale, 1.0), "Dedicated Eat lasts one second")
	var sk := a.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check(sk.get_bone_count() == 105, "105 bones")
	a.anim.play("Walk")
	a.anim.seek(0.0, true)
	var start := {}
	for side in ["L", "R"]:
		for i in [1, 2, 3]:
			var name := "leg%d_lower.%s" % [i, side]
			start[name] = sk.get_bone_pose(sk.find_bone(name))
	# Quarter cycle is deliberately different for all six legs.
	a.anim.seek(0.2, true)
	for name in start:
		check(not sk.get_bone_pose(sk.find_bone(name)).is_equal_approx(start[name]), "Walk moves " + name)
	for stage in [Monster.LARVA, Monster.PUPA]:
		m.stage = stage
		v.swap_model(false)
		var pivot := v._pivot.transform
		v.hurt()
		check(v.actor._flash_t == 0.18 and v._bar_timer == 3.0, "White flash and HP bar retained")
		check(v._proc_tween == null and v._pivot.transform == pivot, "No pillbug damage deformation")
	check(v.actor.current == "idle" and v.actor._clip("idle") == "CurlIdle", "Curled pupa idle")
	v.swap_model(true)
	check(v.actor.current == "spawn" and v.actor._clip("spawn") == "Curl", "Stage change curls once")
	v.actor.anim.seek(0.6, true)
	var pupa_sk := v.actor.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var underbody := pupa_sk.find_bone("Underbody")
	print("CURL UNDERBODY SCALE ", pupa_sk.get_bone_pose_scale(underbody))
	check(pupa_sk.get_bone_pose_scale(underbody).y < 0.3, "Curled internal body retracts")
	v._play_request("hatch", Balance.PUPA_HATCH_TIME)
	check(v._evolving and v._evo_wait_key == "bug_pupa", "Existing separate evolution still used")
	check(MonsterCatalog.MODELS["bug_evolution"]["path"] == "res://assets/models/broad-scythe/pillbug-to-scythe-evolution.glb", "Evolution model unchanged")
	check(MonsterCatalog.MODELS["bug_adult"]["path"] == "res://assets/models/broad-scythe/broad-scythe.glb", "Adult model unchanged")
	# Complete the existing evolution and ensure it ends in the adult model.
	m.stage = Monster.ADULT
	v._update_evolution(3.6)
	check(not v._evolving and v.actor._clip("idle") == "Hover", "Evolution connects to adult hover")
	v.queue_free()
	await create_timer(0.25).timeout
	for stage in [Monster.LARVA, Monster.PUPA]:
		var dead := MonsterVisual.new()
		var victim := Monster.new()
		victim.kind = Monster.Kind.BUG
		victim.stage = stage
		root.add_child(dead)
		dead.setup(victim, false)
		dead.die("killed")
		check(dead._dying and dead.actor.current == "die", "Authored death for both stages")
		dead.step_animation(0.5, true, true)
		check(dead.actor.anim.current_animation_position > 0.4, "Death keeps advancing")
		await create_timer(1.55).timeout
		check(not is_instance_valid(dead), "Death visual removed after clip")
	print("VOXEL PILLBUG PASS failures=", failures)
	quit(1 if failures else 0)


