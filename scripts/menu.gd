extends Control
## Title screen: pick a night, read how to play.

var _t := 0.0
var _help: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "NIGHT WATCHMAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Keep the lights on. Keep your nerve. Make it to 6 AM."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	box.add_child(sub)

	box.add_child(_spacer(16))

	for n in range(1, GameState.MAX_NIGHT + 1):
		var b := _button(GameState.NIGHTS[n]["title"])
		b.disabled = n > GameState.unlocked
		var best := int(GameState.best_scores.get(str(n), 0))
		if best > 0:
			b.text += "   (best %d)" % best
		b.pressed.connect(GameState.start_night.bind(n))
		box.add_child(b)

	var help_btn := _button("How to play")
	help_btn.pressed.connect(func(): _help.visible = not _help.visible)
	box.add_child(help_btn)

	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var quit := _button("Quit")
		quit.pressed.connect(func(): get_tree().quit())
		box.add_child(quit)

	_help = Label.new()
	_help.visible = false
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(520, 0)
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_help.text = """Your shift runs 10 PM to 6 AM. Punch all 5 clocks (red lights) once before 2 AM, then again before 6 AM.
Thieves (you hear their footsteps as rings) go for the valuables. Hold your flashlight on one to scare it off. Three thefts and you are done.
Darkness raises your FEAR. Lamps and your flashlight calm you. Batteries (green blinks) recharge the light.
From Night 2 something else walks the halls. It cannot move while it is in your beam.

Keyboard: WASD/arrows move, mouse aims, Shift runs, F/Space/right-click toggles the light, E punches.
Touch: left side is a joystick, buttons on the right."""
	box.add_child(_help)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.06))
	# A sweeping flashlight beam behind the title.
	var origin := Vector2(size.x * 0.5, size.y + 40)
	var ang := -PI / 2 + sin(_t * 0.6) * 0.7
	for i in 6:
		var spread := 0.08 + i * 0.05
		var length := size.y * 1.3
		var pts := PackedVector2Array([
			origin,
			origin + Vector2.from_angle(ang - spread) * length,
			origin + Vector2.from_angle(ang + spread) * length,
		])
		draw_colored_polygon(pts, Color(1.0, 0.92, 0.65, 0.035))
