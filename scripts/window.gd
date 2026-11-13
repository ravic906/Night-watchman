extends Node2D
## A window in the building's outer wall: another way in.
## Thieves smash an intact window (loud), walk through a broken one
## (silent), or pry the boards off one the watchman has boarded up.

enum Pane { INTACT, BROKEN, BOARDED }

var glow: Node2D
var room := ""
var pane := Pane.INTACT
var progress := 0.0
var interact_range := 62.0
var pick_progress := 0.0
var picker = null


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


# --- entrance API (shared with outside_door.gd) -------------------------------

func entrance_label() -> String:
	return "%s window" % room


func is_open() -> bool:
	return pane == Pane.BROKEN


func passable_exit() -> bool:
	return pane == Pane.BROKEN


func entry_work_time(cfg: Dictionary) -> float:
	return cfg["window_break_time"] if pane == Pane.INTACT else cfg["pry_time"]


## Sound made while working on it ("" = quiet until the glass goes).
func work_sound() -> String:
	return "pry" if pane == Pane.BOARDED else ""


func force_open(game) -> void:
	var smashed := pane == Pane.INTACT
	pane = Pane.BROKEN
	refresh()
	game.on_window_forced(self, smashed)


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return pane == Pane.BROKEN


func action_label() -> String:
	return "board up the %s window" % room


func hold_time() -> float:
	return 2.5


func complete(game) -> void:
	pane = Pane.BOARDED
	refresh()
	game.on_window_boarded(self)


func refresh() -> void:
	glow.queue_redraw()


func _process(_delta: float) -> void:
	if progress > 0.0 or picker != null:
		glow.queue_redraw()


func _draw_glow() -> void:
	var r := Rect2(-18, -5, 36, 10)
	match pane:
		Pane.INTACT:
			glow.draw_rect(r, Color(0.35, 0.5, 0.7, 0.55))
			glow.draw_line(Vector2(0, -5), Vector2(0, 5), Color(0.2, 0.25, 0.35), 2.0)
		Pane.BROKEN:
			glow.draw_rect(r, Color(0.02, 0.02, 0.04))
			for i in 4:
				var x := -18.0 + i * 12.0
				glow.draw_colored_polygon(PackedVector2Array([
					Vector2(x, -5), Vector2(x + 6, -5), Vector2(x + 3, 2 - i % 2 * 3)]),
					Color(0.5, 0.65, 0.85, 0.6))
		Pane.BOARDED:
			glow.draw_rect(r, Color(0.1, 0.07, 0.05))
			glow.draw_line(Vector2(-20, -6), Vector2(20, 6), Color(0.55, 0.38, 0.2), 4.0)
			glow.draw_line(Vector2(-20, 6), Vector2(20, -6), Color(0.5, 0.34, 0.18), 4.0)
	glow.draw_rect(r, Color(0.3, 0.32, 0.4), false, 1.5)
	if picker != null:
		glow.draw_arc(Vector2.ZERO, 22, -PI / 2, -PI / 2 + TAU * pick_progress, 24, Color(1, 0.4, 0.3, 0.9), 3)
	if progress > 0.0:
		glow.draw_arc(Vector2.ZERO, 24, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
