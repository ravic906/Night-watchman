extends Node2D
## Spare flashlight battery. Walk over it to recharge.

const AMOUNT := 45.0

var glow: Node2D
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func _process(delta: float) -> void:
	_t += delta
	glow.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-6, -10, 12, 20), Color(0.2, 0.6, 0.3))
	draw_rect(Rect2(-3, -13, 6, 3), Color(0.8, 0.8, 0.8))


func _draw_glow() -> void:
	var a := 0.55 + 0.4 * sin(_t * 4.0)
	glow.draw_circle(Vector2.ZERO, 6, Color(0.45, 1.0, 0.55, a))
	# An expanding pulse ring makes spare batteries easy to spot.
	var pulse := fmod(_t * 0.8, 1.0)
	glow.draw_arc(Vector2.ZERO, 10 + pulse * 22, 0, TAU, 24, Color(0.45, 1.0, 0.55, (1.0 - pulse) * 0.6), 2.0)


func remove() -> void:
	glow.queue_free()
	queue_free()
