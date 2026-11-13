extends Node2D
## The Shadow. It only moves when your flashlight is not on it.

var game
var glow: Node2D
var speed := 55.0
var lit := false

var _path := PackedVector2Array()
var _path_i := 0
var _repath := 0.0
var _t := 0.0
var _wake := 6.0
var _brush_cooldown := 0.0
var _unlit_time := 1.0
var _last_floor := Vector2.ZERO


func _ready() -> void:
	glow.draw.connect(_draw_glow)


func reset_to(pos: Vector2) -> void:
	global_position = pos
	_last_floor = pos
	_path = PackedVector2Array()
	_wake = 6.0


func _physics_process(delta: float) -> void:
	_t += delta
	var player: Node2D = game.player
	lit = game.player.is_lit(global_position, 12.0)
	if _wake > 0.0:
		_wake -= delta
	elif lit and global_position.distance_to(player.global_position) < 30.0:
		# Lit but right on top of the watchman (who stood still): it recoils
		# instead of sitting there forever.
		var away: Vector2 = (global_position - player.global_position)
		if away.length() < 1.0:
			away = Vector2.RIGHT
		var dest: Vector2 = global_position + away.normalized() * 48.0
		if not game.level.is_wall(game.level.world_to_cell(dest)):
			global_position = global_position.move_toward(dest, speed * 2.0 * delta)
		_brush_cooldown = maxf(0.0, _brush_cooldown - delta)
		if _brush_cooldown <= 0.0:
			_brush_cooldown = 3.0
			game.player.fear = minf(100.0, game.player.fear + 10.0)
			game.message("You brush against something cold...", 2.0)
	elif lit:
		# Frozen by the beam - but never left blocking a one-tile doorway.
		var cell: Vector2i = game.level.world_to_cell(global_position)
		if game.level.is_doorway(cell):
			# Back out straight along the doorway (never diagonally into a wall),
			# to the side away from the watchman.
			var lvl = game.level
			var axis := Vector2(0, 1) if lvl.is_wall(cell + Vector2i.LEFT) else Vector2(1, 0)
			var away := axis if (global_position - player.global_position).dot(axis) >= 0.0 else -axis
			var back: Vector2 = lvl.cell_to_world(cell) + away * 48.0
			if not lvl.is_wall(lvl.world_to_cell(back)):
				global_position = global_position.move_toward(back, speed * 1.5 * delta)
		# Brushing past a frozen Shadow is still terrifying.
		_brush_cooldown = maxf(0.0, _brush_cooldown - delta)
		if global_position.distance_to(player.global_position) < 22.0 and _brush_cooldown <= 0.0:
			_brush_cooldown = 3.0
			game.player.fear = minf(100.0, game.player.fear + 10.0)
			game.message("You brush against something cold...", 2.0)
	else:
		_unlit_time += delta
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.5
			_path = game.level.find_path(global_position, player.global_position)
			_path_i = 1
		if _path_i < _path.size():
			var to := _path[_path_i] - global_position
			var step := speed * delta
			if to.length() <= step:
				global_position = _path[_path_i]
				_path_i += 1
			else:
				global_position += to.normalized() * step
		# A short grace after leaving the beam, so stepping past a frozen
		# Shadow is a scare, not a catch.
		if global_position.distance_to(player.global_position) < 26.0 and _unlit_time > 0.4:
			game.on_shadow_caught(self)

	if lit:
		_unlit_time = 0.0
	# Safety net: never stay inside a wall.
	var here: Vector2i = game.level.world_to_cell(global_position)
	if game.level.is_wall(here):
		global_position = _last_floor
		_path = PackedVector2Array()
	else:
		_last_floor = game.level.cell_to_world(here)

	glow.position = global_position
	glow.queue_redraw()
	queue_redraw()


func _draw() -> void:
	# A ragged mass of darkness - only ever seen in the beam.
	for i in 9:
		var a := TAU * i / 9.0 + _t * 0.7
		var r := 15.0 + sin(_t * 5.0 + i * 1.7) * 4.0
		draw_circle(Vector2(cos(a), sin(a)) * r * 0.6, r * 0.7, Color(0.03, 0.0, 0.05, 0.85))
	draw_circle(Vector2.ZERO, 16, Color(0.0, 0.0, 0.0))


func _draw_glow() -> void:
	# Its eyes are always visible. Watch them.
	var blink := fmod(_t, 4.0) > 3.85
	if blink:
		return
	var col := Color(1.0, 0.1, 0.1, 0.55 if lit else 0.95)
	glow.draw_circle(Vector2(-6, -3), 2.6, col)
	glow.draw_circle(Vector2(6, -3), 2.6, col)
