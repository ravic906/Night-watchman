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

	# Top-right: patrol checklist
	var x := size.x - 232
	draw_rect(Rect2(x - 12, 12, 232, 50 + game.checkpoints.size() * 22 + 48), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(x, 36), "Round %d/2" % game.patrol_round, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.6))
	var y := 62.0
	for cp in game.checkpoints:
		var done: bool = cp.done
		var mark := "[x] " if done else "[ ] "
		draw_string(font, Vector2(x, y), mark + cp.cp_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color(0.5, 0.95, 0.55) if done else Color(0.85, 0.85, 0.85))
		y += 22.0
	draw_string(font, Vector2(x, y + 6), "Score  %d" % game.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.85, 0.95))
	draw_string(font, Vector2(x, y + 28), "Stolen %d/%d" % [game.thefts, game.MAX_THEFTS], HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(1, 0.45, 0.4) if game.thefts > 0 else Color(0.85, 0.85, 0.95))

	# Punch prompt
	if game.near_checkpoint != null:
		var key := "PUNCH" if GameState.use_touch_controls() else "E"
		var txt := "Hold %s to punch the %s clock" % [key, game.near_checkpoint.cp_name]
		draw_string(font, Vector2(0, size.y * 0.68), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 0.95, 0.7))

	# Messages
	var my := size.y * 0.78
	for m in game.messages():
		var alpha := clampf(float(m["time"]), 0.0, 1.0)
		draw_string(font, Vector2(0, my), m["text"], HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.92, 0.92, 0.95, alpha))
		my += 26.0
