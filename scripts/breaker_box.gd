extends Node2D
## Breaker box in the basement: one circuit per wing of the building.
## A thief can flip a circuit off, killing that wing's lamps.

const WINGS := ["West", "Centre", "East"]

var glow: Node2D
var circuits := {"West": true, "Centre": true, "East": true}
var progress := 0.0
var interact_range := 56.0
var saboteur = null


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func dead_wings() -> Array:
	return WINGS.filter(func(w): return not circuits[w])


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return not dead_wings().is_empty()


func action_label() -> String:
	return "reset the breaker"


func hold_time() -> float:
	return 2.0


func complete(game) -> void:
	for w in WINGS:
		circuits[w] = true
	game.on_power_restored()
	refresh()


# --- thief sabotage ----------------------------------------------------------

func can_sabotage() -> bool:
	return saboteur == null and dead_wings().size() < WINGS.size()


func sabotage_time() -> float:
	return 3.0


func sabotage(game) -> void:
	var live: Array = WINGS.filter(func(w): return circuits[w])
	if live.is_empty():
		return
	var wing: String = live.pick_random()
	circuits[wing] = false
	game.on_power_cut(wing, self)
	refresh()


func refresh() -> void:
	queue_redraw()
	glow.queue_redraw()


func _process(_delta: float) -> void:
	if progress > 0.0:
		glow.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-18, -24, 36, 30), Color(0.32, 0.34, 0.3))
	draw_rect(Rect2(-18, -24, 36, 30), Color(0.12, 0.13, 0.11), false, 2.0)
	for i in WINGS.size():
		var x := -11 + i * 11
		draw_rect(Rect2(x - 3, -18, 6, 18), Color(0.15, 0.15, 0.15))
		var lever_y := -16 if circuits[WINGS[i]] else -6
		draw_rect(Rect2(x - 4, lever_y, 8, 5), Color(0.75, 0.72, 0.6))
	# Hazard stripe
	draw_line(Vector2(-18, 4), Vector2(18, 4), Color(0.85, 0.7, 0.1), 3)


func _draw_glow() -> void:
	for i in WINGS.size():
		var on: bool = circuits[WINGS[i]]
		glow.draw_circle(Vector2(-11 + i * 11, -21), 2.5,
				Color(0.3, 1.0, 0.4, 0.8) if on else Color(1.0, 0.25, 0.2, 0.95))
	if progress > 0.0:
		glow.draw_arc(Vector2(0, -8), 28, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
