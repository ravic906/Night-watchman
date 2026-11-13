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
const WindowPane = preload("res://scripts/window.gd")
const Shutter = preload("res://scripts/shutter.gd")
const CallSpot = preload("res://scripts/call_spot.gd")
const Machine = preload("res://scripts/machine.gd")

const MAX_COMPLAINTS := 3

const SHIFT_SECONDS := 360.0     # 10 PM -> 6 AM
const START_HOUR := 22
const HEARING_RANGE := 650.0
const MAX_THEFTS := 3
const MAX_BATTERIES := 3

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
var windows: Array = []
## Location twists.
var shutters: Array = []
var call_spots: Array = []
var machines: Array = []
var complaints := 0
var calls_answered := 0
var twist_events := 0
var _call_timer := 25.0
## The location being guarded (map_def.gd instance).
var location
## Every way into the building: doors + windows.
var entrances: Array = []
var alarm = null
var breaker = null
## Everything the watchman can hold "interact" on: clocks, alarm, breaker, doors.
var devices: Array = []

var shift_len := SHIFT_SECONDS
var elapsed := 0.0
## Hourly patrol orders: which hour (0 = 10 PM) and how the night is going.
var patrol_hour := -1
var _next_picks: Array = []
var _window := {}
var _last_player_pos := Vector2.INF
var punches := 0
var orders_total := 0
var orders_missed := 0
var crew_sent := false
var retries := 0
var thefts := 0
var scared := 0
var score := 0
var ended := false
var flash := 0.0
## Seconds during which fear cannot rise (after waking from a Shadow touch).
var fear_grace := 0.0
## Always-on lamp over the security desk (the start tile).
var desk_light: PointLight2D
var near_device = null
var entered := 0
var escaped := 0
var touches := 0
var loot_recovered := 0
var sabotages := 0

var _intruder_timer := 0.0
var _battery_timer := 12.0
var _event_timer := 18.0
var _shadow_timer := 35.0
var _noises: Array = []   # [{ "pos": Vector2, "age": float, "color": Color }]
var _messages: Array = []
## Full message history for the Log tab: [{ "time": String, "text": String }].
var log_entries: Array = []
var _retry_queue: Array = []   # [{ "time": float, "avoid": entrance, "retries": int }]
var _last_cell := Vector2i(-1, -1)
var _door_cooldown := 0.0


func _ready() -> void:
	if GameState.seed_value >= 0:
		seed(GameState.seed_value)
	else:
		randomize()
	cfg = GameState.settings()
	if GameState.fast:
		Engine.time_scale = 4.0
	if GameState.autotest:
		_shadow_timer = 3.0
		Engine.time_scale = 6.0

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

	location = GameState.location_def()
	level = Level.new()
	level.name = "Level"
	world.add_child(level)
	level.build(location)
	glow_layer.add_child(level.wall_node)

	fx = Node2D.new()
	fx.name = "Noises"
	fx.draw.connect(_draw_noises)
	glow_layer.add_child(fx)

	for pos in level.lamps:
		var lamp = _spawn(WallLamp, pos, false)
		lamp.tint = location.theme["lamp"]
		world.add_child(lamp)
		lamps.append(lamp)
	for pos in level.valuables:
		var v = _spawn(Valuable, pos, false)
		v.style = location.loot
		world.add_child(v)
		valuables.append(v)
	for cp in level.checkpoints:
		var node = _spawn(Checkpoint, cp["pos"], false)
		node.cp_name = cp["name"]
		world.add_child(node)
		checkpoints.append(node)
	for lamp in lamps:
		lamp.wing = level.wing_of(lamp.position)

	alarm = _spawn(AlarmPanel, level.alarm_pos)
	breaker = _spawn(BreakerBox, level.breaker_pos)
	for e in level.entries:
		var door = _spawn(OutsideDoor, e["pos"], false)
		door.door_name = e["name"]
		door.inward = level.inward_of(e["pos"])
		world.add_child(door)
		doors.append(door)
	for w in level.windows:
		var win = _spawn(WindowPane, w["pos"], false)
		win.room = w["name"]
		world.add_child(win)
		windows.append(win)
	for sh in level.shutters:
		var node = _spawn(Shutter, sh["pos"], false)
		node.shop = sh["name"]
		node.game = self
		world.add_child(node)
		shutters.append(node)
	for c in level.call_spots:
		var node = _spawn(CallSpot, c["pos"], false)
		node.flat = c["name"]
		world.add_child(node)
		call_spots.append(node)
	for m in level.machines:
		var node = _spawn(Machine, m["pos"], false)
		node.machine_name = m["name"]
		node.game = self
		world.add_child(node)
		machines.append(node)
	entrances = doors + windows
	devices = checkpoints + [alarm, breaker] + doors + windows + shutters + call_spots + machines
	_assign_shop_gates()

	desk_light = PointLight2D.new()
	desk_light.texture = preload("res://scripts/flashlight.gd").make_radial_texture(256)
	desk_light.texture_scale = 130.0 / 128.0
	desk_light.color = Color(0.85, 0.9, 1.0)
	desk_light.energy = 0.8
	desk_light.position = level.player_spawn
	world.add_child(desk_light)

	player = Player.new()
	player.name = "Watchman"
	player.position = level.player_spawn
	if GameState.start_cell.x >= 0:
		player.position = level.cell_to_world(GameState.start_cell)
	player.battery_drain = cfg["battery_drain"]
	world.add_child(player)
	player.set_camera_limits(level.world_size())
	player.use_auto = GameState.autotest or GameState.inputs_path != ""
	_load_inputs()

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
	message("%s - %s" % [location.title, GameState.difficulty_name()], 4.0)
	message(location.duty_hint, 6.0, false)
	message("Every hour the radio tells you which clocks to punch.", 6.0, false)


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


## Score never goes below zero.
func add_score(n: int) -> void:
	score = maxi(0, score + n)


## Every message goes to the log (Objectives panel > Log tab). With `toast`,
## it also pops up as the single line in the middle of the screen.
func message(text: String, seconds := 3.0, toast := true) -> void:
	if GameState.autotest:
		print("MSG ", clock_text(), "  ", text)
	log_entries.append({"time": clock_text(), "text": text})
	if log_entries.size() > 40:
		log_entries.pop_front()
	if toast:
		_messages = [{"text": text, "time": seconds}]


## Pop-up only (the full text is logged separately).
func toast(text: String, seconds := 3.0) -> void:
	_messages = [{"text": text, "time": seconds}]


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


## True if a running machine drowns out sounds at `pos` (factory twist).
func is_masked(pos: Vector2) -> bool:
	return machines.any(func(m): return m.masks(pos))


func add_noise(pos: Vector2, color: Color, anywhere := false) -> void:
	if is_masked(pos) and not anywhere:
		return
	if anywhere or pos.distance_to(player.global_position) <= HEARING_RANGE:
		_noises.append({"pos": pos, "age": 0.0, "color": color})


func _physics_process(delta: float) -> void:
	if ended:
		return
	elapsed += delta
	_update_harness()
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
	_update_calls(delta)
	if not _window.is_empty():
		if _last_player_pos != Vector2.INF:
			_window["walked"] += player.global_position.distance_to(_last_player_pos)
		_last_player_pos = player.global_position

	for b in batteries.duplicate():
		if b.global_position.distance_to(player.global_position) < 26.0 and player.battery < 95.0:
			player.battery = minf(100.0, player.battery + BatteryPickup.AMOUNT)
			batteries.erase(b)
			b.remove()
			message("Fresh batteries. +45%", 2.0)

	if GameState.autotest_survive:
		player.fear = minf(player.fear, 90.0)
		if elapsed >= shift_len:
			_end_of_shift()
	elif complaints >= MAX_COMPLAINTS:
		_end(false, "The residents complained to management. You're fired.")
	elif player.fear >= 100.0:
		_end(false, "Terror got the better of you. You fled your post.")
	elif thefts >= max_thefts():
		_end(false, "Too much was stolen on your watch.")
	elif elapsed >= shift_len:
		_end_of_shift()


const HOURS := 8   # 10 PM -> 6 AM


func current_hour() -> int:
	return mini(int(elapsed / shift_len * HOURS), HOURS - 1)


## How far through the night we are (0 at 10 PM, 1 at 6 AM).
func night_progress() -> float:
	return clampf(elapsed / shift_len, 0.0, 1.0)


func hour_label(h: int) -> String:
	var hour := (START_HOUR + h) % 24
	var h12 := hour % 12
	if h12 == 0:
		h12 = 12
	return "%d %s" % [h12, "PM" if hour >= 12 else "AM"]


## How many in-game hours each radio check covers, and rooms per check.
func radio_hours() -> int:
	return int(cfg["radio_hours"])


func check_window_seconds() -> float:
	return shift_len / HOURS * radio_hours()


## Every `radio_hours` hours the radio names clocks to punch before the next
## check, and previews the check after that so you can plan a route.
func _update_rounds() -> void:
	var h := current_hour()
	if not crew_sent and h >= 6:
		crew_sent = true
		_send_crew()
	var window_start: int = h - h % radio_hours()
	if window_start == patrol_hour:
		return
	if patrol_hour >= 0:
		_log_window()
		var missed: Array = checkpoints.filter(func(c): return c.ordered and not c.done)
		if not missed.is_empty():
			orders_missed += missed.size()
			add_score(-(30 * missed.size()))
			message("Missed: %s" % ", ".join(missed.map(func(c): return c.cp_name)), 3.0)
	var previous: Array = checkpoints.filter(func(c): return c.ordered)
	patrol_hour = window_start
	var picks: Array = _next_picks if not _next_picks.is_empty() else _pick_rooms(previous)
	var has_next: bool = window_start + radio_hours() < HOURS
	_next_picks = _pick_rooms(picks) if has_next else []
	for cp in checkpoints:
		cp.set_ordered(cp in picks)
		cp.next_ordered = cp in _next_picks
	orders_total += picks.size()
	_window = {"start": elapsed, "rooms": picks.map(func(c): return c.cp_name), "punched": [],
			"walked": 0.0, "entered": entered, "sabotages": sabotages, "twist": twist_events}
	var text := "Radio, %s: punch %s." % [hour_label(window_start), _names(picks)]
	if has_next:
		text += " Next: %s." % _names(_next_picks)
	message(text, 5.0, false)
	toast("Radio: punch %s" % _names(picks), 4.0)
	Music.stinger("radio", -4.0)


## Pick this check's rooms, avoiding last check's rooms whenever possible.
func _pick_rooms(avoid: Array) -> Array:
	var count: int = mini(mini(int(cfg["rooms_per_check"]), int(location.max_rooms)), checkpoints.size())
	if GameState.overrides.has("rooms_per_check"):
		count = mini(int(cfg["rooms_per_check"]), checkpoints.size())
	var fresh: Array = checkpoints.filter(func(c): return not c in avoid)
	var repeat: Array = checkpoints.filter(func(c): return c in avoid)
	fresh.shuffle()
	repeat.shuffle()
	return (fresh + repeat).slice(0, count)


func _names(list: Array) -> String:
	return ", ".join(list.map(func(c): return c.cp_name))


func next_orders() -> Array:
	return _next_picks


## Test/data log: one line per check window (rooms, slack, distance, events).
func _log_window() -> void:
	if _window.is_empty() or not (GameState.autotest or GameState.log_windows):
		return
	var length := check_window_seconds()
	var punched: Array = _window["punched"]
	var all_done: bool = punched.size() >= _window["rooms"].size()
	var slack := "missed"
	if all_done:
		var last: float = punched.max() if not punched.is_empty() else 0.0
		slack = "%.1f" % (length - last)
	print("WINDOW loc=%s diff=%d cfg=%dhx%d start=%s len=%.0f rooms=%d done=%d slack=%s walked=%.0f breakins=%d sabotage=%d twist=%d" % [
		location.id, GameState.difficulty, radio_hours(), int(cfg["rooms_per_check"]),
		hour_label(patrol_hour), length, _window["rooms"].size(), punched.size(), slack,
		_window["walked"], entered - int(_window["entered"]), sabotages - int(_window["sabotages"]),
		twist_events - int(_window["twist"])])


func _same_set(a: Array, b: Array) -> bool:
	return a.size() == b.size() and a.all(func(x): return x in b)


func orders_open() -> Array:
	return checkpoints.filter(func(c): return c.ordered)


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
	# Jamming only matters for clocks on the current orders.
	return checkpoints.filter(func(c): return c.ordered and not c.done) + [alarm, breaker] + machines


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
	if not _window.is_empty():
		_window["punched"].append(elapsed - float(_window["start"]))
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


func on_window_forced(win, smashed: bool) -> void:
	sabotages += 1
	if smashed:
		Music.sfx_at("glass_break", win.global_position, 2.0, randf_range(0.9, 1.1), 2600.0)
		add_noise(win.global_position, Color(0.7, 0.85, 1.0))
		player.fear = minf(100.0, player.fear + 4.0)
		message("Glass shatters in the %s!" % win.room, 3.0)
	elif alarm_armed():
		message("ALARM: the boards on the %s window were pried off!" % win.room, 3.0)


func on_window_boarded(win) -> void:
	score += 40
	message("The %s window is boarded up." % win.room, 2.0)
	Music.stinger("board", -3.0)


func windows_broken() -> int:
	return windows.filter(func(w): return w.is_open()).size()


## A thief scared away from an entrance tries again elsewhere, once.
func on_entry_foiled(intruder, entrance) -> void:
	scared += 1
	score += 100
	message("You scared someone away from the %s!" % entrance.entrance_label(), 2.5)
	Music.stinger("spotted", -3.0)
	if intruder.retries_left > 0:
		_retry_queue.append({"time": randf_range(6.0, 10.0), "avoid": entrance,
				"retries": intruder.retries_left - 1})


func on_saboteur_caught(_intruder) -> void:
	scared += 1
	score += 150
	message("Caught a saboteur in the act! They ran.", 2.5)
	Music.stinger("spotted", -3.0)


# --- intruders coming and going ---------------------------------------------

func on_intruder_entered(_intruder, door) -> void:
	entered += 1
	if GameState.autotest:
		print("ENTER ", clock_text())
	var where: String = door.entrance_label() if door != null else "?"
	if door != null and door in doors:
		Music.sfx_at("door_creak", door.global_position, 0.0, randf_range(0.85, 1.05), 1400.0)
	if alarm_armed() and door != null:
		message("ALARM: break-in at the %s! (%d inside)" % [where, intruders_inside()], 3.5)
		Music.stinger("alarm_chime", -2.0)


func on_intruder_exit(_intruder, pos: Vector2) -> void:
	var door = null
	var best := INF
	for e in entrances:
		var d: float = e.global_position.distance_to(pos)
		if d < best:
			best = d
			door = e
	if door != null and door in doors and door.locked:
		door.locked = false
		door.refresh()
		if alarm_armed():
			message("ALARM: the %s door was opened from inside." % door.door_name, 3.0)


func in_safe_light(pos: Vector2) -> bool:
	if desk_light != null and pos.distance_to(level.player_spawn) < 110.0:
		return true
	for lamp in lamps:
		if lamp.covers(pos):
			return true
	return false


func _update_fear(delta: float) -> void:
	fear_grace = maxf(0.0, fear_grace - delta)
	var rate: float = cfg["fear_dark"]
	if player.light_active() or in_safe_light(player.global_position):
		rate = -6.0
	for s in shadows:
		var d: float = s.global_position.distance_to(player.global_position)
		if d < 240.0:
			rate += (240.0 - d) / 240.0 * 9.0
		if s.lit:
			rate += 2.0
	if fear_grace > 0.0:
		rate = minf(rate, -6.0)
	player.fear = clampf(player.fear + rate * delta, 0.0, 100.0)


func _update_spawns(delta: float) -> void:
	_intruder_timer -= delta
	if _intruder_timer <= 0.0:
		# Thieves come more often as the night wears on.
		var late: float = lerpf(1.0, float(cfg["late_interval_mult"]), night_progress())
		_intruder_timer = cfg["intruder_interval"] * late * randf_range(0.8, 1.2)
		if entrances.any(func(e): return e.is_open()):
			_intruder_timer *= 0.7  # an open way in invites company
		if intruders.size() < intruder_cap() and _any_loot_left():
			_spawn_intruder()

	for r in _retry_queue:
		r["time"] -= delta
	for r in _retry_queue.filter(func(r): return r["time"] <= 0.0):
		_retry_queue.erase(r)
		if _any_loot_left() and _spawn_intruder(r["avoid"], r["retries"]) != null:
			retries += 1
			add_noise(player.global_position, Color(0.8, 0.8, 0.8))

	_battery_timer -= delta
	if _battery_timer <= 0.0:
		_battery_timer = randf_range(14.0, 22.0)
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


## More thieves can be inside at once late in the night.
func max_thefts() -> int:
	return int(cfg.get("max_thefts", MAX_THEFTS))


func intruder_cap() -> int:
	var cap := int(cfg["intruder_max"])
	if float(cfg.get("early_cap", 0)) > 0.0 and current_hour() < 2:
		return mini(cap, 2)
	if night_progress() >= 0.5:
		cap += 1
	if night_progress() >= 0.75:
		cap += 1
	return cap


func _any_loot_left() -> bool:
	return valuables.any(func(v): return v.available())


## Thieves choose the entrance farthest from the watchman, preferring ones
## that are already open, and never one somebody is already working on.
func _choose_entrance(avoid = null, taken: Array = []):
	var best = null
	var best_score := -INF
	for e in entrances:
		if e == avoid or e in taken or e.picker != null:
			continue
		var s: float = e.global_position.distance_to(player.global_position)
		s += 350.0 if e.is_open() else 0.0
		s += randf() * 300.0
		if s > best_score:
			best_score = s
			best = e
	return best


func _spawn_intruder(avoid = null, retries_left := 1, taken: Array = []):
	var entrance = _choose_entrance(avoid, taken)
	if entrance == null:
		return null
	var it = _spawn(Intruder, entrance.global_position, false)
	it.game = self
	it.door = entrance
	it.retries_left = retries_left
	it.speed = cfg["intruder_speed"]
	it.expose_time = cfg["expose_time"]
	it.sabotage_chance = float(cfg["sabotage_chance"]) + 0.15 * night_progress()
	intruders.append(it)
	world.add_child(it)
	return it


## 4 AM: a crew hits several entrances at once.
func _send_crew() -> void:
	message("Dispatch: a crew is heading your way. Hold the building!", 4.5)
	player.fear = minf(100.0, player.fear + 8.0)
	var taken: Array = []
	for i in int(cfg["crew_size"]):
		var it = _spawn_intruder(null, 0, taken)
		if it != null:
			taken.append(it.door)


## Spread batteries out: no two within about one room of each other.
func _battery_near(pos: Vector2) -> bool:
	return batteries.any(func(b): return b.global_position.distance_to(pos) < 330.0)


func _spawn_battery() -> void:
	# Prefer a spot near a clock you'll be sent to, so batteries sit on your route.
	var pos: Vector2 = level.random_floor_far_from(player.global_position, 350.0)
	var route: Array = orders_open().filter(func(c): return not c.done) + _next_picks
	if not route.is_empty() and randf() < 0.7:
		var c = route.pick_random()
		for attempt in 12:
			var p: Vector2 = c.global_position + Vector2(randf_range(-3, 3), randf_range(-3, 3)).round() * 48.0
			var cell: Vector2i = level.world_to_cell(p)
			if level.floor_cells.has(cell) and not level.is_cell_solid(p) and p.distance_to(player.global_position) > 150.0 \
					and p.distance_to(c.global_position) > 40.0 and not _battery_near(level.cell_to_world(cell)):
				pos = level.cell_to_world(cell)
				break
	if _battery_near(pos):
		for attempt in 10:
			pos = level.random_floor_far_from(player.global_position, 350.0)
			if not _battery_near(pos):
				break
		if _battery_near(pos):
			return
	var b = _spawn(BatteryPickup, pos)
	batteries.append(b)


## Where the Shadow reappears after a touch. Option "smart" also keeps it
## away from the clocks you have to punch next.
func _shadow_respawn_spot() -> Vector2:
	if str(cfg.get("shadow_respawn", "far")) != "smart":
		return _far_shadow_spawn()
	var targets: Array = orders_open().filter(func(c): return not c.done) + _next_picks
	var best: Vector2 = level.shadow_spawns[0]
	var best_score := -INF
	for p in level.shadow_spawns:
		var score_p: float = p.distance_to(player.global_position)
		for c in targets:
			score_p = minf(score_p, p.distance_to(c.global_position) * 1.5)
		if score_p > best_score:
			best_score = score_p
			best = p
	return best


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
			if GameState.difficulty >= 3 and live_lamps.size() > 3:
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
	if dropped_loot:
		loot_recovered += 1
	scared += 1
	score += 150 if dropped_loot else 100
	message("Thief scared off - they dropped the loot!" if dropped_loot else "Thief scared off!", 2.5)
	Music.stinger("spotted", -3.0)


func on_item_grabbed(intruder, _valuable) -> void:
	add_noise(intruder.global_position, Color(1.0, 0.4, 0.3))
	message("You hear glass breaking!", 2.5)
	# Posted last so the warning is the pop-up you actually see.
	if float(cfg.get("escape_warning", 0)) > 0.0 and alarm_armed():
		intruder.warned = true
		message("ALARM: footsteps heading for the %s!" % intruder.exit_name, 4.0)


func on_theft(_intruder, valuable) -> void:
	escaped += 1
	thefts += 1
	if GameState.autotest_survive:
		valuable.stolen = false  # keep the building worth robbing in survive tests
		valuable.refresh()
	add_score(-(200))
	message("Something was stolen! (%d/%d)" % [thefts, max_thefts()], 3.0)
	Music.stinger("theft")


func on_shadow_caught(s) -> void:
	touches += 1
	player.fear = minf(100.0, player.fear + 30.0)
	flash = 1.0
	# Wake at the lit security desk with the light on and a moment to recover.
	player.global_position = level.player_spawn
	player.stun(1.0)
	player.flashlight_on = true
	player.battery = maxf(player.battery, 25.0)
	fear_grace = 5.0
	s.reset_to(_shadow_respawn_spot())
	message("IT TOUCHED YOU. You come to at the security desk.", 3.5)
	if float(cfg.get("touch_cost", 0)) > 0.0:
		# Lost time: the clock jumps 10 s and the shaken watchman loses score.
		elapsed += 10.0
		add_score(-100)
		_update_rounds()   # the radio reacts straight away if the hour rolled over
	Music.stinger("scare")


# --- location twists ---------------------------------------------------------

## Mall: which shutter guards each valuable (the one that, closed, cuts it off).
func _assign_shop_gates() -> void:
	if shutters.is_empty():
		return
	for sh in shutters:
		level.set_cell_solid(sh.global_position, true)
	for v in valuables:
		var spot: Vector2 = v.global_position + Vector2(0, 26)
		if not level.find_path(level.player_spawn, spot).is_empty():
			continue
		for sh in shutters:
			level.set_cell_solid(sh.global_position, false)
			var reachable := not level.find_path(level.player_spawn, spot).is_empty()
			level.set_cell_solid(sh.global_position, true)
			if reachable:
				v.gate = sh
				break
	for sh in shutters:
		level.set_cell_solid(sh.global_position, false)


func shutter_at(pos: Vector2):
	for sh in shutters:
		if sh.global_position.distance_to(pos) < 30.0:
			return sh
	return null


func shutters_closed() -> int:
	return shutters.filter(func(s): return s.closed).size()


func on_shutter_closed(sh) -> void:
	score += 25
	message("The %s shutter is down." % sh.shop, 2.0)
	Music.sfx_at("shutter", sh.global_position, -2.0, 1.0, 1200.0)


func on_shutter_forced(sh) -> void:
	sabotages += 1
	twist_events += 1
	add_noise(sh.global_position, Color(1.0, 0.5, 0.3))
	message("Metal screeches - the %s shutter was forced!" % sh.shop, 3.0)


## Apartment: residents call the intercom about noises.
func _update_calls(delta: float) -> void:
	if call_spots.is_empty():
		return
	for c in call_spots:
		if c.active and c.time_left <= 0.0:
			c.active = false
			complaints += 1
			add_score(-(50))
			message("%s gave up waiting and complained. (%d/%d)" % [c.flat, complaints, MAX_COMPLAINTS], 3.5)
	_call_timer -= delta
	if _call_timer > 0.0:
		return
	_call_timer = randf_range(45.0, 70.0) / float(cfg["event_mult"]) * lerpf(1.0, 0.75, night_progress())
	var idle := call_spots.filter(func(c): return not c.active)
	if idle.is_empty():
		return
	var spot = idle.pick_random()
	var real := randf() < 0.45 and _any_loot_left()
	spot.activate(real)
	twist_events += 1
	Music.stinger("intercom", -2.0)
	message("Intercom: %s hears noises. Check it within a minute." % spot.flat, 4.0)
	if real:
		# A thief already inside the flat (came over the balcony).
		var it = _spawn(Intruder, spot.global_position, false)
		it.game = self
		it.door = null
		it.retries_left = 0
		it.speed = cfg["intruder_speed"]
		it.expose_time = cfg["expose_time"]
		it.sabotage_chance = 0.0
		intruders.append(it)
		world.add_child(it)


func on_call_answered(c) -> void:
	calls_answered += 1
	score += 60
	var close := intruders.any(func(it): return it.global_position.distance_to(c.global_position) < 320.0)
	if c.real and close:
		message("The resident points down the hall: \"Someone's in here!\"", 3.0)
		player.fear = minf(100.0, player.fear + 4.0)
	elif c.real:
		message("%s: \"They ran off when you buzzed!\"" % c.flat, 2.5)
	else:
		message(["%s: false alarm - the radiator again.", "%s: false alarm - just the cat.",
				"%s: false alarm - a neighbour's TV."].pick_random() % c.flat, 2.5)


func calls_active() -> Array:
	return call_spots.filter(func(c): return c.active)


## Factory: machines.
func on_machine_started(m) -> void:
	sabotages += 1
	twist_events += 1
	message("%s roars into life. You can't hear anything near it." % m.machine_name, 3.5)


func on_machine_stopped(m) -> void:
	score += 40
	message("%s shut down." % m.machine_name, 2.0)


func on_machine_overheat(m) -> void:
	var wing: String = level.wing_of(m.global_position)
	breaker.circuits[wing] = false
	breaker.refresh()
	for lamp in lamps:
		if lamp.wing == wing:
			lamp.set_powered(false)
	player.fear = minf(100.0, player.fear + 8.0)
	Music.sfx_at("overheat", m.global_position, 0.0, 1.0, 2600.0)
	message("%s OVERHEATS - the %s wing loses power!" % [m.machine_name, wing], 4.0)


func machines_running() -> Array:
	return machines.filter(func(m): return m.running)


func _end_of_shift() -> void:
	_log_window()
	if orders_total > 0 and float(punches) / orders_total < 0.6:
		_end(false, "6:00 AM. You skipped too many patrol orders - you're fired.")
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
		"location": location.title,
		"difficulty": GameState.difficulty_name(),
		"complaints": complaints,
		"twist_events": twist_events,
		"score": maxi(0, score),
		"punches": punches,
		"punches_total": orders_total,
		"orders_missed": orders_missed,
		"retries": retries,
		"crew": crew_sent,
		"scared": scared,
		"thefts": thefts,
		"entered": entered,
		"escaped": escaped,
		"loot_recovered": loot_recovered,
		"touches": touches,
		"sabotages": sabotages,
		"time": clock_text(),
	}
	print("Shift ended: ", result)
	if GameState.autotest:
		print("AUTOTEST TWIST: %s shutters down=%d/%d, calls answered=%d complaints=%d, machines running=%d, twist events=%d" % [
			location.id, shutters_closed(), shutters.size(), calls_answered, complaints, machines_running().size(), twist_events])
		print("AUTOTEST DUTIES: windows broken=%d boarded=%d, alarm armed=%s cut=%s, doors locked %d/%d, dead wings=%s, jammed clocks=%d" % [
			windows_broken(), windows.filter(func(w): return w.pane == WindowPane.Pane.BOARDED).size(),
			alarm.armed, alarm.cut, doors_locked(), doors.size(), breaker.dead_wings(),
			checkpoints.filter(func(c): return c.jammed).size()])
	await get_tree().create_timer(2.5).timeout
	GameState.finish_night(result)


## Self-playing watchman for the headless smoke test: walk to the nearest
## device that needs attention (clocks, alarm, breaker, doors).
func _autopilot() -> void:
	var target = null
	var best := INF
	# Like a sensible player: when the hour is running out, clocks come first.
	var time_left := check_window_seconds() - (elapsed - float(_window.get("start", elapsed)))
	var urgent: Array = orders_open().filter(func(c): return not c.done)
	var pool: Array = urgent if (time_left < 22.0 and not urgent.is_empty()) else devices
	# Like a player who sees or hears it: go after a thief carrying loot nearby
	# (or anywhere, if the alarm is tracking it), unless clocks are urgent.
	if not (time_left < 22.0 and not urgent.is_empty()):
		var chase = null
		var chase_d := INF
		for it in intruders:
			if it.state != Intruder.State.ESCAPE:
				continue
			var cd: float = it.global_position.distance_to(player.global_position)
			if (cd < 450.0 or it.warned) and cd < chase_d:
				chase_d = cd
				chase = it
		if chase != null:
			player.auto_aim = (chase.global_position - player.global_position).normalized()
			var cpath: PackedVector2Array = level.find_path(player.global_position, chase.global_position)
			player.auto_move = Vector2.ZERO
			if cpath.size() > 1 and chase_d > 120.0:
				player.auto_move = (cpath[1] - player.global_position).normalized()
			return
	for dev in pool:
		if dev.needs_action():
			var d: float = dev.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				target = dev
	player.auto_move = Vector2.ZERO
	# Point the flashlight at the nearest thief within reach, if any.
	player.auto_aim = Vector2.ZERO
	var near := 380.0
	for it in intruders + shadows:
		var dist: float = it.global_position.distance_to(player.global_position)
		if dist < near:
			near = dist
			player.auto_aim = (it.global_position - player.global_position).normalized()
	if target != null and best > target.interact_range - 14.0:
		var path: PackedVector2Array = level.find_path(player.global_position, target.global_position)
		if path.size() > 1:
			player.auto_move = (path[1] - player.global_position).normalized()
		elif path.size() == 1:
			player.auto_move = (path[0] - player.global_position).normalized()


# --- automated play harness (dev only; see README) ----------------------------

var _inputs: Array = []     # [{ "t": float, "cmd": String, "args": PackedStringArray }]
var _snaps: Array = []


func _load_inputs() -> void:
	_snaps = GameState.snap_times.duplicate()
	if GameState.inputs_path == "":
		return
	var f := FileAccess.open(GameState.inputs_path, FileAccess.READ)
	if f == null:
		push_error("Cannot read inputs file %s" % GameState.inputs_path)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.size() >= 2:
			_inputs.append({"t": float(parts[0]), "cmd": parts[1], "args": parts.slice(2), "line": _inputs.size()})
	# Stable order: by time, then by line in the file.
	_inputs.sort_custom(func(a, b): return a["t"] < b["t"] or (a["t"] == b["t"] and a["line"] < b["line"]))


func _update_harness() -> void:
	while not _inputs.is_empty() and _inputs[0]["t"] <= elapsed:
		_apply_input(_inputs.pop_front())
	while not _snaps.is_empty() and _snaps[0] <= elapsed:
		_snapshot(_snaps.pop_front())
	if GameState.until_time > 0.0 and elapsed >= GameState.until_time and not ended:
		ended = true
		_finish_harness()


func _finish_harness() -> void:
	await _snapshot(elapsed)
	print("HARNESS until reached at ", clock_text())
	get_tree().quit()


func _apply_input(i: Dictionary) -> void:
	var a: PackedStringArray = i["args"]
	match i["cmd"]:
		"move":
			player.auto_move = Vector2(float(a[0]), float(a[1])).limit_length(1.0) if a.size() >= 2 else Vector2.ZERO
		"aim":
			player.auto_aim = Vector2(float(a[0]), float(a[1])).normalized() if a.size() >= 2 else Vector2.ZERO
		"hold":
			Input.action_press("interact")
		"release":
			Input.action_release("interact")
		"run":
			if a.size() > 0 and a[0] == "on":
				Input.action_press("run")
			else:
				Input.action_release("run")
		"light":
			player.flashlight_on = not player.flashlight_on
		_:
			push_warning("Unknown harness command: %s" % i["cmd"])


func _cell_of(n: Node2D) -> Array:
	var c: Vector2i = level.world_to_cell(n.global_position)
	return [c.x, c.y]


## Writes state_<t>.json (and shot_<t>.png when rendering) into --out.
func _snapshot(t: float) -> void:
	var state := {
		"time": snappedf(t, 0.01), "clock": clock_text(), "location": location.id,
		"difficulty": GameState.difficulty_name(), "score": score, "thefts": thefts,
		"player": {"cell": _cell_of(player), "fear": snappedf(player.fear, 0.1),
				"battery": snappedf(player.battery, 0.1), "stamina": snappedf(player.stamina, 0.1),
				"light_on": player.flashlight_on, "aim": [snappedf(player.aim.x, 0.01), snappedf(player.aim.y, 0.01)]},
		"orders": orders_open().map(func(c): return {"name": c.cp_name, "done": c.done, "jammed": c.jammed, "cell": _cell_of(c)}),
		"next_orders": _next_picks.map(func(c): return c.cp_name),
		"window_due": hour_label(maxi(patrol_hour, 0) + radio_hours()),
		"near_device": near_device.action_label() if near_device != null else "",
		"duties": {"alarm_armed": alarm.armed, "alarm_cut": alarm.cut,
				"doors": doors.map(func(d): return {"name": d.door_name, "locked": d.locked, "cell": _cell_of(d)}),
				"windows": windows.map(func(w): return {"room": w.room, "state": ["intact", "broken", "boarded"][w.pane], "cell": _cell_of(w)}),
				"dead_wings": breaker.dead_wings(),
				"shutters": shutters.map(func(x): return {"shop": x.shop, "closed": x.closed, "cell": _cell_of(x)}),
				"calls": calls_active().map(func(c): return {"flat": c.flat, "time_left": snappedf(c.time_left, 0.1), "cell": _cell_of(c)}),
				"machines": machines.map(func(m): return {"name": m.machine_name, "running": m.running, "overheated": m.overheated, "cell": _cell_of(m)})},
		"intruders": intruders.map(func(it): return {"cell": _cell_of(it), "state": Intruder.State.keys()[it.state], "inside": it.inside, "lit": it.lit}),
		"shadows": shadows.map(func(sh): return {"cell": _cell_of(sh), "lit": sh.lit}),
		"batteries": batteries.map(func(b): return _cell_of(b)),
		"messages": log_entries.slice(-6).map(func(m): return m["text"]),
	}
	var dir := GameState.out_dir if GameState.out_dir != "" else "user://harness"
	DirAccess.make_dir_recursive_absolute(dir)
	var tag := "%07.2f" % t
	var f := FileAccess.open("%s/state_%s.json" % [dir, tag], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, "  "))
		f.close()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shot_%s.png" % [dir, tag])
	print("HARNESS snap t=%s %s" % [tag, clock_text()])


func _draw_noises() -> void:
	for n in _noises:
		var t: float = n["age"] / 1.4
		var c: Color = n["color"]
		c.a = (1.0 - t) * 0.6
		fx.draw_arc(n["pos"], 8.0 + t * 46.0, 0, TAU, 28, c, 2.0)
