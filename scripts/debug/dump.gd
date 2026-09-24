extends Node
## Debug helper added by main.gd with `--dump`.
##   --dump                 print every ModelActor with its viewport (world-leak check)
##   --dump --focus_bug=S   keep the camera on the first ザクザクムシ of stage S (0 larva, 1 pupa, 2 adult)

func _ready() -> void:
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
