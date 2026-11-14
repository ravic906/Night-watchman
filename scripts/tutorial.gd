extends Node
## Guided first shift on the Museum: one short step at a time, with a prompt
## at the top of the screen and an arrow / pulsing marker on the target.
## The clock stands still, fear is off and nothing can end the shift.

const ThiefScript = preload("res://scripts/intruder.gd")
const ShadowScript = preload("res://scripts/shadow.gd")

var game
var step := -1
var text := ""
var target = null            # Vector2, a Node2D, or null
var finished := false

var _marker: Node2D
var _t := 0.0
var _start_pos := Vector2.ZERO
var _light_was_off := false
var _thief = null
var _shadow = null
var _shadow_lit := 0.0
var _outro := -1.0

const STEPS := [
	"Welcome, watchman. Move with the joystick (or WASD) to the glowing marker.",
	"Your flashlight drains its battery. Switch it off and on again with LIGHT (or F).",
	"Thieves come in through the outside doors. Walk to the west door and hold USE (E) to lock it.",
	"Arm the alarm in the lobby (hold USE at the panel). While armed, it tells you how many thieves are inside.",
	"Every hour the radio orders clocks to punch. Punch the Gallery clock.",
	"A thief! Keep your flashlight on them until they run.",
	"Something else walks these halls. It only moves in the dark - hold your light on it.",
	"That's the job: follow the radio, keep the lights on, stop thieves, and survive until 6 AM. Good luck!",
]


func _ready() -> void:
	_marker = Node2D.new()
	_marker.draw.connect(_draw_marker)
	game.glow_layer.add_child(_marker)
	_next()


func step_count() -> int:
	return STEPS.size()


func target_pos():
	if target is Vector2:
		return target
	if target != null and is_instance_valid(target):
		return target.global_position
	return null


func _next() -> void:
	step += 1
	text = STEPS[step]
	_t = 0.0
	Music.stinger("punch", -8.0)
	var lvl = game.level
	match step:
		0:
			target = lvl.cell_to_world(Vector2i(24, 9))
		1:
			target = null
			_light_was_off = false
		2:
			target = game.doors.filter(func(d): return d.door_name == "west")[0]
		3:
			target = game.alarm
		4:
			var gallery = game.checkpoints.filter(func(c): return c.cp_name == "Gallery")[0]
			for c in game.checkpoints:
				c.set_ordered(c == gallery)
			target = gallery
		5:
			_spawn_thief()
		6:
			_shadow = game._spawn(ShadowScript, lvl.cell_to_world(Vector2i(31, 10)), false)
			_shadow.game = game
			_shadow.speed = 40.0
			game.world.add_child(_shadow)
			_shadow._wake = 1.5
			game.shadows.append(_shadow)
			target = _shadow
		7:
			target = null
			_outro = 6.0


func _spawn_thief() -> void:
	var p = game.player
	var spot: Vector2 = game.level.cell_to_world(Vector2i(13, 10))
	if spot.distance_to(p.global_position) < 200.0:
		spot = game.level.cell_to_world(Vector2i(26, 10))
	_thief = game._make_intruder(spot, null, 0, 0.0)
	target = _thief


func _physics_process(delta: float) -> void:
	if finished or game.ended:
		return
	_t += delta
	var p = game.player
	match step:
		0:
			if p.global_position.distance_to(target) < 50.0:
				_next()
		1:
			if not p.flashlight_on:
				_light_was_off = true
			elif _light_was_off:
				_next()
		2:
			if target.locked:
				_next()
		3:
			if game.alarm.armed:
				_next()
		4:
			if target.done:
				_next()
		5:
			if game.scared >= 1:
				_next()
			elif _thief == null or not is_instance_valid(_thief):
				_spawn_thief()   # it got away: here comes another
		6:
			if _shadow != null and is_instance_valid(_shadow) and _shadow.lit:
				_shadow_lit += delta
			if _shadow_lit >= 2.0:
				game.shadows.erase(_shadow)
				_shadow.glow.queue_free()
				_shadow.queue_free()
				_shadow = null
				_next()
		7:
			_outro -= delta
			if _outro <= 0.0:
				finish()
	_marker.queue_redraw()


func finish() -> void:
	if finished:
		return
	finished = true
	GameState.tutorial = false
	GameState.tutorial_done = true
	GameState.save_game()
	GameState.go_to_menu()


func _draw_marker() -> void:
	var pos = target_pos()
	if pos == null or step == 5 or step == 6:
		return   # thieves and the Shadow are pointed at by the arrow only
	var pulse := fmod(Time.get_ticks_msec() / 900.0, 1.0)
	_marker.draw_arc(pos, 18 + pulse * 26, 0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - pulse)), 3.0)
	_marker.draw_arc(pos, 14, 0, TAU, 24, Color(1, 0.9, 0.5, 0.9), 2.0)
