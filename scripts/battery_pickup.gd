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
	var a := 0.35 + 0.35 * sin(_t * 4.0)
	glow.draw_circle(Vector2.ZERO, 5, Color(0.4, 1.0, 0.5, a))
	glow.draw_arc(Vector2.ZERO, 12, 0, TAU, 16, Color(0.4, 1.0, 0.5, a * 0.5), 1.5)


func remove() -> void:
	glow.queue_free()
	queue_free()
