extends Node2D
## Factory machine control panel. A thief can switch the machine on: its
## racket hides nearby footsteps, and after a minute it overheats and trips
## that wing's power. Shut it down at the panel.

const OVERHEAT_TIME := 60.0
const MASK_RADIUS := 300.0

var glow: Node2D
var machine_name := ""
var running := false
var overheated := false
var run_time := 0.0
var progress := 0.0
var interact_range := 56.0
var saboteur = null
var game
var _hum: AudioStreamPlayer2D
var _t := 0.0


func _ready() -> void:
	glow.draw.connect(_draw_glow)
	glow.position = global_position
	_hum = AudioStreamPlayer2D.new()
	var stream: AudioStreamOggVorbis = load("res://audio/machine_loop.ogg")
	stream.loop = true
	_hum.stream = stream
	_hum.bus = "SFX"
	_hum.max_distance = 1100.0
	_hum.attenuation = 1.4
	_hum.volume_db = -4.0
	add_child(_hum)


## Is a sound at `pos` drowned out by this machine?
func masks(pos: Vector2) -> bool:
	return running and pos.distance_to(global_position) < MASK_RADIUS


# --- guard interaction -------------------------------------------------------

func needs_action() -> bool:
	return running


func action_label() -> String:
	return "shut down %s" % machine_name


func hold_time() -> float:
	return 1.5


func complete(g) -> void:
	running = false
	overheated = false
	_hum.stop()
	g.on_machine_stopped(self)


# --- thief sabotage ----------------------------------------------------------

func can_sabotage(by = null) -> bool:
	return not running and (saboteur == null or saboteur == by)


func sabotage_time() -> float:
	return 2.5


func sabotage(g) -> void:
	running = true
	overheated = false
	run_time = 0.0
	_hum.play()
	g.on_machine_started(self)


func _physics_process(delta: float) -> void:
	_t += delta
	if running:
		run_time += delta
		if run_time >= OVERHEAT_TIME and not overheated:
			overheated = true
			game.on_machine_overheat(self)
	glow.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-12, -16, 24, 28), Color(0.35, 0.37, 0.4))
	draw_rect(Rect2(-12, -16, 24, 28), Color(0.15, 0.15, 0.17), false, 2.0)
	draw_circle(Vector2(0, 0), 6, Color(0.7, 0.15, 0.1))  # big stop button


func _draw_glow() -> void:
	var c: Color
	if overheated:
		c = Color(1.0, 0.45, 0.1, 0.5 + 0.5 * float(fmod(_t * 6.0, 1.0) > 0.5))
	elif running:
		c = Color(1.0, 0.2, 0.15, 0.6 + 0.4 * sin(_t * 8.0))
	else:
		c = Color(0.35, 1.0, 0.45, 0.6)
	glow.draw_circle(Vector2(0, -12), 3.5, c)
	if running:
		# Vibration lines: visible even in the dark.
		for i in 3:
			var r := 18.0 + i * 9.0 + fmod(_t * 30.0, 9.0)
			glow.draw_arc(Vector2.ZERO, r, -0.6, 0.6, 8, Color(1, 0.6, 0.3, 0.35 - i * 0.1), 2)
			glow.draw_arc(Vector2.ZERO, r, PI - 0.6, PI + 0.6, 8, Color(1, 0.6, 0.3, 0.35 - i * 0.1), 2)
		var heat := clampf(run_time / OVERHEAT_TIME, 0.0, 1.0)
		glow.draw_arc(Vector2.ZERO, 16, -PI / 2, -PI / 2 + TAU * heat, 24, Color(1, 0.5, 0.1, 0.8), 3)
	if progress > 0.0:
		glow.draw_arc(Vector2.ZERO, 26, -PI / 2, -PI / 2 + TAU * progress, 32, Color(1, 0.9, 0.5), 4)
