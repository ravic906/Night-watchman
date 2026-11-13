extends Control
## Title screen: pick a location and a difficulty, read how to play.

var _t := 0.0
var _help: Label
var _cards := {}       # location id -> Button
var _diff_buttons := {} # difficulty -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Music.play_menu()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(640, 0)
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

	box.add_child(_spacer(6))

	# Location cards (2 x 2).
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var loc_group := ButtonGroup.new()
	for loc_id in GameState.LOCATIONS:
		var def = GameState.location_def(loc_id)
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = loc_group
		card.custom_minimum_size = Vector2(315, 92)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 14)
		card.text = "%s\n%s" % [def.title.to_upper(), def.blurb]
		card.pressed.connect(func():
			GameState.location = loc_id
			_refresh_best())
		grid.add_child(card)
		_cards[loc_id] = card
	_cards[GameState.location].button_pressed = true

	# Difficulty toggle.
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	box.add_child(diff_row)
	var diff_group := ButtonGroup.new()
	for d in [1, 2, 3]:
		var b := _button(GameState.DIFFICULTY_NAMES[d])
		b.toggle_mode = true
		b.button_group = diff_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			GameState.difficulty = d
			_refresh_best())
		diff_row.add_child(b)
		_diff_buttons[d] = b
	_diff_buttons[GameState.difficulty].button_pressed = true

	var start := _button("START SHIFT")
	start.add_theme_font_size_override("font_size", 24)
	start.custom_minimum_size = Vector2(0, 60)
	start.pressed.connect(func(): GameState.start_shift())
	box.add_child(start)
	_refresh_best()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var sound_btn := _button(_sound_label())
	sound_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_btn.pressed.connect(func():
		GameState.sound_enabled = not GameState.sound_enabled
		Music.set_enabled(GameState.sound_enabled)
		GameState.save_game()
		sound_btn.text = _sound_label())
	row.add_child(sound_btn)

	var help_btn := _button("How to play")
	help_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_btn.pressed.connect(func(): _help.visible = not _help.visible)
	row.add_child(help_btn)

	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var quit := _button("Quit")
		quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quit.pressed.connect(func(): get_tree().quit())
		row.add_child(quit)

	_help = Label.new()
	_help.visible = false
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(520, 0)
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_help.text = """Your shift runs 10 PM to 6 AM. Every hour the radio names clocks to punch (red lights) before the next hour - do at least 60% of the night's orders.
Lock the doors, arm the alarm, keep the power on and board up smashed windows. Thieves will undo it all, and more of them come as dawn nears.
Thieves (you hear their footsteps as rings) go for the valuables. Hold your flashlight on one to scare it off. Three thefts and you are done.
Darkness raises your FEAR. Lamps and your flashlight calm you. Batteries (green blinks) recharge the light.
On Normal and Hard something else walks the halls. It cannot move while it is in your beam.

Keyboard: WASD/arrows move, mouse aims, Shift runs, F/Space/right-click toggles the light, E uses (punch, lock, arm, reset, board).
Touch: left side is a joystick, buttons on the right."""
	box.add_child(_help)


## Show each location's best score at the chosen difficulty.
func _refresh_best() -> void:
	for loc_id in _cards:
		var def = GameState.location_def(loc_id)
		var best := GameState.best_score(loc_id, GameState.difficulty)
		var line := "Best (%s): %d" % [GameState.difficulty_name(), best] if best > 0 else ""
		_cards[loc_id].text = "%s\n%s%s" % [def.title.to_upper(), def.blurb, "\n" + line if line != "" else ""]


func _sound_label() -> String:
	return "Sound: On" if GameState.sound_enabled else "Sound: Off"


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
