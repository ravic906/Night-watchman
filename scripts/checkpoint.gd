extends Node2D
## A punch clock on the patrol route. Each hour the radio orders a few clocks
## to be punched; hold "interact" next to an ordered clock to punch in.
## Thieves can jam it; a jammed clock takes longer (fix, then punch).

var cp_name := ""
var done := false
## On this hour's patrol orders?
var ordered := false
## On the next check's orders (shown dimly so you can plan a route).
var next_ordered := false
var jammed := false
var progress := 0.0
var interact_range := 56.0
var saboteur = null
var glow: Node2D
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func set_ordered(value: bool) -> void:
	ordered = value
	done = false
	progress = 0.0


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return ordered and not done


func action_label() -> String:
	return ("fix and punch the %s clock" if jammed else "punch the %s clock") % cp_name


func hold_time() -> float:
	return 3.0 if jammed else 1.0


func complete(game) -> void:
	var was_jammed := jammed
	jammed = false
	done = true
	game.on_punch(self, was_jammed)


# --- thief sabotage ----------------------------------------------------------

func can_sabotage(by = null) -> bool:
	# Only clocks still waiting on this check's orders are worth jamming.
	return ordered and not done and not jammed and (saboteur == null or saboteur == by)


func sabotage_time() -> float:
	return 3.0


func sabotage(game) -> void:
	jammed = true
	game.on_clock_jammed(self)


var _redraw_acc := 0.0
var _drawn_state := ""


func _process(delta: float) -> void:
	_t += delta
	_redraw_acc += delta
	if _redraw_acc >= 0.05:   # animate glows at 20 Hz, not every frame
		_redraw_acc = 0.0
		glow.queue_redraw()
	var state := "%s%s" % [jammed, done]
	if state != _drawn_state:   # the clock body only changes when jammed / punched
		_drawn_state = state
		queue_redraw()


func _draw() -> void:
	# Wall-mounted clock box (seen only when lit).
	draw_rect(Rect2(-13, -16, 26, 30), Color(0.35, 0.33, 0.3))
	draw_rect(Rect2(-13, -16, 26, 30), Color(0.15, 0.14, 0.13), false, 2.0)
	draw_circle(Vector2(0, -3), 8, Color(0.85, 0.82, 0.72))
	draw_line(Vector2(0, -3), Vector2(0, -9), Color.BLACK, 1.5)
	draw_line(Vector2(0, -3), Vector2(4, -3), Color.BLACK, 1.5)
	if jammed:
		# Something wedged into the card slot.
		draw_line(Vector2(-10, 8), Vector2(10, 12), Color(0.55, 0.4, 0.25), 3)


func _draw_glow() -> void:
	# The status LED glows in the dark so you can find your route.
	var pulse := 0.6 + 0.4 * sin(_t * 3.0)
	var col: Color
	if jammed:
		col = Color(1.0, 0.65, 0.1, 0.5 + 0.5 * float(fmod(_t * 5.0, 1.0) > 0.5))
	elif done:
		col = Color(0.3, 1.0, 0.4, 0.9)
	elif not ordered and next_ordered:
		col = Color(1.0, 0.7, 0.2, 0.45)
	elif not ordered:
		col = Color(0.45, 0.45, 0.5, 0.45)
	else:
		col = Color(1.0, 0.25, 0.2, 0.5 + 0.5 * pulse)
	glow.draw_circle(Vector2(0, 10), 4, col)
	if ordered and not done:
		glow.draw_arc(Vector2(0, 10), 9 + pulse * 3, 0, TAU, 20, Color(col, 0.25), 1.5)
	if progress > 0.0 and not done:
		glow.draw_arc(Vector2.ZERO, 26, -PI / 2, -PI / 2 + TAU * progress, 32,
				Color(1, 0.7, 0.3) if jammed else Color(1, 0.9, 0.5), 4)
