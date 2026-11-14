extends Control
## Play Store feature graphic (1024x500). Render with:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1024x500 \
##       res://tools/feature_graphic.tscn -- --screenshot=store/feature_1024x500.png

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _draw() -> void:
	var s := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	# Night gradient
	for i in 40:
		var t := i / 39.0
		draw_rect(Rect2(0, s.y * t, s.x, s.y / 39.0 + 1), Color(0.03, 0.035, 0.07).lerp(Color(0.08, 0.09, 0.16), sin(t * PI) * 0.8))
	# Floor tiles fading into the dark
	for x in range(0, int(s.x), 48):
		for y in range(int(s.y * 0.55), int(s.y), 48):
			var fade := clampf(1.0 - absf(x - s.x * 0.3) / (s.x * 0.6), 0.0, 1.0) * 0.18
			draw_rect(Rect2(x + 1, y + 1, 46, 46), Color(0.36, 0.33, 0.29, fade))
	# Flashlight beam from the watchman
	var w := Vector2(s.x * 0.2, s.y * 0.68)
	for k in 6:
		var spread := 0.1 + k * 0.045
		var length := s.x * 0.9
		draw_colored_polygon(PackedVector2Array([w, w + Vector2.from_angle(-0.32 - spread) * length,
				w + Vector2.from_angle(-0.32 + spread) * length]), Color(1.0, 0.93, 0.7, 0.07))
	# The watchman
	draw_circle(w, 34, Color(0.17, 0.27, 0.47))
	draw_circle(w, 22, Color(0.08, 0.12, 0.22))
	draw_circle(w + Vector2(10, -3), 5, Color(0.9, 0.78, 0.4))
	# The Shadow's eyes in the far corner
	for e in [Vector2(s.x * 0.86, s.y * 0.2), Vector2(s.x * 0.86 + 34, s.y * 0.2)]:
		draw_circle(e, 16, Color(1, 0.15, 0.1, 0.18))
		draw_circle(e, 6, Color(1, 0.35, 0.3))
	# Title
	draw_string(font, Vector2(0, s.y * 0.36), "NIGHT WATCHMAN", HORIZONTAL_ALIGNMENT_CENTER, s.x, 92, Color(0.97, 0.91, 0.62))
	draw_string(font, Vector2(0, s.y * 0.36 + 56), "Keep the lights on. Keep your nerve. Make it to 6 AM.", HORIZONTAL_ALIGNMENT_CENTER, s.x, 28, Color(0.78, 0.82, 0.95))
