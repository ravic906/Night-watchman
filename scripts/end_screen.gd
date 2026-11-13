extends Control
## Shift report after a night ends.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var r: Dictionary = GameState.last_result
	var win: bool = r.get("win", false)
	var where := "%s - %s" % [r.get("location", "?"), r.get("difficulty", "?")]

	if GameState.autotest:
		print("AUTOTEST RESULT: ", r)
		get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "SHIFT COMPLETE" if win else "SHIFT FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6) if win else Color(1, 0.4, 0.35))
	box.add_child(title)

	var reason := Label.new()
	reason.text = str(r.get("reason", ""))
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reason)

	var stats := Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.text = "%s   -   ended at %s\nPatrol orders done: %d / %d\nIntruders: %d got in, %d scared off\nSabotage attempts that worked: %d\nItems stolen: %d\nScore: %d" % [
		where, r.get("time", "?"), r.get("punches", 0), r.get("punches_total", 10),
		r.get("entered", 0), r.get("scared", 0), r.get("sabotages", 0), r.get("thefts", 0), r.get("score", 0)]
	box.add_child(stats)

	box.add_child(_button("Retry", GameState.start_shift))
	box.add_child(_button("Main Menu", GameState.go_to_menu))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.03, 0.03, 0.06))
