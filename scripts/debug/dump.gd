extends Node
## Debug helper added by main.gd with `--dump`.
##   --dump                 print every ModelActor with its viewport (world-leak check)
##   --dump --focus_bug=S   keep the camera on the first ザクザクムシ of stage S (0 larva, 1 pupa, 2 adult)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			_probe.call_deferred(a.get_slice("=", 1))
	await get_tree().create_timer(0.5).timeout
	for n in get_tree().root.find_children("*", "ModelActor", true, false):
		var a := n as ModelActor
		print("actor under %s  vis=%s  gpos=%s  vp=%s own_world=%s" % [a.get_parent().name, a.is_visible_in_tree(), a.global_position, a.get_viewport().name, a.get_viewport().own_world_3d])


func _process(_delta: float) -> void:
	var main := get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--focus_bug="):
			var stage := int(a.get_slice("=", 1))
			for m in main.eco.monsters:
				if m.kind == Monster.Kind.BUG and m.stage == stage and m.visual:
					main.cam.focus_on(m.visual.global_position, true)
					return


## --showcase: larva / pupa side by side in the starter corridor, plus a larva that dies (Death clip).
var _victim: Monster
var _t := 0.0


func _physics_process(delta: float) -> void:
	if "--showcase_plants" in OS.get_cmdline_user_args():
		_process_plants(delta)
		_process_plants_log()
		return
	if not ("--showcase" in OS.get_cmdline_user_args()):
		return
	var main := get_parent()
	var e: Ecosystem = main.eco
	var y := 5
	var x0: int = main.grid.entrance.x - 3
	_t += delta
	if _victim == null and _t > 0.3:
		var larva := e.spawn(Monster.Kind.BUG, Monster.LARVA, Vector2i(x0, y), 10, "load")
		larva.busy = 999.0
		var pupa := e.spawn(Monster.Kind.BUG, Monster.PUPA, Vector2i(x0 + 2, y), 10, "birth")
		pupa.busy = 999.0
		_victim = e.spawn(Monster.Kind.BUG, Monster.LARVA, Vector2i(x0 + 4, y), 10, "load")
		_victim.busy = 999.0
		main.cam.focus_on(DungeonGrid.cell_center(Vector2i(x0 + 2, y)), true)
		main.cam.zoom = 0.32
	elif _victim and _victim.alive and _t > 1.5:
		e.kill(_victim, "killed")


## --showcase_plants: grass dies, a tree stabs forward with its root, another tree withers.
var _plants := []
var _pt := 0.0


func _process_plants(delta: float) -> void:
	var main := get_parent()
	var e: Ecosystem = main.eco
	var y := 5
	var x0: int = main.grid.entrance.x - 3
	_pt += delta
	if _plants.is_empty() and _pt > 0.3:
		var grass := e.spawn(Monster.Kind.MOSS, Monster.MOSS, Vector2i(x0, y), 2, "load")
		var tree := e.spawn(Monster.Kind.MOSS, Monster.FLOWER, Vector2i(x0 + 2, y), 4, "load")
		var tree2 := e.spawn(Monster.Kind.MOSS, Monster.FLOWER, Vector2i(x0 + 4, y), 4, "load")
		for m in [grass, tree, tree2]:
			m.busy = 999.0
			m.dir = Vector2i(0, 1)
		tree.dir = Vector2i(-1, 0)
		main.cam.set_angle(0.0, deg_to_rad(78.0))
		_plants = [grass, tree, tree2]
		main.cam.focus_on(DungeonGrid.cell_center(Vector2i(x0 + 2, y)), true)
		main.cam.zoom = 0.34
	elif _plants.size() == 3 and _pt > 1.2 and _plants[0].alive:
		e.kill(_plants[0], "killed")
		e.kill(_plants[2], "killed")
		_plants[1].anim_request = "attack"
		_plants[1].busy = 1.0


func _process_plants_log() -> void:
	if _plants.size() == 3 and _plants[1].visual:
		var a: ModelActor = _plants[1].visual.actor
		if a and a.anim and a.anim.current_animation == "attack" and a.anim.current_animation_position > 0.68 and not has_meta("shot"):
			set_meta("shot", true)
			var img := get_viewport().get_texture().get_image()
			img.save_png("debug_shots/tree_strike.png")
		if a and a.anim and Engine.get_process_frames() % 6 == 0:
			print("TREE t=%.2f cur=%s playing=%s pos=%.2f speed=%.2f" % [_pt, a.current, a.anim.current_animation, a.anim.current_animation_position if a.anim.is_playing() else -1.0, a.anim.speed_scale])


## --probe=evo|adult|fx : isolates a feature to check for renderer errors.
func _probe(kind: String) -> void:
	var main := get_parent()
	var e: Ecosystem = main.eco
	var c := Vector2i(main.grid.entrance.x - 3, 5)
	match kind:
		"evo":
			var m := e.spawn(Monster.Kind.MOSS, Monster.MOSS, c, 3, "load")
			e._evolve(m, Monster.BUD)
		"evoactor":
			var a := MonsterCatalog.make_actor("evolution")
			main.add_child(a)
			a.position = DungeonGrid.cell_center(c)
		"evoraw":
			var r: Node3D = MonsterCatalog.scene("evolution").instantiate()
			main.add_child(r)
		"stages":
			# five blocks, one per soil stage, in a row just below the starter corridor
			var y := 2
			var x0: int = main.grid.entrance.x + 2
			for i in 5:
				var cc := Vector2i(x0 + i * 2, y)
				main.grid.set_nutrient(cc, [0, 3, 7, 11, 14][i])
				for dd in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
					if main.grid.is_block(cc + dd):
						main.grid.dig(cc + dd)
			main.cam.focus_on(DungeonGrid.cell_center(Vector2i(x0 + 4, y)) + Vector3(0, 0, 0.8), true)
			main.cam.zoom = 0.36
		"adult":
			e.spawn(Monster.Kind.BUG, Monster.ADULT, c, 3, "load")
		"fx":
			main.fx.ring(DungeonGrid.cell_center(c), Color.YELLOW)
			main.fx.sparkle(DungeonGrid.cell_center(c), Color.YELLOW)
			main.fx.motes(DungeonGrid.cell_center(c), DungeonGrid.cell_center(c + Vector2i(1, 0)))
			main.fx.dust(DungeonGrid.cell_center(c), Color.WHITE)
			main.fx.debris(c, 0.5)
