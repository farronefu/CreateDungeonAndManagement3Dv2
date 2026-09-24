class_name Hud
extends CanvasLayer
## In-game HUD. Kept light so the board stays visible:
##   top-left   stage chip + ecosystem roster (icon, count, name)
##   top-centre build: arrival timer + call button / invasion: hero plate
##   top-right  time controls (pause, x1, x2, x3)
##   bottom-left dig gauge
## plus mouse/pad tooltip, prompts, toasts and the gamepad guide.

signal call_hero_pressed
## 0.0 = paused
signal speed_changed(speed: float)

const SPEEDS := [0.0, 1.0, 2.0, 3.0]

var root: Control
var _stage_label: Label
var _eco_labels := {}
var _soil_label: Label
# top centre
var _build_box: Control
var _timer_caption: Label
var _timer_value: Label
var _call_btn: Button
var _hero_box: Control
var _hero_portrait: TextureRect
var _hero_name: Label
var _hp_fill: ColorRect
var _hp_back: ColorRect
var _hp_text: Label
var _mp_fill: ColorRect
var _elapsed: Label
var _hp_shown := 1.0
# time controls
var _speed_btns: Array[IconButton] = []
var _paused_banner: Control
# dig
var _dig_value: Label
var _dig_max: Label
var _dig_fill: ColorRect
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
	_build_left()
	_build_center()
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
	_build_paused_banner()


func _studio(key: String, px: int, cam_pos: Vector3, look: Vector3, fov: float = 30.0, height: float = 0.0) -> TextureRect:
	var s := PortraitStudio.new()
	add_child(s)
	var entry: Dictionary = MonsterCatalog.MODELS[key]
	s.setup(MonsterCatalog.scene(key), Vector2i(px, px), height, cam_pos, look, fov, bool(entry["fix_colors"]), [], (entry["anims"] as Dictionary).duplicate())
	s.freeze_after(4)
	_studios.append(s)
	var tr := TextureRect.new()
	tr.texture = s.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _bar(w: float, h: float, col: Color) -> Array:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.custom_minimum_size = Vector2(w, h)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(w, h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.16)
	shine.size = Vector2(w, maxf(1.0, h * 0.35))
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(shine)
	return [back, fill]


# ------------------------------------------------------------------ top-left: stage + ecosystem
func _build_left() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(18, 16)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UiTheme.chip())
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_label = UiTheme.heading("STAGE 1", 19, UiTheme.GOLD, 700)
	chip.add_child(_stage_label)
	col.add_child(chip)
	var pc := PanelContainer.new()
	var sb := UiTheme.panel()
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	pc.add_child(vb)
	var rows := [
		["moss", "モコゴケ", Vector3(0, 0.55, 0.9), Vector3(0, 0.22, 0), 0.45],
		["moss_flower", "ツボミ・モコバナ", Vector3(0, 0.62, 1.25), Vector3(0, 0.36, 0), 0.72],
		["bug_larva", "ザクザクムシ幼虫", Vector3(0.55, 0.62, 0.95), Vector3(0, 0.12, 0), 0.4],
		["bug_pupa", "サナギ", Vector3(0.35, 0.55, 0.8), Vector3(0, 0.12, 0), 0.4],
		["bug_adult", "成虫", Vector3(0.45, 0.65, 0.8), Vector3(0, 0.22, 0), 0.0],
	]
	for r in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var icon := _studio(r[0], 96, r[2], r[3], 30.0, r[4])
		icon.custom_minimum_size = Vector2(40, 40)
		hb.add_child(icon)
		var cnt := UiTheme.heading("0", 24, UiTheme.TEXT, 800)
		cnt.custom_minimum_size = Vector2(38, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(cnt)
		var name_l := UiTheme.label(r[1], 15, UiTheme.TEXT_DIM)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(name_l)
		_eco_labels[r[0]] = cnt
		vb.add_child(hb)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_soil_label = UiTheme.label("土の養分 0", 15, Color(0.74, 0.86, 0.58))
	vb.add_child(_soil_label)


func set_stage(text: String) -> void:
	_stage_label.text = text


func update_eco(counts: Dictionary, soil: int) -> void:
	for k in counts:
		if _eco_labels.has(k):
			var l: Label = _eco_labels[k]
			l.text = str(counts[k])
			l.modulate.a = 0.45 if int(counts[k]) == 0 else 1.0
	_soil_label.text = "土の養分 %d" % soil


# ------------------------------------------------------------------ top-centre: timer / hero plate
func _build_center() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(anchor)
	# build phase: arrival timer + call button
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", UiTheme.panel())
	bp.mouse_filter = Control.MOUSE_FILTER_STOP
	bp.position = Vector2(-150, 14)
	bp.custom_minimum_size = Vector2(300, 0)
	anchor.add_child(bp)
	_build_box = bp
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	bp.add_child(vb)
	_timer_caption = UiTheme.label("勇者の到着まで", 15, UiTheme.TEXT_DIM)
	_timer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_timer_caption)
	_timer_value = UiTheme.heading("02:30", 40, UiTheme.TEXT, 900)
	_timer_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_timer_value)
	_call_btn = Button.new()
	_call_btn.text = "勇者を呼ぶ"
	_call_btn.focus_mode = Control.FOCUS_NONE
	_call_btn.add_theme_font_size_override("font_size", UiTheme.px(19))
	_call_btn.pressed.connect(func() -> void:
		Sfx.play("click")
		call_hero_pressed.emit())
	vb.add_child(_call_btn)
	# invasion: hero plate
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.12, 0.04, 0.03, 0.84), Color(0.9, 0.45, 0.32, 0.6)))
	hp.mouse_filter = Control.MOUSE_FILTER_STOP
	hp.position = Vector2(-270, 14)
	hp.custom_minimum_size = Vector2(540, 0)
	anchor.add_child(hp)
	_hero_box = hp
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hp.add_child(hb)
	_hero_portrait = TextureRect.new()
	_hero_portrait.custom_minimum_size = Vector2(64, 64)
	_hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(_hero_portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(info)
	var top := HBoxContainer.new()
	info.add_child(top)
	_hero_name = UiTheme.heading("勇者", 22, UiTheme.TEXT, 800)
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_hero_name)
	_elapsed = UiTheme.label("00:00", 16, UiTheme.TEXT_DIM)
	top.add_child(_elapsed)
	var hpb := _bar(420, 16, UiTheme.HP)
	_hp_back = hpb[0]
	_hp_fill = hpb[1]
	_hp_back.color = Color(0.3, 0.05, 0.03, 0.8)
	info.add_child(_hp_back)
	_hp_text = UiTheme.label("", 13, UiTheme.TEXT, true)
	_hp_text.position = Vector2(6, -2)
	_hp_text.add_theme_constant_override("outline_size", 4)
	_hp_back.add_child(_hp_text)
	var mpb := _bar(420, 5, UiTheme.MP)
	_mp_fill = mpb[1]
	info.add_child(mpb[0])
	_hero_box.visible = false


func set_hero(hname: String, portrait: Texture2D) -> void:
	_hero_name.text = "勇者 " + hname
	_hero_portrait.texture = portrait


func update_hero(hp: float, max_hp: float, mp: float, max_mp: float, show: bool) -> void:
	_hero_box.visible = show
	_build_box.visible = not show
	var r := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	_hp_shown = r
	_hp_fill.size.x = 420.0 * r
	_hp_fill.color = UiTheme.HP if r > 0.3 else UiTheme.WARN
	_hp_text.text = "%d / %d" % [maxi(0, int(ceil(hp))), int(max_hp)]
	_mp_fill.size.x = 420.0 * clampf(mp / maxf(1.0, max_mp), 0.0, 1.0)


## title: phase caption, time_text: big clock text
func update_phase(title: String, time_text: String, can_call: bool) -> void:
	_timer_caption.text = title
	_timer_value.text = time_text
	_elapsed.text = time_text
	_call_btn.visible = can_call


# ------------------------------------------------------------------ top-right: time controls
func _build_time_controls() -> void:
	var pc := PanelContainer.new()
	var sb := UiTheme.chip()
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.position = Vector2(-236, 16)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	pc.add_child(hb)
	var kinds := ["pause", "play1", "play2", "play3"]
	for i in SPEEDS.size():
		var b := IconButton.new(kinds[i])
		b.button_pressed = SPEEDS[i] == 1.0
		b.tooltip_text = "一時停止 (P / Start)" if i == 0 else "速度 x%d (RB)" % int(SPEEDS[i])
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
	_paused_banner.visible = s == 0.0


func _build_paused_banner() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.chip(Color(0.05, 0.04, 0.03, 0.78), Color(0.95, 0.8, 0.5, 0.8)))
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.position = Vector2(-110, -250)
	pc.custom_minimum_size = Vector2(220, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.heading("一時停止中", 26, UiTheme.GOLD, 800)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	pc.visible = false
	root.add_child(pc)
	_paused_banner = pc


# ------------------------------------------------------------------ bottom-left: dig gauge
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
	var icon := _studio("pickaxe", 128, Vector3(0.0, 0.42, 1.25), Vector3(0, 0.38, 0), 34.0)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.rotation = -0.5
	icon.pivot_offset = Vector2(32, 32)
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	row.add_child(UiTheme.label("掘れる回数", 15, UiTheme.TEXT_DIM))
	_dig_value = UiTheme.heading("100", 30, UiTheme.TEXT, 900)
	row.add_child(_dig_value)
	_dig_max = UiTheme.label("/ 100", 15, UiTheme.TEXT_DIM)
	_dig_max.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(_dig_max)
	var bar := _bar(220, 8, UiTheme.GOLD)
	_dig_fill = bar[1]
	vb.add_child(bar[0])


func update_dig(left: int, max_dig: int) -> void:
	var ratio := float(left) / maxf(1.0, max_dig)
	_dig_fill.size.x = 220.0 * ratio
	_dig_fill.color = UiTheme.GOLD if ratio >= 0.2 else UiTheme.WARN
	_dig_value.text = str(left)
	_dig_value.add_theme_color_override("font_color", UiTheme.TEXT if ratio >= 0.2 else UiTheme.WARN)
	_dig_max.text = "/ %d" % max_dig


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
	l.text = "[center][color=#6fd06f]A[/color] 掘る・決定（押しながら十字で連続）　[color=#f0c040]Y[/color] 勇者を呼ぶ　[color=#d8d0c0]RB[/color] 速度　[color=#d8d0c0]Start[/color] 一時停止　[color=#d8d0c0]LB[/color] 勇者追跡　[color=#d8d0c0]Rスティック[/color] カメラ[/center]"
	_pad_hint.add_child(l)
	_pad_hint.visible = false
	root.add_child(_pad_hint)


func set_pad_hint(v: bool) -> void:
	_pad_hint.visible = v
	_toasts.position.y = -270.0 if v else -230.0


func set_visible_all(v: bool) -> void:
	root.visible = v
