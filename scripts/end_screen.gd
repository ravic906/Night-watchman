extends Control
## Shift report after a night ends.


## Android Back / Esc on the report goes back to the title screen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		GameState.go_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		GameState.go_to_menu()


func _ready() -> void:
	GameState.set_menu_power(true)
	GameState.fade_in(self)
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

	# Room for the star rating, drawn in _draw().
	_stars = int(r.get("stars", 0))
	var star_space := Control.new()
	star_space.custom_minimum_size = Vector2(0, 64)
	box.add_child(star_space)
	_star_anchor = star_space
	if r.get("new_best", false):
		var best := Label.new()
		best.text = "NEW BEST!"
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.add_theme_font_size_override("font_size", 22)
		best.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		box.add_child(best)

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

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var retry := _button("Retry", GameState.start_shift)
	var next_loc: String = GameState.next_location()
	var next := _button("Try the %s" % GameState.location_def(next_loc).title, func(): GameState.start_shift(next_loc))
	var menu := _button("Main Menu", GameState.go_to_menu)
	for b in [retry, next, menu]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	retry.grab_focus()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


var _stars := 0
var _star_anchor: Control


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.03, 0.03, 0.06))
	if _star_anchor == null:
		return
	var c := _star_anchor.get_global_rect().get_center()
	for i in 3:
		var p := c + Vector2((i - 1) * 64.0, 0)
		var lit := i < _stars
		draw_colored_polygon(_star_points(p, 26.0), Color(1, 0.82, 0.3) if lit else Color(1, 1, 1, 0.1))
		draw_polyline(_star_points(p, 26.0) + PackedVector2Array([_star_points(p, 26.0)[0]]), Color(1, 0.85, 0.5, 0.6), 1.5)


func _star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var rad := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * rad)
	return pts
