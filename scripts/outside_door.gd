extends Node2D
## One of the building's outside doors. Lock it to keep thieves out; they
## will try to pick the lock, and an unlocked door lets them walk right in.

var glow: Node2D
var door_name := "west"
var locked := false
var progress := 0.0
var interact_range := 62.0
var pick_progress := 0.0   # 0..1 while a thief works on the lock
var picker = null


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


# --- entrance API (shared with window.gd) -------------------------------------

func entrance_label() -> String:
	return "%s door" % door_name


func is_open() -> bool:
	return not locked


## Thieves can always leave by a door (they unlock it from inside).
func passable_exit() -> bool:
	return true


func entry_work_time(cfg: Dictionary) -> float:
	return cfg["lockpick_time"]


func work_sound() -> String:
	return "lockpick"


func force_open(game) -> void:
	locked = false
	refresh()
	game.on_lock_picked(null, self)


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return not locked


func action_label() -> String:
	return "lock the %s door" % door_name


func hold_time() -> float:
	return 1.2


func complete(game) -> void:
	locked = true
	game.on_door_locked(self)


func refresh() -> void:
	glow.queue_redraw()


func _process(_delta: float) -> void:
	if progress > 0.0 or picker != null:
		glow.queue_redraw()


func _draw_glow() -> void:
	# Padlock icon on the inside face of the door.
	var x := 30.0 if door_name == "west" else -30.0
	var c := Color(0.35, 1.0, 0.45, 0.85) if locked else Color(1.0, 0.3, 0.2, 0.85)
	glow.draw_rect(Rect2(x - 6, -2, 12, 10), c)
	if locked:
		glow.draw_arc(Vector2(x, -2), 4.5, PI, TAU, 10, c, 2.0)
	else:
		glow.draw_arc(Vector2(x + 4, -5), 4.5, PI, TAU, 10, c, 2.0)
	if picker != null:
		glow.draw_arc(Vector2.ZERO, 22, -PI / 2, -PI / 2 + TAU * pick_progress, 24, Color(1, 0.4, 0.3, 0.9), 3)
	if progress > 0.0:
		glow.draw_arc(Vector2(x, 3), 22, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
