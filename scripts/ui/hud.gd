class_name Hud
extends CanvasLayer
## In-game HUD: hero status bar, phase/timer panel, ecosystem panel, dig gauge, cell info,
## prompts and toasts.

signal call_hero_pressed
signal speed_changed(speed: float)

var root: Control
var _hero_portrait: TextureRect
var _hero_name: Label
var _hp_val: Label
var _mp_val: Label
var _hp_bar: ColorRect
var _mp_bar: ColorRect
var _hero_box: Control
var _stage_label: Label
var _phase_title: Label
var _phase_time: Label
var _call_btn: Button
var _speed_btns: Array[Button] = []
var _eco_labels := {}
var _soil_label: Label
var _dig_segments: Array[Panel] = []
var _dig_label: Label
var _info: PanelContainer
var _info_label: RichTextLabel
var _prompt: PanelContainer
var _prompt_label: Label
var _toasts: VBoxContainer
var _seg_on: StyleBoxFlat
var _seg_warn: StyleBoxFlat
var _seg_off: StyleBoxFlat
var _studios: Array[PortraitStudio] = []


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)
	_build_top_bar()
	_build_phase_panel()
	_build_eco_panel()
	_build_dig_panel()
	_build_info()
	_build_prompt()
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.position = Vector2(-300, -210)
	_toasts.size = Vector2(600, 160)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func _studio(key: String, px: int, cam_pos: Vector3, look: Vector3, fov: float = 30.0) -> TextureRect:
	var s := PortraitStudio.new()
	add_child(s)
	s.setup(MonsterCatalog.scene(key), Vector2i(px, px), 0.0, cam_pos, look, fov, true)
	s.freeze_after(4)
	_studios.append(s)
	var tr := TextureRect.new()
	tr.texture = s.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ------------------------------------------------------------------ top bar
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.13, 0.26, 0.93)
	sb.border_color = UiTheme.GOLD_DARK
	sb.border_width_bottom = 3
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 64)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)
	_hero_box = HBoxContainer.new()
	_hero_box.add_theme_constant_override("separation", 10)
	hb.add_child(_hero_box)
	_hero_portrait = TextureRect.new()
	_hero_portrait.custom_minimum_size = Vector2(56, 56)
	_hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_box.add_child(_hero_portrait)
	_hero_name = UiTheme.label("勇者", 26, UiTheme.TEXT, true)
	_hero_box.add_child(_hero_name)
	var hp := _stat_block("HP", UiTheme.HP)
	_hp_val = hp[0]
	_hp_bar = hp[1]
	_hero_box.add_child(hp[2])
	var mp := _stat_block("MP", UiTheme.MP)
	_mp_val = mp[0]
	_mp_bar = mp[1]
	_hero_box.add_child(mp[2])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	_stage_label = UiTheme.label("STAGE 1", 24, UiTheme.GOLD, true)
	_stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_stage_label)


func _stat_block(title: String, col: Color) -> Array:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.label(title, 22, col, true))
	var val := UiTheme.label("0/0", 24, UiTheme.TEXT, true)
	val.custom_minimum_size = Vector2(110, 0)
	row.add_child(val)
	vb.add_child(row)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.custom_minimum_size = Vector2(150, 6)
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(150, 6)
	bg.add_child(fill)
	vb.add_child(bg)
	return [val, fill, vb]


func set_hero(hname: String, portrait: Texture2D) -> void:
	_hero_name.text = hname
	_hero_portrait.texture = portrait


func update_hero(hp: float, max_hp: float, mp: float, max_mp: float, show: bool) -> void:
	_hero_box.modulate.a = 1.0 if show else 0.35
	_hp_val.text = "%d/%d" % [maxi(0, int(ceil(hp))), int(max_hp)]
	_mp_val.text = "%d/%d" % [int(mp), int(max_mp)]
	_hp_bar.size.x = 150.0 * clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	_mp_bar.size.x = 150.0 * clampf(mp / maxf(1.0, max_mp), 0.0, 1.0)
	_hp_bar.color = UiTheme.HP if hp > max_hp * 0.3 else UiTheme.WARN


func set_stage(text: String) -> void:
	_stage_label.text = text


# ------------------------------------------------------------------ phase panel
func _build_phase_panel() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.position = Vector2(-370, 78)
	pc.custom_minimum_size = Vector2(350, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	_phase_title = UiTheme.label("建設フェーズ", 22, UiTheme.GOLD, true)
	_phase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_phase_title)
	_phase_time = UiTheme.label("02:30", 32, UiTheme.TEXT, true)
	_phase_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_phase_time)
	_call_btn = Button.new()
	_call_btn.text = "勇者を呼ぶ"
	_call_btn.pressed.connect(func() -> void:
		Sfx.play("click")
		call_hero_pressed.emit())
	vb.add_child(_call_btn)
	var sp := HBoxContainer.new()
	sp.alignment = BoxContainer.ALIGNMENT_CENTER
	sp.add_theme_constant_override("separation", 6)
	vb.add_child(sp)
	var lbl := UiTheme.label("速度", 18)
	sp.add_child(lbl)
	for s in [1.0, 2.0, 3.0]:
		var b := Button.new()
		b.text = "x%d" % int(s)
		b.toggle_mode = true
		b.button_pressed = s == 1.0
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(62, 34)
		b.pressed.connect(_on_speed.bind(s, b))
		sp.add_child(b)
		_speed_btns.append(b)


func _on_speed(s: float, btn: Button) -> void:
	for b in _speed_btns:
		b.button_pressed = b == btn
	Sfx.play("click")
	speed_changed.emit(s)


func update_phase(title: String, time_text: String, can_call: bool) -> void:
	_phase_title.text = title
	_phase_time.text = time_text
	_call_btn.visible = can_call


# ------------------------------------------------------------------ ecosystem panel
func _build_eco_panel() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pc.position = Vector2(14, 78)
	pc.custom_minimum_size = Vector2(290, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)
	vb.add_child(UiTheme.label("ダンジョンの生態系", 20, UiTheme.GOLD, true))
	var rows := [
		["moss", "モコゴケ", Vector3(0, 0.55, 0.75), Vector3(0, 0.2, 0)],
		["moss_flower", "ツボミ / モコバナ", Vector3(0, 0.75, 0.95), Vector3(0, 0.38, 0)],
		["bug_larva", "ザクザクムシ 幼虫", Vector3(0.35, 0.5, 0.75), Vector3(0, 0.12, 0.02)],
		["bug_pupa", "ザクザクムシ サナギ", Vector3(0, 0.5, 0.95), Vector3(0, 0.22, 0)],
		["bug_adult", "ザクザクムシ 成虫", Vector3(0.45, 0.65, 0.8), Vector3(0, 0.22, 0)],
	]
	for r in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var icon := _studio(r[0], 96, r[2], r[3])
		icon.custom_minimum_size = Vector2(44, 44)
		hb.add_child(icon)
		var name_l := UiTheme.label(r[1], 19)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(name_l)
		var cnt := UiTheme.label("0", 24, UiTheme.TEXT, true)
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(cnt)
		_eco_labels[r[0]] = cnt
		vb.add_child(hb)
	_soil_label = UiTheme.label("土の養分: 0", 18, Color(0.75, 0.9, 0.6))
	vb.add_child(_soil_label)


func update_eco(counts: Dictionary, soil: int) -> void:
	for k in counts:
		if _eco_labels.has(k):
			_eco_labels[k].text = str(counts[k])
	_soil_label.text = "土の養分: %d" % soil


# ------------------------------------------------------------------ dig gauge
func _build_dig_panel() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pc.position = Vector2(16, -150)
	pc.custom_minimum_size = Vector2(430, 128)
	pc.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.06, 0.08, 0.12, 0.92), Color(0.5, 0.52, 0.58), 8, 3))
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	var icon := _studio("pickaxe", 128, Vector3(0.0, 0.42, 1.25), Vector3(0, 0.38, 0), 34.0)
	icon.custom_minimum_size = Vector2(92, 92)
	icon.rotation = -0.5
	icon.pivot_offset = Vector2(46, 46)
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	vb.add_child(UiTheme.label("採掘可能数", 22, UiTheme.TEXT, true))
	var segs := HBoxContainer.new()
	segs.add_theme_constant_override("separation", 3)
	vb.add_child(segs)
	_seg_on = StyleBoxFlat.new()
	_seg_on.bg_color = Color(1.0, 0.72, 0.18)
	_seg_on.border_color = Color(1.0, 0.9, 0.55)
	_seg_on.border_width_top = 2
	_seg_warn = _seg_on.duplicate()
	_seg_warn.bg_color = Color(1.0, 0.35, 0.2)
	_seg_off = StyleBoxFlat.new()
	_seg_off.bg_color = Color(0.12, 0.16, 0.24)
	_seg_off.border_color = Color(0.25, 0.3, 0.4)
	_seg_off.set_border_width_all(1)
	for i in 10:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(26, 24)
		p.add_theme_stylebox_override("panel", _seg_off)
		segs.add_child(p)
		_dig_segments.append(p)
	_dig_label = UiTheme.label("残り 100 / 100", 26, UiTheme.TEXT, true)
	vb.add_child(_dig_label)


func update_dig(left: int, max_dig: int) -> void:
	var ratio := float(left) / maxf(1.0, max_dig)
	var filled := int(ceil(ratio * 10.0 - 0.001))
	for i in 10:
		var on := i < filled
		_dig_segments[i].add_theme_stylebox_override("panel", (_seg_warn if ratio < 0.2 else _seg_on) if on else _seg_off)
	_dig_label.text = "残り %d / %d" % [left, max_dig]


# ------------------------------------------------------------------ cell info / prompt / toast
func _build_info() -> void:
	_info = PanelContainer.new()
	_info.top_level = true
	_info.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.05, 0.07, 0.13, 0.94), UiTheme.GOLD, 8, 2))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_label.scroll_active = false
	_info_label.add_theme_font_size_override("normal_font_size", 19)
	_info_label.add_theme_font_override("normal_font", UiTheme.font())
	_info_label.add_theme_font_override("bold_font", UiTheme.font(true))
	_info_label.add_theme_font_size_override("bold_font_size", 21)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_info_label)
	_info.visible = false


## Small popup next to the mouse (HP / nutrient of whatever is under the cursor).
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
	var p := mouse_pos + Vector2(26, 24)
	if p.x + sz.x > vp.x - 8:
		p.x = mouse_pos.x - sz.x - 18
	if p.y + sz.y > vp.y - 8:
		p.y = mouse_pos.y - sz.y - 12
	_info.position = p


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt.position = Vector2(-360, 82)
	_prompt.custom_minimum_size = Vector2(720, 0)
	_prompt.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.25, 0.08, 0.3, 0.9), Color(0.9, 0.6, 1.0), 12, 2))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt)
	_prompt_label = UiTheme.label("", 26, UiTheme.TEXT, true)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_child(_prompt_label)
	_prompt.visible = false


func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt_label.text = text


func toast(text: String, color: Color = UiTheme.TEXT) -> void:
	var l := UiTheme.label(text, 24, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(l)
	if _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func set_visible_all(v: bool) -> void:
	root.visible = v
