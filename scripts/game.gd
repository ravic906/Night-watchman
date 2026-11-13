extends Node2D
## One night shift: builds the world, runs the clock and decides win/lose.

const Level = preload("res://scripts/level.gd")
const Player = preload("res://scripts/player.gd")
const Checkpoint = preload("res://scripts/checkpoint.gd")
const Valuable = preload("res://scripts/valuable.gd")
const BatteryPickup = preload("res://scripts/battery_pickup.gd")
const WallLamp = preload("res://scripts/wall_lamp.gd")
const Intruder = preload("res://scripts/intruder.gd")
const ShadowEntity = preload("res://scripts/shadow.gd")
const Hud = preload("res://scripts/hud.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const AlarmPanel = preload("res://scripts/alarm_panel.gd")
const BreakerBox = preload("res://scripts/breaker_box.gd")
const OutsideDoor = preload("res://scripts/outside_door.gd")

const SHIFT_SECONDS := 360.0     # 10 PM -> 6 AM
const START_HOUR := 22
const HEARING_RANGE := 650.0
const MAX_THEFTS := 3
const MAX_BATTERIES := 2

var cfg: Dictionary
var level: Level
var player: Player
var hud: Hud
var world: Node2D
var glow_layer: CanvasLayer
var fx: Node2D

var checkpoints: Array = []
var valuables: Array = []
var lamps: Array = []
var intruders: Array = []
var shadows: Array = []
var batteries: Array = []
var doors: Array = []
var alarm = null
var breaker = null
## Everything the watchman can hold "interact" on: clocks, alarm, breaker, doors.
var devices: Array = []

var shift_len := SHIFT_SECONDS
var elapsed := 0.0
var patrol_round := 1
var punches := 0
var thefts := 0
var scared := 0
var score := 0
var ended := false
var flash := 0.0
var near_device = null
var entered := 0
var sabotages := 0

var _intruder_timer := 0.0
var _battery_timer := 12.0
var _event_timer := 18.0
var _shadow_timer := 35.0
var _noises: Array = []   # [{ "pos": Vector2, "age": float, "color": Color }]
var _messages: Array = []
var _last_cell := Vector2i(-1, -1)
var _door_cooldown := 0.0


func _ready() -> void:
	randomize()
	cfg = GameState.settings()
	if GameState.autotest:
		shift_len = 120.0
		_shadow_timer = 3.0
		Engine.time_scale = 4.0

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	var dark := CanvasModulate.new()
	dark.color = Color(0.07, 0.07, 0.11)
	add_child(dark)

	# Things that glow in the dark live on their own layer that follows the
	# camera but is not darkened by the CanvasModulate.
	glow_layer = CanvasLayer.new()
	glow_layer.name = "Glow"
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)

	level = Level.new()
	level.name = "Level"
	world.add_child(level)
	level.build()
	glow_layer.add_child(level.wall_node)

	fx = Node2D.new()
	fx.name = "Noises"
	fx.draw.connect(_draw_noises)
	glow_layer.add_child(fx)

	for pos in level.lamps:
		lamps.append(_spawn(WallLamp, pos))
	for pos in level.valuables:
		valuables.append(_spawn(Valuable, pos))
	for cp in level.checkpoints:
		var node = _spawn(Checkpoint, cp["pos"], false)
		node.cp_name = cp["name"]
		world.add_child(node)
		checkpoints.append(node)
	for lamp in lamps:
		lamp.wing = level.wing_of(lamp.position)

	alarm = _spawn(AlarmPanel, level.alarm_pos)
	breaker = _spawn(BreakerBox, level.breaker_pos)
	for pos in level.entries:
		var door = _spawn(OutsideDoor, pos, false)
		door.door_name = "west" if pos.x < level.world_size().x / 2.0 else "east"
		world.add_child(door)
		doors.append(door)
	devices = checkpoints + [alarm, breaker] + doors

	player = Player.new()
	player.name = "Watchman"
	player.position = level.player_spawn
	if GameState.start_cell.x >= 0:
		player.position = level.cell_to_world(GameState.start_cell)
	player.battery_drain = cfg["battery_drain"]
	world.add_child(player)
	player.set_camera_limits(level.world_size())
	player.use_auto = GameState.autotest

	_intruder_timer = cfg["first_intruder"]
	if GameState.autotest:
		_intruder_timer = 2.0
	_spawn_battery()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud_layer.add_child(hud)
	if GameState.use_touch_controls():
		var touch := TouchControls.new()
		hud_layer.add_child(touch)

	Music.play_game()
	message(cfg["title"], 4.0)
	message("Lock both outside doors and arm the alarm in the lobby.", 6.0)
	message("Punch all 5 clocks before 2 AM, then again before 6 AM.", 6.0)


## Creates an entity in the world plus its partner node in the glow layer.
func _spawn(script, pos: Vector2, add := true) -> Node2D:
	var node = script.new()
	node.position = pos
	var glow := Node2D.new()
	glow.position = pos
	glow_layer.add_child(glow)
	node.glow = glow
	if add:
		world.add_child(node)
	return node


func message(text: String, seconds := 3.0) -> void:
	if GameState.autotest:
		print("MSG ", clock_text(), "  ", text)
	_messages.append({"text": text, "time": seconds})
	if _messages.size() > 3:
		_messages.pop_front()


func messages() -> Array:
	return _messages


func clock_text() -> String:
	var minutes := int(elapsed / shift_len * 8.0 * 60.0)
	var hour := (START_HOUR + minutes / 60) % 24
	var minute := minutes % 60
	var h12 := hour % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, minute, "PM" if hour >= 12 else "AM"]


func add_noise(pos: Vector2, color: Color) -> void:
	if pos.distance_to(player.global_position) <= HEARING_RANGE:
		_noises.append({"pos": pos, "age": 0.0, "color": color})


func _physics_process(delta: float) -> void:
	if ended:
		return
	elapsed += delta
	flash = maxf(0.0, flash - delta * 1.5)

	for m in _messages:
		m["time"] -= delta
	_messages = _messages.filter(func(m): return m["time"] > 0.0)

	for n in _noises:
		n["age"] += delta
	_noises = _noises.filter(func(n): return n["age"] < 1.4)
	fx.queue_redraw()

	if GameState.autotest:
		_autopilot()

	_update_rounds()
	_update_interaction(delta)
	_update_fear(delta)
	_update_spawns(delta)
	_update_events(delta)
	_update_music()
	_update_doors(delta)

	for b in batteries.duplicate():
		if b.global_position.distance_to(player.global_position) < 26.0:
			player.battery = minf(100.0, player.battery + BatteryPickup.AMOUNT)
			batteries.erase(b)
			b.remove()
			message("Fresh batteries. +45%", 2.0)

	if player.fear >= 100.0:
		_end(false, "Terror got the better of you. You fled your post.")
	elif thefts >= MAX_THEFTS:
		_end(false, "Too much was stolen on your watch.")
	elif elapsed >= shift_len:
		_end_of_shift()


func _update_rounds() -> void:
	if patrol_round == 1 and elapsed >= shift_len * 0.5:
		patrol_round = 2
		for cp in checkpoints:
			cp.reset_round()
		message("2:00 AM - second round. Punch every clock again.", 4.0)


## Hold "interact" next to the nearest device that needs attention.
func _update_interaction(delta: float) -> void:
	near_device = null
	var best := INF
	for dev in devices:
		if not dev.needs_action():
			continue
		var d: float = dev.global_position.distance_to(player.global_position)
		if d < dev.interact_range and d < best:
			best = d
			near_device = dev
	var holding := Input.is_action_pressed("interact") or GameState.autotest
	for dev in devices:
		if dev == near_device and holding:
			dev.progress += delta / dev.hold_time()
			if dev.progress >= 1.0:
				dev.progress = 0.0
				dev.complete(self)
		else:
			dev.progress = maxf(0.0, dev.progress - delta * 2.0)


func sabotage_targets() -> Array:
	return checkpoints + [alarm, breaker]


func alarm_armed() -> bool:
	return alarm != null and alarm.armed


func intruders_inside() -> int:
	return intruders.filter(func(it): return it.inside).size()


func doors_locked() -> int:
	return doors.filter(func(d): return d.locked).size()


func door_nearest(pos: Vector2):
	var best = null
	var best_d := INF
	for d in doors:
		var dist: float = d.global_position.distance_to(pos)
		if dist < best_d:
			best_d = dist
			best = d
	return best


# --- duties ------------------------------------------------------------------

func on_punch(cp, was_jammed: bool) -> void:
	punches += 1
	score += 50 + (50 if was_jammed else 0)
	message(("Fixed and punched: %s" if was_jammed else "Punched in: %s") % cp.cp_name, 2.0)
	Music.stinger("punch", -4.0)


func on_alarm_armed(was_cut: bool) -> void:
	score += 50
	message("Alarm re-wired and armed. %d intruder(s) inside." % intruders_inside() if was_cut
			else "Alarm armed. You'll know when someone breaks in.", 3.0)
	Music.stinger("alarm_arm", -4.0)


func on_power_restored() -> void:
	score += 50
	for lamp in lamps:
		lamp.set_powered(true)
	message("Breaker reset. The lights come back on.", 2.5)
	Music.stinger("breaker", -3.0)


func on_door_locked(door) -> void:
	score += 25
	message("The %s door is locked." % door.door_name, 2.0)
	Music.stinger("lock", -4.0)


# --- sabotage ----------------------------------------------------------------

func on_clock_jammed(cp) -> void:
	sabotages += 1
	add_noise(cp.global_position, Color(1.0, 0.6, 0.2))
	message("Something rattles near the %s clock..." % cp.cp_name, 2.5)


func on_alarm_cut(panel) -> void:
	sabotages += 1
	Music.sfx_at("alarm_cut", panel.global_position, 0.0, 1.0, 2400.0)
	message("The alarm panel squeals and goes dead. Someone cut it!", 3.5)
	player.fear = minf(100.0, player.fear + 5.0)


func on_power_cut(wing: String, box) -> void:
	sabotages += 1
	for lamp in lamps:
		if lamp.wing == wing:
			lamp.set_powered(false)
	Music.sfx_at("breaker", box.global_position, 0.0, 0.85, 2400.0)
	message("A breaker clunks off - the %s wing goes dark." % wing, 3.5)
	player.fear = minf(100.0, player.fear + 6.0)


func on_lock_picked(_intruder, door) -> void:
	sabotages += 1
	if alarm_armed():
		message("ALARM: the %s door lock was forced!" % door.door_name, 3.0)


func on_saboteur_caught(_intruder) -> void:
	scared += 1
	score += 150
	message("Caught a saboteur in the act! They ran.", 2.5)
	Music.stinger("spotted", -3.0)


# --- intruders coming and going ---------------------------------------------

func on_intruder_entered(_intruder, door) -> void:
	entered += 1
	var where: String = door.door_name if door != null else "?"
	Music.sfx_at("door_creak", door.global_position if door != null else player.global_position,
			0.0, randf_range(0.85, 1.05), 1400.0)
	if alarm_armed():
		message("ALARM: break-in at the %s door! (%d inside)" % [where, intruders_inside()], 3.5)
		Music.stinger("alarm_chime", -2.0)


func on_intruder_exit(_intruder, pos: Vector2) -> void:
	var door = door_nearest(pos)
	if door != null and door.locked:
		door.locked = false
		door.refresh()
		if alarm_armed():
			message("ALARM: the %s door was opened from inside." % door.door_name, 3.0)


func in_safe_light(pos: Vector2) -> bool:
	for lamp in lamps:
		if lamp.covers(pos):
			return true
	return false


func _update_fear(delta: float) -> void:
	var rate: float = cfg["fear_dark"]
	if player.light_active() or in_safe_light(player.global_position):
		rate = -6.0
	for s in shadows:
		var d: float = s.global_position.distance_to(player.global_position)
		if d < 240.0:
			rate += (240.0 - d) / 240.0 * 9.0
		if s.lit:
			rate += 2.0
	player.fear = clampf(player.fear + rate * delta, 0.0, 100.0)


func _update_spawns(delta: float) -> void:
	_intruder_timer -= delta
	if _intruder_timer <= 0.0:
		_intruder_timer = cfg["intruder_interval"] * randf_range(0.8, 1.2)
		if doors_locked() < doors.size():
			_intruder_timer *= 0.7  # an open door invites company
		var any_left := valuables.any(func(v): return v.available())
		if intruders.size() < cfg["intruder_max"] and any_left:
			_spawn_intruder()

	_battery_timer -= delta
	if _battery_timer <= 0.0:
		_battery_timer = randf_range(18.0, 28.0)
		if batteries.size() < MAX_BATTERIES:
			_spawn_battery()

	if shadows.size() < int(cfg["shadows"]):
		_shadow_timer -= delta
		if _shadow_timer <= 0.0:
			_shadow_timer = 25.0
			var s = _spawn(ShadowEntity, _far_shadow_spawn(), false)
			s.game = self
			s.speed = cfg["shadow_speed"]
			world.add_child(s)
			shadows.append(s)
			message("Something moves in the dark...", 3.0)
			player.fear = minf(100.0, player.fear + 10.0)


func _spawn_intruder() -> void:
	# Thieves prefer an unlocked door; otherwise they pick a lock nobody is
	# already working on.
	var open := doors.filter(func(d): return not d.locked)
	var free := doors.filter(func(d): return d.locked and d.picker == null)
	var door = null
	if not open.is_empty():
		door = open.pick_random()
	elif not free.is_empty():
		door = free.pick_random()
	else:
		return
	var it = _spawn(Intruder, door.global_position, false)
	it.game = self
	it.door = door
	it.speed = cfg["intruder_speed"]
	it.expose_time = cfg["expose_time"]
	it.sabotage_chance = cfg["sabotage_chance"]
	it.lockpick_time = cfg["lockpick_time"]
	intruders.append(it)
	world.add_child(it)


func _spawn_battery() -> void:
	var pos: Vector2 = level.random_floor_far_from(player.global_position, 350.0)
	var b = _spawn(BatteryPickup, pos)
	batteries.append(b)


func _far_shadow_spawn() -> Vector2:
	var best: Vector2 = level.shadow_spawns[0]
	for p in level.shadow_spawns:
		if p.distance_to(player.global_position) > best.distance_to(player.global_position):
			best = p
	return best


func _update_events(delta: float) -> void:
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(14.0, 26.0) / float(cfg["event_mult"])
	var live_lamps := lamps.filter(func(l): return not l.dead)
	match randi() % 3:
		0:
			if not live_lamps.is_empty():
				live_lamps.pick_random().flicker(randf_range(2.0, 5.0))
				message("The lights flicker...", 2.5)
		1:
			var pos: Vector2 = level.random_floor_far_from(player.global_position, 150.0)
			var at := player.global_position + (pos - player.global_position).limit_length(450.0)
			add_noise(at, Color(0.7, 0.7, 0.7))
			Music.sfx_at("door_creak", at, -3.0, randf_range(0.7, 1.0), 1200.0)
			message(["A door creaks somewhere.", "Footsteps? No... just the pipes.", "Something fell over."].pick_random(), 2.5)
			player.fear = minf(100.0, player.fear + 3.0)
		2:
			if GameState.night >= 3 and live_lamps.size() > 3:
				live_lamps.pick_random().kill()
				message("A bulb bursts somewhere in the dark.", 3.0)
				player.fear = minf(100.0, player.fear + 6.0)
			elif not live_lamps.is_empty():
				live_lamps.pick_random().flicker(randf_range(1.0, 3.0))


func _update_doors(delta: float) -> void:
	_door_cooldown = maxf(0.0, _door_cooldown - delta)
	var cell: Vector2i = level.world_to_cell(player.global_position)
	if cell != _last_cell:
		_last_cell = cell
		if level.is_doorway(cell) and _door_cooldown <= 0.0:
			_door_cooldown = 1.2
			Music.stinger("door_swing", -9.0, randf_range(0.9, 1.15))
			level.swing_door(cell)


## Danger (0..1) drives the string layer: the Shadow closing in, a thief
## nearby, or a dying flashlight.
func _update_music() -> void:
	var pp := player.global_position
	var danger := 0.0
	for s in shadows:
		danger = maxf(danger, 1.0 - s.global_position.distance_to(pp) / 300.0)
	for it in intruders:
		danger = maxf(danger, (1.0 - it.global_position.distance_to(pp) / 350.0) * 0.7)
	if player.battery < 15.0:
		danger = maxf(danger, 0.5)
	Music.set_mood(player.fear / 100.0, danger)


func on_intruder_scared(_intruder, dropped_loot: bool) -> void:
	scared += 1
	score += 150 if dropped_loot else 100
	message("Thief scared off - they dropped the loot!" if dropped_loot else "Thief scared off!", 2.5)
	Music.stinger("spotted", -3.0)


func on_item_grabbed(intruder, _valuable) -> void:
	add_noise(intruder.global_position, Color(1.0, 0.4, 0.3))
	message("You hear glass breaking!", 2.5)


func on_theft(_intruder, _valuable) -> void:
	thefts += 1
	score -= 200
	message("Something was stolen! (%d/%d)" % [thefts, MAX_THEFTS], 3.0)
	Music.stinger("theft")


func on_shadow_caught(s) -> void:
	player.fear = minf(100.0, player.fear + 40.0)
	flash = 1.0
	player.global_position = level.player_spawn
	player.stun(1.0)
	s.reset_to(_far_shadow_spawn())
	message("IT TOUCHED YOU. You come to in the lobby.", 3.5)
	Music.stinger("scare")


func _end_of_shift() -> void:
	if punches < checkpoints.size():
		_end(false, "6:00 AM. You skipped most of your rounds - you're fired.")
	else:
		score += 500 + int((100.0 - player.fear) * 2.0)
		_end(true, "6:00 AM. The day guard arrives. You made it.")


func _end(win: bool, reason: String) -> void:
	if ended:
		return
	ended = true
	player.set_physics_process(false)
	Music.end_shift(win)
	message(reason, 10.0)
	var result := {
		"win": win,
		"reason": reason,
		"night": GameState.night,
		"score": maxi(0, score),
		"punches": punches,
		"punches_total": checkpoints.size() * 2,
		"scared": scared,
		"thefts": thefts,
		"entered": entered,
		"sabotages": sabotages,
		"time": clock_text(),
	}
	print("Shift ended: ", result)
	if GameState.autotest:
		print("AUTOTEST DUTIES: alarm armed=%s cut=%s, doors locked %d/%d, dead wings=%s, jammed clocks=%d" % [
			alarm.armed, alarm.cut, doors_locked(), doors.size(), breaker.dead_wings(),
			checkpoints.filter(func(c): return c.jammed).size()])
	await get_tree().create_timer(2.5).timeout
	GameState.finish_night(result)


## Self-playing watchman for the headless smoke test: walk to the nearest
## device that needs attention (clocks, alarm, breaker, doors).
func _autopilot() -> void:
	var target = null
	var best := INF
	for dev in devices:
		if dev.needs_action():
			var d: float = dev.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				target = dev
	player.auto_move = Vector2.ZERO
	if target != null and best > 20.0:
		var path: PackedVector2Array = level.find_path(player.global_position, target.global_position)
		if path.size() > 1:
			player.auto_move = (path[1] - player.global_position).normalized()
		elif path.size() == 1:
			player.auto_move = (path[0] - player.global_position).normalized()


func _draw_noises() -> void:
	for n in _noises:
		var t: float = n["age"] / 1.4
		var c: Color = n["color"]
		c.a = (1.0 - t) * 0.6
		fx.draw_arc(n["pos"], 8.0 + t * 46.0, 0, TAU, 28, c, 2.0)
