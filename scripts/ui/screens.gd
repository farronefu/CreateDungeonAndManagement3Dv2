class_name Screens
extends Control
## Title, result (evolution points + upgrades) and game-over screens.

signal start_pressed
signal next_stage_pressed
signal retry_pressed
signal title_pressed

var _panel: PanelContainer
var _box: VBoxContainer
var _ep_label: Label
var _upgrade_rows := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	theme = UiTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	Pad.mode_changed.connect(func(on: bool) -> void:
		if on and visible:
			_focus_first())


## Focus the first enabled button so A / Enter / the D-pad drive the menu right away.
func _focus_first() -> void:
	for b in find_children("*", "Button", true, false):
		var btn := b as Button
		if btn.visible and not btn.disabled and not btn.is_queued_for_deletion():
			btn.grab_focus()
			return


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_upgrade_rows.clear()


func _dim(alpha: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _center_panel(min_w: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(min_w, 0)
	_panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.INK_SOLID, UiTheme.EDGE, 12, 1))
	cc.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_panel.add_child(_box)
	return _box


func _button(text: String, cb: Callable, big: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	if big:
		b.custom_minimum_size = Vector2(320, 60)
		b.add_theme_font_size_override("font_size", UiTheme.px(28))
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		cb.call())
	return b


# ------------------------------------------------------------------ title
## Title over the live, slowly orbiting diorama: logo on the left, two actions, a how-to overlay.
func show_title() -> void:
	_clear()
	# gradient shade on the left so the logo reads, the scene stays visible on the right
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.03, 0.02, 0.015, 0.85), Color(0.03, 0.02, 0.015, 0.55), Color(0.03, 0.02, 0.015, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	vb.offset_left = 120
	vb.offset_right = 900
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	var small := UiTheme.heading("DUNGEON  ECOSYSTEM", 22, Color(1, 1, 1, 0.85), 600)
	vb.add_child(small)
	var t := UiTheme.heading("ダンジョン生態系", 104, Color(1, 1, 1), 900)
	t.add_theme_constant_override("outline_size", 18)
	t.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	t.add_theme_constant_override("shadow_offset_y", 6)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	vb.add_child(t)
	var line := ColorRect.new()
	line.color = Color(UiTheme.GOLD, 0.6)
	line.custom_minimum_size = Vector2(520, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(line)
	var s := UiTheme.heading("掘って、育てて、勇者を返り討ち。", 30, UiTheme.TEXT, 600)
	vb.add_child(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 48)
	vb.add_child(gap)
	var start := _button("はじめる", func() -> void: start_pressed.emit())
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.custom_minimum_size = Vector2(340, 64)
	vb.add_child(start)
	var how := _button("あそびかた", _show_howto, false)
	how.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	how.custom_minimum_size = Vector2(340, 50)
	how.add_theme_font_size_override("font_size", UiTheme.px(20))
	vb.add_child(how)
	var hint := UiTheme.label("マウス / キーボード / コントローラー（Xbox配置）対応", 15, UiTheme.TEXT_DIM)
	vb.add_child(hint)
	visible = true
	_focus_first.call_deferred()


func _show_howto() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.INK_SOLID, UiTheme.EDGE, 12, 1))
	pc.custom_minimum_size = Vector2(820, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	vb.add_child(UiTheme.heading("あそびかた", 34))
	var how := RichTextLabel.new()
	how.bbcode_enabled = true
	how.fit_content = true
	how.scroll_active = false
	how.custom_minimum_size = Vector2(780, 0)
	how.add_theme_font_override("normal_font", UiTheme.font())
	how.add_theme_font_override("bold_font", UiTheme.font(true))
	how.add_theme_font_size_override("normal_font_size", UiTheme.px(19))
	how.add_theme_font_size_override("bold_font_size", UiTheme.px(19))
	how.add_theme_constant_override("line_separation", 6)
	how.text = "・通路に面した土を[b]掘る[/b]（クリック / Aボタン）。掘れる回数には限りがある\n・土は養分がたまるほど 何もない土→植生のある土→植生が多い土→少し枯れた土→枯れた土 と変わる
・植生のある土を掘ると[color=#b8e080]モコチュリ[/color]、枯れはじめた土を掘ると[color=#f0b070]ザクザクムシ（ダンゴムシ）[/color]が生まれる\n・モコチュリは養分を運び、やがて木（ツボミ→モコバナ）になって仲間を増やす\n・ザクザクムシはモコチュリを食べて育ち、サナギ→成虫になって子を産む\n・時間が来るか「勇者を呼ぶ」と、[b]魔王[/b]を置いて迎え撃つ\n・勇者が魔王を入口まで運ぶと負け。魔物たちで勇者を倒そう\n\n[color=#c8bca8]カメラ: WASD・右ドラッグ・画面端（移動）／ホイール（ズーム）／中ドラッグ・Q/E（回転）\n一時停止（生態系の確認）: Start / P　速度: 右上のボタン / RB[/color]"
	vb.add_child(how)
	var close := _button("閉じる", func() -> void:
		dim.queue_free()
		_focus_first.call_deferred(), false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(220, 48)
	vb.add_child(close)
	if Pad.using_pad:
		close.grab_focus.call_deferred()


# ------------------------------------------------------------------ result
func show_result(data: Dictionary) -> void:
	_clear()
	_dim(0.55)
	var vb := _center_panel(820)
	var t := UiTheme.heading("勇者撃退！", 64, UiTheme.GOLD, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for row in data["rows"]:
		grid.add_child(UiTheme.label(row[0], 26))
		var v := UiTheme.label(row[1], 26, UiTheme.TEXT, true)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		var p := UiTheme.label("+%d pt" % row[2], 26, Color(0.6, 1.0, 0.6), true)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(p)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_ep_label = UiTheme.label("", 34, UiTheme.TEXT, true)
	_ep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_ep_label)
	vb.add_child(UiTheme.label("進化ポイントを割り振る", 24, UiTheme.TEXT, true))
	for id in Balance.UPGRADES:
		var u: Dictionary = Balance.UPGRADES[id]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiTheme.label(u["name"], 24, UiTheme.TEXT, true))
		info.add_child(UiTheme.label(u["desc"], 18, Color(0.8, 0.8, 0.85)))
		hb.add_child(info)
		var lv := UiTheme.label("", 22, UiTheme.TEXT, true)
		lv.custom_minimum_size = Vector2(110, 0)
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(lv)
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 52)
		b.pressed.connect(_buy.bind(id))
		hb.add_child(b)
		vb.add_child(hb)
		_upgrade_rows[id] = [lv, b]
	var c := CenterContainer.new()
	c.add_child(_button("次のステージへ", func() -> void: next_stage_pressed.emit()))
	vb.add_child(c)
	_refresh_upgrades()
	visible = true
	_focus_first.call_deferred()


func _buy(id: String) -> void:
	if GameState.buy(id):
		Sfx.play("evolve")
	else:
		Sfx.play("dig_fail")
	_refresh_upgrades()


func _refresh_upgrades() -> void:
	_ep_label.text = "進化ポイント: %d" % GameState.evolution_points
	for id in _upgrade_rows:
		var u: Dictionary = Balance.UPGRADES[id]
		var lvl := GameState.upgrade_level(id)
		var lv: Label = _upgrade_rows[id][0]
		var b: Button = _upgrade_rows[id][1]
		lv.text = "Lv %d/%d" % [lvl, u["max"]]
		if lvl >= int(u["max"]):
			b.text = "MAX"
			b.disabled = true
		else:
			b.text = "%d pt で強化" % int(u["cost"])
			b.disabled = GameState.evolution_points < int(u["cost"])


# ------------------------------------------------------------------ game over
func show_game_over() -> void:
	_clear()
	_dim(0.6)
	var vb := _center_panel(700)
	var t := UiTheme.heading("魔王が連れ去られた…", 56, UiTheme.WARN, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := UiTheme.label("ダンジョンをもう一度作り直そう", 26)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	hb.add_child(_button("このステージをやり直す", func() -> void: retry_pressed.emit()))
	hb.add_child(_button("タイトルへ", func() -> void: title_pressed.emit()))
	vb.add_child(hb)
	visible = true
	_focus_first.call_deferred()


func hide_all() -> void:
	visible = false
	_clear()
