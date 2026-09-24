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
var follow_hero := true

var _hero_portrait: Texture2D
var _hero_cutin: PortraitStudio
var _maou_cutin: PortraitStudio
var _hud_timer := 0.0
var _debug := {}
var _frames := 0


func _ready() -> void:
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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.49, 0.75, 0.93)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.6, 0.56)
	env.ambient_light_energy = 0.58
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.rotation_degrees = Vector3(-58, -28, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 0.9)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill)


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
	eco.hero = hero
	hero.died.connect(_on_hero_died)
	hero.escaped_with_maou.connect(_on_defeat)
	hero.picked_up_maou.connect(func() -> void:
		hud.toast("魔王が捕まった！入口に連れて行かれる前に勇者を倒せ！", UiTheme.WARN)
		follow_hero = true
		Sfx.play("dig_fail"))
	cam = GameCamera.new()
	add_child(cam)
	cam.set_bounds(Rect2(4, -1.5, grid.w - 8, grid.h - 3.5))
	cam.focus_on(DungeonGrid.cell_center(grid.entrance) + Vector3(-1, 0, 4.5), true)
	cam.current = true
	cursor = DigCursor.new()
	add_child(cursor)
	cursor.grid = grid
	cursor.view = view
	cursor.camera = cam
	cursor.validator = _cursor_color
	cursor.clicked.connect(_on_click)
	cursor.hovered.connect(_on_hover)
	dig_max = GameState.dig_capacity()
	dig_left = dig_max
	build_left = float(stage["build_time"])


func _build_ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.call_hero_pressed.connect(_on_call_hero)
	hud.speed_changed.connect(func(s: float) -> void: speed = s)
	hud.set_stage("STAGE %d  %s" % [GameState.stage_index + 1, stage["name"]])
	var hero_scene := load(profile.model_path) as PackedScene
	var portrait := PortraitStudio.new()
	add_child(portrait)
	portrait.setup(hero_scene, Vector2i(160, 160), 1.0, Vector3(0.05, 0.84, 0.62), Vector3(0, 0.78, 0), 30.0)
	portrait.freeze_after(4)
	_hero_portrait = portrait.get_texture()
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
	hud.set_visible_all(true)
	Sfx.play_bgm("build")
	_hero_cutin.actor.play(profile.anim_idle, 0.0)
	await _cutin("勇者%sがやってくる！" % profile.display_name, "到着まであと%d秒。ダンジョンを掘って魔物を育てよう" % int(build_left), _hero_cutin.get_texture(), Color(0.75, 0.2, 0.12))
	_begin_build()


func _begin_build() -> void:
	phase = Phase.BUILD
	cursor.mode = DigCursor.Mode.DIG
	hud.toast("通路につながったブロックをクリックして掘ろう", UiTheme.GOLD)


func _on_call_hero() -> void:
	if phase == Phase.BUILD:
		_begin_place()


func _begin_place() -> void:
	phase = Phase.PLACE
	cursor.mode = DigCursor.Mode.PLACE
	hud.set_prompt("魔王を置く場所をクリック（入口から4マス以上離れた通路）")
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
	hud.set_prompt("")
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
	hud.toast("侵攻中も掘れる！ 新しい通路で勇者を迷わせよう", UiTheme.GOLD)
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
	var time_bonus := maxi(0, Balance.EP_TIME_BONUS_MAX - int(invasion_time / Balance.EP_TIME_STEP))
	var dig_bonus := dig_left * Balance.EP_PER_DIG_LEFT
	var total := Balance.EP_BASE + time_bonus + dig_bonus
	GameState.evolution_points += total
	screens.show_result({"rows": [
		["ステージクリア", "", Balance.EP_BASE],
		["撃退タイム", _fmt_time(invasion_time), time_bonus],
		["残り採掘可能数", "%d / %d" % [dig_left, dig_max], dig_bonus],
	]})


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
		Phase.ENDING, Phase.RESULT:
			eco.tick(delta)
			hero.tick(delta)
	cam.user_moved = false
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
			hud.update_phase("建設フェーズ", "勇者到着まで " + _fmt_time(build_left), phase == Phase.BUILD)
		Phase.PLACE, Phase.HERO_INTRO:
			hud.update_phase("魔王配置", "--:--", false)
		_:
			hud.update_phase("勇者侵攻中！" if phase == Phase.INVASION else "決着", "経過 " + _fmt_time(invasion_time), false)
	hud.update_eco({
		"moss": eco.count(Monster.Kind.MOSS, Monster.MOSS),
		"moss_flower": eco.count(Monster.Kind.MOSS, Monster.BUD) + eco.count(Monster.Kind.MOSS, Monster.FLOWER),
		"bug_larva": eco.count(Monster.Kind.BUG, Monster.LARVA),
		"bug_pupa": eco.count(Monster.Kind.BUG, Monster.PUPA),
		"bug_adult": eco.count(Monster.Kind.BUG, Monster.ADULT),
	}, grid.total_nutrient())


# ------------------------------------------------------------------ input
func _on_click(c: Vector2i) -> void:
	match phase:
		Phase.BUILD, Phase.INVASION:
			_try_dig(c)
		Phase.PLACE:
			_try_place(c)


func _try_dig(c: Vector2i) -> bool:
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
	_on_hover(c)
	return true


func _cursor_color(c: Vector2i) -> Color:
	if phase == Phase.PLACE:
		return Color(0.85, 0.45, 1.0, 1.0) if _valid_place(c) else Color(1, 0.25, 0.2, 0.45)
	if grid.is_floor(c):
		return Color(0, 0, 0, 0)
	if grid.can_dig(c) and dig_left > 0:
		var n := grid.get_nutrient(c)
		if n >= Balance.BUG_SPAWN_MIN:
			return Color(1.0, 0.45, 0.2, 1.0)
		if n >= Balance.MOSS_SPAWN_MIN:
			return Color(0.55, 1.0, 0.3, 1.0)
		return Color(1.0, 0.8, 0.45, 1.0)
	return Color(1.0, 0.25, 0.2, 0.5)


func _on_hover(c: Vector2i) -> void:
	if not grid.in_bounds(c):
		hud.show_cell_info("")
		return
	var t := grid.get_type(c)
	var txt := ""
	if t == DungeonGrid.BEDROCK:
		txt = "[b]岩盤[/b]\n硬すぎて掘れない"
	elif t == DungeonGrid.BLOCK:
		var n := grid.get_nutrient(c)
		var born := "何も生まれない"
		if n >= Balance.BUG_SPAWN_MIN:
			born = "[color=#ffa060]ザクザクムシ[/color]が生まれる"
		elif n >= Balance.MOSS_SPAWN_MIN:
			born = "[color=#a0f070]モコゴケ[/color]が生まれる"
		txt = "[b]土ブロック[/b]　養分 [color=#c0ff80]%d[/color]\n掘ると %s" % [n, born]
		if not grid.can_dig(c):
			txt += "\n[color=#a0a0a0]（通路に面していないので掘れない）[/color]"
	else:
		txt = "[b]通路[/b]"
		if c == grid.entrance:
			txt += "（入口）"
		if maou.placed and maou.cell == c:
			txt += "\n[color=#d090ff]魔王さま[/color]"
		for m in eco.monsters:
			if m.cell == c:
				txt += "\n%s  HP %d/%d  養分 %d" % [m.display_name(), int(m.hp), int(m.max_hp), m.nutrient]
	hud.show_cell_info(txt)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_SPACE and phase == Phase.BUILD:
			_on_call_hero()
		elif k.keycode == KEY_F and phase == Phase.INVASION:
			follow_hero = not follow_hero
			hud.toast("勇者を追跡中" if follow_hero else "追跡を解除", UiTheme.TEXT)
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
		speed = float(_debug["speed"])
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
	if _debug.has("dump"):
		add_child(load("res://scripts/debug/dump.gd").new())
	if _debug.has("hover"):
		var p2: PackedStringArray = str(_debug["hover"]).split(",")
		_on_hover(Vector2i(int(p2[0]), int(p2[1])))


func _debug_tick() -> void:
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
			speed = 3.0
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
			speed = 3.0
		Phase.RESULT:
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
