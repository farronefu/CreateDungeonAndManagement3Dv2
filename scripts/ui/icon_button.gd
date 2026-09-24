class_name IconButton
extends Button
## Toggle button that draws a vector icon instead of text (speed / pause controls).
##   icon_kind: "pause", "play1", "play2", "play3"

var icon_kind := "play1"
var _hover := false


func _init(kind: String = "play1") -> void:
	icon_kind = kind
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(46, 40)
	flat = true
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if button_pressed:
		draw_rect(r.grow(-3), Color(1, 1, 1, 0.22), true)
		draw_rect(r.grow(-3), Color(1, 1, 1, 0.9), false, 2.0)
	elif _hover:
		draw_rect(r.grow(-3), Color(1, 1, 1, 0.07), true)
	var col := Color(1, 1, 1) if button_pressed or _hover else Color(1, 1, 1, 0.75)
	var c := size * 0.5
	var h := 14.0
	match icon_kind:
		"pause":
			draw_rect(Rect2(c + Vector2(-7, -h * 0.5), Vector2(5, h)), col)
			draw_rect(Rect2(c + Vector2(2, -h * 0.5), Vector2(5, h)), col)
		_:
			var n := int(icon_kind.substr(4, 1))
			var w := 9.0
			var total := w * n - 2.0 * (n - 1)
			var x0 := c.x - total * 0.5
			for i in n:
				var x := x0 + i * (w - 2.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x, c.y - h * 0.5), Vector2(x + w, c.y), Vector2(x, c.y + h * 0.5)]), col)
