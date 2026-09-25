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
var hero: Hero
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

var _hero_portrait: Texture2D
var _hero_cutin: PortraitStudio
var _maou_cutin: PortraitStudio
var _hud_timer := 0.0
var _title_t := 0.0
var _debug := {}
var _frames := 0


func _ready() -> void:
	MonsterVisual.time_scale = 1.0
	_debug = _parse_args()
	if not GameState.in_run:
		GameState.new_run()
		if _debug.has("seed"):
			GameState.seed_value = int(_debug["seed"])
	_build_environment()
	_setup_stage()
	_build_ui()
	if _debug.has("autostart") or _debug.has("skip_title"):
		_debug_bootstrap()
	elif GameState.stage_index > 0 or _debug.has("stage_reload"):
		_begin_intro()
	else:
		phase = Phase.TITLE
		hud.set_visible_all(false)
		screens.show_title()
		Sfx.play_bgm("build")


# ------------------------------------------------------------------ setup
func _build_environment() -> void:
	# late-afternoon sky over the town; the dungeon below is kept darker by its shaders,
	# (no torches: the dungeon is lit by the sun, ambient light and the effects)
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
	env.ambient_light_energy = 0.42
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
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_opacity = 0.85
	sun.directional_shadow_max_distance = 50.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation_degrees = Vector3(-50, -32, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill)


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
	profile = load(stage["hero"]) as HeroProfile
	var snap: Dictionary = GameState.dungeon_snapshot
	if snap.is_empty():
		grid = DungeonGrid.new()
		grid.generate(GameState.seed_value)
	else:
		grid = DungeonGrid.from_dict(snap["grid"])
	eco = Ecosystem.new(grid, GameState.seed_value + GameState.stage_index * 101)
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
		# a few moss already living in the starter room
		for c in [Vector2i(grid.entrance.x - 7, 5), Vector2i(grid.entrance.x - 5, 4), Vector2i(grid.entrance.x - 6, 7)]:
			if grid.is_floor(c):
				eco.spawn(Monster.Kind.MOSS, Monster.MOSS, c, 2, "load")
	else:
		eco.load_array(snap["monsters"])
	GameState.stage_start_snapshot = {"grid": grid.to_dict(), "monsters": eco.to_array()}
	maou = Maou.new()
	add_child(maou)
	hero = Hero.new()
	add_child(hero)
	hero.setup(profile, grid, eco, maou, fx, float(stage["hero_mult"]))
	hero.entry_path = view.surface.entry_path()
	eco.hero = hero
	hero.died.connect(_on_hero_died)
	hero.escaped_with_maou.connect(_on_defeat)
	hero.found_maou.connect(func() -> void:
		hud.toast("勇者が魔王を見つけた！ 今のうちに攻撃だ！", UiTheme.WARN))
	hero.picked_up_maou.connect(func() -> void:
		hud.toast("魔王が捕まった！入口に連れて行かれる前に勇者を倒せ！", UiTheme.WARN)
		follow_hero = true
		Sfx.play("dig_fail"))
	cam = GameCamera.new()
	add_child(cam)
	cam.set_bounds(Rect2(4, -1.5, grid.w - 8, grid.h - 3.5))
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
	dig_max = GameState.dig_capacity()
	dig_left = dig_max
	build_left = float(stage["build_time"])


func _build_ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.call_hero_pressed.connect(_on_call_hero)
	hud.speed_changed.connect(_set_speed)
	hud.resume_pressed.connect(func() -> void:
		if speed == 0.0:
			_toggle_pause())
	Pad.button_pressed.connect(_on_pad_button)
	var hero_scene := load(profile.model_path) as PackedScene
	_hero_portrait = load(profile.icon_path) as Texture2D
	hud.set_hero(profile.display_name, _hero_portrait)
	_hero_cutin = PortraitStudio.new()
	add_child(_hero_cutin)
	_hero_cutin.setup(hero_scene, Vector2i(560, 560), 1.0, Vector3(0.45, 0.62, 1.7), Vector3(0, 0.5, 0), 30.0)
	_hero_cutin.actor.rotation.y = 0.35
	_maou_cutin = PortraitStudio.new()
	add_child(_maou_cutin)
	_maou_cutin.setup(MonsterCatalog.scene("maou"), Vector2i(560, 560), 0.0, Vector3(0.0, 0.62, 1.55), Vector3(0, 0.45, 0), 30.0, true)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	cutin = CutIn.new()
	ui.add_child(cutin)
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
	_hero_cutin.actor.play(profile.anim_idle, 0.0)
	await _cutin("勇者%sがやってくる！" % profile.display_name, "到着まであと%d秒。ダンジョンを掘って魔物を育てよう" % int(build_left), _hero_cutin.get_texture(), Color(0.75, 0.2, 0.12))
	_begin_build()


func _begin_build() -> void:
	phase = Phase.BUILD
	cursor.mode = DigCursor.Mode.DIG
	hud.toast("通路につながったブロックをクリックして掘ろう", UiTheme.TEXT)


func _on_call_hero() -> void:
	if phase == Phase.BUILD:
		_begin_place()


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
		Sfx.play("dig_fail")
		return
	maou.place(c)
	cursor.mode = DigCursor.Mode.NONE
	phase = Phase.HERO_INTRO
	await get_tree().create_timer(0.8 if not _debug.has("autostart") else 0.01).timeout
	_hero_cutin.actor.play_once(profile.anim_attack, 1.0)
	await _cutin("勇者%sが現れた！" % profile.display_name, profile.intro_line, _hero_cutin.get_texture(), Color(0.8, 0.12, 0.1))
	_begin_invasion()


func _begin_invasion() -> void:
	phase = Phase.INVASION
	invasion_time = 0.0
	cursor.mode = DigCursor.Mode.DIG
	hero.begin_invasion()
	Sfx.play_bgm("battle")
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(0, 0, 4))
	hud.toast("侵攻中も掘れる！ 新しい通路で勇者を迷わせよう", UiTheme.TEXT)
	hud.toast("F キー: 勇者をカメラで追う / 解除", UiTheme.TEXT)
	follow_hero = true


func _on_hero_died() -> void:
	if phase != Phase.INVASION:
		return
	phase = Phase.ENDING
	cursor.mode = DigCursor.Mode.NONE
	Sfx.play_bgm("")
	Sfx.play("victory")
	maou.set_mood("cheer")
	_maou_cutin.actor.play("cheer", 0.0)
	await get_tree().create_timer(1.6 if not _debug.has("autostart") else 0.01).timeout
	await _cutin("勇者を撃退した！", "魔物たちの勝利だ！", _maou_cutin.get_texture(), Color(0.55, 0.25, 0.8))
	_show_result()


func _on_defeat() -> void:
	if phase != Phase.INVASION:
		return
	phase = Phase.ENDING
	cursor.mode = DigCursor.Mode.NONE
	hero.visible = false
	maou.visible = false
	Sfx.play_bgm("")
	Sfx.play("defeat")
	_maou_cutin.actor.play("carried", 0.0)
	await _cutin("魔王が連れ去られた…", "ゲームオーバー", _maou_cutin.get_texture(), Color(0.25, 0.1, 0.35))
	phase = Phase.DEFEAT
	screens.show_game_over()


func _show_result() -> void:
	phase = Phase.RESULT
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


## Stops everything in the dungeon (simulation, animation, camera) while the upgrade screen is open.
func _freeze_world() -> void:
	for n in [view, layer, fx, hero, maou, cursor, cam]:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	hud.show_tooltip("", Vector2.ZERO)


func _on_next_stage() -> void:
	GameState.dungeon_snapshot = {"grid": grid.to_dict(), "monsters": eco.to_array()}
	GameState.stage_index += 1
	get_tree().reload_current_scene()


func _on_retry() -> void:
	GameState.dungeon_snapshot = GameState.stage_start_snapshot
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
			build_left -= dt
			if build_left <= 0.0:
				build_left = 0.0
				_begin_place()
		Phase.INVASION:
			eco.tick(dt)
			hero.tick(dt)
			invasion_time += dt
			_update_maou_mood()
			if cam.user_moved:
				follow_hero = false
			if follow_hero and hero.is_targetable():
				cam.focus_on(hero.position + Vector3(0, 0, 1.0))
		Phase.ENDING:
			eco.tick(delta)
			hero.tick(delta)
	cam.user_moved = false
	_update_tooltip(delta)
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.2
		_update_hud(false)
	_debug_tick()


func _update_maou_mood() -> void:
	if maou.carrier != null or not maou.placed:
		return
	var d := absi(hero.cell.x - maou.cell.x) + absi(hero.cell.y - maou.cell.y)
	maou.set_mood("scared" if hero.is_targetable() and d <= 4 else "idle")


func _fmt_time(t: float) -> String:
	var s := int(ceil(t)) if t > 0 else 0
	return "%02d:%02d" % [s / 60, s % 60]


func _update_hud(_force: bool) -> void:
	hud.update_hero(hero.hp, hero.max_hp, hero.mp, hero.max_mp, phase == Phase.INVASION or phase == Phase.ENDING)
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
		"bug_larva": eco.count(Monster.Kind.BUG, Monster.LARVA),
		"bug_pupa": eco.count(Monster.Kind.BUG, Monster.PUPA),
		"bug_adult": eco.count(Monster.Kind.BUG, Monster.ADULT),
	}, grid.total_nutrient())


# ------------------------------------------------------------------ input
## Gamepad shortcuts (Xbox layout). Digging / placing is handled by DigCursor.
func _on_pad_button(b: int) -> void:
	# paused: only Start (resume) and A on the focused resume button do anything
	if speed == 0.0 and _can_change_speed():
		if b == JOY_BUTTON_START:
			_toggle_pause()
		return
	match b:
		JOY_BUTTON_RIGHT_SHOULDER:
			if _can_change_speed():
				_cycle_speed()
		JOY_BUTTON_START:
			if _can_change_speed():
				_toggle_pause()
		JOY_BUTTON_Y:
			if phase == Phase.BUILD:
				_on_call_hero()
		JOY_BUTTON_LEFT_SHOULDER:
			if phase == Phase.INVASION:
				_toggle_follow()


func _cycle_speed() -> void:
	_set_speed(1.0 if speed == 0.0 or speed >= 3.0 else speed + 1.0)
	Sfx.play("click")


func _toggle_pause() -> void:
	_set_speed(_run_speed if speed == 0.0 else 0.0)
	Sfx.play("click")


## 0 pauses: everything in the dungeon freezes and the pause screen (monster roster) opens.
func _set_speed(s: float) -> void:
	speed = s
	if s > 0.0:
		_run_speed = s
		MonsterVisual.time_scale = s
	hud.set_speed(s)
	var pm := Node.PROCESS_MODE_DISABLED if s == 0.0 else Node.PROCESS_MODE_INHERIT
	for n in [layer, fx, hero, maou, cursor]:
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


func _try_dig(c: Vector2i) -> bool:
	if speed == 0.0:
		Sfx.play("dig_fail")
		hud.toast("一時停止中は掘れません", UiTheme.TEXT_DIM)
		return false
	if dig_left <= 0:
		Sfx.play("dig_fail")
		hud.toast("採掘可能数が残っていない！", UiTheme.WARN)
		return false
	if not grid.can_dig(c):
		Sfx.play("dig_fail")
		return false
	var n := grid.dig(c)
	dig_left -= 1
	cursor.swing()
	fx.debris(c, clampf(n / 12.0, 0.0, 1.0))
	cam.shake(0.35)
	Sfx.play("dig")
	var m := eco.spawn_from_dig(c, n)
	if m:
		hud.toast("%s が生まれた！" % m.display_name(), Color(0.6, 1.0, 0.4) if m.kind == Monster.Kind.MOSS else Color(1.0, 0.65, 0.3))
	_tip_timer = 0.0
	return true


func _cursor_color(c: Vector2i) -> Color:
	if phase == Phase.PLACE:
		return Color(0.86, 0.6, 1.0, 1.0) if _valid_place(c) else Color(1, 0.4, 0.32, 0.5)
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
	var active := (phase == Phase.BUILD or phase == Phase.PLACE or phase == Phase.INVASION or phase == Phase.ENDING) and speed != 0.0
	hud.set_pad_hint(Pad.using_pad and active)
	if not active or (not Pad.using_pad and get_viewport().gui_get_hovered_control() != null):
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
	if hero.visible and hero.state != Hero.State.DEAD:
		consider.call(hero, hero.global_position + Vector3(0, 0.45, 0))
	if maou.placed and maou.visible:
		consider.call(maou, maou.global_position + Vector3(0, 0.4, 0))
	var best: Object = pick["obj"]
	if best is Monster:
		return _monster_tip(best as Monster)
	if best == hero:
		var st := "[color=#ff8070]魔王を運搬中！[/color]" if hero.carrying else ("戦闘中" if hero.busy > 0.0 else "探索中")
		return "[img=24x24]%s[/img] [b]勇者 %s[/b]\nHP %s %d/%d\nMP %d/%d\n%s" % [profile.icon_path, profile.display_name, _bar(hero.hp, hero.max_hp, "#ff7060"), int(ceil(hero.hp)), int(hero.max_hp), int(hero.mp), int(hero.max_mp), st]
	if best == maou:
		return "[b][color=#d8a0ff]魔王さま[/color][/b]\n" + ("[color=#ff8070]勇者に運ばれている！[/color]" if maou.carrier else "勇者に入口まで運ばれると負け")
	return _cell_tip(cell)


func _bar(v: float, max_v: float, col: String) -> String:
	var n := int(round(clampf(v / maxf(1.0, max_v), 0.0, 1.0) * 10.0))
	return "[color=%s]%s[/color][color=#3a4150]%s[/color]" % [col, "■".repeat(n), "■".repeat(10 - n)]


func _monster_tip(m: Monster) -> String:
	var col := "#a8f070" if m.kind == Monster.Kind.MOSS else "#ffb060"
	var status := ""
	if m.kind == Monster.Kind.MOSS:
		match m.stage:
			Monster.MOSS:
				status = "養分を運びながら壁まで直進"
				if m.nutrient >= 2 and m.hp <= 6:
					status += "\n[color=#f0e070]もうすぐツボミになる[/color]"
			Monster.BUD:
				status = "開花まで 養分 %d / %d" % [m.nutrient, Balance.BUD_TARGET]
			Monster.FLOWER:
				status = "子を生むまで %d秒" % maxi(0, int(ceil(Balance.FLOWER_LIFE - m.age)))
	else:
		match m.stage:
			Monster.LARVA:
				status = "HP %d でサナギになる" % int(Balance.LARVA_PUPATE * (1.0 + 0.25 * eco.bug_level))
				if m.hp <= Balance.LARVA_HUNGRY * (1.0 + 0.25 * eco.bug_level):
					status += "　[color=#ffb060]空腹[/color]"
			Monster.PUPA:
				status = "羽化まで %d秒" % maxi(0, int(ceil((Balance.PUPA_TIME - maxf(0.0, m.timer)) / (1.0 + 0.15 * eco.bug_level))))
			Monster.ADULT:
				status = "産卵に必要な養分 %d / %d" % [m.nutrient, Balance.ADULT_LAY_NUTRIENT]
	return "[b][color=%s]%s[/color][/b]\nHP %s %d/%d\n養分 %d\n%s" % [col, m.display_name(), _bar(m.hp, m.max_hp, "#70e060"), int(ceil(m.hp)), int(m.max_hp), m.nutrient, status]


func _cell_tip(c: Vector2i) -> String:
	if not grid.in_bounds(c):
		return "[b]岩盤[/b]\n硬すぎて掘れない" if c.y > 0 else ""
	var t := grid.get_type(c)
	if t == DungeonGrid.BEDROCK:
		return "[b]岩盤[/b]\n硬すぎて掘れない" if c.y > 0 else ("[b]入口[/b]" if c == grid.entrance else "")
	if t == DungeonGrid.FLOOR:
		return "[b]入口[/b]\n勇者はここから侵入してくる" if c == grid.entrance else ""
	var n := grid.get_nutrient(c)
	var stage := Balance.soil_stage(n)
	var title: String = ["①", "②", "③", "④", "⑤"][stage] + " " + Balance.SOIL_NAMES[stage]
	title = "[color=%s]%s[/color]" % [["#e8d8c0", "#c8f090", "#98e070", "#e8d070", "#f0c060"][stage], title]
	var born := "何も生まれない"
	if n >= Balance.BUG_SPAWN_MIN:
		born = "[color=#ffa060]ザクザクムシ（ダンゴムシ）[/color]が生まれる"
	elif n >= Balance.MOSS_SPAWN_MIN:
		born = "[color=#a0f070]モコチュリ[/color]が生まれる"
	if stage < 4:
		born += "
[color=#b0a898]養分があと %d で次の段階へ[/color]" % (Balance.SOIL_STAGE_MIN[stage + 1] - n)
	var txt := "[b]%s[/b]\n養分 %s %d\n掘ると %s" % [title, _bar(n, Balance.MAX_NUTRIENT, "#c0ff80"), n, born]
	if not grid.can_dig(c):
		txt += "\n[color=#a0a0a0]通路に面していないので掘れない[/color]"
	return txt


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


func _debug_bootstrap() -> void:
	screens.hide_all()
	hud.set_visible_all(true)
	phase = Phase.BUILD
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
			hero.tick(0.05)
			invasion_time += 0.05
			tt += 0.05
		if _debug.has("report"):
			print("hero hp %d/%d  mp %d  cell %s carrying %s  time %.1f  monsters %d  phase %d" % [hero.hp, hero.max_hp, hero.mp, hero.cell, hero.carrying, invasion_time, eco.monsters.size(), phase])
	if _debug.has("cam"):
		var p: PackedStringArray = str(_debug["cam"]).split(",")
		cam.focus_on(Vector3(float(p[0]), 0, float(p[1])), true)
		if p.size() > 2:
			cam.zoom = float(p[2])
	if _debug.has("place"):
		_begin_place()
	if _debug.has("result"):
		_show_result()
	if _debug.has("title"):
		screens.show_title()
	if _debug.has("cutin"):
		cutin.play("勇者%sが現れた！" % profile.display_name, profile.intro_line, _hero_cutin.get_texture(), Color(0.8, 0.12, 0.1), 60.0)
	if _debug.has("angle"):
		add_child(load("res://scripts/debug/angle.gd").new())
	if _debug.has("dump"):
		add_child(load("res://scripts/debug/dump.gd").new())


func _debug_tick() -> void:
	if _debug.has("mouse_hero") and hero.visible:
		get_viewport().warp_mouse(cam.unproject_position(hero.global_position + Vector3(0, 0.45, 0)))
	if _debug.has("menutest"):
		_menutest()
	if _debug.has("padtest"):
		_padtest()
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
		cutin._t = 99.0
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
		print("MENUTEST ", _mt)
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


## Scripted Xbox-controller session: orbit camera, RB speed, X-hold tunnel digging, A placement.
func _padtest() -> void:
	var f := _frames
	if f == 20:
		_pt["yaw0"] = cam.yaw
		_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, -0.6)
	elif f == 60:
		_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
		_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_pt["yaw1"] = cam.yaw
		_pt["pitch1"] = rad_to_deg(cam.pitch)
		_pad_event(JOY_BUTTON_RIGHT_STICK, true)
		_pad_event(JOY_BUTTON_RIGHT_STICK, false)
	elif f == 90:
		_pt["yaw_reset"] = cam.yaw
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, true)
		_pad_event(JOY_BUTTON_RIGHT_SHOULDER, false)
		_pt["speed"] = speed
	elif f == 100:
		# start at the east end of the starter corridor and tunnel east holding X
		cursor.pad_cell = Vector2i(grid.entrance.x + 3, 5)
		_pt["speed_after_RB"] = speed
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
	elif f == 200:
		_pt["phase_after_Y"] = phase
		cursor.pad_cell = Vector2i(grid.entrance.x + 3, 8)
		_pad_event(JOY_BUTTON_A, true)
		_pad_event(JOY_BUTTON_A, false)
	elif f == 205:
		_pad_event(JOY_BUTTON_START, true)
		_pad_event(JOY_BUTTON_START, false)
	elif f == 208:
		_pt["paused_speed"] = speed
		_pt["dig_before_paused_dig"] = dig_left
		_on_click(Vector2i(grid.entrance.x + 4, 5))
		_pt["dig_after_paused_dig"] = dig_left
		_pad_event(JOY_BUTTON_START, true)
		_pad_event(JOY_BUTTON_START, false)
	elif f == 215:
		_pt["speed_after_unpause"] = speed
		_pt["maou_placed"] = maou.placed
		_pt["maou_cell"] = maou.cell
		print("PADTEST ", _pt)
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
			elif _auto_digs >= 45 and build_left < float(stage["build_time"]) - 60.0:
				_on_call_hero()
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
			get_tree().quit()
		Phase.DEFEAT:
			_screenshot("debug_shots/auto_defeat.png")
			print("AUTOPLAY RESULT defeat time %.1f" % invasion_time)
			get_tree().quit()


func _screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
