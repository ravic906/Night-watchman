extends Node2D
## A punch clock on the patrol route. Hold "interact" next to it to punch in.

var cp_name := ""
var done := false
var progress := 0.0
var glow: Node2D
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func reset_round() -> void:
	done = false
	progress = 0.0


func _process(delta: float) -> void:
	_t += delta
	glow.queue_redraw()
	queue_redraw()


func _draw() -> void:
	# Wall-mounted clock box (seen only when lit).
	draw_rect(Rect2(-13, -16, 26, 30), Color(0.35, 0.33, 0.3))
	draw_rect(Rect2(-13, -16, 26, 30), Color(0.15, 0.14, 0.13), false, 2.0)
	draw_circle(Vector2(0, -3), 8, Color(0.85, 0.82, 0.72))
	draw_line(Vector2(0, -3), Vector2(0, -9), Color.BLACK, 1.5)
	draw_line(Vector2(0, -3), Vector2(4, -3), Color.BLACK, 1.5)


func _draw_glow() -> void:
	# The status LED glows in the dark so you can find your route.
	var pulse := 0.6 + 0.4 * sin(_t * 3.0)
	var col := Color(0.3, 1.0, 0.4, 0.9) if done else Color(1.0, 0.25, 0.2, 0.5 + 0.5 * pulse)
	glow.draw_circle(Vector2(0, 10), 4, col)
	if not done:
		glow.draw_arc(Vector2(0, 10), 9 + pulse * 3, 0, TAU, 20, Color(col, 0.25), 1.5)
	if progress > 0.0 and not done:
		glow.draw_arc(Vector2.ZERO, 26, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
