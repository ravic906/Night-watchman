extends Node2D
## Mall shop shutter. Closed, it blocks the watchman and thieves (who then
## have to force it open, loudly). The watchman closes it with a hold.

const TILE := 48

var glow: Node2D
var game
var shop := ""
var closed := false
var progress := 0.0
var interact_range := 60.0
var picker = null          # thief forcing it
var pick_progress := 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	_shape.shape = rect
	_shape.disabled = true
	body.add_child(_shape)
	add_child(body)


func set_closed(value: bool) -> void:
	closed = value
	_shape.set_deferred("disabled", not value)
	game.level.set_cell_solid(global_position, value)
	refresh()


func force_time() -> float:
	return 4.0


func force_open() -> void:
	set_closed(false)
	game.on_shutter_forced(self)


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return not closed


func action_label() -> String:
	return "close the %s shutter" % shop


func hold_time() -> float:
	return 1.0


func complete(g) -> void:
	# Never shut someone (or yourself) inside the shutter itself.
	if g.player.global_position.distance_to(global_position) < 30.0 \
			or g.intruders.any(func(it): return it.global_position.distance_to(global_position) < 30.0):
		g.message("Step clear of the doorway first.", 2.0)
		return
	set_closed(true)
	g.on_shutter_closed(self)


func refresh() -> void:
	glow.queue_redraw()


func _process(_delta: float) -> void:
	if progress > 0.0 or picker != null:
		glow.queue_redraw()


func _draw_glow() -> void:
	var half := TILE / 2.0
	if closed:
		glow.draw_rect(Rect2(-half, -half + 4, TILE, TILE - 8), Color(0.32, 0.34, 0.38, 0.9))
		for i in 6:
			var y := -half + 8 + i * 6.5
			glow.draw_line(Vector2(-half, y), Vector2(half, y), Color(0.18, 0.19, 0.22), 1.5)
	else:
		# Rolled up into its drum.
		glow.draw_rect(Rect2(-half, -half, TILE, 7), Color(0.3, 0.32, 0.36, 0.8))
	var c := Color(0.35, 1.0, 0.45, 0.85) if closed else Color(1.0, 0.3, 0.2, 0.85)
	glow.draw_circle(Vector2(half - 6, -half + 3), 3.0, c)
	if picker != null:
		glow.draw_arc(Vector2.ZERO, 24, -PI / 2, -PI / 2 + TAU * pick_progress, 24, Color(1, 0.4, 0.3, 0.9), 3)
	if progress > 0.0:
		glow.draw_arc(Vector2.ZERO, 26, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
