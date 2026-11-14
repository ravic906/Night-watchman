extends Control
## Title screen: pick a location and a difficulty, read how to play.

var _t := 0.0
var _help: Label
var _cards := {}       # location id -> Button
var _diff_buttons := {} # difficulty -> Button


var _quit_dialog: ConfirmationDialog
var _tutorial_offer: ConfirmationDialog
var _defs := {}   # location id -> map definition (loaded once)


func _ready() -> void:
	GameState.set_menu_power(true)
	GameState.fade_in(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.dialog_text = "Quit Night Watchman?"
	_quit_dialog.ok_button_text = "Quit"
	_quit_dialog.cancel_button_text = "Stay"
	_quit_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(_quit_dialog)
	_tutorial_offer = ConfirmationDialog.new()
	_tutorial_offer.dialog_text = "First shift? The 2-minute tutorial shows you the ropes."
	_tutorial_offer.ok_button_text = "Play tutorial"
	_tutorial_offer.cancel_button_text = "Skip it"
	_tutorial_offer.confirmed.connect(GameState.start_tutorial)
	_tutorial_offer.canceled.connect(func():
		GameState.tutorial_done = true
		GameState.save_game()
		GameState.start_shift())
	add_child(_tutorial_offer)
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
		_defs[loc_id] = def
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
	start.pressed.connect(_on_start)
	box.add_child(start)
	_refresh_best()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var settings_btn := _button("Settings")
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.pressed.connect(_open_settings)
	row.add_child(settings_btn)
	_build_settings()

	var tut_btn := _button("Tutorial")
	tut_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_btn.pressed.connect(GameState.start_tutorial)
	row.add_child(tut_btn)

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
Thieves (you hear their footsteps as rings) go for the valuables. Hold your flashlight on one to scare it off. Four thefts and you are done. With the alarm armed you are told when a thief runs for an exit with loot.
Darkness raises your FEAR. Lamps and your flashlight calm you. Batteries (green blinks) recharge the light.
On Normal and Hard something else walks the halls. It cannot move while it is in your beam.

Keyboard: WASD/arrows move, mouse aims, Shift runs, F/Space/right-click toggles the light, E uses (punch, lock, arm, reset, board), Tab opens the Objectives panel.
Touch: left side is a joystick, buttons on the right."""
	box.add_child(_help)


## Show each location's best score at the chosen difficulty.
func _refresh_best() -> void:
	for loc_id in _cards:
		var def = _defs[loc_id]
		var best := GameState.best_score(loc_id, GameState.difficulty)
		var line := "Best (%s): %d" % [GameState.difficulty_name(), best] if best > 0 else ""
		_cards[loc_id].text = "%s\n%s%s" % [def.title.to_upper(), def.blurb, "\n" + line if line != "" else ""]


# --- Settings panel -----------------------------------------------------------

var _settings: PanelContainer
var _backdrop: ColorRect


func _build_settings() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.75)
	_backdrop.visible = false
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_settings = PanelContainer.new()
	_settings.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	style.border_color = Color(1, 0.85, 0.5, 0.4)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	_settings.add_theme_stylebox_override("panel", style)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_settings)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 14)
	_settings.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	box.add_child(title)
	box.add_child(_slider_row("Music volume", GameState.music_volume, func(v):
		GameState.music_volume = v
		Music.apply_volumes()))
	box.add_child(_slider_row("Sound effects", GameState.sfx_volume, func(v):
		GameState.sfx_volume = v
		Music.apply_volumes()
		Music.stinger("punch", -6.0)))
	box.add_child(_toggle_row("High-quality shadows", not GameState.graphics_low,
			"Turn off for smoother play on budget phones", func(on): GameState.graphics_low = not on))
	box.add_child(_toggle_row("Vibration", GameState.vibration, "Short buzz on scares and thefts",
			func(on):
				GameState.vibration = on
				GameState.vibrate(60)))
	var done := _button("Done")
	done.pressed.connect(_close_settings)
	box.add_child(done)


func _slider_row(label_text: String, value: float, on_change: Callable) -> Control:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 40)   # big enough for a thumb
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _toggle_row(label_text: String, on: bool, hint: String, on_change: Callable) -> Control:
	var row := VBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = on
	toggle.custom_minimum_size = Vector2(0, 48)
	toggle.add_theme_font_size_override("font_size", 17)
	toggle.toggled.connect(on_change)
	row.add_child(toggle)
	var small := Label.new()
	small.text = hint
	small.add_theme_font_size_override("font_size", 13)
	small.add_theme_color_override("font_color", Color(0.65, 0.68, 0.8))
	row.add_child(small)
	return row


func _open_settings() -> void:
	_backdrop.visible = true
	_settings.visible = true
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.reset_size()
	_settings.position = (get_viewport_rect().size - _settings.size) / 2.0


func _close_settings() -> void:
	_backdrop.visible = false
	_settings.visible = false
	GameState.save_game()


func _sound_label() -> String:
	return "Sound: On" if GameState.sound_enabled else "Sound: Off"


## Android Back (and Esc on desktop) on the title screen: confirm before quitting.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_ask_quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_ask_quit()


func _ask_quit() -> void:
	if _settings != null and _settings.visible:
		_close_settings()
		return
	if _help != null and _help.visible:
		_help.visible = false
		return
	if not _quit_dialog.visible:
		_quit_dialog.popup_centered()


func _on_start() -> void:
	if GameState.tutorial_done:
		GameState.start_shift()
	else:
		_tutorial_offer.popup_centered()


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
