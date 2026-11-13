extends Control
## Heads-up display, drawn entirely in code.

var game  # game.gd
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused


func _process(delta: float) -> void:
	_t += delta
	# First shift of a session: show the objectives once, paused, so players
	# can read them in peace (never in automated runs).
	if not _auto_opened and game != null and game.elapsed > 0.6:
		_auto_opened = true
		if not GameState.autotest and not GameState.harness_active() and not GameState.seen_objectives:
			GameState.seen_objectives = true
			tab = 0
			set_expanded(true)
	queue_redraw()


func _bar(pos: Vector2, label: String, value: float, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.82, 0.9))
	var r := Rect2(pos + Vector2(80, 2), Vector2(170, 14))
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(value / 100.0, 0.0, 1.0), r.size.y)), color)
	draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)


func _draw() -> void:
	if game == null or game.player == null:
		return
	var font := ThemeDB.fallback_font
	var size := get_viewport_rect().size
	var p = game.player

	# Fear vignette: the screen closes in as panic rises.
	var fear: float = p.fear
	if fear > 30.0:
		var a := (fear - 30.0) / 70.0 * 0.55
		if fear > 80.0:
			a += sin(_t * 8.0) * 0.08
		var w := 40.0 + fear * 1.2
		var c := Color(0.35, 0.0, 0.0, a)
		draw_rect(Rect2(0, 0, size.x, w), c)
		draw_rect(Rect2(0, size.y - w, size.x, w), c)
		draw_rect(Rect2(0, w, w, size.y - 2 * w), c)
		draw_rect(Rect2(size.x - w, w, w, size.y - 2 * w), c)
	if game.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.0, 0.0, game.flash * 0.7))

	# Top-left panel
	draw_rect(Rect2(12, 12, 280, 132), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(24, 44), game.clock_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.9, 0.6))
	draw_string(font, Vector2(160, 30), game.location.title, HORIZONTAL_ALIGNMENT_LEFT, 125, 14, Color(0.7, 0.75, 0.9))
	draw_string(font, Vector2(160, 47), GameState.difficulty_name(), HORIZONTAL_ALIGNMENT_LEFT, 125, 13, Color(0.55, 0.6, 0.75))
	var batt_col := Color(0.95, 0.85, 0.3) if p.battery > 15.0 else Color(1, 0.3, 0.2)
	_bar(Vector2(24, 58), "Battery" if p.flashlight_on else "Battery (off)", p.battery, batt_col)
	_bar(Vector2(24, 82), "Fear", fear, Color(0.8, 0.15, 0.25))
	_bar(Vector2(24, 106), "Stamina", p.stamina, Color(0.35, 0.7, 0.9))

	_draw_pointers(font, size)
	_draw_tracker(font, size)

	# Action prompt
	if game.near_device != null:
		var key := "USE" if GameState.use_touch_controls() else "E"
		var txt := "Hold %s to %s" % [key, game.near_device.action_label()]
		draw_string(font, Vector2(0, size.y * 0.68), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 0.95, 0.7))

	# One short pop-up line at a time (everything is kept in the Log tab).
	for m in game.messages():
		var alpha := clampf(float(m["time"]), 0.0, 1.0)
		var tw := font.get_string_size(m["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var box := Rect2((size.x - tw) / 2.0 - 14, size.y * 0.78 - 22, tw + 28, 32)
		draw_rect(box, Color(0, 0, 0, 0.5 * alpha))
		draw_string(font, Vector2(0, size.y * 0.78), m["text"], HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, Color(0.95, 0.95, 0.97, alpha))

	if expanded:
		_draw_panel(font, size)


const OK_COL := Color(0.5, 0.95, 0.55)
const TODO_COL := Color(0.85, 0.85, 0.85)
const BAD_COL := Color(1.0, 0.55, 0.25)
const DIM_COL := Color(0.65, 0.68, 0.8)
const WARN_COL := Color(1.0, 0.8, 0.35)


## --- Objectives tracker (compact, always on) and full panel (tabs) ----------

const TABS := ["Objectives", "Status", "Log"]
const TRACKER_W := 250.0

## Full panel open (the game is paused while it is).
var expanded := false
var tab := 0
var _tracker_rect := Rect2()
var _tab_rects: Array = []
var _panel_rect := Rect2()
var _auto_opened := false


func _key_hint() -> String:
	return "tap" if GameState.use_touch_controls() else "Tab"


## Everything that needs doing, most urgent first: [text, color, urgency].
func _objectives() -> Array:
	var items: Array = []
	var due: float = game.check_window_seconds() - (game.elapsed - float(game._window.get("start", game.elapsed)))
	for c in game.calls_active():
		items.append(["Check %s (%ds)" % [c.flat, maxi(0, int(c.time_left))], BAD_COL, 100 - c.time_left])
	for m in game.machines_running():
		items.append(["Shut down %s%s" % [m.machine_name, " - OVERHEATED" if m.overheated else ""], BAD_COL, 90])
	for cp in game.orders_open():
		if cp.done:
			continue
		var t := "Punch %s%s (%ds)" % [cp.cp_name, " - jammed" if cp.jammed else "", maxi(0, int(due))]
		items.append([t, BAD_COL if due < 15.0 else WARN_COL, 80 if due < 15.0 else 60])
	if game.alarm.cut:
		items.append(["Re-wire the alarm (lobby)", BAD_COL, 55])
	elif not game.alarm.armed:
		items.append(["Arm the alarm", TODO_COL, 50])
	var open_doors: int = game.doors.size() - game.doors_locked()
	if open_doors > 0:
		items.append(["Lock %d outside door%s" % [open_doors, "s" if open_doors > 1 else ""], TODO_COL, 45])
	var broken: int = game.windows_broken()
	if broken > 0:
		items.append(["Board up %d window%s" % [broken, "s" if broken > 1 else ""], BAD_COL, 48])
	var dead: Array = game.breaker.dead_wings()
	if not dead.is_empty():
		items.append(["Reset the breaker (%s dark)" % ", ".join(dead), BAD_COL, 52])
	var shut_open: int = game.shutters.size() - game.shutters_closed()
	if shut_open > 0:
		items.append(["Close %d shop shutter%s" % [shut_open, "s" if shut_open > 1 else ""], TODO_COL, 44])
	items.sort_custom(func(a, b): return a[2] > b[2])
	return items


func _draw_tracker(font: Font, size: Vector2) -> void:
	var items := _objectives()
	var x := size.x - TRACKER_W - 12.0
	var lines := mini(items.size(), 3)
	var h := 58.0 + lines * 22.0 + (18.0 if items.size() > 3 else 0.0)
	_tracker_rect = Rect2(x, 12, TRACKER_W, h)
	draw_rect(_tracker_rect, Color(0, 0, 0, 0.5))
	draw_rect(_tracker_rect, Color(1, 0.85, 0.5, 0.25), false, 1.0)
	draw_string(font, Vector2(x + 12, 32), "OBJECTIVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.6))
	draw_string(font, Vector2(x + 12, 32), "[%s] more" % _key_hint(), HORIZONTAL_ALIGNMENT_RIGHT, TRACKER_W - 24, 12, DIM_COL)
	var inside := "Inside: %d" % game.intruders_inside() if game.alarm_armed() else "Inside: ?? (alarm off)"
	draw_string(font, Vector2(x + 12, 50), inside, HORIZONTAL_ALIGNMENT_LEFT, TRACKER_W - 24, 13,
			Color(1, 0.45, 0.4) if game.alarm_armed() and game.intruders_inside() > 0 else DIM_COL)
	var y := 72.0
	if items.is_empty():
		draw_string(font, Vector2(x + 12, y), "All clear. Patrol and listen.", HORIZONTAL_ALIGNMENT_LEFT, TRACKER_W - 24, 15, OK_COL)
	for i in lines:
		draw_string(font, Vector2(x + 12, y), items[i][0], HORIZONTAL_ALIGNMENT_LEFT, TRACKER_W - 24, 15, items[i][1])
		y += 22.0
	if items.size() > 3:
		draw_string(font, Vector2(x + 12, y - 4), "+%d more" % (items.size() - 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM_COL)


func _draw_panel(font: Font, size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var w := minf(560.0, size.x - 40.0)
	var h := minf(470.0, size.y - 60.0)
	_panel_rect = Rect2((size.x - w) / 2.0, (size.y - h) / 2.0, w, h)
	var r := _panel_rect
	draw_rect(r, Color(0.06, 0.07, 0.1, 0.97))
	draw_rect(r, Color(1, 0.85, 0.5, 0.35), false, 2.0)
	# Tabs
	_tab_rects.clear()
	var tw := (w - 24.0) / TABS.size()
	for i in TABS.size():
		var tr := Rect2(r.position.x + 12 + i * tw, r.position.y + 12, tw - 6, 40)
		_tab_rects.append(tr)
		draw_rect(tr, Color(1, 0.85, 0.5, 0.22) if i == tab else Color(1, 1, 1, 0.06))
		draw_string(font, tr.position + Vector2(0, 27), TABS[i], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 18,
				Color(0.95, 0.9, 0.6) if i == tab else DIM_COL)
	var lines: Array = []
	match tab:
		0:
			lines = _objective_lines()
		1:
			lines = _status_lines()
		2:
			for e in game.log_entries.slice(-15):
				lines.append(["%s  %s" % [e["time"], e["text"]], TODO_COL, 14])
			if lines.is_empty():
				lines.append(["Nothing has happened yet.", DIM_COL, 14])
	var y := r.position.y + 80.0
	for l in lines:
		if y > r.end.y - 40.0:
			break
		draw_string(font, Vector2(r.position.x + 22, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, w - 44, l[2], l[1])
		y += l[2] + 9.0
	var foot := "Paused - %s to close" % ("tap outside" if GameState.use_touch_controls() else "Tab / Esc")
	if not GameState.use_touch_controls():
		foot += ", Left/Right to switch tabs"
	draw_string(font, Vector2(r.position.x, r.end.y - 16), foot, HORIZONTAL_ALIGNMENT_CENTER, w, 13, DIM_COL)


func _objective_lines() -> Array:
	var out: Array = []
	var hr: int = maxi(game.patrol_hour, 0)
	out.append(["PATROL  -  due by %s" % game.hour_label(hr + game.radio_hours()), WARN_COL, 15])
	for cp in game.orders_open():
		var mark := "[x]" if cp.done else ("[!]" if cp.jammed else "[ ]")
		var extra := "  (jammed - hold longer)" if cp.jammed and not cp.done else ""
		out.append(["   %s Punch the %s clock%s" % [mark, cp.cp_name, extra], OK_COL if cp.done else TODO_COL, 15])
	var nxt: Array = game.next_orders()
	if not nxt.is_empty():
		out.append(["   Next: %s" % ", ".join(nxt.map(func(c): return c.cp_name)), Color(1.0, 0.75, 0.35, 0.85), 14])
	out.append(["DUTIES", WARN_COL, 15])
	var a = game.alarm
	out.append(["   %s Alarm %s" % ["[x]" if a.armed else "[ ]", "armed" if a.armed else ("CUT - re-wire it" if a.cut else "- arm it in the lobby")],
			OK_COL if a.armed else (BAD_COL if a.cut else TODO_COL), 15])
	var locked: int = game.doors_locked()
	out.append(["   %s Outside doors locked %d/%d" % ["[x]" if locked == game.doors.size() else "[ ]", locked, game.doors.size()],
			OK_COL if locked == game.doors.size() else TODO_COL, 15])
	var broken: int = game.windows_broken()
	out.append(["   %s Windows %s" % ["[x]" if broken == 0 else "[!]", "secure" if broken == 0 else "broken: %d - board them up" % broken],
			OK_COL if broken == 0 else BAD_COL, 15])
	var dead: Array = game.breaker.dead_wings()
	out.append(["   %s Power %s" % ["[x]" if dead.is_empty() else "[!]", "on" if dead.is_empty() else "out (%s) - reset the breaker" % ", ".join(dead)],
			OK_COL if dead.is_empty() else BAD_COL, 15])
	if not game.shutters.is_empty():
		var shut: int = game.shutters_closed()
		out.append(["   %s Shop shutters down %d/%d" % ["[x]" if shut == game.shutters.size() else "[ ]", shut, game.shutters.size()],
				OK_COL if shut == game.shutters.size() else TODO_COL, 15])
	for c in game.calls_active():
		out.append(["   [!] Intercom: check %s within %ds" % [c.flat, maxi(0, int(c.time_left))], BAD_COL, 15])
	for m in game.machines_running():
		out.append(["   [!] %s is running - shut it down" % m.machine_name, BAD_COL, 15])
	out.append(["HOW TO", WARN_COL, 15])
	out.append(["   %s" % game.location.duty_hint, DIM_COL, 13])
	out.append(["   Hold %s next to a device to use it. Keep your light on thieves to scare them off." % ("USE" if GameState.use_touch_controls() else "E"), DIM_COL, 13])
	return out


func _status_lines() -> Array:
	var p = game.player
	var out: Array = []
	out.append(["%s  -  %s  -  %s" % [game.location.title, GameState.difficulty_name(), game.clock_text()], WARN_COL, 16])
	out.append(["Intruders inside: %s" % (str(game.intruders_inside()) if game.alarm_armed() else "?? (arm the alarm to know)"), TODO_COL, 15])
	out.append(["Items stolen: %d / %d" % [game.thefts, game.MAX_THEFTS], BAD_COL if game.thefts > 0 else TODO_COL, 15])
	out.append(["Patrol orders done: %d / %d" % [game.punches, game.orders_total], TODO_COL, 15])
	out.append(["Thieves scared off: %d" % game.scared, TODO_COL, 15])
	if not game.call_spots.is_empty():
		out.append(["Resident complaints: %d / %d" % [game.complaints, game.MAX_COMPLAINTS], BAD_COL if game.complaints > 0 else TODO_COL, 15])
	out.append(["Battery %d%%   Fear %d%%   Stamina %d%%" % [int(p.battery), int(p.fear), int(p.stamina)], TODO_COL, 15])
	out.append(["Score: %d" % game.score, Color(0.85, 0.85, 0.95), 15])
	out.append(["You lose if fear hits 100%, 3 items are stolen" + (", 3 residents complain" if not game.call_spots.is_empty() else "") + ",", DIM_COL, 13])
	out.append(["or you finish fewer than 60% of patrol orders by 6 AM.", DIM_COL, 13])
	return out


func set_expanded(value: bool) -> void:
	expanded = value
	get_tree().paused = value
	queue_redraw()


func _input(event: InputEvent) -> void:
	if game == null or game.ended:
		return
	if event.is_action_pressed("objectives"):
		set_expanded(not expanded)
		get_viewport().set_input_as_handled()
		return
	if expanded and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				set_expanded(false)
			KEY_LEFT, KEY_A:
				tab = posmod(tab - 1, TABS.size())
			KEY_RIGHT, KEY_D:
				tab = (tab + 1) % TABS.size()
		get_viewport().set_input_as_handled()
		return
	# Taps / clicks (touch screens send touches; desktops send mouse clicks).
	var pos := Vector2.INF
	if GameState.use_touch_controls():
		if event is InputEventScreenTouch and event.pressed:
			pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == Vector2.INF:
		return
	if expanded:
		for i in _tab_rects.size():
			if (_tab_rects[i] as Rect2).has_point(pos):
				tab = i
				get_viewport().set_input_as_handled()
				return
		if not _panel_rect.has_point(pos):
			set_expanded(false)
		get_viewport().set_input_as_handled()
	elif _tracker_rect.has_point(pos):
		tab = 0
		set_expanded(true)
		get_viewport().set_input_as_handled()


## Arrows at the screen edge pointing to things that need you but are off
## screen: ordered clocks (amber), intercom calls (orange), machines (red).
func _draw_pointers(font: Font, size: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var targets: Array = []
	for cp in game.orders_open():
		if not cp.done:
			targets.append([cp.global_position, cp.cp_name, Color(1.0, 0.8, 0.3)])
	for c in game.calls_active():
		targets.append([c.global_position, c.flat, Color(1.0, 0.55, 0.15)])
	for m in game.machines_running():
		targets.append([m.global_position, m.machine_name, Color(1.0, 0.3, 0.25)])
	var centre := size / 2.0
	var margin := 34.0
	var bottom := 30.0 + (260.0 if GameState.use_touch_controls() else 0.0)  # keep clear of touch buttons
	var bounds := Rect2(Vector2(margin, margin + 120.0), size - Vector2(margin * 2, margin + 120.0 + bottom))
	for t in targets:
		var screen: Vector2 = xf * (t[0] as Vector2)
		if Rect2(Vector2.ZERO, size).grow(-10).has_point(screen):
			continue
		var dir := (screen - centre).normalized()
		# Walk from the centre towards the target until we hit the margin box.
		var scale_x := INF if is_zero_approx(dir.x) else ((bounds.end.x if dir.x > 0 else bounds.position.x) - centre.x) / dir.x
		var scale_y := INF if is_zero_approx(dir.y) else ((bounds.end.y if dir.y > 0 else bounds.position.y) - centre.y) / dir.y
		var p := centre + dir * minf(absf(scale_x), absf(scale_y))
		var col: Color = t[2]
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([p + dir * 14, p - dir * 6 + side * 9, p - dir * 6 - side * 9]), col)
		draw_string(font, p - dir * 22 - Vector2(40, -5), t[1], HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(col, 0.9))
