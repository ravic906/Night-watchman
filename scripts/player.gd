extends CharacterBody2D
## The night watchman: walks, runs, and points a battery-hungry flashlight.

const Flashlight = preload("res://scripts/flashlight.gd")

const WALK_SPEED := 150.0
const RUN_SPEED := 245.0
const CONE_HALF := deg_to_rad(27.0)
const LIGHT_RANGE := 430.0
const CONE_TEX_SIZE := 256

var battery := 100.0
var fear := 0.0
var stamina := 100.0
var battery_drain := 1.2
var flashlight_on := true
var aim := Vector2.RIGHT
var stunned := 0.0

## Set by the game for the self-playing smoke test.
var use_auto := false
var auto_move := Vector2.ZERO

var light: PointLight2D
var glow_light: PointLight2D
var camera: Camera2D

var _mouse_aim_until := 0.0
var _walk_phase := 0.0
var _flicker := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)

	light = PointLight2D.new()
	light.texture = Flashlight.make_cone_texture(CONE_TEX_SIZE, CONE_HALF)
	light.texture_scale = LIGHT_RANGE / (CONE_TEX_SIZE / 2.0)
	light.color = Color(1.0, 0.93, 0.75)
	light.energy = 1.25
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(light)

	glow_light = PointLight2D.new()
	glow_light.texture = Flashlight.make_radial_texture(128)
	glow_light.texture_scale = 1.4
	glow_light.color = Color(0.6, 0.65, 0.9)
	glow_light.energy = 0.55
	add_child(glow_light)

	camera = Camera2D.new()
	camera.zoom = Vector2(1.1, 1.1)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.make_current()


func set_camera_limits(size: Vector2) -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not GameState.use_touch_controls():
		_mouse_aim_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _mouse_aiming() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _mouse_aim_until


func light_active() -> bool:
	return flashlight_on and battery > 0.0


## True when `pos` is inside the flashlight cone with nothing blocking it.
func is_lit(pos: Vector2) -> bool:
	if not light_active():
		return false
	var to := pos - global_position
	var d := to.length()
	if d > LIGHT_RANGE * 0.9:
		return false
	if d > 16.0 and absf(aim.angle_to(to)) > CONE_HALF:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, pos, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func stun(seconds: float) -> void:
	stunned = seconds


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if use_auto:
		input = auto_move
	else:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.2)

	if Input.is_action_just_pressed("flashlight"):
		flashlight_on = not flashlight_on

	if stunned > 0.0:
		stunned -= delta
		input = Vector2.ZERO

	var running := Input.is_action_pressed("run") and stamina > 1.0 and input.length() > 0.1
	if running:
		stamina = maxf(0.0, stamina - 30.0 * delta)
	else:
		stamina = minf(100.0, stamina + 18.0 * delta)
	velocity = input * (RUN_SPEED if running else WALK_SPEED)
	move_and_slide()

	if _mouse_aiming():
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 4.0:
			aim = to_mouse.normalized()
	elif input.length() > 0.2:
		aim = aim.slerp(input.normalized(), clampf(10.0 * delta, 0.0, 1.0)).normalized()

	if light_active():
		battery = maxf(0.0, battery - battery_drain * delta)

	light.enabled = light_active()
	light.rotation = aim.angle()
	light.energy = 1.25
	if battery < 15.0 and light.enabled:
		# A dying battery stutters.
		_flicker -= delta
		if _flicker <= 0.0:
			_flicker = randf_range(0.05, 0.4)
		light.energy = 1.25 if _flicker > 0.12 else randf_range(0.1, 0.6)

	if velocity.length() > 1.0:
		var before := floori(_walk_phase / PI)
		_walk_phase += delta * (14.0 if running else 9.0)
		if floori(_walk_phase / PI) != before:
			Music.stinger("step", -7.0 if running else -12.0, randf_range(0.9, 1.08))
	queue_redraw()


func _draw() -> void:
	var side := aim.orthogonal()
	var bob := sin(_walk_phase) * 3.0
	# Feet
	draw_circle(side * 7 + aim * bob, 5, Color(0.08, 0.08, 0.1))
	draw_circle(-side * 7 - aim * bob, 5, Color(0.08, 0.08, 0.1))
	# Body (navy uniform) and shoulders
	draw_circle(Vector2.ZERO, 14, Color(0.17, 0.25, 0.45))
	draw_line(side * 13, -side * 13, Color(0.12, 0.18, 0.34), 7)
	# Flashlight held forward
	draw_line(side * 9 + aim * 6, side * 9 + aim * 22, Color(0.25, 0.25, 0.28), 5)
	draw_circle(side * 9 + aim * 22, 3.5, Color(1.0, 0.95, 0.7) if light_active() else Color(0.3, 0.3, 0.3))
	# Cap with brim
	draw_circle(Vector2.ZERO, 9, Color(0.1, 0.13, 0.25))
	draw_line(aim * 6 + side * 6, aim * 6 - side * 6, Color(0.05, 0.06, 0.12), 4)
	draw_circle(aim * 2, 2.5, Color(0.85, 0.75, 0.3))  # badge
