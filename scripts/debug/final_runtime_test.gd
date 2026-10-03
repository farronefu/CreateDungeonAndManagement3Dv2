extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var spec := {
		"moss": [0.37, {"walk":1.0,"gather":4.0,"attack":1.5,"die":1.933333}],
		"moss_bud": [0.29,{"attack":1.5,"die":1.933333}],
		"moss_flower": [0.37,{"attack":1.5,"die":1.933333}],
		"evolution": [0.37,{"Scene":7.0}],
		"bug_adult": [0.3,{"Hover":0.8,"Fly":0.8,"Attack":1.4,"LayEgg":1.5,"Death":1.5}],
		"bug_evolution": [0.38,{"Evolve":3.5}],
		"maou": [0.47,{"idle":3.0,"cower":1.0,"look_around":6.333333,"cower_in":0.8,"cower_out":0.8}],
		"maou_wrapped": [0.47,{"struggle":1.2}],
		"breaker": [0.45,{"HoverCycle_Preview":2.094395,"DigBurst_Preview":0.315}]
	}
	var loops := ["walk","gather","idle","Hover","Fly","Attack","cower","struggle"]
	for key in spec:
		var a := MonsterCatalog.make_actor(key)
		root.add_child(a)
		check(a.scale.is_equal_approx(Vector3.ONE * float(spec[key][0])), "scale " + key)
		check(a.model.scale == Vector3.ONE and a.model.position == Vector3.ZERO and a.model.rotation == Vector3.ZERO, "authored origin/rest " + key)
		check(not MonsterCatalog.MODELS[key]["fix_colors"], "no blanket color fix " + key)
		for clip in spec[key][1]:
			check(a.anim.has_animation(clip), "clip exists " + key + "/" + clip)
			var animation := a.anim.get_animation(clip)
			check(absf(animation.length-float(spec[key][1][clip])) < 0.0001, "clip duration " + key + "/" + clip)
			check(animation.loop_mode == (Animation.LOOP_LINEAR if clip in loops else Animation.LOOP_NONE), "clip loop " + key + "/" + clip)
		if key in ["maou","maou_wrapped","bug_evolution"]:
			var corrected := 0
			for mesh in a._meshes:
				if mesh is MeshInstance3D:
					for surface in mesh.mesh.get_surface_count():
						var src := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
						var mat := mesh.get_active_material(surface) as BaseMaterial3D
						var colors = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
						check(mat.albedo_texture == src.albedo_texture and mat.albedo_color == src.albedo_color, "source albedo preserved " + key)
						check(mat.emission_enabled == src.emission_enabled and mat.emission == src.emission and mat.emission_energy_multiplier == src.emission_energy_multiplier, "emission preserved " + key)
						if colors != null and not colors.is_empty() and mat.albedo_texture == null:
							check(mat.vertex_color_use_as_albedo, "authored palette visible " + key)
							corrected += 1
						elif mat.albedo_texture != null:
							check(mat.vertex_color_use_as_albedo == src.vertex_color_use_as_albedo, "texture flags preserved " + key)
			check(corrected > 0, "palette surfaces found " + key)
		if key == "moss":
			var green_emission := false
			for mesh in a._meshes:
				if mesh is MeshInstance3D:
					for surface in mesh.mesh.get_surface_count():
						var mat := mesh.get_active_material(surface) as BaseMaterial3D
						if mat and mat.emission_enabled and mat.emission.g > mat.emission.r:
							green_emission = true
			check(green_emission, "green nutrient emission retained")
		if key == "bug_adult":
			check(a.bone_world_position("tail_tip") != null, "tail_tip retained")
			var sk := a.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var wing := sk.find_bone("wing_fore.L")
			check(wing >= 0, "wing bone retained")
			a.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			a.anim.play("Hover", 0.0)
			a.anim.seek(0.0, true)
			var rest := sk.get_bone_pose_rotation(wing)
			a.anim.seek(0.05, true)
			check(not rest.is_equal_approx(sk.get_bone_pose_rotation(wing)), "hover wings animate")
			a.anim.play("Death", 0.0)
			a.anim.seek(0.25, true)
			var stopped := sk.get_bone_pose_rotation(wing)
			a.anim.seek(1.0, true)
			check(absf(stopped.dot(sk.get_bone_pose_rotation(wing))) > 0.9999, "death wings stop after quarter second within import precision")
		if key == "breaker":
			check(not a.anim.is_playing(), "breaker previews never autoplay")
			var chisel := a.model.find_child("MetalChisel",true,false) as Node3D
			check(chisel != null and chisel.position.is_equal_approx(Vector3(-0.039801061,1.105000019,0.267682195)), "neutral chisel rest")
			check(a.model.find_child("BreakerBody",true,false) != null, "breaker body retained")
		a.queue_free()
		await process_frame
	for kind in [Monster.Kind.MOSS,Monster.Kind.BUG]:
		var v := MonsterVisual.new()
		root.add_child(v)
		var m := Monster.new()
		m.kind = kind
		m.stage = Monster.MOSS if kind == Monster.Kind.MOSS else Monster.PUPA
		v.setup(m,false)
		var key := "evolution" if kind == Monster.Kind.MOSS else "bug_evolution"
		v.play_evolution(key)
		check(v._evo_time == (7.0 if kind == Monster.Kind.MOSS else 3.5), "evolution duration " + key)
		if kind == Monster.Kind.MOSS:
			check(v._evo_mat != null and v._evo_mat.get_shader_parameter("color_tex") != null, "autumn shader texture retained")
		m.stage = Monster.BUD if kind == Monster.Kind.MOSS else Monster.ADULT
		v._update_evolution(v._evo_time-0.01)
		check(v._evolving, "evolution remains before endpoint " + key)
		v._update_evolution(0.02)
		check(not v._evolving and is_equal_approx(v.actor.scale.x, MonsterCatalog.scale_of(m.model_key())), "evolution final actor " + key)
		v.queue_free()
		await process_frame
	var Cursor = load("res://scripts/player/dig_cursor.gd")
	var cursor = Cursor.new()
	root.add_child(cursor)
	cursor.set_process(false)
	check(cursor._chisel != null, "runtime cursor finds chisel")
	cursor.swing()
	var tw := get_processed_tweens()[-1] as Tween
	tw.pause()
	for hit in 3:
		tw.custom_step(0.035)
		check(absf(cursor._chisel.position.y - (cursor._chisel_y - (0.3 if hit == 0 else 0.24))) < 0.001, "runtime chisel extension %d" % hit)
		tw.custom_step(0.07)
		check(absf(cursor._chisel.position.y-cursor._chisel_y) < 0.001, "runtime chisel return %d" % hit)
	tw.custom_step(0.0001)
	check(not cursor._swinging, "three blows finish in 0.315 seconds")
	cursor.queue_free()
	await process_frame
	# Destruction during evolution must dispose of the effect with the visual.
	var dying := MonsterVisual.new()
	root.add_child(dying)
	var dm := Monster.new()
	dm.kind = Monster.Kind.BUG
	dm.stage = Monster.PUPA
	dying.setup(dm,false)
	dying.play_evolution("bug_evolution")
	dm.alive = false
	dying.die("attack")
	check(dying._dying, "evolution death enters disposal")
	await create_timer(1.8).timeout
	check(not is_instance_valid(dying), "dead evolution effect freed")
	await create_timer(0.3).timeout
	print("FINAL RUNTIME PASS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
