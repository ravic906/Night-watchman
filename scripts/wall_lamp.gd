extends Node2D
## A ceiling lamp. Standing in its light calms your nerves, while it works.

const Flashlight = preload("res://scripts/flashlight.gd")
const RADIUS := 170.0

var glow: Node2D
var light: PointLight2D
var on := true
var dead := false
var tint := Color(1.0, 0.85, 0.6)
## False while the breaker for this lamp's wing is off.
var powered := true
var wing := ""
var _flicker_left := 0.0
var _flick := 0.0


func _ready() -> void:
	light = PointLight2D.new()
	light.texture = Flashlight.make_radial_texture(256)
	light.texture_scale = RADIUS / 128.0
	light.color = tint
	light.energy = 0.9
	light.shadow_enabled = not GameState.graphics_low
	add_child(light)
	glow.draw.connect(_draw_glow)
	glow.position = global_position


func flicker(seconds: float) -> void:
	if not dead:
		_flicker_left = seconds


func kill() -> void:
	dead = true
	on = false
	light.enabled = false
	glow.queue_redraw()


func set_powered(value: bool) -> void:
	powered = value
	glow.queue_redraw()


func lit() -> bool:
	return on and powered


func covers(pos: Vector2) -> bool:
	if not lit() or pos.distance_to(global_position) > RADIUS * 0.75:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, pos, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _flicker_left > 0.0:
		_flicker_left -= delta
		_flick -= delta
		if _flick <= 0.0:
			_flick = randf_range(0.04, 0.3)
			on = randf() > 0.5
		if _flicker_left <= 0.0:
			on = true
	light.enabled = lit()
	glow.queue_redraw()


func _draw_glow() -> void:
	var col := Color(1.0, 0.9, 0.6, 0.9) if lit() else Color(0.35, 0.33, 0.3, 0.8)
	glow.draw_circle(Vector2.ZERO, 5, col)
	if lit():
		glow.draw_circle(Vector2.ZERO, 10, Color(1.0, 0.9, 0.6, 0.15))
