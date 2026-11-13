extends Control
## Heads-up display, drawn entirely in code.

var game  # game.gd
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
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
	draw_string(font, Vector2(170, 44), "Night %d" % GameState.night, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.75, 0.9))
	var batt_col := Color(0.95, 0.85, 0.3) if p.battery > 15.0 else Color(1, 0.3, 0.2)
	_bar(Vector2(24, 58), "Battery" if p.flashlight_on else "Battery (off)", p.battery, batt_col)
	_bar(Vector2(24, 82), "Fear", fear, Color(0.8, 0.15, 0.25))
	_bar(Vector2(24, 106), "Stamina", p.stamina, Color(0.35, 0.7, 0.9))

	_draw_duties(font, size)

	# Action prompt
	if game.near_device != null:
		var key := "USE" if GameState.use_touch_controls() else "E"
		var txt := "Hold %s to %s" % [key, game.near_device.action_label()]
		draw_string(font, Vector2(0, size.y * 0.68), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 0.95, 0.7))

	# Messages
	var my := size.y * 0.78
	for m in game.messages():
		var alpha := clampf(float(m["time"]), 0.0, 1.0)
		draw_string(font, Vector2(0, my), m["text"], HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.92, 0.92, 0.95, alpha))
		my += 26.0


const OK_COL := Color(0.5, 0.95, 0.55)
const TODO_COL := Color(0.85, 0.85, 0.85)
const BAD_COL := Color(1.0, 0.55, 0.25)
const DIM_COL := Color(0.65, 0.68, 0.8)


## Top-right panel: intruder count (only while the alarm is armed), duties,
## patrol clocks, score.
func _draw_duties(font: Font, size: Vector2) -> void:
	var lines: Array = []   # [text, color, font_size]
	if game.alarm_armed():
		var n: int = game.intruders_inside()
		lines.append(["Intruders inside: %d" % n, Color(1, 0.4, 0.35) if n > 0 else OK_COL, 18])
	else:
		lines.append(["Intruders inside: ??", DIM_COL, 18])
	lines.append(["DUTIES", DIM_COL, 13])
	var a = game.alarm
	if a.armed:
		lines.append(["[x] Alarm armed", OK_COL, 15])
	elif a.cut:
		lines.append(["[!] Alarm CUT - re-wire it", BAD_COL, 15])
	else:
		lines.append(["[ ] Arm the alarm (lobby)", TODO_COL, 15])
	var locked: int = game.doors_locked()
	var total: int = game.doors.size()
	lines.append(["%s Doors locked %d/%d" % ["[x]" if locked == total else "[ ]", locked, total],
			OK_COL if locked == total else TODO_COL, 15])
	var broken: int = game.windows_broken()
	if broken == 0:
		lines.append(["[x] Windows secure", OK_COL, 15])
	else:
		lines.append(["[!] Windows broken: %d" % broken, BAD_COL, 15])
	var dead: Array = game.breaker.dead_wings()
	if dead.is_empty():
		lines.append(["[x] Power OK", OK_COL, 15])
	else:
		lines.append(["[!] Power out: %s" % ", ".join(dead), BAD_COL, 15])
	var hr: int = maxi(game.patrol_hour, 0)
	lines.append(["PATROL %s - DUE BY %s" % [game.hour_label(hr), game.hour_label(hr + 1)], DIM_COL, 13])
	for cp in game.orders_open():
		if cp.jammed and not cp.done:
			lines.append(["[!] %s (jammed)" % cp.cp_name, BAD_COL, 15])
		elif cp.done:
			lines.append(["[x] %s" % cp.cp_name, OK_COL, 15])
		else:
			lines.append(["[ ] %s" % cp.cp_name, TODO_COL, 15])
	lines.append(["Score %d   Stolen %d/%d" % [game.score, game.thefts, game.MAX_THEFTS],
			Color(1, 0.45, 0.4) if game.thefts > 0 else Color(0.85, 0.85, 0.95), 15])

	var w := 250.0
	var x := size.x - w
	var h := 20.0
	for l in lines:
		h += 22.0 if l[2] >= 15 else 20.0
	draw_rect(Rect2(x - 12, 12, w, h), Color(0, 0, 0, 0.45))
	var y := 34.0
	for l in lines:
		draw_string(font, Vector2(x, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, w - 16, l[2], l[1])
		y += 22.0 if l[2] >= 15 else 20.0
