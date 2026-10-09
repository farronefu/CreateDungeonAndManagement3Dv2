extends Game
## The game scene's script: scripts/game.gd (the game itself) plus everything that only exists for
## development: the command-line switches (--autostart, --stage=N, --autoplay, ...), the autoplayer,
## the performance log and the automated tests that tools/run_tests.sh runs.


# ------------------------------------------------------------------ debug / automated capture
func _debug_bootstrap() -> void:
	screens.hide_all()
	hud.set_visible_all(true)
	phase = Phase.BUILD
	for i in heroes.size():
		heroes[i].begin_descent(1.6 * i)
	cursor.mode = DigCursor.Mode.DIG
	if _debug.has("speed"):
		_set_speed(float(_debug["speed"]))
	var digs := int(_debug.get("digs", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in digs:
		var cands: Array[Vector2i] = []
		for y in grid.h:
			for x in grid.w:
				if grid.can_dig(Vector2i(x, y)):
					cands.append(Vector2i(x, y))
		if cands.is_empty():
			break
		# grow corridors downward / sideways like a player would
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return grid.get_nutrient(a) * 0.3 + a.y * 0.2 > grid.get_nutrient(b) * 0.3 + b.y * 0.2)
		var pick := cands[rng.randi() % mini(10, cands.size())]
		var n := grid.dig(pick)
		dig_left -= 1
		eco.spawn_from_dig(pick, n)
	var sim := float(_debug.get("simulate", 0))
	var t := 0.0
	while t < sim:
		eco.tick(0.1)
		t += 0.1
	build_left = maxf(5.0, build_left - sim)
	if _debug.has("invade"):
		var dist := grid.distance_map(grid.entrance)
		var best := grid.entrance
		for y in grid.h:
			for x in grid.w:
				var c := Vector2i(x, y)
				if dist[grid.idx(c)] > dist[grid.idx(best)]:
					best = c
		maou.place(best)
		_begin_invasion()
		var ht := float(_debug.get("hero_time", 0))
		var tt := 0.0
		while tt < ht and phase == Phase.INVASION:
			eco.tick(0.05)
			_tick_heroes(0.05)
			invasion_time += 0.05
			tt += 0.05
		if _debug.has("report"):
			print("hero hp %d/%d  mp %d  cell %s carrying %s  time %.1f  monsters %d  phase %d" % [hero.hp, hero.max_hp, hero.mp, hero.cell, hero.carrying, invasion_time, eco.monsters.size(), phase])
	# --cam_maou: look at the placed 魔王 (screenshots); --carry: the hero grabs him first
	if _debug.has("carry") and maou.placed:
		hero.cell = maou.cell
		hero.from_cell = maou.cell
		hero.position = maou.position
		hero._pick_up()
	if _debug.has("cam_maou") and maou.placed:
		cam.edge_scroll = false
		cam.set_bounds(Rect2(-60, -40, 160, 80))
		cam.zoom = 0.45
		cam.focus_on(maou.position + Vector3(0, 0, 0.6), true)
	if _debug.has("cam"):
		var p: PackedStringArray = str(_debug["cam"]).split(",")
		cam.edge_scroll = false   # a fixed debug view must not drift with the real cursor
		cam.set_bounds(Rect2(-60, -40, 160, 80))   # debug shots may look anywhere
		cam.focus_on(Vector3(float(p[0]), 0, float(p[1])), true)
		if p.size() > 2:
			cam.zoom = float(p[2])
	if _debug.has("place"):
		_begin_place()
	if _debug.has("result"):
		_show_result()
	if _debug.has("title"):
		screens.show_title()
	if _debug.has("angle"):
		add_child(load("res://scripts/debug/angle.gd").new())
	if _debug.has("dump"):
		add_child(load("res://scripts/debug/dump.gd").new())


var _perf_last := 0
## per-frame script timings (ms, summed; reported by --perf)
var _perf_cpu := 0.0
var _perf_gpu := 0.0
var _perf_proc := 0.0
var _perf_spikes: Array[String] = []
var _perf_ev := {}
var _perf_dts: Array[float] = []
var _perf_prims := 0.0
var _perf_draws := 0.0


## --perf: frame-time report over a busy stretch (run with --autostart --digs=45 --simulate=80
## --invade --speed=3 --perf). Prints average fps, the slowest frames and the draw load.
func _perf_tick() -> void:
	var now := Time.get_ticks_usec()
	if _frames > 60 and _perf_last > 0:
		_perf_dts.append((now - _perf_last) / 1000.0)
		if (now - _perf_last) / 1000.0 > 35.0:
			_perf_spikes.append("%.0fms spawn%d die%d evo%d decor%d" % [(now - _perf_last) / 1000.0, _perf_ev.get("spawn", 0), _perf_ev.get("die", 0), _perf_ev.get("evo", 0), view._dirty.size()])
		_perf_ev.clear()
		_perf_prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_perf_draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var rid := get_viewport().get_viewport_rid()
		_perf_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		_perf_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_perf_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	elif _frames == 1:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		eco.spawned.connect(func(_m, _c) -> void: _perf_ev["spawn"] = int(_perf_ev.get("spawn", 0)) + 1)
		eco.died.connect(func(_m, _c) -> void: _perf_ev["die"] = int(_perf_ev.get("die", 0)) + 1)
		eco.evolved.connect(func(_m) -> void: _perf_ev["evo"] = int(_perf_ev.get("evo", 0)) + 1)
		_prof.clear()
	if _frames == 60:
		# experiments: switch parts off to see what they cost
		if _debug.has("perf_nosync"):
			layer.process_mode = Node.PROCESS_MODE_DISABLED
		if _debug.has("perf_noanim"):
			for ap in layer.find_children("*", "AnimationPlayer", true, false):
				(ap as AnimationPlayer).active = false
		if _debug.has("perf_hide"):
			layer.visible = false
		if _debug.has("perf_nosurface"):
			view.surface.visible = false
	_perf_last = now
	if _perf_dts.size() >= int(_debug.get("perf_frames", 900)):
		var n := _perf_dts.size()
		var total := 0.0
		for d in _perf_dts:
			total += d
		var sorted := _perf_dts.duplicate()
		sorted.sort()
		var hitches := 0
		for d in _perf_dts:
			if d > 50.0:
				hitches += 1
		var t0 := Time.get_ticks_usec()
		view._rebuild_decor()
		var decor_ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("PERF avg_fps %.1f  avg_ms %.1f  p99_ms %.1f  max_ms %.1f  hitches>50ms %d  prims %dk  draws %d  decor_rebuild_ms %.1f  monsters %d" % [
			n * 1000.0 / total, total / n, sorted[int(n * 0.99)], sorted[n - 1], hitches, int(_perf_prims / n / 1000.0), int(_perf_draws / n), decor_ms, eco.monsters.size()])
		var parts := []
		for k in _prof:
			parts.append("%s %.2f" % [k, float(_prof[k]) / n])
		var on := 0
		for v in layer.find_children("*", "AnimationPlayer", true, false):
			if (v as AnimationPlayer).active:
				on += 1
		print("PERF animating %d of %d animation players" % [on, layer.find_children("*", "AnimationPlayer", true, false).size()])
		print("PERF spikes: ", _perf_spikes)
		print("PERF ms/frame: process(all scripts) %.2f  render_cpu %.2f  render_gpu %.2f  | %s" % [_perf_proc / n, _perf_cpu / n, _perf_gpu / n, "  ".join(parts)])
		get_tree().quit()


## (run with --autostart --cowertest) the 魔王 already stands near the entrance; when the hero comes
## within MAOU_SCARED_ENTER cells he crouches (cower_in) and trembles (cower loop), and once it is
## MAOU_SCARED_LEAVE cells away he gets back up (cower_out) and stands (idle) again.
var _cw := {}
func _cowertest() -> void:
	var f := _frames
	if f == 10:
		_cw["start_cell"] = maou.cell
		_cw["start_steps"] = grid.distance_map(grid.entrance)[grid.idx(maou.cell)]
		_cw["placed_at_start"] = maou.placed and maou.visible
		cam.edge_scroll = false
		cam.zoom = 0.45
		cam.focus_on(maou.position + Vector3(0, 0, 0.6), true)
	elif f == 20:
		hero.state = Hero.State.ACTIVE
		phase = Phase.RESULT   # nothing ticks the hero or the ecosystem: the test drives the mood itself
		hero.visible = true
	elif f > 20 and f < 150:
		hero.cell = maou.cell + Vector2i(0, 2) if f < 90 else maou.cell + Vector2i(0, 12)
		hero.from_cell = hero.cell
		hero.position = DungeonGrid.cell_center(hero.cell)
		_update_maou_mood()
		if f == 60:
			_cw["mood_near"] = maou.mood
			_cw["clip_near"] = maou.actor.current
			_screenshot("debug_shots/cowertest_down.png")
		elif f == 140:
			_cw["mood_far"] = maou.mood
			_cw["clip_far"] = maou.actor.current
	elif f == 150:
		var ok: bool = _cw["placed_at_start"] and _cw["start_steps"] >= 1 and _cw["start_steps"] <= 4
		ok = ok and _cw["mood_near"] == "scared" and _cw["clip_near"] == "cower"
		ok = ok and _cw["mood_far"] == "idle" and _cw["clip_far"] in ["idle", "look_around"]
		print("COWERTEST ", "PASS " if ok else "FAIL ", _cw)
		get_tree().quit()


## --trailer: real play recorded for a clip (use with --write-movie): the camera follows the
## hero at the middle zoom from above, no cursor / popups / hints; logs the hero's swings so
## the busiest stretch can be cut out.
func _trailer_tick() -> void:
	if _frames == 1:
		# the recording is 16:9: keep the UI canvas 16:9 too (a wider screen would push the HUD past the edges)
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if _frames == 2:
		cursor.mode = DigCursor.Mode.NONE
		cam.edge_scroll = false
		cam.zoom = GameCamera.ZOOM_STEPS[1]
		cam.set_angle(0.0, deg_to_rad(62.0))
		follow_hero = true
		for t in hud._toasts.get_children():
			t.queue_free()
		# --trailer_bugs: put some pill bugs and scythe bugs near the hero's way in, so the clip
		# shows every kind of monster (from then on they act on their own)
		if _debug.has("trailer_bugs"):
			var dist := grid.distance_map(grid.entrance)
			var spots: Array[Vector2i] = []
			for i in dist.size():
				if dist[i] >= 3 and dist[i] <= 9:
					spots.append(Vector2i(i % grid.w, i / grid.w))
			var r := RandomNumberGenerator.new()
			r.seed = int(_debug.get("seed", 1))
			var kinds := [Monster.LARVA, Monster.LARVA, Monster.LARVA, Monster.ADULT, Monster.ADULT, Monster.PUPA]
			for st in kinds.slice(0, int(_debug["trailer_bugs"])):
				if spots.is_empty():
					break
				var c: Vector2i = spots.pop_at(r.randi() % spots.size())
				var m := eco.spawn(Monster.Kind.BUG, st, c, 6, "load")
				m.hp = m.max_hp
	if phase == Phase.INVASION and hero.is_targetable():
		cam.focus_on(hero.position + Vector3(0, 0, 0.6))
	if _frames % 10 == 0:
		var near := 0
		var bugs := 0
		for m in eco.monsters:
			if m.alive and absi(m.cell.x - hero.cell.x) + absi(m.cell.y - hero.cell.y) <= 4:
				near += 1
				if m.kind == Monster.Kind.BUG:
					bugs += 1
		print("TRAILER f=%d attacks=%d near=%d bugs=%d hp=%d" % [_frames, hero.attacks, near, bugs, int(hero.hp)])


func _debug_tick() -> void:
	if _debug.has("perf"):
		_perf_tick()
	if _debug.has("trailer"):
		_trailer_tick()
	if _debug.has("mouse_hero") and hero.visible:
		get_viewport().warp_mouse(cam.unproject_position(hero.global_position + Vector3(0, 0.45, 0)))
	if _debug.has("menutest"):
		_menutest()
	if _debug.has("padtest"):
		_padtest()
	if _debug.has("cowertest"):
		_cowertest()
	if _debug.has("dragtest") and _frames == 20:
		_dragtest()
	if _debug.has("herotest") and _frames == 20:
		_herotest()
	# --askhero: open the "call the hero?" question (for screenshots)
	if _debug.has("askhero") and _frames == 10:
		_on_call_hero()
	if _debug.has("poketest") and _frames == 20:
		_poketest()
	if _debug.has("birthtest") and _frames == 20:
		_birthtest()
	if _debug.has("scorpionshot"):
		_scorpionshot()
	if _debug.has("scorpiondemo"):
		_scorpiondemo()
	# --tiptest: every monster that can still evolve shows what it needs; BGM files are used
	# --dietest: monsters that die play their death clip to the end (not frozen on the first frame)
	if _debug.has("dietest"):
		_dietest()
	if (_debug.has("capturetest") or _debug.has("capturedemo")) and _frames == 20:
		_capturetest()
	if _debug.has("tiptest") and _frames == 20:
		Sfx.play_bgm("captured")
	if _debug.has("tiptest") and _frames == 80:
		var path: String = Sfx._bgm.stream.resource_path if Sfx._bgm.stream else ""
		var ok_bgm := (path.ends_with("captured.wav") or path.ends_with("captured.ogg")) and Sfx._bgm.playing
		var bad := 0
		var shown := {}
		for m in eco.monsters:
			var final_form := (m.kind == Monster.Kind.MOSS and m.stage == Monster.FLOWER) or (m.kind == Monster.Kind.BUG and m.stage == Monster.ADULT)
			if _monster_tip(m).contains("進化まで") == final_form:
				bad += 1
			shown[m.display_name()] = _evolution_need(m)
		print("TIPTEST ", "PASS " if bad == 0 and ok_bgm and eco.monsters.size() > 0 else "FAIL ", {"monsters": eco.monsters.size(), "wrong_popups": bad, "bgm": path, "examples": shown})
		get_tree().quit()
	# --retrytest: "retry" from the pause menu must reload the stage at the arrival cut-in
	if _debug.has("retrytest") and _frames == 30:
		if not GameState.has_meta("retried"):
			GameState.set_meta("retried", true)
			_on_retry()
		else:
			print("RETRYTEST ", "PASS " if phase == Phase.INTRO else "FAIL ", {"phase_after_retry": phase})
			get_tree().quit()
	if _debug.has("camtest"):
		_camtest()
	if _debug.has("mouse_monster") and not eco.monsters.is_empty():
		var mv: Node3D = eco.monsters[int(_debug["mouse_monster"]) % eco.monsters.size()].visual
		if mv:
			get_viewport().warp_mouse(cam.unproject_position(mv.global_position + Vector3(0, 0.25, 0)))
	if _debug.has("mouse"):
		var mp: PackedStringArray = str(_debug["mouse"]).split(",")
		get_viewport().warp_mouse(Vector2(float(mp[0]), float(mp[1])))
	if _debug.has("autoplay"):
		_autoplay()
	if _debug.has("fps") and _frames % 60 == 0:
		print("frame %d  fps %d  monsters %d  draw_calls %d  prims %d" % [_frames, Engine.get_frames_per_second(), eco.monsters.size(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	# --strike: fire the dig cursor's hammer blow so the shot catches the chisel extended
	if _debug.has("strike") and _frames == int(_debug.get("frames", 90)) - 2:
		cursor.swing()
	if _debug.has("shot") and _frames == int(_debug.get("frames", 90)):
		_screenshot(str(_debug["shot"]))
		get_tree().quit()
	elif _debug.has("quit_after") and _frames >= int(_debug["quit_after"]):
		get_tree().quit()


var _auto_digs := 0
var _mt := {}


## Title: A starts the game. Pause: Y / RB are ignored, A on 再開する resumes.
func _menutest() -> void:
	var f := _frames
	if f == 30:
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_A, false)
	elif f == 40:
		_mt["phase_after_A_on_title"] = phase
		letterbox.skipped = true   # skip the opening scene
	elif f == 60:
		_mt["phase_before_pause"] = phase
		_pad_event(JOY_BUTTON_START, true)
		_pad_event(JOY_BUTTON_START, false)
	elif f == 65:
		_mt["paused_speed"] = speed
		_pad_event(JOY_BUTTON_Y, true)
		_pad_event(JOY_BUTTON_Y, false)
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, true)
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, false)
	elif f == 70:
		_mt["phase_after_Y_while_paused"] = phase
		_mt["speed_after_RB_while_paused"] = speed
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_A, false)
	elif f == 76:
		_mt["speed_after_A_on_resume"] = speed
		# pause again and move down to the new "retry" button (not pressed: it reloads the scene)
		_pad_event(JOY_BUTTON_START, true)
		_pad_event(JOY_BUTTON_START, false)
	elif f == 82:
		_pad_event(JOY_BUTTON_DPAD_DOWN, true)
		_pad_event(JOY_BUTTON_DPAD_DOWN, false)
	elif f == 86:
		var fo := get_viewport().gui_get_focus_owner()
		_mt["focus_after_down"] = (fo as Button).text if fo is Button else ""
		_pad_event(JOY_BUTTON_B, true)
		_pad_event(JOY_BUTTON_B, false)
	elif f == 90:
		_mt["speed_after_B"] = speed
		var ok: bool = _mt.get("phase_after_A_on_title") == Phase.INTRO and _mt.get("paused_speed") == 0.0 \
			and _mt.get("phase_after_Y_while_paused") == Phase.BUILD and _mt.get("speed_after_RB_while_paused") == 0.0 \
			and _mt.get("speed_after_A_on_resume") == 1.0 and _mt["focus_after_down"] == "このステージをやり直す" and _mt.get("speed_after_B") == 1.0
		print("MENUTEST ", "PASS " if ok else "FAIL ", _mt)
		get_tree().quit()
var _pt := {}


func _pad_event(button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _pad_axis(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)


## Hero rules (run with --autostart --digs=45 --simulate=40 --herotest): once the invasion has
## started, tunnels dug afterwards are never entered, and the hero looks around at most once per
## cell, only at forks of one-block-wide corridors.
func _herotest() -> void:
	maou.place(_farthest_floor())
	_begin_invasion()
	# dig a fresh tunnel off the known dungeon: 12 cells, following whatever can be dug
	var fresh: Array[Vector2i] = []
	for i in 12:
		var pick := Vector2i(-1, -1)
		for y in grid.h:
			for x in grid.w:
				var c := Vector2i(x, y)
				if pick.x < 0 and grid.can_dig(c) and (fresh.is_empty() or grid.floor_neighbors(c).has(fresh[-1])):
					pick = c
		if pick.x < 0:
			break
		grid.dig(pick)
		fresh.append(pick)
	var entered := 0
	var bad_looks := 0
	var t := 0.0
	while t < 200.0 and phase == Phase.INVASION and hero.state != Hero.State.DEAD:
		eco.tick(0.05)
		_tick_heroes(0.05)
		t += 0.05
		if hero.known[grid.idx(hero.cell)] == 0:
			entered += 1
	for c in hero._looked:
		if not hero._is_corridor_fork(c):
			bad_looks += 1
	var planted := torches.size()
	# sight: standing in the starter room (4x5) the hero takes in nearly all of it at once
	var room_c := Vector2i(grid.entrance.x - 6, 5)
	hero.visited.fill(0)
	hero.cell = room_c
	hero._mark_visited()
	var room_seen := 0
	for y in range(3, 8):
		for x in range(grid.entrance.x - 8, grid.entrance.x - 4):
			room_seen += hero.visited[grid.idx(Vector2i(x, y))]
	# a torch heals a tenth of HP / MP when stepped on
	var tc := Vector2i(grid.entrance.x, 3)
	_place_torch(tc)
	hero.hp = hero.max_hp * 0.5
	hero.cell = tc
	hero._on_torch = Vector2i(-999, -999)
	hero._torch_step()
	var healed := hero.hp - hero.max_hp * 0.5
	# the breaker knocks it over for free
	speed = 1.0
	var dig0 := dig_left
	_try_dig(tc)
	var broken := not torches.has(tc) and dig_left == dig0
	var ok := fresh.size() > 0 and entered == 0 and bad_looks == 0 and room_seen >= 18 \
		and absf(healed - hero.max_hp * Balance.TORCH_HEAL) < 0.01 and broken
	print("HEROTEST ", "PASS " if ok else "FAIL ", {"fresh_cells": fresh.size(), "ticks_on_fresh_cells": entered, "forks_looked": hero._looked.size(), "non_fork_looks": bad_looks, "time": snappedf(t, 0.1), "torches_planted": planted, "room_cells_seen_at_once": room_seen, "torch_heal": healed, "torch_broken_free": broken})
	get_tree().quit()


var _dt := {}


func _dietest() -> void:
	if _frames == 10:
		var cells := [Vector2i(grid.entrance.x, 2), Vector2i(grid.entrance.x, 3), Vector2i(grid.entrance.x, 4), Vector2i(grid.entrance.x + 1, 5)]
		_dt["mons"] = [
			eco.spawn(Monster.Kind.BUG, Monster.LARVA, cells[0], 0, "load"),
			eco.spawn(Monster.Kind.BUG, Monster.PUPA, cells[1], 0, "load"),
			eco.spawn(Monster.Kind.BUG, Monster.ADULT, cells[2], 0, "load"),
			eco.spawn(Monster.Kind.MOSS, Monster.MOSS, cells[3], 0, "load")]
	elif _frames == 30:
		_dt["vis"] = []
		for m in _dt["mons"]:
			_dt["vis"].append(m.visual)
			eco.kill(m, "killed")
	elif _frames == 50 and _debug.has("shot"):
		return   # --shot takes the picture instead
	elif _frames == 50:
		var res := {}
		var ok := true
		for v in _dt["vis"]:
			var mv := v as MonsterVisual
			if not is_instance_valid(mv):
				continue
			var a := mv.actor
			if a == null or not a.has_anim("die"):
				continue
			var pos := a.anim.current_animation_position
			res[mv.m.display_name()] = "%s %.2f" % [a.anim.current_animation, pos]
			ok = ok and a.anim.current_animation == a._clip("die") and pos > 0.15
		print("DIETEST ", "PASS " if ok and res.size() >= 3 else "FAIL ", res)
		get_tree().quit()


## (run with --autostart --seed=3 --capturetest) with the 魔王 at the end of the starter corridor
## and no monsters around: the hero grabs him from the next cell, he turns into the wrapped
## model, is dragged exactly one cell behind the hero and out through the entrance.
func _capturetest() -> void:
	for m in eco.monsters.duplicate():
		eco.kill(m, "eaten")
	maou.place(Vector2i(grid.entrance.x + 3, 5))
	_begin_invasion()
	if _debug.has("capturedemo"):
		return   # same setup, but play it out in real time (screenshots)
	var escaped := {"v": false}
	hero.escaped_with_maou.connect(func() -> void: escaped["v"] = true)
	var grab_dist := -1
	var wrapped := false
	var max_dist := 0
	var t := 0.0
	while t < 150.0 and hero.state != Hero.State.DEAD:
		_tick_heroes(0.05)
		t += 0.05
		var d := absi(hero.cell.x - maou.cell.x) + absi(hero.cell.y - maou.cell.y)
		if hero.carrying:
			if grab_dist < 0:
				grab_dist = d
				wrapped = maou._wrapped.get_parent().visible and not maou.actor.visible
			max_dist = maxi(max_dist, d)
	var ok: bool = grab_dist == 1 and wrapped and max_dist <= 1 and escaped["v"]
	print("CAPTURETEST ", "PASS " if ok else "FAIL ", {"grab_distance": grab_dist, "wrapped_model": wrapped, "max_distance_while_dragged": max_dist, "escaped": escaped["v"], "time": snappedf(t, 0.1)})
	get_tree().quit()


## (run with --autostart --scorpiondemo) plays every scorpion feature once in the real scene and
## saves one capture of each to debug_shots/scorpion_demo/ (closer zoom than the default so the
## models are readable; the popups are the pad cursor's).
func _scorpiondemo() -> void:
	var e := grid.entrance
	var soil := Vector2i(e.x, 6)
	if _frames < 20:
		return
	if _frames == 20:
		speed = 1.0
		phase = Phase.BUILD
		DirAccess.make_dir_recursive_absolute("debug_shots/scorpion_demo")
		grid.set_nutrient(soil, 14)
		_dt = {"step": 0, "t": 0, "look": DungeonGrid.cell_center(Vector2i(e.x, 5))}
		eco.egg_laid.connect(func(c: Vector2i, _m: Monster) -> void: _dt["egg"] = c)
	Pad.using_pad = true
	cam.zoom = 0.62
	var s: Monster = _dt.get("s")
	if s and s.alive and s.visual:
		_dt["look"] = (s.visual as Node3D).position
	cam.focus_on(_dt["look"], true)
	_dt["t"] += 1
	var t: int = _dt["t"]
	var shot := func(name: String) -> void:
		_screenshot("debug_shots/scorpion_demo/%s.png" % name)
		_dt["step"] += 1
		_dt["t"] = 0
	match int(_dt["step"]):
		0:   # cracked soil and its popup
			cursor.pad_cell = soil
			if t == 40:
				shot.call("01_cracked_soil")
		1:   # digging it: a scorpion is born
			if t == 2:
				_try_dig(soil)
				for m in eco.monsters:
					if m.kind == Monster.Kind.SCORPION:
						_dt["s"] = m
			if t == 26:
				shot.call("02_born_from_dig")
		2:   # the scorpion's popup (it is held still so the cursor sits on it)
			cursor.pad_cell = s.cell
			if not s.is_moving():
				s.busy = 0.5
			if t >= 70 and not s.is_moving():
				shot.call("03_scorpion_popup")
		3:   # eating a pill bug
			cursor.pad_cell = Vector2i(e.x + 3, 8)
			if t == 2:
				s.hp = 70
				var spot := s.cell + Vector2i(1, 0) if grid.is_floor(s.cell + Vector2i(1, 0)) else s.cell + Vector2i(-1, 0)
				eco.spawn(Monster.Kind.BUG, Monster.LARVA, spot, 6, "load")
				eco.spawn(Monster.Kind.BUG, Monster.LARVA, Vector2i(e.x + 2, 5), 0, "load").busy = 30.0   # stands still for a size comparison
			if s.eat_target != null and not _dt.has("eat_at"):
				_dt["eat_at"] = t
			if _dt.has("eat_at") and t == int(_dt["eat_at"]) + 24:
				shot.call("04_eating")
		4:   # after three meals: stinging a wall to lay the egg
			if t == 30:
				s.meals = Balance.SCORPION_LAY_MEALS
				s.lay_cooldown = 0.0
				s.hp = s.max_hp
			if s.timer < 0.0 and not _dt.has("lay_at"):
				_dt["lay_at"] = t
			if _dt.has("lay_at") and t == int(_dt["lay_at"]) + 27:
				shot.call("05_laying_egg")
		5:   # the egg block and its popup (once the mother has stepped away)
			if _dt.has("egg"):
				var egg: Vector2i = _dt["egg"]
				cursor.pad_cell = egg
				_dt["look"] = DungeonGrid.cell_center(egg)
				_dt.erase("s")
				var far := true
				for m in eco.monsters:
					if absi(m.cell.x - egg.x) + absi(m.cell.y - egg.y) <= 1:
						far = false
				if (far and t > 40) or t > 500:
					shot.call("06_egg_block_popup")
		6:   # left alone, it hatches by itself
			if t == 2:
				grid.eggs[_dt["egg"]] = 0.2
			if t == 30:
				shot.call("07_hatched_by_itself")
		7:   # an egg block that is dug hatches too
			var wall := Vector2i(e.x - 3, 6)
			_dt["look"] = DungeonGrid.cell_center(wall)
			cursor.pad_cell = wall
			if t == 2:
				grid.set_nutrient(wall, 4)
				grid.make_egg(wall, 8, Balance.SCORPION_EGG_TIME)
			if t == 40:
				_try_dig(wall)
			if t == 62:
				shot.call("08_hatched_by_digging")
				for m in eco.monsters:   # clear the stage for the last two captures
					m.nutrient = 0
					eco.kill(m, "eaten")
		8:   # the sting (the same clip is used against the hero)
			if t == 2:
				var a := eco.spawn(Monster.Kind.SCORPION, 0, Vector2i(e.x - 1, 5), 0, "load")
				a.dir = Vector2i(1, 0)
				a.busy = 5.0
				_dt["s"] = a
			cursor.pad_cell = Vector2i(e.x + 3, 8)
			if t == 40:
				s.anim_request = "attack"
				s.busy = Balance.SCORPION_ATTACK_BUSY
			if t == 40 + 28:
				shot.call("09_sting")
		9:   # death: it crumbles into grains
			if t == 30:
				eco.kill(s, "killed")
			if t == 30 + 30:
				shot.call("10_death")
		10:  # the pause screen lists the scorpion
			if t == 20:
				for i in 2:
					eco.spawn(Monster.Kind.SCORPION, 0, Vector2i(e.x - 2 + i, 5), 0, "load")
				_set_speed(0.0)
			if t == 50:
				shot.call("11_pause_screen")
		_:
			print("SCORPIONDEMO DONE")
			get_tree().quit()


## (run with --autostart --scorpionshot) the scorpion in the real scene: its model and clips,
## the egg block's look, and the popups for the scorpion, cracked soil and the egg block.
func _scorpionshot() -> void:
	var e := grid.entrance
	if _frames == 20:
		speed = 1.0
		phase = Phase.BUILD
		var egg := Vector2i(e.x - 2, 6)
		var cracked := Vector2i(e.x, 6)
		grid.set_nutrient(cracked, 14)
		grid.set_nutrient(egg, 3)
		grid.make_egg(egg, 9, Balance.SCORPION_EGG_TIME)
		var s := eco.spawn(Monster.Kind.SCORPION, 0, Vector2i(e.x - 1, 5), 12, "dig")
		s.dir = Vector2i(0, 1)
		_dt["scorpion"] = s
		_dt["dying"] = eco.spawn(Monster.Kind.SCORPION, 0, Vector2i(e.x + 2, 5), 0, "load")
		_dt["egg"] = egg
		_dt["cracked"] = cracked
	if _frames >= 20:
		cam.focus_on(DungeonGrid.cell_center(Vector2i(e.x, 5)), true)   # the dig cursor would pull the view away
	if _frames == 70:
		eco.kill(_dt["dying"], "killed")
	if _frames == 88:
		var s: Monster = _dt["scorpion"]
		var v := layer.visual_of(s)
		var clips_ok := v != null and v.actor != null
		for clip in ["idle", "move", "attack", "eat", "lay_egg", "die"]:
			clips_ok = clips_ok and v.actor.has_anim(clip)
		var tip_egg := _cell_tip(_dt["egg"])
		var tip_soil := _cell_tip(_dt["cracked"])
		var tip_mon := _monster_tip(s)
		var slot: Array = view._slot[_dt["egg"]]
		var kind: float = slot[0].get_instance_custom_data(slot[1]).a
		var res := {
			"clips": clips_ok,
			"egg_tip": tip_egg.contains("サソリの卵") and tip_egg.contains("秒で自然にふ化"),
			"soil_tip": tip_soil.contains("掘るとサソリが生まれる"),
			"monster_tip": tip_mon.contains("産卵まで あと%d匹" % Balance.SCORPION_LAY_MEALS),
			"egg_look": is_equal_approx(kind, 0.5),
		}
		_screenshot("debug_shots/scorpionshot.png")
		print("SCORPIONSHOT ", "PASS " if not res.values().has(false) else "FAIL ", res)
		get_tree().quit()


## (run with --autostart --digs=45 --simulate=40 --birthtest) a pupa that hatches into the scythe
## bug lays two larvae straight away; total nutrient stays the same.
func _birthtest() -> void:
	var c := Vector2i(grid.entrance.x, 3)
	var total0 := grid.total_nutrient() + eco.total_nutrient()
	var pupa := eco.spawn(Monster.Kind.BUG, Monster.PUPA, c, 20, "dig")
	pupa.timer = Balance.PUPA_TIME
	var larvae0 := eco.count(Monster.Kind.BUG, Monster.LARVA)
	var t := 0.0
	while t < 12.0:
		eco.tick(0.05)
		t += 0.05
	var born := eco.count(Monster.Kind.BUG, Monster.LARVA) - larvae0
	var total1 := grid.total_nutrient() + eco.total_nutrient() - 20   # the test pupa brought 20
	var ok := pupa.stage == Monster.ADULT and born >= Balance.ADULT_BIRTH_LARVAE and total1 == total0
	print("BIRTHTEST ", "PASS " if ok else "FAIL ", {"adult": pupa.stage == Monster.ADULT, "larvae_born": born, "adult_nutrient_left": pupa.nutrient, "nutrient_before": total0, "nutrient_after": total1})
	get_tree().quit()


## (run with --autostart --digs=45 --simulate=40 --poketest)
##  * three breaker pokes kill a monster whatever its HP, cost no dig, and its nutrient goes
##    back into the soil (total nutrient unchanged)
##  * a corridor with a one-block side stub is not a fork; once the stub is two blocks it is
func _poketest() -> void:
	speed = 1.0
	var m: Monster = null
	for x in eco.monsters:
		if x.alive and grid.is_floor(x.cell):
			m = x
			break
	var total0 := grid.total_nutrient() + eco.total_nutrient()
	var dig0 := dig_left
	m.hp = m.max_hp
	var alive_after := []
	for i in Balance.BREAKER_POKES_TO_KILL:
		_try_dig(m.cell)
		alive_after.append(m.alive)
	var total1 := grid.total_nutrient() + eco.total_nutrient()
	var poke_ok := alive_after == [true, true, false] and dig_left == dig0 and total1 == total0
	# fork rule on a small hand-made map
	var g := DungeonGrid.new(9, 9)
	g.types.fill(DungeonGrid.BLOCK)
	for x in range(1, 8):
		g.types[g.idx(Vector2i(x, 4))] = DungeonGrid.FLOOR
	g.types[g.idx(Vector2i(4, 3))] = DungeonGrid.FLOOR     # a single dug block off the corridor
	var saved_grid := hero.grid
	var saved_known := hero.known
	hero.grid = g
	hero.known = PackedByteArray()
	var stub_is_fork := hero._is_corridor_fork(Vector2i(4, 4))
	g.types[g.idx(Vector2i(4, 2))] = DungeonGrid.FLOOR     # now the branch is two blocks long
	var branch_is_fork := hero._is_corridor_fork(Vector2i(4, 4))
	hero.grid = saved_grid
	hero.known = saved_known
	var ok := poke_ok and not stub_is_fork and branch_is_fork
	print("POKETEST ", "PASS " if ok else "FAIL ", {"alive_after_each_poke": alive_after, "dig_cost": dig0 - dig_left, "nutrient_before": total0, "nutrient_after": total1, "one_block_stub_is_fork": stub_is_fork, "two_block_branch_is_fork": branch_is_fork})
	get_tree().quit()


func _farthest_floor() -> Vector2i:
	var dist := grid.distance_map(grid.entrance)
	var best := grid.entrance
	for i in dist.size():
		if dist[i] > dist[grid.idx(best)]:
			best = Vector2i(i % grid.w, i / grid.w)
	return best


## Mouse drag digging (run with --autostart --dragtest): a fast drag from the end of the starter
## corridor six cells east must dig all six (the cursor fills in the skipped cells in order),
## and dragging back over floor must not dig or cost anything.
func _dragtest() -> void:
	var start := Vector2i(grid.entrance.x + 3, 5)
	var dig0 := dig_left
	cursor._drag_cell = start
	cursor._drag_to(start + Vector2i(6, 0))
	var dug := dig0 - dig_left
	cursor._drag_to(start)
	var back := dig0 - dig_left - dug
	var ok := dug == 6 and back == 0 and grid.is_floor(start + Vector2i(6, 0))
	print("DRAGTEST ", "PASS " if ok else "FAIL ", {"dug": dug, "dug_on_way_back": back})
	get_tree().quit()


## Scripted Xbox-controller session (run with --autostart --padtest), new layout:
## RT + right stick moves the camera (up to the town), right stick alone looks around the cursor,
## R3 zoom steps, RB / LB speed up / down, LT jumps to the hero, A-hold digs a tunnel,
## Y asks before calling the hero (B = no, A = yes), A places the 魔王, Start pauses, B resumes.
func _padtest() -> void:
	var f := _frames
	# re-send the stick state every frame: a real controller plugged into the machine emits its
	# own (near-zero) axis events that would otherwise overwrite the scripted ones
	if f > 10 and f < 40:
		_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
	elif f > 40 and f < 80:
		_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, -0.6)
	if f == 10:
		_pt["focus_z0"] = cam.focus.z
	elif f == 40:
		_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_pt["focus_z_after_RT_pan_up"] = snappedf(cam.focus.z, 0.01)
		_pt["yaw0"] = cam.yaw
	elif f == 80:
		_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_pt["yaw1"] = cam.yaw
		_pt["pitch1"] = snappedf(rad_to_deg(cam.pitch), 0.1)
		var pc := DungeonGrid.cell_center(cursor.pad_cell)
		_pt["orbit_around_cursor"] = Vector2(cam._target_focus.x, cam._target_focus.z).distance_to(Vector2(pc.x, pc.z)) < 0.05
		_pad_event(JOY_BUTTON_RIGHT_STICK, true)
		_pad_event(JOY_BUTTON_RIGHT_STICK, false)
	elif f == 84:
		# R3 steps the zoom out; two more presses wrap back to the closest (default) view
		_pt["zoom_after_R3"] = cam._zoom_goal
		for i in 2:
			_pad_event(JOY_BUTTON_RIGHT_STICK, true)
			_pad_event(JOY_BUTTON_RIGHT_STICK, false)
	elif f == 88:
		_pt["zoom_after_3R3"] = cam._zoom_goal
		_pt["speed"] = speed
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, true)
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, false)
	elif f == 92:
		_pt["speed_after_RB"] = speed
		_pad_event(JOY_BUTTON_LEFT_SHOULDER, true)
		_pad_event(JOY_BUTTON_LEFT_SHOULDER, false)
	elif f == 96:
		_pt["speed_after_LB"] = speed
		_pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	elif f == 98:
		_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
		var hp := _hero_focus_point()
		_pt["LT_to_hero"] = Vector2(cam._target_focus.x, cam._target_focus.z).distance_to(Vector2(hp.x, hp.z)) < 1.0
	elif f == 100:
		# start at the east end of the starter corridor and tunnel east holding A
		cursor.pad_cell = Vector2i(grid.entrance.x + 3, 5)
		_pt["dig0"] = dig_left
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_DPAD_RIGHT, true)
	elif f == 190:
		_pad_event(JOY_BUTTON_DPAD_RIGHT, false)
		_pad_event(JOY_BUTTON_A, false)
		_pt["dig1"] = dig_left
		_pt["cursor"] = cursor.pad_cell
		_pad_event(JOY_BUTTON_Y, true)
		_pad_event(JOY_BUTTON_Y, false)
	elif f == 194:
		_pt["Y_asks"] = hud.is_confirming()
		_pad_event(JOY_BUTTON_B, true)
		_pad_event(JOY_BUTTON_B, false)
	elif f == 198:
		_pt["phase_after_B"] = phase
		_pt["asks_after_B"] = hud.is_confirming()
		_pad_event(JOY_BUTTON_Y, true)
		_pad_event(JOY_BUTTON_Y, false)
	elif f == 202:
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_A, false)
	elif f == 206:
		_pt["phase_after_Y_A"] = phase
		cursor.pad_cell = Vector2i(grid.entrance.x + 3, 8)
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_A, false)
	elif f == 211:
		_pad_event(JOY_BUTTON_START, true)
		_pad_event(JOY_BUTTON_START, false)
	elif f == 214:
		_pt["paused_speed"] = speed
		_pt["dig_before_paused_dig"] = dig_left
		_on_click(Vector2i(grid.entrance.x + 4, 5))
		_pt["dig_after_paused_dig"] = dig_left
		_pad_event(JOY_BUTTON_B, true)
		_pad_event(JOY_BUTTON_B, false)
	elif f == 220:
		_pt["speed_after_B_resume"] = speed
		_pt["maou_placed"] = maou.placed
		_pt["maou_cell"] = maou.cell
		var ok: bool = _pt["focus_z_after_RT_pan_up"] < _pt["focus_z0"] - 0.5 and absf(_pt["yaw1"] - _pt["yaw0"]) > 0.1 and _pt["orbit_around_cursor"]
		ok = ok and _pt["zoom_after_R3"] == GameCamera.ZOOM_STEPS[1] and _pt["zoom_after_3R3"] == GameCamera.ZOOM_STEPS[0]
		ok = ok and _pt["speed_after_RB"] == 2.0 and _pt["speed_after_LB"] == 1.0 and _pt["LT_to_hero"]
		ok = ok and _pt["dig1"] < _pt["dig0"] and _pt["Y_asks"] and _pt["phase_after_B"] == Phase.BUILD and not _pt["asks_after_B"]
		ok = ok and _pt["phase_after_Y_A"] == Phase.PLACE and _pt["maou_placed"]
		ok = ok and _pt["paused_speed"] == 0.0 and _pt["dig_after_paused_dig"] == _pt["dig_before_paused_dig"] and _pt["speed_after_B_resume"] == 1.0
		print("PADTEST ", "PASS " if ok else "FAIL ", _pt)
		_screenshot("debug_shots/padtest.png")
		get_tree().quit()


var _ct_prev := Vector3.ZERO
var _ct_speeds: Array[float] = []


## Holds the D-pad (no dig) and measures how smoothly the camera pans after the cursor.
func _camtest() -> void:
	var f := _frames
	if f == 15:
		_pad_event(JOY_BUTTON_LEFT_STICK, true)   # unused button: just switches into pad mode
		_pad_event(JOY_BUTTON_LEFT_STICK, false)
	elif f == 20:
		cam.zoom = 1.0
		cursor.pad_cell = Vector2i(4, 6)
		cam.focus_on(DungeonGrid.cell_center(cursor.pad_cell), true)
	elif f == 30:
		_pad_event(JOY_BUTTON_DPAD_RIGHT, true)
		_ct_prev = cam.focus
	elif f > 30 and f <= 130:
		var dt := get_process_delta_time()
		_ct_speeds.append((cam.focus - _ct_prev).length() / maxf(dt, 1e-4))
		_ct_prev = cam.focus
	elif f == 131:
		_pad_event(JOY_BUTTON_DPAD_RIGHT, false)
		# measure from the moment the camera starts following the cursor
		var first := -1
		for i in _ct_speeds.size():
			if _ct_speeds[i] > 1.0:
				first = i
				break
		var s := _ct_speeds.slice(maxi(first, 0) + 6)
		var mean := 0.0
		for v in s:
			mean += v
		mean /= maxf(1.0, s.size())
		var stalls := s.filter(func(v: float) -> bool: return v < mean * 0.25).size()
		print("CAMSERIES ", ", ".join(_ct_speeds.map(func(v: float) -> String: return "%.1f" % v)))
		print("CAMTEST follow_start=%d mean=%.2f min=%.2f max=%.2f stalled=%d/%d cursor=%s" % [first, mean, s.min(), s.max(), stalls, s.size(), cursor.pad_cell])
		get_tree().quit()


var _freeze_probe := []
var _freeze_frame := 0


func _world_probe() -> Array:
	var p := [eco.monsters.size(), cam.position]
	for m in eco.monsters.slice(0, 5):
		p.append([m.cell, m.move_t, m.hp, m.visual.position if m.visual else Vector3.ZERO])
	return p
var _auto_last_shot := 0


## Plays the real flow (title → cut-ins → digging → placement → invasion) without input devices.


func _census() -> String:
	var rich := 0
	var cracked := 0
	for v in grid.nutrient:
		if v >= Balance.BUG_SPAWN_MIN:
			rich += 1
		if v >= Balance.SCORPION_SPAWN_MIN:
			cracked += 1
	return "scorpions_born %d | soil %d (+%d in monsters) rich_blocks %d cracked %d | moss %d flower %d larva %d adult %d scorpion %d" % [_scorpions_born,
		grid.total_nutrient(), eco.total_nutrient(), rich, cracked,eco.count(Monster.Kind.MOSS, Monster.MOSS),
		eco.count(Monster.Kind.MOSS, Monster.BUD) + eco.count(Monster.Kind.MOSS, Monster.FLOWER),
		eco.count(Monster.Kind.BUG, Monster.LARVA) + eco.count(Monster.Kind.BUG, Monster.PUPA), eco.count(Monster.Kind.BUG, Monster.ADULT),
		eco.count(Monster.Kind.SCORPION)]


func _autoplay() -> void:
	var every := int(_debug.get("shots_every", 0))
	if every > 0 and _frames - _auto_last_shot >= every and phase != Phase.TITLE:
		_auto_last_shot = _frames
		_screenshot("debug_shots/auto_%05d_p%d.png" % [_frames, phase])
	match phase:
		Phase.TITLE:
			if _frames == 40:
				screens.start_pressed.emit()
		Phase.BUILD:
			if _frames % 12 == 0 and _auto_digs < 45:
				var best := Vector2i(-1, -1)
				var bs := -1.0
				for y in grid.h:
					for x in grid.w:
						var c := Vector2i(x, y)
						if grid.can_dig(c):
							var sc := grid.get_nutrient(c) * 0.4 + y * 0.3 + randf() * 3.0
							if sc > bs:
								bs = sc
								best = c
				if best.x >= 0:
					cursor.hover = best
					_on_click(best)
					_auto_digs += 1
			elif _auto_digs >= 45 and build_left < float(stage["build_time"]) * 0.4:
				_begin_place()
			if speed != 3.0:
				_set_speed(3.0)
		Phase.PLACE:
			var dist := grid.distance_map(grid.entrance)
			var far := grid.entrance
			for y in grid.h:
				for x in grid.w:
					var c := Vector2i(x, y)
					if dist[grid.idx(c)] > dist[grid.idx(far)]:
						far = c
			_on_click(far)
		Phase.INVASION:
			if speed != 3.0:
				_set_speed(3.0)
		Phase.RESULT:
			if _freeze_probe.is_empty():
				_freeze_probe = _world_probe()
				_freeze_frame = _frames
				return
			if _frames - _freeze_frame < 120:
				return
			print("FREEZE ", "OK" if _world_probe() == _freeze_probe else "NG", " ", _freeze_probe)
			_screenshot("debug_shots/auto_result.png")
			print("AUTOPLAY RESULT victory time %.1f dig_left %d EP %d" % [invasion_time, dig_left, GameState.evolution_points])
			# --run=N: go on to the next stage (same dungeon) until N stages are cleared
			print("AUTORUN stage %d victory time %.1f monsters %s" % [GameState.stage_index + 1, invasion_time, _census()])
			if GameState.stage_index + 1 < int(_debug.get("run", 1)):
				_on_next_stage()
				return
			get_tree().quit()
		Phase.DEFEAT:
			_screenshot("debug_shots/auto_defeat.png")
			print("AUTOPLAY RESULT defeat time %.1f" % invasion_time)
			print("AUTORUN stage %d defeat time %.1f monsters %s" % [GameState.stage_index + 1, invasion_time, _census()])
			get_tree().quit()
