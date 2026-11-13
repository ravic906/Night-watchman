extends Control
## On-screen controls for phones/tablets: a floating joystick on the left
## and LIGHT / RUN / PUNCH buttons on the right. Multi-touch aware.

const JOY_RADIUS := 80.0
const DEADZONE := 0.15

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _buttons := [
	{"action": "interact", "label": "PUNCH", "offset": Vector2(-110, -120), "r": 58.0, "index": -1},
	{"action": "flashlight", "label": "LIGHT", "offset": Vector2(-250, -80), "r": 46.0, "index": -1},
	{"action": "run", "label": "RUN", "offset": Vector2(-120, -260), "r": 42.0, "index": -1},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _btn_pos(b: Dictionary) -> Vector2:
	return get_viewport_rect().size + b["offset"]


func _default_joy_center() -> Vector2:
	return Vector2(160, get_viewport_rect().size.y - 160)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			for b in _buttons:
				if touch.position.distance_to(_btn_pos(b)) < b["r"] * 1.25:
					b["index"] = touch.index
					Input.action_press(b["action"])
					queue_redraw()
					return
			if touch.position.x < get_viewport_rect().size.x * 0.5 and _joy_index == -1:
				_joy_index = touch.index
				_joy_center = touch.position
				_joy_vec = Vector2.ZERO
		else:
			if touch.index == _joy_index:
				_joy_index = -1
				_joy_vec = Vector2.ZERO
				_apply_joystick()
			for b in _buttons:
				if b["index"] == touch.index:
					b["index"] = -1
					Input.action_release(b["action"])
		queue_redraw()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _joy_index:
			_joy_vec = ((drag.position - _joy_center) / JOY_RADIUS).limit_length(1.0)
			_apply_joystick()
			queue_redraw()


func _apply_joystick() -> void:
	_set_axis("move_left", "move_right", _joy_vec.x)
	_set_axis("move_up", "move_down", _joy_vec.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < -DEADZONE:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > DEADZONE:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var center := _joy_center if _joy_index != -1 else _default_joy_center()
	draw_circle(center, JOY_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(center, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.3), 2.0)
	draw_circle(center + _joy_vec * JOY_RADIUS, 32, Color(1, 1, 1, 0.3))
	for b in _buttons:
		var pressed: bool = b["index"] != -1
		var pos := _btn_pos(b)
		var r: float = b["r"]
		draw_circle(pos, r, Color(1, 0.9, 0.6, 0.35 if pressed else 0.14))
		draw_arc(pos, r, 0, TAU, 36, Color(1, 0.9, 0.6, 0.5), 2.0)
		draw_string(font, pos + Vector2(-r, 6), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r * 2, 16, Color(1, 1, 1, 0.85))
