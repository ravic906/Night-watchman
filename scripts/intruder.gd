extends Node2D
## A thief. Gets in through an entrance (picking a lock, smashing or prying a window),
## may sabotage one of the watchman's duties, then sneaks to a valuable,
## grabs it and runs for the nearest door.
## Keep your flashlight on them long enough and they bolt empty-handed.

enum State { PICK, SNEAK, STEAL, ESCAPE, FLEE, GO_SABOTAGE, SABOTAGE, GO_FORCE, FORCE }

const STEAL_TIME := 3.0

var game
var glow: Node2D
var speed := 70.0
var expose_time := 1.5
var sabotage_chance := 0.4
var lockpick_time := 6.0
var door = null            # the entrance (door or window) this thief came in by
## A thief scared away from an entrance comes back once, somewhere else.
var retries_left := 1
## Escape warning (balance option): the alarm is tracking this loot carrier.
var warned := false
var exit_name := ""
var _warn_timer := 0.0
var _pick_total := 1.0
## Mall: the shutter this thief is forcing, and what it was doing before.
var gate = null
var _resume := State.SNEAK
var _blocked_at := Vector2.INF

var state := State.SNEAK
var target = null          # valuable
var device = null          # sabotage target
var inside := false
var exposure := 0.0
var lit := false
var facing := Vector2.RIGHT

var _path := PackedVector2Array()
var _path_i := 0
var _steal_left := 0.0
var _work_left := 0.0
var _work_sound := 0.0
var _did_sabotage := false
var _step_timer := 0.0
var _walk_phase := 0.0
var _gone := false


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	_step_timer = randf_range(1.0, 3.0)
	if door != null and not door.is_open():
		state = State.PICK
		_work_left = door.entry_work_time(game.cfg)
		_pick_total = _work_left
		door.picker = self
		door.pick_progress = 0.0
	else:
		_enter()


func is_escaping() -> bool:
	return state == State.ESCAPE


func _enter() -> void:
	inside = true
	if door != null and door.picker == self:
		door.picker = null
		door.refresh()
	game.on_intruder_entered(self, door)
	_choose_objective()


func _choose_objective() -> void:
	if not _did_sabotage and randf() < sabotage_chance:
		var options: Array = game.sabotage_targets().filter(func(d): return d.can_sabotage())
		if not options.is_empty():
			device = options.pick_random()
			device.saboteur = self
			state = State.GO_SABOTAGE
			_path = game.level.find_path(global_position, device.global_position)
			_path_i = 0
			return
	_pick_target()


func _pick_target() -> void:
	var options: Array = game.valuables.filter(func(v): return v.available())
	if options.is_empty():
		_run_for_exit(State.FLEE)
		return
	target = options.pick_random()
	var route: PackedVector2Array = game.level.find_path(global_position, target.global_position + Vector2(0, 26))
	if route.is_empty() and target.gate != null and target.gate.closed:
		# Only force the shutter if it actually stands between us and the loot.
		_go_force(target.gate, State.SNEAK)
		return
	state = State.SNEAK
	_path = route
	_path_i = 0


## Walk up to a closed shutter (from whichever side we are on) to force it.
func _go_force(sh, resume: State) -> void:
	gate = sh
	_resume = resume
	state = State.GO_FORCE
	var best := PackedVector2Array()
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var spot: Vector2 = sh.global_position + d * 48.0
		if game.level.is_cell_solid(spot) or game.level.is_wall(game.level.world_to_cell(spot)):
			continue
		var p: PackedVector2Array = game.level.find_path(global_position, spot)
		if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
			best = p
	_path = best
	_path_i = 0
	if best.is_empty():
		gate = null
		_drop_loot()
		_run_for_exit(State.FLEE)


## Carry on with what we were doing before a shutter got in the way.
func _resume_after_gate() -> void:
	if gate != null and gate.picker == self:
		gate.picker = null
		gate.refresh()
	gate = null
	match _resume:
		State.ESCAPE, State.FLEE:
			_run_for_exit(_resume)
		State.GO_SABOTAGE:
			if device != null:
				state = State.GO_SABOTAGE
				_path = game.level.find_path(global_position, device.global_position)
				_path_i = 0
			else:
				_pick_target()
		_:
			_pick_target()


func _carrying() -> bool:
	return target != null and target.carrier == self


func _drop_loot() -> void:
	if target != null and target.carrier == self:
		target.carrier = null
		target.refresh()
		target = null


## Is the reserved device still worth sabotaging (the guard may have
## changed it, or another thief got there first)?
func _device_still_valid() -> bool:
	if device == null:
		return false
	return device.can_sabotage(self)


func _release_device() -> void:
	if device != null and device.saboteur == self:
		device.saboteur = null
	device = null


func _run_for_exit(next_state: State) -> void:
	state = next_state
	var best := global_position
	var best_d := INF
	for e in game.entrances:
		if not e.passable_exit():
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e.global_position
			exit_name = e.entrance_label()
	_path = game.level.find_path(global_position, best)
	_path_i = 0


func _follow(delta: float, spd: float) -> bool:
	if _path.is_empty():
		# No route at all (e.g. a shutter closed us in): never treat as arrived.
		_blocked_at = global_position
		return false
	if _path_i >= _path.size():
		return true
	# A shutter came down in front of us.
	if game.level.is_cell_solid(_path[_path_i]):
		_blocked_at = _path[_path_i]
		return false
	var to := _path[_path_i] - global_position
	var step := spd * delta
	var before := floori(_walk_phase / PI)
	_walk_phase += delta * spd * 0.08
	if floori(_walk_phase / PI) != before and not game.is_masked(global_position):
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


## Periodic sound while working on a lock, a window or a device.
func _work_noise(delta: float, volume_db: float, sound := "lockpick") -> void:
	_work_sound -= delta
	if _work_sound <= 0.0:
		_work_sound = randf_range(0.7, 1.1)
		if sound != "" and not game.is_masked(global_position):
			Music.sfx_at(sound, global_position, volume_db, randf_range(0.9, 1.1), 900.0)
		game.add_noise(global_position, Color(1.0, 0.6, 0.3))


func _physics_process(delta: float) -> void:
	if _gone:
		return
	lit = game.player.is_lit(global_position)
	if lit:
		exposure += delta
	else:
		exposure = maxf(0.0, exposure - delta * 0.5)

	match state:
		State.PICK:
			if door.is_open():
				# Another thief left it open from inside: no need to pick it.
				door.picker = null
				door.refresh()
				_enter()
			elif exposure >= expose_time:
				door.picker = null
				door.refresh()
				game.on_entry_foiled(self, door)
				_leave(false)
				return
			else:
				_work_left -= delta
				door.pick_progress = clampf(1.0 - _work_left / _pick_total, 0.0, 1.0)
				_work_noise(delta, -3.0, door.work_sound())
				if _work_left <= 0.0:
					door.force_open(game)
					_enter()
		State.GO_SABOTAGE:
			if exposure >= expose_time:
				_release_device()
				game.on_intruder_scared(self, false)
				_run_for_exit(State.FLEE)
			elif not _device_still_valid():
				_release_device()
				_pick_target()
			elif _follow(delta, speed):
				state = State.SABOTAGE
				_work_left = device.sabotage_time()
		State.SABOTAGE:
			if exposure >= expose_time * 0.8:
				_release_device()
				game.on_saboteur_caught(self)
				_run_for_exit(State.FLEE)
			elif not _device_still_valid():
				_release_device()
				_pick_target()
			else:
				_work_left -= delta
				_work_noise(delta, -8.0)
				if _work_left <= 0.0:
					var d = device
					_release_device()
					d.sabotage(game)
					_did_sabotage = true
					_pick_target()
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
					_run_for_exit(State.ESCAPE)
					game.on_item_grabbed(self, target)
		State.ESCAPE:
			if warned:
				_warn_timer -= delta
				if _warn_timer <= 0.0:
					_warn_timer = 1.5
					game.add_noise(global_position, Color(1.0, 0.35, 0.3), true)
			if exposure >= expose_time * 0.8:
				target.carrier = null
				target.refresh()
				target = null
				game.on_intruder_scared(self, true)
				_run_for_exit(State.FLEE)
			elif _follow(delta, speed * float(game.cfg.get("escape_speed", 1.15))):
				target.carrier = null
				target.stolen = true
				target.refresh()
				game.on_theft(self, target)
				_leave()
		State.FLEE:
			if _follow(delta, speed * 1.9):
				_leave()
		State.GO_FORCE:
			if exposure >= expose_time:
				var had_loot := _carrying()
				_drop_loot()
				gate = null
				game.on_intruder_scared(self, had_loot)
				_run_for_exit(State.FLEE)
			elif not gate.closed:
				_resume_after_gate()
			elif _follow(delta, speed):
				state = State.FORCE
				_work_left = gate.force_time()
				_pick_total = _work_left
		State.FORCE:
			if gate.picker == null:
				gate.picker = self
			if exposure >= expose_time * 0.8:
				var had_loot := _carrying()
				_drop_loot()
				if gate.picker == self:
					gate.picker = null
					gate.refresh()
				gate = null
				if had_loot:
					game.on_intruder_scared(self, true)
				else:
					game.on_saboteur_caught(self)
				_run_for_exit(State.FLEE)
			elif not gate.closed:
				_resume_after_gate()
			elif gate.picker == self:
				_work_left -= delta
				gate.pick_progress = clampf(1.0 - _work_left / _pick_total, 0.0, 1.0)
				_work_noise(delta, -1.0, "shutter_force")
				if _work_left <= 0.0:
					var g = gate
					g.picker = null
					g.force_open()
					_resume_after_gate()

	# Blocked by a closed shutter on the way: force it, then carry on.
	if _blocked_at != Vector2.INF and not _gone:
		var at := _blocked_at
		_blocked_at = Vector2.INF
		var sh = game.shutter_at(at)
		if sh == null:
			sh = game.nearest_reachable_closed_shutter(global_position)
		var resume: State = _resume if state == State.GO_FORCE else state
		if sh != null and state in [State.SNEAK, State.ESCAPE, State.FLEE, State.GO_SABOTAGE, State.GO_FORCE]:
			_go_force(sh, resume)
		elif state in [State.ESCAPE, State.FLEE, State.GO_FORCE]:
			# Truly walled in: give up quietly (dropping anything carried).
			_drop_loot()
			_leave(false)
			return
		elif state == State.GO_SABOTAGE:
			_release_device()
			_pick_target()
		elif state == State.SNEAK:
			target = null
			_run_for_exit(State.FLEE)

	# Footsteps you can hear (not see) when they are moving nearby.
	if state not in [State.STEAL, State.PICK, State.SABOTAGE, State.FORCE]:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = randf_range(2.5, 5.0)
			game.add_noise(global_position, Color(0.85, 0.85, 1.0))

	glow.position = global_position
	glow.queue_redraw()
	queue_redraw()


## Leave the building. Thieves who were inside leave the door they used
## unlocked behind them.
func _leave(was_inside := true) -> void:
	_gone = true
	_release_device()
	_drop_loot()
	if gate != null and gate.picker == self:
		gate.picker = null
		gate.refresh()
	if was_inside and inside:
		game.on_intruder_exit(self, global_position)
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
	if state in [State.SABOTAGE, State.PICK, State.FORCE]:
		draw_line(facing * 10, facing * 20, Color(0.7, 0.7, 0.75), 2)  # tool


func _draw_glow() -> void:
	if exposure > 0.0 and state != State.FLEE:
		var need := expose_time * (0.8 if state in [State.ESCAPE, State.SABOTAGE] else 1.0)
		var f := clampf(exposure / need, 0.0, 1.0)
		glow.draw_arc(Vector2.ZERO, 20, -PI / 2, -PI / 2 + TAU * f, 24, Color(1, 0.85, 0.3, 0.9), 3)
