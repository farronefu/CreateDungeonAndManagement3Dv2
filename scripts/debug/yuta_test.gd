extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("YUTA: " + label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var hero = game.hero
	var a: ModelActor = hero.actor
	var p: HeroProfile = hero.profile
	check(p.model_height == 1.05 and p.model_yaw_offset_deg == 0.0,"profile height/yaw unchanged")
	check(p.attack_hit_time == 0.7 and p.attack_anim_speed == 1.4,"attack profile unchanged")
	check(absf(p.attack_hit_time/p.attack_anim_speed-0.5)<0.00001,"hit at half second")
	check(absf(a.model.scale.x-0.231481469)<0.00001,"single normalization scale")
	check(absf(a.model.position.y-0.009375)<0.00001,"single ground offset")
	check(a.model.rotation == Vector3.ZERO,"no model yaw correction")
	var box := a.model.transform * a.local_aabb()
	check(absf(box.size.y-1.05)<0.0001 and absf(box.position.y)<0.0001,"grounded 1.05 tile bounds")
	check(a._meshes.size()==3,"three voxel meshes")
	var sk := a.model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	check(sk.get_bone_count()==23,"23 original joints")
	for mesh in a._meshes:
		if mesh is MeshInstance3D:
			for surface in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(surface) as BaseMaterial3D
				check(mat.vertex_color_use_as_albedo,"imported vertex palette visible")
				check(mat.albedo_color == Color.WHITE and mat.albedo_texture == null,"authored palette not tinted/replaced")
				check(absf(mat.metallic-0.12)<0.0001 and absf(mat.roughness-0.64)<0.0001,"authored material unaffected by legacy plasticize")
	var lengths := {"idle":3.0416666667,"walk":1.1333333333,"attack":1.5333333333,"death":3.9333333333,"joy":3.2333333333,"look_around":3.7}
	check(a.anim.get_animation_list().size()==6,"exactly six clips")
	a.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in lengths:
		check(a.has_anim(clip),"clip exists " + clip)
		check(absf(a.anim_length(clip)-lengths[clip])<0.0001,"untrimmed length " + clip)
		check(a.anim.get_animation(clip).loop_mode==(Animation.LOOP_LINEAR if clip in ["idle","walk"] else Animation.LOOP_NONE),"loop " + clip)
		a.anim.play(clip,0.0)
		a.anim.seek(lengths[clip]*0.5,true)
		check(a.anim.current_animation==clip,"clip plays " + clip)
	a._one_shot_until = 0.0
	hero.move_t = 0.0
	hero.move_dur = p.move_time
	hero._visual(0.1)
	check(a.current==p.anim_walk and is_equal_approx(a.anim.speed_scale,1.0),"normal walk speed")
	hero.move_dur = p.carry_move_time
	hero._visual(0.1)
	check(is_equal_approx(a.anim.speed_scale,0.6875),"carry walk speed")
	hero.move_t = 1.0
	hero._visual(0.1)
	check(a.current==p.anim_idle and is_equal_approx(a.anim.speed_scale,1.0),"idle speed")
	a.play_once(p.anim_look,p.look_anim_speed)
	check(a.current==p.anim_look and is_equal_approx(a.anim.speed_scale,1.4),"look-around speed")
	a._one_shot_until = 0.0
	hero.state = hero.State.ACTIVE
	hero.hp = hero.max_hp-35
	var mp_before: float = hero.mp
	hero._heal()
	check(a.current==p.anim_idle and hero.hp==hero.max_hp and hero.mp==mp_before-p.heal_cost,"heal retains idle and stats")
	hero._celebrate_then_grab()
	check(a.current==p.anim_joy and is_equal_approx(a.anim.speed_scale,1.2),"joy speed")
	check(absf(hero._grab_timer-lengths["joy"]/1.2)<0.0001,"capture waits for joy")
	hero._grab_timer = -1.0
	a._one_shot_until = 0.0
	var target := Monster.new()
	target.cell = hero.cell+Vector2i(0,1)
	target.alive = true
	hero._attack(target)
	check(a.current==p.anim_attack and is_equal_approx(a.anim.speed_scale,1.4),"attack speed")
	check(is_equal_approx(hero._hit_timer,0.5),"controller hit timer")
	hero._pending_hit = null
	hero.take_damage(2,target)
	check(a._flash_t>0.0 and hero.hp < hero.max_hp,"hurt retains flash and damage")
	hero._die()
	check(a.current==p.anim_death and is_equal_approx(a.anim.speed_scale,1.0),"death speed")
	var sfx := root.get_node("Sfx")
	if sfx._bgm_tween:
		sfx._bgm_tween.kill()
	sfx._bgm.stop()
	sfx._bgm.stream = null
	for player in sfx._players:
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	game.queue_free()
	target = null
	hero = null
	await process_frame
	await process_frame
	print("YUTA PASS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
