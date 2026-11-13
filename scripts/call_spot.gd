extends Node2D
## Apartment intercom call: a resident reports a noise. Get there and check
## before time runs out. Sometimes there really is a thief inside.

const CALL_TIME := 60.0

var glow: Node2D
var flat := ""
var active := false
var real := false
var time_left := 0.0
var progress := 0.0
var interact_range := 56.0
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func activate(is_real: bool) -> void:
	active = true
	real = is_real
	time_left = CALL_TIME
	glow.queue_redraw()


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return active


func action_label() -> String:
	return "check on %s" % flat


func hold_time() -> float:
	return 1.0


func complete(game) -> void:
	active = false
	game.on_call_answered(self)


func _physics_process(delta: float) -> void:
	_t += delta
	if active:
		time_left -= delta
	glow.queue_redraw()


func _draw() -> void:
	# Intercom handset by the flat door.
	draw_rect(Rect2(-7, -12, 14, 20), Color(0.55, 0.52, 0.45))
	draw_rect(Rect2(-4, -8, 8, 6), Color(0.25, 0.25, 0.25))


func _draw_glow() -> void:
	if active:
		var blink := fmod(_t * 3.0, 1.0) > 0.4
		var c := Color(1.0, 0.75, 0.2, 0.95 if blink else 0.45)
		glow.draw_circle(Vector2(0, -16), 4.0, c)
		glow.draw_arc(Vector2.ZERO, 22, -PI / 2, -PI / 2 + TAU * clampf(time_left / CALL_TIME, 0, 1),
				32, Color(1.0, 0.75, 0.2, 0.7), 3)
		if progress > 0.0:
			glow.draw_arc(Vector2.ZERO, 27, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
	else:
		glow.draw_circle(Vector2(0, -16), 2.0, Color(0.5, 0.5, 0.55, 0.4))
