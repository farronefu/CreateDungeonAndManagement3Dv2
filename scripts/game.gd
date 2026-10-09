class_name Game
extends Node3D
## Game flow:
##   title → 勇者来訪カットイン → 建設フェーズ (dig, ecosystem runs) → 魔王配置 →
##   勇者出現カットイン → 侵攻フェーズ (keep digging, monsters fight) → 勝利 → リザルト/進化 → next stage
## The dungeon carries over between stages (GameState.dungeon_snapshot).

enum Phase { TITLE, INTRO, BUILD, PLACE, HERO_INTRO, INVASION, ENDING, RESULT, DEFEAT }

var phase := Phase.TITLE
var grid: DungeonGrid
var eco: Ecosystem
var view: DungeonView
var fx: Effects
var layer: MonsterLayer
## the hero the camera, the cower check and the debug tools look at (the first one alive)
var hero: Hero
## everyone invading this stage (stage 3 sends two)
var heroes: Array[Hero] = []
var maou: Maou
var cursor: DigCursor
var cam: GameCamera
var hud: Hud
var cutin: CutIn
var screens: Screens
var stage: Dictionary
var profile: HeroProfile
var dig_left := 0
var dig_max := 0
var build_left := 0.0
var invasion_time := 0.0
var speed := 1.0
## last non-zero speed (restored when un-pausing)
var _run_speed := 1.0
var env: Environment
var follow_hero := true

var letterbox: Letterbox
var _maou_cutin: PortraitStudio
var _hud_timer := 0.0
var _title_t := 0.0
var _debug := {}
var _frames := 0
var _victory_audio_end := 0
## torches the hero planted: cell -> Torch (shared with the hero)
var torches := {}


func _ready() -> void:
	MonsterVisual.time_scale = 1.0
	_debug = _parse_args()
	if not GameState.in_run:
		GameState.new_run()
		if _debug.has("seed"):
			GameState.seed_value = int(_debug["seed"])
		# --stage=N: start at that stage (0 = the first) with a fresh dungeon
		if _debug.has("stage"):
			GameState.stage_index = int(_debug["stage"])
	_build_environment()
	_setup_stage()
	_build_ui()
	if _debug.has("autostart") or _debug.has("skip_title"):
		_debug_bootstrap()
	elif GameState.stage_index > 0 or _debug.has("stage_reload") or GameState.restart_stage:
		GameState.restart_stage = false
		_begin_intro()
	else:
		phase = Phase.TITLE
		hud.set_visible_all(false)
		screens.show_title()
		Sfx.play_bgm("title")

	if _debug.has("audiotest"):
		add_child(load("res://scripts/debug/audio_test.gd").new())


# ------------------------------------------------------------------ setup
func _build_environment() -> void:
	# late-afternoon sky over the town. Lighting is split by RenderLayers: the sun lights the
	# surface only, the dungeon gets a dim light from above, monsters their own key light.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.46, 0.72)
	sky_mat.sky_horizon_color = Color(0.86, 0.76, 0.62)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.72, 0.66, 0.56)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.28)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.62)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8
	env.ssao_detail = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.35
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.8, 0.74, 0.66)
	env.fog_density = 1.0
	env.fog_depth_begin = 48.0
	env.fog_depth_end = 170.0
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# the sun shines on the surface world only
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.light_cull_mask = RenderLayers.SURFACE
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_opacity = 0.85
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation_degrees = Vector3(-50, -32, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.22
	fill.light_cull_mask = RenderLayers.SURFACE
	fill.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill)
	# under ground: a dim, cool light from almost straight above - tops read brighter than sides
	var cave := DirectionalLight3D.new()
	cave.light_color = Color(0.78, 0.8, 0.92)
	cave.light_energy = 0.62
	cave.light_cull_mask = RenderLayers.DUNGEON
	cave.shadow_enabled = true
	cave.shadow_blur = 1.6
	cave.shadow_opacity = 0.7
	cave.directional_shadow_max_distance = 45.0
	cave.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	cave.rotation_degrees = Vector3(-72, -24, 0)
	add_child(cave)
	# characters get their own warm key light so monsters stay vivid everywhere
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.3
	key.light_cull_mask = RenderLayers.ACTORS
	key.rotation_degrees = Vector3(-55, -30, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.light_energy = 0.45
	rim.light_cull_mask = RenderLayers.ACTORS
	rim.rotation_degrees = Vector3(-25, 150, 0)
	add_child(rim)


## Full-screen ink outline + grade + vignette, attached to the game camera.
func _attach_post(camera: Camera3D) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post.gdshader")
	mat.render_priority = -128
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	camera.add_child(mi)


func _setup_stage() -> void:
	stage = StageDefs.get_stage(GameState.stage_index)
	var entries: Array = stage["heroes"]
	profile = load(entries[0]["profile"]) as HeroProfile
	var snap: Dictionary = GameState.dungeon_snapshot
	if snap.is_empty():
		grid = DungeonGrid.new()
		grid.generate(GameState.seed_value)
	else:
		grid = DungeonGrid.from_dict(snap["grid"])
	eco = Ecosystem.new(grid, GameState.seed_value + GameState.stage_index * 101)
	eco.spawned.connect(func(m: Monster, _cause: String) -> void:
		if m.kind == Monster.Kind.SCORPION:
			_scorpions_born += 1)
	eco.moss_level = GameState.upgrade_level("moss")
	eco.bug_level = GameState.upgrade_level("bug")
	view = DungeonView.new()
	add_child(view)
	view.setup(grid)
	fx = Effects.new()
	add_child(fx)
	layer = MonsterLayer.new()
	add_child(layer)
	layer.setup(eco, fx)
	if snap.is_empty():
		# two moss already living in the starter room
		for c in [Vector2i(grid.entrance.x - 7, 5), Vector2i(grid.entrance.x - 5, 4)]:
			if grid.is_floor(c):
				eco.spawn(Monster.Kind.MOSS, Monster.MOSS, c, 2, "load")
	else:
		eco.load_array(snap["monsters"])
	GameState.stage_start_snapshot = {"grid": grid.to_dict(), "monsters": eco.to_array()}
	maou = Maou.new()
	add_child(maou)
	heroes.clear()
	for e in entries:
		var h := Hero.new()
		add_child(h)
		heroes.append(h)
	hero = heroes[0]
	# the 魔王 stands near the entrance from the start (the player moves him when the hero is called)
	maou.place(_maou_start_cell(), true)
	for i in heroes.size():
		var h := heroes[i]
		var e: Dictionary = entries[i]
		h.setup(load(e["profile"]) as HeroProfile, grid, eco, maou, fx, float(e.get("mult", 1.0)), e)
		h.entry_path = view.surface.entry_path()
		h.descent_path = view.surface.descent_path()
		h.gate = view.surface
		h.others = heroes
		h.enter_delay = 1.6 * i   # the second one comes through the gate behind the first
		h.died.connect(_on_hero_died.bind(h))
		h.torches = torches
		h.torch_request.connect(_place_torch)
		h.escaped_with_maou.connect(_on_defeat)
		h.found_maou.connect(func() -> void:
			hud.toast("勇者が魔王を見つけた！ 今のうちに攻撃だ！", UiTheme.WARN))
		h.picked_up_maou.connect(func() -> void:
			hud.toast("魔王が捕まった！入口に連れて行かれる前に勇者を倒せ！", UiTheme.WARN)
			_watch_hero(h)
			follow_hero = true
			Sfx.play_bgm("captured"))
	eco.heroes = heroes
	cam = GameCamera.new()
	add_child(cam)
	# up to the town on the cliff (the focus rises onto it), down to the bottom rows
	cam.set_bounds(Rect2(4, -9.5, grid.w - 8, grid.h + 4.5))
	cam.lift = Vector3(-1.0, -8.5, SurfaceWorld.GROUND_Y)
	# the right stick looks around the pad cursor
	cam.orbit_pivot = func() -> Vector3: return DungeonGrid.cell_center(cursor.pad_cell)
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(-1, 0, 4.5), true)
	cam.current = true
	_attach_post(cam)
	cursor = DigCursor.new()
	add_child(cursor)
	cursor.grid = grid
	cursor.view = view
	cursor.camera = cam
	cursor.validator = _cursor_color
	cursor.clicked.connect(_on_click)
	cursor.dragged.connect(_on_drag)
	dig_max = GameState.dig_capacity()
	dig_left = dig_max
	build_left = float(stage["build_time"])


func _build_ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.call_hero_pressed.connect(_on_call_hero)
	hud.speed_changed.connect(_set_speed)
	hud.retry_pressed.connect(_on_retry)
	hud.title_pressed.connect(_on_title)
	hud.resume_pressed.connect(func() -> void:
		if speed == 0.0:
			_toggle_pause())
	Pad.button_pressed.connect(_on_pad_button)
	Pad.trigger_pressed.connect(_on_pad_trigger)
	hud.set_hero_count(heroes.size())
	for i in heroes.size():
		hud.set_hero(heroes[i].profile.display_name, load(heroes[i].profile.icon_path) as Texture2D, i)
	_maou_cutin = PortraitStudio.new()
	add_child(_maou_cutin)
	_maou_cutin.setup(MonsterCatalog.scene("maou"), Vector2i(560, 560), 1.1, Vector3(0.0, 0.8, 1.7), Vector3(0, 0.6, 0), 30.0, false)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	cutin = CutIn.new()
	ui.add_child(cutin)
	letterbox = Letterbox.new()
	ui.add_child(letterbox)
	screens = Screens.new()
	ui.add_child(screens)
	screens.start_pressed.connect(func() -> void:
		screens.hide_all()
		_begin_intro())
	screens.next_stage_pressed.connect(_on_next_stage)
	screens.retry_pressed.connect(_on_retry)
	screens.title_pressed.connect(_on_title)
	_update_hud(true)


# ------------------------------------------------------------------ phases
func _begin_intro() -> void:
	phase = Phase.INTRO
	cam.reset_angle()
	cam.zoom = 1.0
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(-1, 0, 4.5))
	hud.set_visible_all(true)
	Sfx.play_bgm("build")
	await _opening()
	_begin_build()


## Opening scene before the build phase: cinema bars slide in, the hero walks along the road in
## the town, stops, raises his sword (the joy clip), says his line in the bottom bar and goes
## down the steps into the fog. Everything else is frozen; A / Enter / Space / click skip it.
func _opening() -> void:
	var frozen := [layer, fx, maou, cursor]
	for n in frozen:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	cursor.mode = DigCursor.Mode.NONE
	hud.set_visible_all(false)
	cam.reset_angle()
	cam.set_angle(0.0, deg_to_rad(30.0))
	cam.zoom = 0.6
	letterbox.begin()
	Sfx.play("cutin")
	for i in heroes.size():
		heroes[i].begin_descent(1.6 * i)
	var stop_at := 2.2   # on the road left of the mound, in plain view of the camera
	var stage := 0       # 0 walking in, 1 each in turn raises his weapon and says his line, 2 down the steps
	var t := 0.0
	var speaker := -1
	var lead := heroes[0]
	while heroes.any(func(h: Hero) -> bool: return h.state == Hero.State.DESCENDING) and not letterbox.skipped:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		if stage < 2:   # the camera stays on the road while they go down the steps
			cam.focus_on(lead.position + Vector3(0.6 * (heroes.size() - 1), 0, 0.3))
		match stage:
			0:
				for h in heroes:
					h.tick(dt)
				if lead.descent_dist() >= stop_at:
					stage = 1
					t = 0.0
			1:
				t += dt
				for h in heroes:
					h.rotation.y = lerp_angle(h.rotation.y, 0.0, 0.2)
				if t >= 0.0:
					speaker += 1
					if speaker >= heroes.size():
						stage = 2
					else:
						var h := heroes[speaker]
						var pr := h.profile
						var d := h.actor.play_once(pr.anim_joy, pr.joy_anim_speed) if h.actor.has_anim(pr.anim_joy) else 1.5
						letterbox.say(pr.display_name, pr.intro_line, 1.6)
						t = -maxf(d, 2.6)   # hold until the clip and the line are done
			2:
				for h in heroes:
					h.tick(dt)
	for h in heroes:
		h.finish_descent()
	var was_skipped := letterbox.skipped
	letterbox.end()
	if not was_skipped:
		await get_tree().create_timer(0.5).timeout
	hud.set_visible_all(true)
	for n in frozen:
		(n as Node).process_mode = Node.PROCESS_MODE_INHERIT
	cam.reset_angle()
	cam.zoom = 1.0
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(-1, 0, 4.5))


func _begin_build() -> void:
	phase = Phase.BUILD
	cursor.mode = DigCursor.Mode.DIG
	hud.toast("通路につながったブロックをクリックして掘ろう", UiTheme.TEXT)


## Y / the button / Space: asks before calling the hero early.
func _on_call_hero() -> void:
	if phase != Phase.BUILD or hud.is_confirming() or speed == 0.0:
		return
	cursor.mode = DigCursor.Mode.NONE
	hud.ask("勇者を呼びますか？", func(yes: bool) -> void:
		if phase != Phase.BUILD:
			return
		if yes:
			_begin_place()
		else:
			cursor.mode = DigCursor.Mode.DIG)


## Where the 魔王 stands at the start of a stage: a corridor cell MAOU_START_STEPS steps from the
## entrance (closest available), preferring the deepest one, then the one straight below it.
const MAOU_START_STEPS := 3
func _maou_start_cell() -> Vector2i:
	var d := grid.distance_map(grid.entrance)
	var best := Vector2i(-1, -1)
	var best_score := INF
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			var dc: int = d[grid.idx(c)]
			if c == grid.entrance or not grid.is_floor(c) or dc < 1:
				continue
			var score := absf(dc - MAOU_START_STEPS) * 100.0 - y * 2.0 + absi(x - grid.entrance.x)
			if score < best_score:
				best_score = score
				best = c
	return best if best.x >= 0 else grid.entrance


func _begin_place() -> void:
	phase = Phase.PLACE
	cursor.mode = DigCursor.Mode.PLACE
	Sfx.play("cutin")


func _valid_place(c: Vector2i) -> bool:
	if not grid.is_floor(c) or c == grid.entrance:
		return false
	var d := grid.distance_map(grid.entrance)
	return d[grid.idx(c)] >= 4


func _try_place(c: Vector2i) -> void:
	if not _valid_place(c):
		Sfx.play("miss")
		return
	maou.place(c)
	cursor.mode = DigCursor.Mode.NONE
	phase = Phase.HERO_INTRO
	await get_tree().create_timer(0.8 if not _debug.has("autostart") else 0.01).timeout
	_begin_invasion()


func _begin_invasion() -> void:
	phase = Phase.INVASION
	invasion_time = 0.0
	cursor.mode = DigCursor.Mode.DIG
	for h in heroes:
		h.begin_invasion()
	Sfx.play_bgm("battle")
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(0, 0, 4))
	hud.toast("侵攻中も掘れる！ 新しい通路で勇者を迷わせよう", UiTheme.TEXT)
	hud.toast("F キー: 勇者をカメラで追う / 解除", UiTheme.TEXT)
	follow_hero = true


## The camera / status focus moves to this hero.
func _watch_hero(h: Hero) -> void:
	hero = h
	profile = h.profile


func _tick_heroes(dt: float) -> void:
	for h in heroes:
		h.tick(dt)


func _on_hero_died(who: Hero) -> void:
	if phase != Phase.INVASION:
		return
	# the stage is won only when every hero is down
	var left: Array[Hero] = heroes.filter(func(h: Hero) -> bool: return h.state != Hero.State.DEAD)
	if not left.is_empty():
		hud.toast("%sを倒した！ 残るは%s" % [who.profile.display_name, left[0].profile.display_name], UiTheme.WARN)
		if hero == who:
			_watch_hero(left[0])
		return
	phase = Phase.ENDING
	cursor.mode = DigCursor.Mode.NONE
	Sfx.play_bgm("")
	Sfx.play("victory")
	_victory_audio_end = Time.get_ticks_msec() + int(Sfx.duration("victory") * 1000.0)
	maou.set_mood("cheer")
	_maou_cutin.actor.play("look_around", 0.0)
	await get_tree().create_timer(1.6 if not _debug.has("autostart") else 0.01).timeout
	await get_tree().create_timer(1.0 if not _debug.has("autostart") else 0.01).timeout
	_show_result()


func _on_defeat() -> void:
	if phase != Phase.INVASION:
		return
	phase = Phase.ENDING
	cursor.mode = DigCursor.Mode.NONE
	for h in heroes:
		h.visible = false
	maou.visible = false
	Sfx.play_bgm("")
	Sfx.play("defeat")
	_maou_cutin.actor.play("idle", 0.0)
	await _cutin("魔王が連れ去られた…", "ゲームオーバー", _maou_cutin.get_texture(), Color(0.25, 0.1, 0.35))
	phase = Phase.DEFEAT
	screens.show_game_over()


func _show_result() -> void:
	phase = Phase.RESULT
	_play_result_music()
	_freeze_world()
	var time_bonus := maxi(0, Balance.EP_TIME_BONUS_MAX - int(invasion_time / Balance.EP_TIME_STEP))
	var dig_bonus := dig_left * Balance.EP_PER_DIG_LEFT
	var total := Balance.EP_BASE + time_bonus + dig_bonus
	GameState.evolution_points += total
	screens.show_result({"rows": [
		["ステージクリア", "", Balance.EP_BASE],
		["撃退タイム", _fmt_time(invasion_time), time_bonus],
		["残り採掘可能数", "%d / %d" % [dig_left, dig_max], dig_bonus],
	]})


func _play_result_music() -> void:
	var remaining := maxf(0.0, (_victory_audio_end - Time.get_ticks_msec()) / 1000.0)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	if phase == Phase.RESULT:
		Sfx.play_bgm("result_victory")


## Stops everything in the dungeon (simulation, animation, camera) while the upgrade screen is open.
func _freeze_world() -> void:
	var nodes: Array = [view, layer, fx, maou, cursor, cam]
	nodes.append_array(heroes)
	for n in nodes:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	hud.show_tooltip("", Vector2.ZERO)


func _on_next_stage() -> void:
	GameState.dungeon_snapshot = {"grid": grid.to_dict(), "monsters": eco.to_array()}
	GameState.stage_index += 1
	get_tree().reload_current_scene()


func _on_retry() -> void:
	GameState.dungeon_snapshot = GameState.stage_start_snapshot
	GameState.restart_stage = true
	get_tree().reload_current_scene()


func _on_title() -> void:
	GameState.in_run = false
	GameState.dungeon_snapshot = {}
	get_tree().reload_current_scene()


func _cutin(title: String, sub: String, tex: Texture2D, col: Color) -> void:
	if _debug.has("autostart"):
		return
	cutin.play(title, sub, tex, col)
	await cutin.finished


# ------------------------------------------------------------------ frame update
func _process(delta: float) -> void:
	_frames += 1
	var dt := delta * speed
	match phase:
		Phase.TITLE:
			# slow orbit over the town and the dungeon behind the title
			_title_t += delta
			cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(sin(_title_t * 0.05) * 6.0, 0, 1.5))
			cam.set_angle(sin(_title_t * 0.07) * 0.55 - 0.25, deg_to_rad(30.0), false)
			cam.zoom = 0.9
			eco.tick(delta)
		Phase.BUILD:
			eco.tick(dt)
			_tick_heroes(dt)
			build_left -= dt
			if build_left <= 0.0:
				build_left = 0.0
				if hud.is_confirming():
					hud.answer(true)
				else:
					_begin_place()
		Phase.PLACE, Phase.HERO_INTRO:
			_tick_heroes(dt)
		Phase.INVASION:
			var t0 := Time.get_ticks_usec()
			eco.tick(dt)
			var t1 := Time.get_ticks_usec()
			_tick_heroes(dt)
			_prof["eco"] = float(_prof.get("eco", 0.0)) + (t1 - t0) / 1000.0
			_prof["hero"] = float(_prof.get("hero", 0.0)) + (Time.get_ticks_usec() - t1) / 1000.0
			invasion_time += dt
			_update_maou_mood()
			if cam.user_moved:
				follow_hero = false
			if follow_hero and hero.is_targetable():
				cam.focus_on(hero.position + Vector3(0, 0, 1.0))
		Phase.ENDING:
			eco.tick(delta)
			_tick_heroes(delta)
	cam.user_moved = false
	var t2 := Time.get_ticks_usec()
	_update_tooltip(delta)
	_prof["tooltip"] = float(_prof.get("tooltip", 0.0)) + (Time.get_ticks_usec() - t2) / 1000.0
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.2
		_update_hud(false)
	_debug_tick()


## The 魔王 cowers while the hero is within MAOU_SCARED_ENTER cells and gets back up once it is
## MAOU_SCARED_LEAVE cells away (the gap stops him bobbing up and down at the edge).
const MAOU_SCARED_ENTER := 4
const MAOU_SCARED_LEAVE := 6
func _update_maou_mood() -> void:
	if maou.carrier != null or not maou.placed:
		return
	var near := false
	for h in heroes:
		var d := absi(h.cell.x - maou.cell.x) + absi(h.cell.y - maou.cell.y)
		if h.is_targetable() and d <= (MAOU_SCARED_LEAVE - 1 if maou.mood == "scared" else MAOU_SCARED_ENTER):
			near = true
	maou.set_mood("scared" if near else "idle")


func _fmt_time(t: float) -> String:
	var s := int(ceil(t)) if t > 0 else 0
	return "%02d:%02d" % [s / 60, s % 60]


func _update_hud(_force: bool) -> void:
	for i in heroes.size():
		hud.update_hero(heroes[i].hp, heroes[i].max_hp, heroes[i].mp, heroes[i].max_mp, phase == Phase.INVASION or phase == Phase.ENDING, i)
	hud.update_dig(dig_left, dig_max)
	match phase:
		Phase.TITLE, Phase.INTRO, Phase.BUILD:
			hud.update_phase("build", "勇者の到着まで", _fmt_time(build_left), phase == Phase.BUILD)
		Phase.PLACE, Phase.HERO_INTRO:
			hud.update_phase("message", "魔王を置く場所を選ぼう
入口から4マス以上
離れた通路に置ける" if phase == Phase.PLACE else "勇者がやってくる…", "", false)
		_:
			hud.update_phase("hero", "", _fmt_time(invasion_time), false)
	hud.update_eco({
		"moss": eco.count(Monster.Kind.MOSS, Monster.MOSS),
		"moss_flower": eco.count(Monster.Kind.MOSS, Monster.BUD) + eco.count(Monster.Kind.MOSS, Monster.FLOWER),
		"bug_larva": eco.count(Monster.Kind.BUG, Monster.LARVA) + eco.count(Monster.Kind.BUG, Monster.PUPA),
		"bug_adult": eco.count(Monster.Kind.BUG, Monster.ADULT),
		"scorpion": eco.count(Monster.Kind.SCORPION),
	}, grid.total_nutrient())


# ------------------------------------------------------------------ input
## Gamepad shortcuts (Xbox layout). Digging / placing is handled by DigCursor.
func _on_pad_button(b: int) -> void:
	# a yes / no question is open: A presses the focused button, B answers no
	if hud.is_confirming():
		if b == JOY_BUTTON_B:
			hud.answer(false)
		return
	# paused: Start / B resume, A presses the focused menu button
	if speed == 0.0 and _can_change_speed():
		if b == JOY_BUTTON_START or b == JOY_BUTTON_B:
			_toggle_pause()
		return
	match b:
		JOY_BUTTON_RIGHT_SHOULDER:
			if _can_change_speed():
				_step_speed(1)
		JOY_BUTTON_LEFT_SHOULDER:
			if _can_change_speed():
				_step_speed(-1)
		JOY_BUTTON_START:
			if _can_change_speed():
				_toggle_pause()
		JOY_BUTTON_Y:
			if phase == Phase.BUILD:
				_on_call_hero()


func _on_pad_trigger(axis: int) -> void:
	if axis == JOY_AXIS_TRIGGER_LEFT and not hud.is_confirming() and speed != 0.0:
		_focus_hero()


## RB / LB: one speed step up or down (x1 .. x3).
func _step_speed(d: int) -> void:
	_set_speed(clampf(_run_speed + d, 1.0, 3.0))


## Where LT takes the camera: the hero, or the gate while it is still up in the town / fog.
func _hero_focus_point() -> Vector3:
	if hero.visible and hero.state != Hero.State.DEAD:
		return hero.position
	return DungeonGrid.cell_center(grid.entrance) + Vector3(0, 0, 1.0)


## LT: jump the camera (and the pad cursor) to the hero; during the invasion keep following it.
func _focus_hero() -> void:
	var p := _hero_focus_point()
	cam.focus_on(p)
	if hero.is_targetable():
		cursor.pad_cell = hero.cell
	follow_hero = phase == Phase.INVASION and hero.is_targetable()


func _toggle_pause() -> void:
	_set_speed(_run_speed if speed == 0.0 else 0.0)


## 0 pauses: everything in the dungeon freezes and the pause screen (monster roster) opens.
func _set_speed(s: float) -> void:
	speed = s
	if s > 0.0:
		_run_speed = s
		MonsterVisual.time_scale = s
	hud.set_speed(s)
	var pm := Node.PROCESS_MODE_DISABLED if s == 0.0 else Node.PROCESS_MODE_INHERIT
	var nodes: Array = [layer, fx, maou, cursor]
	nodes.append_array(heroes)
	for n in nodes:
		(n as Node).process_mode = pm
	if s == 0.0:
		hud.show_tooltip("", Vector2.ZERO)


func _can_change_speed() -> bool:
	return phase == Phase.BUILD or phase == Phase.PLACE or phase == Phase.INVASION


func _toggle_follow() -> void:
	follow_hero = not follow_hero
	if follow_hero and hero.is_targetable():
		cursor.pad_cell = hero.cell
	hud.toast("勇者を追跡中" if follow_hero else "追跡を解除", UiTheme.TEXT)


func _on_click(c: Vector2i) -> void:
	match phase:
		Phase.BUILD, Phase.INVASION:
			_try_dig(c)
		Phase.PLACE:
			_try_place(c)


## Mouse held and dragged: dig every diggable cell passed over, silently skipping the rest.
func _on_drag(c: Vector2i) -> void:
	if (phase == Phase.BUILD or phase == Phase.INVASION) and speed > 0.0 and (torches.has(c) or _monster_at(c) != null or (dig_left > 0 and grid.can_dig(c))):
		_try_dig(c)


## The monster standing on (or walking into) cell `c`, if any.
func _monster_at(c: Vector2i) -> Monster:
	if not grid.is_floor(c):
		return null
	for m in eco.monsters:
		if m.alive and m.cell == c:
			return m
	return null


## Breaker poke: deals 1/BREAKER_POKES_TO_KILL of the monster's max HP, so a healthy monster
## dies on the third poke; like any death its nutrient scatters into the soil. Costs no dig.
func _poke_monster(m: Monster) -> void:
	cursor.swing()
	var dmg := m.max_hp / float(Balance.BREAKER_POKES_TO_KILL)
	m.hp -= dmg
	var v := m.visual as MonsterVisual
	if v:
		v.hurt()
		fx.number(v.position + Vector3(0, 0.6, 0), str(int(round(dmg))), Color(1, 1, 1))
	cam.shake(0.15)
	Sfx.play("miss")
	if m.hp <= 0.01:
		m.hp = 0.0
		eco.kill(m, "killed")


## The hero plants a torch where it has explored (only the breaker can remove it).
func _place_torch(c: Vector2i) -> void:
	if torches.has(c):
		return
	var t := Torch.new()
	t.position = DungeonGrid.cell_center(c)
	add_child(t)
	torches[c] = t
	fx.dust(t.position + Vector3(0, 0.1, 0), Color(0.8, 0.7, 0.55, 0.6), 0.6)


## Breaker blow on a torch: it is knocked over and gone (costs no dig).
func _break_torch(c: Vector2i) -> void:
	var t: Node3D = torches[c]
	torches.erase(c)
	cursor.swing()
	fx.debris(c, 0.0)
	fx.dust(t.position + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.3, 0.7), 0.8)
	cam.shake(0.2)
	Sfx.play("torch_break")
	t.queue_free()


func _try_dig(c: Vector2i) -> bool:
	if speed == 0.0:
		Sfx.play("miss")
		hud.toast("一時停止中は掘れません", UiTheme.TEXT_DIM)
		return false
	if dig_left <= 0 and not torches.has(c) and _monster_at(c) == null:
		Sfx.play("miss")
		hud.toast("採掘可能数が残っていない！", UiTheme.WARN)
		return false
	if torches.has(c):
		_break_torch(c)
		return true
	var target := _monster_at(c)
	if target:
		_poke_monster(target)
		return true
	if not grid.can_dig(c):
		Sfx.play("miss")
		return false
	var n := grid.dig(c)
	dig_left -= 1
	cursor.swing()
	fx.debris(c, clampf(n / 12.0, 0.0, 1.0), n)
	cam.shake(0.35)
	Sfx.play("dig")
	var m := eco.spawn_from_dig(c, n)
	if m:
		hud.toast("%s が生まれた！" % m.display_name(), Color(0.6, 1.0, 0.4) if m.kind == Monster.Kind.MOSS else (Color(0.5, 0.75, 1.0) if m.kind == Monster.Kind.SCORPION else Color(1.0, 0.65, 0.3)))
	_tip_timer = 0.0
	return true


func _cursor_color(c: Vector2i) -> Color:
	if phase == Phase.PLACE:
		return Color(0.86, 0.6, 1.0, 1.0) if _valid_place(c) else Color(1, 0.4, 0.32, 0.5)
	if torches.has(c) or ((phase == Phase.BUILD or phase == Phase.INVASION) and _monster_at(c) != null):
		return Color(1.0, 0.55, 0.25, 1.0)
	if grid.is_floor(c):
		return Color(0, 0, 0, 0)
	if grid.can_dig(c) and dig_left > 0:
		var n := grid.get_nutrient(c)
		if n >= Balance.BUG_SPAWN_MIN:
			return Color(1.0, 0.62, 0.35, 1.0)
		if n >= Balance.MOSS_SPAWN_MIN:
			return Color(0.72, 1.0, 0.55, 1.0)
		return Color(1.0, 0.92, 0.72, 1.0)
	return Color(1.0, 0.45, 0.38, 0.45)


# ------------------------------------------------------------------ hover popup
var _tip_timer := 0.0
var _tip_text := ""


func _update_tooltip(delta: float) -> void:
	if _debug.has("trailer"):
		hud.show_tooltip("", Vector2.ZERO)
		return
	var active := (phase == Phase.BUILD or phase == Phase.PLACE or phase == Phase.INVASION or phase == Phase.ENDING) and speed != 0.0
	hud.set_pad_hint(Pad.using_pad and active)
	if not active or hud.is_confirming() or (not Pad.using_pad and get_viewport().gui_get_hovered_control() != null):
		hud.show_tooltip("", Vector2.ZERO)
		return
	# with a gamepad the popup follows the pad cursor instead of the mouse
	var cell := cursor.pad_cell if Pad.using_pad else cursor.mouse_cell()
	var mp := cam.unproject_position(DungeonGrid.cell_center(cell, 0.4)) if Pad.using_pad else get_viewport().get_mouse_position()
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_tip_timer = 0.1
		_tip_text = _tooltip_text(mp, cell)
	hud.show_tooltip(_tip_text, mp)


func _tooltip_text(mp: Vector2, cell: Vector2i) -> String:
	# monsters / hero / 魔王 under the mouse take priority over the cell
	# (lambdas capture locals by value, so the running best lives in a Dictionary)
	var pick := {"obj": null, "d": 44.0}
	var consider := func(obj: Object, pos: Vector3) -> void:
		if cam.is_position_behind(pos):
			return
		var d := cam.unproject_position(pos).distance_to(mp)
		if d < float(pick["d"]):
			pick["d"] = d
			pick["obj"] = obj
	for m in eco.monsters:
		if m.visual:
			consider.call(m, m.visual.global_position + Vector3(0, 0.25, 0))
	for h in heroes:
		if h.visible and h.state != Hero.State.DEAD:
			consider.call(h, h.global_position + Vector3(0, 0.45, 0))
	if maou.placed and maou.visible:
		consider.call(maou, maou.global_position + Vector3(0, 0.4, 0))
	var best: Object = pick["obj"]
	if best is Monster:
		return _monster_tip(best as Monster)
	if best is Hero:
		var h := best as Hero
		var st := "[color=#ff8070]魔王を運搬中！[/color]" if h.carrying else ("戦闘中" if h.busy > 0.0 else "探索中")
		var mp_line := "MP %d/%d\n" % [int(h.mp), int(h.max_mp)] if h.max_mp > 0 else ""
		return "[img=24x24]%s[/img] [b]%s[/b]\nHP %s %d/%d\n%s%s" % [h.profile.icon_path, h.profile.display_name, _bar(h.hp, h.max_hp, "#ff7060"), int(ceil(h.hp)), int(h.max_hp), mp_line, st]
	if best == maou:
		return "[b][color=#d8a0ff]魔王さま[/color][/b]\n" + ("[color=#ff8070]勇者に運ばれている！[/color]" if maou.carrier else "勇者に入口まで運ばれると負け")
	return _cell_tip(cell)


func _bar(v: float, max_v: float, col: String) -> String:
	var n := int(round(clampf(v / maxf(1.0, max_v), 0.0, 1.0) * 10.0))
	return "[color=%s]%s[/color][color=#3a4150]%s[/color]" % [col, "■".repeat(n), "■".repeat(10 - n)]


## Popup for a monster: HP, nutrient and what it still needs to evolve.
func _monster_tip(m: Monster) -> String:
	var txt := "HP %s %d/%d\n養分 %d" % [_bar(m.hp, m.max_hp, "#70e060"), int(ceil(m.hp)), int(m.max_hp), m.nutrient]
	var evo := _evolution_need(m)
	if evo != "":
		txt += "\n[color=#f0e070]進化まで %s[/color]" % evo
	if m.kind == Monster.Kind.SCORPION:
		txt += "\n[color=#b0a898]ザクザクムシを食べる[/color]"
		if m.meals >= Balance.SCORPION_LAY_MEALS:
			txt += "\n[color=#f0e070]隣の土に卵を産みつける[/color]"
		else:
			txt += "\n[color=#f0e070]産卵まで あと%d匹[/color]" % (Balance.SCORPION_LAY_MEALS - m.meals)
	return txt


## The values the next evolution waits for, as shown in the popup ("" for final forms).
func _evolution_need(m: Monster) -> String:
	if m.kind == Monster.Kind.SCORPION:
		return ""
	if m.kind == Monster.Kind.MOSS:
		match m.stage:
			Monster.MOSS:
				# roots into a ツボミ when its HP runs down while it carries enough nutrient
				return "養分 %d/%d ・ HP %d→%d" % [mini(m.nutrient, Balance.MOSS_BUD_NUTRIENT), Balance.MOSS_BUD_NUTRIENT, int(ceil(m.hp)), Balance.MOSS_BUD_HP]
			Monster.BUD:
				return "養分 %d/%d" % [m.nutrient, Balance.BUD_TARGET]
	else:
		var mult := 1.0 + 0.25 * eco.bug_level
		match m.stage:
			Monster.LARVA:
				return "HP %d/%d" % [int(ceil(m.hp)), int(Balance.LARVA_PUPATE * mult)]
			Monster.PUPA:
				return "あと %d秒" % maxi(0, int(ceil((Balance.PUPA_TIME - maxf(0.0, m.timer)) / (1.0 + 0.15 * eco.bug_level))))
	return ""


## Popup for a soil block: nutrient and how much more reaches the next stage.
func _cell_tip(c: Vector2i) -> String:
	if grid.is_egg(c):
		return _egg_tip(c)
	if not grid.is_block(c):
		return ""
	var n := grid.get_nutrient(c)
	var stage := Balance.soil_stage(n)
	var txt := "養分 %s %d" % [_bar(n, Balance.MAX_NUTRIENT, "#c0ff80"), n]
	if stage < Balance.SOIL_STAGE_MIN.size() - 1:
		txt += "\n[color=#b0a898]養分があと %d で次の段階へ[/color]" % (Balance.SOIL_STAGE_MIN[stage + 1] - n)
	if n >= Balance.SCORPION_SPAWN_MIN:
		txt += "\n[color=#9cc4ff]掘るとサソリが生まれる[/color]"
	return txt


## Popup for a block a scorpion laid its egg in.
func _egg_tip(c: Vector2i) -> String:
	var left := maxi(0, int(ceil(float(grid.eggs.get(c, 0.0)))))
	return "[b][color=#ffd040]サソリの卵[/color][/b]\n掘るとサソリが生まれる\nあと %d秒で自然にふ化する\n養分 %d" % [left, grid.get_nutrient(c)]


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_P and _can_change_speed():
			_toggle_pause()
		elif speed == 0.0:
			return
		elif k.keycode == KEY_SPACE and phase == Phase.BUILD:
			_on_call_hero()
		elif k.keycode == KEY_F and phase == Phase.INVASION:
			_toggle_follow()
		elif k.keycode == KEY_F12:
			_screenshot("user://shot_%d.png" % Time.get_ticks_msec())


# ------------------------------------------------------------------ debug / automated capture
func _parse_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			d[s.substr(0, i)] = s.substr(i + 1)
		else:
			d[s] = true
	return d


func _screenshot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # The dummy renderer has no image; event tests still run.
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)


# ------------------------------------------------------------------ hooks for scripts/main.gd
## The scene runs scripts/main.gd, which extends this class with the command-line debug switches,
## the autoplayer and the automated tests. Here they do nothing.
var _prof := {}
## scorpions hatched this stage (reported by the autoplay run)
var _scorpions_born := 0


func _debug_bootstrap() -> void:
	pass


func _debug_tick() -> void:
	pass
