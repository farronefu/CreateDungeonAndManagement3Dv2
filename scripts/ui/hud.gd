class_name Hud
extends CanvasLayer
## In-game HUD. Kept light so the board stays visible:
##   top-left   status window: arrival timer / 魔王 placement / hero HP・MP
##   top-right  speed controls (x1, x2, x3); pausing is Start / P and opens the pause screen,
##              which lists the dungeon's monsters
##   bottom-left dig gauge (count + pip gauge)
## plus mouse/pad tooltip, prompts, toasts and the gamepad guide.

signal call_hero_pressed
signal resume_pressed
## 0.0 = paused
signal speed_changed(speed: float)

const SPEEDS := [1.0, 2.0, 3.0]

var root: Control
var _status: PanelContainer
var _message: Label
var _mp_text: Label
var _eco_labels := {}
var _soil_label: Label
# top centre
var _build_box: VBoxContainer
var _timer_caption: Label
var _timer_value: Label
var _call_btn: Button
var _hero_box: VBoxContainer
var _hero_portrait: TextureRect
var _hero_name: Label
var _hp_fill: PipBar
var _hp_text: Label
var _mp_fill: PipBar
var _elapsed: Label   # invasion clock, shown in the pause screen
# time controls
var _speed_btns: Array[IconButton] = []
var _pause_screen: Control
var _resume_btn: Button
# dig
var _dig_value: Label
var _dig_max: Label
var _dig_fill: PipBar
# misc
var _info: PanelContainer
var _info_label: RichTextLabel
var _prompt: PanelContainer
var _prompt_label: Label
var _toasts: VBoxContainer
var _studios: Array[PortraitStudio] = []
var _pad_hint: PanelContainer
var _t := 0.0


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)
	_build_status()
	_build_time_controls()
	_build_dig()
	_build_info()
	_build_prompt()
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.position = Vector2(-400, -230)
	_toasts.size = Vector2(800, 170)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)
	_build_pad_hint()
	_build_pause_screen()


func _studio(key: String, px: int, cam_pos: Vector3, look: Vector3, fov: float = 30.0, height: float = 0.0, yaw: float = 0.0) -> TextureRect:
	var s := PortraitStudio.new()
	add_child(s)
	var entry: Dictionary = MonsterCatalog.MODELS[key]
	s.setup(MonsterCatalog.scene(key), Vector2i(px, px), height, cam_pos, look, fov, bool(entry["fix_colors"]), [], (entry["anims"] as Dictionary).duplicate())
	s.actor.rotation.y = yaw
	s.freeze_after(4)
	_studios.append(s)
	var tr := TextureRect.new()
	tr.texture = s.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ------------------------------------------------------------------ pause screen (Start / P)
## Shown while the game is paused: which monsters live in the dungeon and how many.
func _build_pause_screen() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# swallows every click so only the resume button can be used
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	_pause_screen = dim
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var pc := PanelContainer.new()
	var sb := UiTheme.panel(UiTheme.INK_SOLID)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var title := UiTheme.heading("一時停止中", 48, UiTheme.GOLD)  # notice text stays gold
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_elapsed = UiTheme.label("侵攻 00:00", 28, UiTheme.TEXT)
	_elapsed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elapsed.visible = false
	vb.add_child(_elapsed)
	var sub := UiTheme.label("ダンジョンの生態系", 24, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var rows := [
		["moss", "モコチュリ", Vector3(0, 0.55, 0.9), Vector3(0, 0.22, 0), 0.45],
		["moss_flower", "ツボミ・モコバナ", Vector3(0, 0.62, 1.25), Vector3(0, 0.36, 0), 0.72],
		["bug_larva", "ザクザクムシ（幼虫）", Vector3(0.55, 0.62, 0.95), Vector3(0, 0.12, 0), 0.4],
		["bug_pupa", "ザクザクムシ（サナギ）", Vector3(0.55, 0.85, 1.35), Vector3(0, 0.14, 0), 0.4],
		["bug_adult", "ザクザクムシ（成虫）", Vector3(0.5, 0.62, 0.95), Vector3(0, 0.2, 0), 0.4],
	]
	for r in rows:
		var icon := _studio(r[0], 128, r[2], r[3], 30.0, r[4])
		icon.custom_minimum_size = Vector2(64, 64)
		grid.add_child(icon)
		var name_l := UiTheme.label(r[1], 24, UiTheme.TEXT)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		var cnt := UiTheme.heading("0 体", 32, UiTheme.TEXT)
		cnt.custom_minimum_size = Vector2(110, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(cnt)
		_eco_labels[r[0]] = cnt
	vb.add_child(HSeparator.new())
	_soil_label = UiTheme.label("土の養分 0", 24, Color(0.74, 0.86, 0.58))
	_soil_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_soil_label)
	_resume_btn = Button.new()
	_resume_btn.text = "再開する"
	_resume_btn.custom_minimum_size = Vector2(280, 52)
	_resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume_btn.pressed.connect(func() -> void:
		Sfx.play("click")
		resume_pressed.emit())
	vb.add_child(_resume_btn)
	var hint := UiTheme.label("Start ボタン / P キーでも再開", 16, UiTheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	dim.visible = false


func set_paused(p: bool) -> void:
	_pause_screen.visible = p
	if p:
		_info.visible = false
		_resume_btn.grab_focus.call_deferred()
	else:
		_resume_btn.release_focus()


func is_paused_screen() -> bool:
	return _pause_screen.visible


func update_eco(counts: Dictionary, soil: int) -> void:
	for k in counts:
		if _eco_labels.has(k):
			var l: Label = _eco_labels[k]
			l.text = "%d 体" % int(counts[k])
			l.modulate.a = 0.45 if int(counts[k]) == 0 else 1.0
	_soil_label.text = "土の養分 %d" % soil


# ------------------------------------------------------------------ top-left: status window
## One translucent black window in the top-left that changes with the phase:
##   build     time until the hero arrives + "call the hero" button
##   placement the instruction to place the 魔王
##   invasion  the hero's portrait, name, HP and MP (elapsed time is in the pause screen)
func _build_status() -> void:
	var pc := PanelContainer.new()
	var sb := UiTheme.dark_panel()
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	pc.position = Vector2(18, 16)
	pc.custom_minimum_size = Vector2(380, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	_status = pc
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	# build phase
	_build_box = VBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 4)
	vb.add_child(_build_box)
	# "勇者の到着まで 02:30" on one line
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 12)
	_build_box.add_child(timer_row)
	_timer_caption = UiTheme.label("勇者の到着まで", 22)
	_timer_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_row.add_child(_timer_caption)
	_timer_value = UiTheme.heading("02:30", 36, UiTheme.TEXT)
	_timer_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_row.add_child(_timer_value)
	_call_btn = Button.new()
	_call_btn.text = "勇者を呼ぶ（Y）"
	_call_btn.focus_mode = Control.FOCUS_NONE
	_call_btn.pressed.connect(func() -> void:
		Sfx.play("click")
		call_hero_pressed.emit())
	_build_box.add_child(_call_btn)
	# placement / other messages
	_message = UiTheme.label("", 24)
	_message.custom_minimum_size = Vector2(340, 0)
	vb.add_child(_message)
	# invasion: hero status
	_hero_box = VBoxContainer.new()
	_hero_box.add_theme_constant_override("separation", 4)
	vb.add_child(_hero_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_hero_box.add_child(top)
	_hero_portrait = TextureRect.new()
	_hero_portrait.custom_minimum_size = Vector2(64, 64)
	_hero_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_hero_portrait)
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	_hero_name = UiTheme.label("", 32)
	nv.add_child(_hero_name)
	var hp_row := _stat_row("HP", UiTheme.HP)
	_hp_text = hp_row[0]
	_hp_fill = hp_row[1]
	_hero_box.add_child(hp_row[2])
	var mp_row := _stat_row("MP", UiTheme.MP)
	_mp_text = mp_row[0]
	_mp_fill = mp_row[1]
	_hero_box.add_child(mp_row[2])
	_hero_box.visible = false
	_message.visible = false


const HP_CAUTION := Color(1.0, 0.86, 0.25)   # HP below half
const HP_DANGER := Color(1.0, 0.3, 0.26)     # HP below 30 %


func _stat_row(title: String, col: Color) -> Array:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var t := UiTheme.label(title, 24)
	t.custom_minimum_size = Vector2(40, 0)
	hb.add_child(t)
	var bar := PipBar.new(10, 13.0, col)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var v := UiTheme.label("0/0", 24)
	hb.add_child(v)
	return [v, bar, hb]


func set_hero(hname: String, portrait: Texture2D) -> void:
	_hero_name.text = hname
	_hero_portrait.texture = portrait


func update_hero(hp: float, max_hp: float, mp: float, max_mp: float, _show: bool = true) -> void:
	var r := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	_hp_fill.ratio = r
	var hp_col := UiTheme.TEXT
	if r < 0.3:
		hp_col = HP_DANGER
	elif r < 0.5:
		hp_col = HP_CAUTION
	_hp_text.add_theme_color_override("font_color", hp_col)
	_hp_fill.set_color(UiTheme.HP if r >= 0.5 else hp_col)
	_hp_text.text = "%d/%d" % [maxi(0, int(ceil(hp))), int(max_hp)]
	_mp_fill.ratio = clampf(mp / maxf(1.0, max_mp), 0.0, 1.0)
	_mp_text.text = "%d/%d" % [int(mp), int(max_mp)]


## mode: "build" (caption + clock + call button), "message" (text only), "hero" (hero status)
func update_phase(mode: String, caption: String, time_text: String, can_call: bool) -> void:
	_build_box.visible = mode == "build"
	_hero_box.visible = mode == "hero"
	_timer_caption.text = caption
	_timer_value.text = time_text
	_call_btn.visible = can_call
	_elapsed.text = "侵攻 " + time_text
	_elapsed.visible = mode == "hero"
	if mode == "message":
		_message.text = caption
	_message.visible = mode == "message"


# ------------------------------------------------------------------ top-right: time controls
func _build_time_controls() -> void:
	var pc := PanelContainer.new()
	var sb := UiTheme.dark_chip()   # same frame as the status window (arrival timer)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.position = Vector2(-186, 16)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	pc.add_child(hb)
	var kinds := ["play1", "play2", "play3"]
	for i in SPEEDS.size():
		var b := IconButton.new(kinds[i])
		b.button_pressed = SPEEDS[i] == 1.0
		b.tooltip_text = "速度 x%d (RB)" % int(SPEEDS[i])
		b.pressed.connect(_on_speed.bind(SPEEDS[i]))
		hb.add_child(b)
		_speed_btns.append(b)


func _on_speed(s: float) -> void:
	set_speed(s)
	Sfx.play("click")
	speed_changed.emit(s)


## Reflects the current speed (0 = paused).
func set_speed(s: float) -> void:
	for i in _speed_btns.size():
		_speed_btns[i].button_pressed = is_equal_approx(SPEEDS[i], s)
	set_paused(s == 0.0)


# ------------------------------------------------------------------ bottom-left: dig gauge
const DIG_YELLOW := Color(1.0, 0.82, 0.12)   # matches the yellow of the dig icon (assets/ui/dig_icon.png)

func _build_dig() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.panel())
	pc.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pc.position = Vector2(18, -108)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/dig_icon.png")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	_dig_value = UiTheme.heading("100", 30, DIG_YELLOW, 900)
	row.add_child(_dig_value)
	_dig_max = UiTheme.label("/ 100", 15, DIG_YELLOW)
	_dig_max.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(_dig_max)
	_dig_fill = PipBar.new(10, 12.0, UiTheme.GOLD)
	vb.add_child(_dig_fill)


func update_dig(left: int, max_dig: int) -> void:
	var ratio := float(left) / maxf(1.0, max_dig)
	_dig_fill.ratio = ratio
	_dig_fill.set_color(UiTheme.GOLD if ratio >= 0.2 else UiTheme.WARN)
	_dig_value.text = str(left)
	_dig_value.add_theme_color_override("font_color", DIG_YELLOW if ratio >= 0.2 else UiTheme.WARN)
	_dig_max.text = "/ %d" % max_dig
	_dig_max.add_theme_color_override("font_color", DIG_YELLOW if ratio >= 0.2 else UiTheme.WARN)


# ------------------------------------------------------------------ tooltip / prompt / toast / pad guide
func _build_info() -> void:
	_info = PanelContainer.new()
	_info.top_level = true
	var sb := UiTheme.panel(UiTheme.INK_SOLID)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	_info.add_theme_stylebox_override("panel", sb)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_label.scroll_active = false
	_info_label.add_theme_font_size_override("normal_font_size", UiTheme.px(17))
	_info_label.add_theme_font_override("normal_font", UiTheme.font())
	_info_label.add_theme_font_override("bold_font", UiTheme.serif(800))
	_info_label.add_theme_font_size_override("bold_font_size", UiTheme.px(19))
	_info_label.add_theme_constant_override("line_separation", 2)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_info_label)
	_info.visible = false


## Small popup next to the mouse / pad cursor.
func show_tooltip(bbcode: String, mouse_pos: Vector2) -> void:
	if bbcode == "":
		_info.visible = false
		return
	if _info_label.text != bbcode:
		_info_label.text = bbcode
		_info.reset_size()
	_info.visible = true
	var vp := root.get_viewport_rect().size
	var sz := _info.get_combined_minimum_size()
	var p := mouse_pos + Vector2(24, 20)
	if p.x + sz.x > vp.x - 8:
		p.x = mouse_pos.x - sz.x - 16
	if p.y + sz.y > vp.y - 8:
		p.y = mouse_pos.y - sz.y - 12
	_info.position = p


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", UiTheme.chip(Color(0.16, 0.06, 0.2, 0.86), Color(0.9, 0.65, 1.0, 0.8)))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt.position = Vector2(-360, 150)
	_prompt.custom_minimum_size = Vector2(720, 0)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt)
	_prompt_label = UiTheme.heading("", 22, UiTheme.TEXT, 700)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_child(_prompt_label)
	_prompt.visible = false


func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt_label.text = text


func toast(text: String, color: Color = UiTheme.TEXT) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.chip(Color(0.06, 0.045, 0.035, 0.72), Color(color, 0.45)))
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(text, 19, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	_toasts.add_child(pc)
	if _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.4)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)


func _build_pad_hint() -> void:
	_pad_hint = PanelContainer.new()
	_pad_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pad_hint.position = Vector2(-480, -50)
	_pad_hint.custom_minimum_size = Vector2(960, 0)
	_pad_hint.add_theme_stylebox_override("panel", UiTheme.chip(Color(0.05, 0.04, 0.03, 0.7)))
	_pad_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", UiTheme.font(true))
	l.add_theme_font_size_override("normal_font_size", UiTheme.px(16))
	l.text = "[center][color=#6fd06f]A[/color] 掘る・決定（押しながら十字で連続）　[color=#f0c040]Y[/color] 勇者を呼ぶ　[color=#d8d0c0]RB[/color] 速度　[color=#d8d0c0]Start[/color] 一時停止・生態系　[color=#d8d0c0]LB[/color] 勇者追跡　[color=#d8d0c0]Rスティック[/color] カメラ移動（LT+で回転）　[color=#6fa8ff]X[/color] ズーム[/center]"
	_pad_hint.add_child(l)
	_pad_hint.visible = false
	root.add_child(_pad_hint)


func set_pad_hint(v: bool) -> void:
	_pad_hint.visible = v
	_toasts.position.y = -270.0 if v else -230.0


func set_visible_all(v: bool) -> void:
	root.visible = v
