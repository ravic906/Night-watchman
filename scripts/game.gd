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

const SHIFT_SECONDS := 360.0     # 10 PM -> 6 AM
const START_HOUR := 22
const PUNCH_TIME := 1.0
const PUNCH_RANGE := 48.0
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

var shift_len := SHIFT_SECONDS
var elapsed := 0.0
var patrol_round := 1
var punches := 0
var thefts := 0
var scared := 0
var score := 0
var ended := false
var flash := 0.0
var near_checkpoint = null

var _intruder_timer := 0.0
var _battery_timer := 12.0
var _event_timer := 18.0
var _shadow_timer := 35.0
var _noises: Array = []   # [{ "pos": Vector2, "age": float, "color": Color }]
var _messages: Array = []


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

	player = Player.new()
	player.name = "Watchman"
	player.position = level.player_spawn
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
	message("Punch all 5 clocks before 2 AM, then again before 6 AM.", 5.0)


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
	_update_punching(delta)
	_update_fear(delta)
	_update_spawns(delta)
	_update_events(delta)
	_update_music()

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


func _update_punching(delta: float) -> void:
	near_checkpoint = null
	var best := PUNCH_RANGE
	for cp in checkpoints:
		var d: float = cp.global_position.distance_to(player.global_position)
		if d < best and not cp.done:
			best = d
			near_checkpoint = cp
	var holding := Input.is_action_pressed("interact") or GameState.autotest
	for cp in checkpoints:
		if cp == near_checkpoint and holding:
			cp.progress += delta / PUNCH_TIME
			if cp.progress >= 1.0:
				cp.done = true
				cp.progress = 0.0
				punches += 1
				score += 50
				message("Punched in: %s" % cp.cp_name, 2.0)
				Music.stinger("punch", -4.0)
		else:
			cp.progress = maxf(0.0, cp.progress - delta * 2.0)


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
	var entry: Vector2 = level.entries.pick_random()
	var it = _spawn(Intruder, entry, false)
	it.game = self
	it.speed = cfg["intruder_speed"]
	it.expose_time = cfg["expose_time"]
	world.add_child(it)
	intruders.append(it)
	add_noise(entry, Color(1.0, 0.7, 0.4))


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
			add_noise(player.global_position + (pos - player.global_position).limit_length(450.0), Color(0.7, 0.7, 0.7))
			message(["A door creaks somewhere.", "Footsteps? No... just the pipes.", "Something fell over."].pick_random(), 2.5)
			player.fear = minf(100.0, player.fear + 3.0)
		2:
			if GameState.night >= 3 and live_lamps.size() > 3:
				live_lamps.pick_random().kill()
				message("A bulb bursts somewhere in the dark.", 3.0)
				player.fear = minf(100.0, player.fear + 6.0)
			elif not live_lamps.is_empty():
				live_lamps.pick_random().flicker(randf_range(1.0, 3.0))


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
		"time": clock_text(),
	}
	print("Shift ended: ", result)
	await get_tree().create_timer(2.5).timeout
	GameState.finish_night(result)


## Self-playing watchman for the headless smoke test: walk to the nearest
## clock that still needs punching and sweep the flashlight around.
func _autopilot() -> void:
	var target = null
	var best := INF
	for cp in checkpoints:
		if not cp.done:
			var d: float = cp.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				target = cp
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
