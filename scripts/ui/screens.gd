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
	_panel.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.06, 0.08, 0.16, 0.96), UiTheme.GOLD, 16, 3))
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
		b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		cb.call())
	return b


# ------------------------------------------------------------------ title
func show_title() -> void:
	_clear()
	_dim(0.45)
	var vb := _center_panel(760)
	var t := UiTheme.label("ダンジョン生態系", 72, UiTheme.GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 10)
	vb.add_child(t)
	var s := UiTheme.label("〜 掘って、育てて、勇者を返り討ち 〜", 28)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	var how := RichTextLabel.new()
	how.bbcode_enabled = true
	how.fit_content = true
	how.scroll_active = false
	how.custom_minimum_size = Vector2(700, 0)
	how.add_theme_font_override("normal_font", UiTheme.font())
	how.add_theme_font_override("bold_font", UiTheme.font(true))
	how.add_theme_font_size_override("normal_font_size", 21)
	how.add_theme_font_size_override("bold_font_size", 21)
	how.text = "[b]遊び方[/b]\n・[color=#f0c060]左クリック[/color]で通路につながったブロックを掘る（採掘可能数を消費）\n・養分を含む土を掘ると魔物が生まれる　[color=#a0e070]養分1〜9: モコゴケ[/color] / [color=#f0a060]10以上: ザクザクムシ[/color]\n・モコゴケは養分を運び、ツボミ→モコバナになって仲間を増やす\n・ザクザクムシはモコゴケを食べて育ち、サナギ→成虫になって子を産む\n・勇者が[b]魔王[/b]を入口まで連れ去ると負け。魔物で勇者を倒そう！\n[color=#a0a0b0]WASD / 矢印 / 右ドラッグ: カメラ移動　ホイール: ズーム[/color]"
	vb.add_child(how)
	var c := CenterContainer.new()
	c.add_child(_button("はじめる", func() -> void: start_pressed.emit()))
	vb.add_child(c)
	visible = true


# ------------------------------------------------------------------ result
func show_result(data: Dictionary) -> void:
	_clear()
	_dim(0.55)
	var vb := _center_panel(820)
	var t := UiTheme.label("勇者撃退！", 64, UiTheme.GOLD, true)
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
	_ep_label = UiTheme.label("", 34, UiTheme.GOLD, true)
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
		var lv := UiTheme.label("", 22, UiTheme.GOLD, true)
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
	var t := UiTheme.label("魔王が連れ去られた…", 60, UiTheme.WARN, true)
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


func hide_all() -> void:
	visible = false
	_clear()
