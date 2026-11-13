extends Node2D
## A thief. Sneaks to a valuable, grabs it and runs for the nearest door.
## Keep your flashlight on them long enough and they bolt empty-handed.

enum State { SNEAK, STEAL, ESCAPE, FLEE }

const STEAL_TIME := 3.0

var game
var glow: Node2D
var speed := 70.0
var expose_time := 1.5

var state := State.SNEAK
var target = null
var exposure := 0.0
var lit := false
var facing := Vector2.RIGHT

var _path := PackedVector2Array()
var _path_i := 0
var _steal_left := 0.0
var _step_timer := 0.0
var _walk_phase := 0.0
var _gone := false


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	_step_timer = randf_range(1.0, 3.0)
	_pick_target()


func _pick_target() -> void:
	var options: Array = game.valuables.filter(func(v): return v.available())
	if options.is_empty():
		_run_for_exit(State.FLEE)
		return
	target = options.pick_random()
	state = State.SNEAK
	_path = game.level.find_path(global_position, target.global_position + Vector2(0, 26))
	_path_i = 0


func _run_for_exit(next_state: State) -> void:
	state = next_state
	var best := global_position
	var best_d := INF
	for e in game.level.entries:
		var d: float = global_position.distance_to(e)
		if d < best_d:
			best_d = d
			best = e
	_path = game.level.find_path(global_position, best)
	_path_i = 0


func _follow(delta: float, spd: float) -> bool:
	if _path_i >= _path.size():
		return true
	var to := _path[_path_i] - global_position
	var step := spd * delta
	var before := floori(_walk_phase / PI)
	_walk_phase += delta * spd * 0.08
	if floori(_walk_phase / PI) != before:
		var running := state == State.FLEE or state == State.ESCAPE
		Music.sfx_at("step" if running else "sneak", global_position,
				-4.0 if running else -6.0, randf_range(0.85, 1.05), 700.0)
	if to.length() <= step:
		global_position = _path[_path_i]
		_path_i += 1
		return _path_i >= _path.size()
	facing = to.normalized()
	global_position += facing * step
	return false


func _physics_process(delta: float) -> void:
	if _gone:
		return
	lit = game.player.is_lit(global_position)
	if lit:
		exposure += delta
	else:
		exposure = maxf(0.0, exposure - delta * 0.5)

	match state:
		State.SNEAK, State.STEAL:
			if exposure >= expose_time:
				game.on_intruder_scared(self, false)
				_run_for_exit(State.FLEE)
			elif target == null or not target.available():
				_pick_target()
			elif state == State.SNEAK:
				if _follow(delta, speed):
					state = State.STEAL
					_steal_left = STEAL_TIME
			else:
				_steal_left -= delta
				if _steal_left <= 0.0:
					target.carrier = self
					target.refresh()
					game.on_item_grabbed(self, target)
					_run_for_exit(State.ESCAPE)
		State.ESCAPE:
			if exposure >= expose_time * 0.8:
				target.carrier = null
				target.refresh()
				target = null
				game.on_intruder_scared(self, true)
				_run_for_exit(State.FLEE)
			elif _follow(delta, speed * 1.15):
				target.carrier = null
				target.stolen = true
				target.refresh()
				game.on_theft(self, target)
				_leave()
		State.FLEE:
			if _follow(delta, speed * 1.9):
				_leave()

	# Footsteps you can hear (not see) when they are moving nearby.
	if state != State.STEAL:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = randf_range(2.5, 5.0)
			game.add_noise(global_position, Color(0.85, 0.85, 1.0))

	glow.position = global_position
	glow.queue_redraw()
	queue_redraw()


func _leave() -> void:
	_gone = true
	Music.sfx_at("door_slam", global_position, -2.0, randf_range(0.9, 1.05), 1400.0)
	game.intruders.erase(self)
	glow.queue_free()
	queue_free()


func _draw() -> void:
	var side := facing.orthogonal()
	var bob := sin(_walk_phase) * 3.0
	draw_circle(side * 6 + facing * bob, 4.5, Color(0.05, 0.05, 0.05))
	draw_circle(-side * 6 - facing * bob, 4.5, Color(0.05, 0.05, 0.05))
	draw_circle(Vector2.ZERO, 13, Color(0.2, 0.22, 0.2))
	draw_circle(facing * 2, 8, Color(0.1, 0.1, 0.1))  # hood
	draw_line(facing * 7 + side * 3, facing * 7 - side * 3, Color(0.85, 0.75, 0.6), 2)  # eyes slit
	if state == State.ESCAPE:
		draw_circle(-facing * 12, 8, Color(0.4, 0.32, 0.2))  # loot bag


func _draw_glow() -> void:
	if exposure > 0.0 and state != State.FLEE:
		var need := expose_time * (0.8 if state == State.ESCAPE else 1.0)
		var f := clampf(exposure / need, 0.0, 1.0)
		glow.draw_arc(Vector2.ZERO, 20, -PI / 2, -PI / 2 + TAU * f, 24, Color(1, 0.85, 0.3, 0.9), 3)
