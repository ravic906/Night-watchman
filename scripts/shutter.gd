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

## True if the watchman is on the shop side (shut in, or would be if closed).
func player_inside() -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _inside_frame:
		return _inside_cached
	_inside_frame = frame
	_inside_cached = _compute_player_inside()
	return _inside_cached


var _inside_frame := -1
var _inside_cached := false


func _compute_player_inside() -> bool:
	var lvl = game.level
	var was_solid: bool = lvl.is_cell_solid(global_position)
	lvl.set_cell_solid(global_position, true)
	var cut_off: bool = lvl.find_path(lvl.player_spawn, game.player.global_position).is_empty()
	lvl.set_cell_solid(global_position, was_solid)
	return cut_off


func needs_action() -> bool:
	return not closed or player_inside()


func action_label() -> String:
	if closed:
		return "raise the %s shutter" % shop
	return "close the %s shutter" % shop


func hold_time() -> float:
	return 1.0


func complete(g) -> void:
	if closed:
		# Only possible from inside: let the watchman out.
		set_closed(false)
		g.message("You raise the %s shutter." % shop, 2.0)
		return
	if player_inside():
		g.message("Close it from outside, or you'll lock yourself in.", 2.5)
		return
	# Never shut someone (or yourself) inside the shutter itself.
	if g.player.global_position.distance_to(global_position) < 40.0 \
			or g.intruders.any(func(it): return it.global_position.distance_to(global_position) < 40.0):
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
		glow.draw_rect(Rect2(-half, -half + 4, TILE, TILE - 8), Color(0.5, 0.53, 0.58, 0.95))
		for i in 6:
			var y := -half + 8 + i * 6.5
			glow.draw_line(Vector2(-half, y), Vector2(half, y), Color(0.25, 0.27, 0.3), 1.5)
	else:
		# Rolled up into its drum, with a dashed red warning line across the gap.
		glow.draw_rect(Rect2(-half, -half, TILE, 7), Color(0.3, 0.32, 0.36, 0.8))
		for i in 6:
			var x := -half + i * 8.0
			glow.draw_line(Vector2(x, 0), Vector2(x + 4, 0), Color(1.0, 0.3, 0.2, 0.75), 2.0)
	var c := Color(0.35, 1.0, 0.45, 0.85) if closed else Color(1.0, 0.3, 0.2, 0.85)
	glow.draw_circle(Vector2(half - 6, -half + 3), 3.0, c)
	if picker != null:
		glow.draw_arc(Vector2.ZERO, 24, -PI / 2, -PI / 2 + TAU * pick_progress, 24, Color(1, 0.4, 0.3, 0.9), 3)
	if progress > 0.0:
		glow.draw_arc(Vector2.ZERO, 26, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
