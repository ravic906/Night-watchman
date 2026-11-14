extends Node2D
## Security panel in the lobby. While armed, the watchman knows exactly how
## many intruders are inside and hears a chime at every break-in.
## Thieves can cut its wires.

var glow: Node2D
var armed := false
var cut := false
var progress := 0.0
var interact_range := 56.0
var saboteur = null
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return not armed


func action_label() -> String:
	return "re-wire the alarm" if cut else "arm the alarm"


func hold_time() -> float:
	return 2.5 if cut else 1.5


func complete(game) -> void:
	var was_cut := cut
	armed = true
	cut = false
	game.on_alarm_armed(was_cut)


# --- thief sabotage ----------------------------------------------------------

func can_sabotage(by = null) -> bool:
	return armed and (saboteur == null or saboteur == by)


func sabotage_time() -> float:
	return 4.0


func sabotage(game) -> void:
	armed = false
	cut = true
	game.on_alarm_cut(self)


var _redraw_acc := 0.0


func _process(delta: float) -> void:
	_t += delta
	_redraw_acc += delta
	if _redraw_acc >= 0.05:   # animate glows at 20 Hz, not every frame
		_redraw_acc = 0.0
		glow.queue_redraw()
	var state := "%s%s" % [armed, cut]
	if state != _drawn_state:
		_drawn_state = state
		queue_redraw()


var _drawn_state := ""


func _draw() -> void:
	# Wall-mounted keypad box.
	draw_rect(Rect2(-15, -22, 30, 26), Color(0.3, 0.32, 0.36))
	draw_rect(Rect2(-15, -22, 30, 26), Color(0.12, 0.12, 0.14), false, 2.0)
	for y in 3:
		for x in 3:
			draw_rect(Rect2(-9 + x * 6, -16 + y * 6, 4, 4), Color(0.7, 0.7, 0.72))
	if cut:
		draw_line(Vector2(-12, 4), Vector2(-4, 14), Color(0.8, 0.2, 0.1), 2)
		draw_line(Vector2(6, 4), Vector2(12, 12), Color(0.2, 0.4, 0.9), 2)


func _draw_glow() -> void:
	var col: Color
	if armed:
		col = Color(0.3, 1.0, 0.4, 0.9)
	elif cut:
		col = Color(1.0, 0.55, 0.1, 0.4 + 0.6 * float(fmod(_t * 7.0, 1.0) > 0.5))
	else:
		col = Color(1.0, 0.25, 0.2, 0.55 + 0.45 * sin(_t * 3.0))
	glow.draw_circle(Vector2(10, -19), 3.5, col)
	if not armed:
		glow.draw_arc(Vector2(10, -19), 8, 0, TAU, 16, Color(col, 0.25), 1.5)
	if progress > 0.0:
		glow.draw_arc(Vector2(0, -8), 26, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
