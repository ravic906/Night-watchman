extends Node2D
## Something worth stealing. Intruders pick these as targets.

var stolen := false
var carrier = null
var glow: Node2D
var kind := 0
## Loot look for the location: "art", "homes", "retail", "industrial".
var style := "art"
## Mall: the shutter that guards this item's shop (or null).
var gate = null


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
	# Stand / shelf
	draw_rect(Rect2(-14, -6, 28, 18), Color(0.45, 0.43, 0.4))
	draw_rect(Rect2(-16, 10, 32, 5), Color(0.3, 0.29, 0.27))
	if not available():
		return
	match style:
		"homes":
			_draw_homes()
		"retail":
			_draw_retail()
		"industrial":
			_draw_industrial()
		_:
			_draw_art()


func _draw_art() -> void:
	match kind:
		0:  # Gem
			draw_colored_polygon(PackedVector2Array([Vector2(0, -24), Vector2(9, -14), Vector2(0, -6), Vector2(-9, -14)]), Color(0.3, 0.85, 0.9))
		1:  # Golden vase
			draw_circle(Vector2(0, -14), 8, Color(0.9, 0.72, 0.25))
			draw_rect(Rect2(-4, -26, 8, 8), Color(0.85, 0.66, 0.2))
		2:  # Small statue
			draw_circle(Vector2(0, -22), 4, Color(0.8, 0.8, 0.85))
			draw_rect(Rect2(-5, -18, 10, 12), Color(0.75, 0.75, 0.8))


func _draw_homes() -> void:
	match kind:
		0:  # TV
			draw_rect(Rect2(-12, -24, 24, 16), Color(0.1, 0.1, 0.12))
			draw_rect(Rect2(-10, -22, 20, 12), Color(0.25, 0.35, 0.45))
		1:  # Jewellery box
			draw_rect(Rect2(-9, -16, 18, 10), Color(0.5, 0.25, 0.3))
			draw_circle(Vector2(0, -18), 3, Color(0.95, 0.85, 0.4))
		2:  # Laptop
			draw_rect(Rect2(-11, -20, 22, 13), Color(0.6, 0.62, 0.66))
			draw_rect(Rect2(-12, -8, 24, 3), Color(0.45, 0.46, 0.5))


func _draw_retail() -> void:
	match kind:
		0:  # Handbag
			draw_rect(Rect2(-10, -18, 20, 12), Color(0.7, 0.2, 0.3))
			draw_arc(Vector2(0, -18), 6, PI, TAU, 10, Color(0.4, 0.1, 0.15), 2)
		1:  # Sneakers
			draw_rect(Rect2(-12, -12, 11, 6), Color(0.9, 0.9, 0.92))
			draw_rect(Rect2(1, -12, 11, 6), Color(0.9, 0.9, 0.92))
		2:  # Phone box
			draw_rect(Rect2(-7, -22, 14, 16), Color(0.15, 0.15, 0.18))
			draw_rect(Rect2(-5, -20, 10, 12), Color(0.35, 0.6, 0.85))


func _draw_industrial() -> void:
	match kind:
		0:  # Copper coil
			draw_circle(Vector2(0, -14), 9, Color(0.75, 0.42, 0.2))
			draw_circle(Vector2(0, -14), 4, Color(0.4, 0.22, 0.1))
		1:  # Tool chest
			draw_rect(Rect2(-11, -20, 22, 14), Color(0.75, 0.15, 0.12))
			draw_line(Vector2(-11, -13), Vector2(11, -13), Color(0.4, 0.08, 0.06), 1.5)
		2:  # Power drill
			draw_rect(Rect2(-10, -20, 16, 7), Color(0.95, 0.75, 0.1))
			draw_rect(Rect2(-6, -14, 6, 8), Color(0.2, 0.2, 0.2))


func _draw_glow() -> void:
	if stolen:
		glow.draw_line(Vector2(-6, -6), Vector2(6, 6), Color(1, 0.2, 0.2, 0.6), 2)
		glow.draw_line(Vector2(6, -6), Vector2(-6, 6), Color(1, 0.2, 0.2, 0.6), 2)
	elif carrier != null:
		glow.draw_arc(Vector2.ZERO, 10, 0, TAU, 16, Color(1, 0.5, 0.2, 0.6), 2)
	else:
		glow.draw_circle(Vector2.ZERO, 2.5, Color(0.6, 0.85, 1.0, 0.35))
