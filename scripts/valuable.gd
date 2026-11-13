extends Node2D
## Something worth stealing. Intruders pick these as targets.

var stolen := false
var carrier = null
var glow: Node2D
var kind := 0


func _ready() -> void:
	kind = randi() % 3
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func available() -> bool:
	return not stolen and carrier == null


func refresh() -> void:
	queue_redraw()
	glow.queue_redraw()


func _draw() -> void:
	# Pedestal
	draw_rect(Rect2(-14, -6, 28, 18), Color(0.45, 0.43, 0.4))
	draw_rect(Rect2(-16, 10, 32, 5), Color(0.3, 0.29, 0.27))
	if not available():
		return
	match kind:
		0:  # Gem
			draw_colored_polygon(PackedVector2Array([Vector2(0, -24), Vector2(9, -14), Vector2(0, -6), Vector2(-9, -14)]), Color(0.3, 0.85, 0.9))
		1:  # Golden vase
			draw_circle(Vector2(0, -14), 8, Color(0.9, 0.72, 0.25))
			draw_rect(Rect2(-4, -26, 8, 8), Color(0.85, 0.66, 0.2))
		2:  # Small statue
			draw_circle(Vector2(0, -22), 4, Color(0.8, 0.8, 0.85))
			draw_rect(Rect2(-5, -18, 10, 12), Color(0.75, 0.75, 0.8))


func _draw_glow() -> void:
	if stolen:
		glow.draw_line(Vector2(-6, -6), Vector2(6, 6), Color(1, 0.2, 0.2, 0.6), 2)
		glow.draw_line(Vector2(6, -6), Vector2(-6, 6), Color(1, 0.2, 0.2, 0.6), 2)
	elif carrier != null:
		glow.draw_arc(Vector2.ZERO, 10, 0, TAU, 16, Color(1, 0.5, 0.2, 0.6), 2)
	else:
		glow.draw_circle(Vector2.ZERO, 2.5, Color(0.6, 0.85, 1.0, 0.35))
