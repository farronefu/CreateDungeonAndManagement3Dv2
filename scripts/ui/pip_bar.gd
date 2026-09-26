class_name PipBar
extends Control
## Dot-style gauge: a row of square pips, ■■■■□□□ (filled squares for the value, hollow ones
## for the rest). Any non-zero value shows at least one filled pip.

var count := 10
var pip := 14.0
var gap := 4.0
var color := Color.WHITE
var ratio := 1.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init(n: int = 10, size_px: float = 14.0, col: Color = Color.WHITE) -> void:
	count = n
	pip = size_px
	color = col
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(count * pip + (count - 1) * gap, pip)


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _draw() -> void:
	var filled := ceili(ratio * count - 0.001) if ratio > 0.0 else 0
	var y := (size.y - pip) * 0.5
	var edge := maxf(2.0, roundf(pip / 7.0))
	for i in count:
		var r := Rect2(i * (pip + gap), y, pip, pip)
		# dark outline around every pip, like a pixel-art frame
		draw_rect(r.grow(edge * 0.5), UiTheme.OUTLINE)
		if i < filled:
			draw_rect(r, color)
			draw_rect(Rect2(r.position, Vector2(pip, edge)), color.lightened(0.35))
			draw_rect(Rect2(r.position + Vector2(0, pip - edge), Vector2(pip, edge)), color.darkened(0.3))
		else:
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r.grow(-edge * 0.5), Color(color.r, color.g, color.b, 0.35), false, edge)
