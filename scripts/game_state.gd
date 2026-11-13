extends Node
## Autoload: night settings, progress, save data, scene flow and input map.

const SAVE_PATH := "user://night_watchman.cfg"
const MAX_NIGHT := 3

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const END_SCENE := "res://scenes/end_screen.tscn"

## Difficulty for each night.
const NIGHTS := {
	1: {
		"title": "Night 1 - First Shift",
		"intruder_max": 2, "intruder_interval": 35.0, "first_intruder": 20.0,
		"intruder_speed": 70.0, "expose_time": 1.3,
		"battery_drain": 1.1, "fear_dark": 1.6,
		"shadows": 0, "shadow_speed": 0.0, "event_mult": 1.0,
		"sabotage_chance": 0.35, "lockpick_time": 8.0,
		"orders_per_hour": 2, "late_interval_mult": 0.55, "crew_size": 2,
		"window_break_time": 1.5, "pry_time": 6.0,
	},
	2: {
		"title": "Night 2 - Something Else Is Here",
		"intruder_max": 3, "intruder_interval": 28.0, "first_intruder": 15.0,
		"intruder_speed": 82.0, "expose_time": 1.5,
		"battery_drain": 1.4, "fear_dark": 2.2,
		"shadows": 1, "shadow_speed": 55.0, "event_mult": 1.3,
		"sabotage_chance": 0.5, "lockpick_time": 6.5,
		"orders_per_hour": 3, "late_interval_mult": 0.5, "crew_size": 3,
		"window_break_time": 1.5, "pry_time": 6.0,
	},
	3: {
		"title": "Night 3 - The Long Dark",
		"intruder_max": 4, "intruder_interval": 22.0, "first_intruder": 10.0,
		"intruder_speed": 95.0, "expose_time": 1.7,
		"battery_drain": 1.7, "fear_dark": 2.8,
		"shadows": 2, "shadow_speed": 70.0, "event_mult": 1.6,
		"sabotage_chance": 0.6, "lockpick_time": 5.0,
		"orders_per_hour": 3, "late_interval_mult": 0.45, "crew_size": 3,
		"window_break_time": 1.2, "pry_time": 5.0,
	},
}

var night := 1
var unlocked := 1
var best_scores := {}
var sound_enabled := true
var last_result := {}

## Run with `-- --autotest` for a short, self-playing shift (used for CI/smoke tests).
var autotest := false
## With --autotest: ignore fear/theft losses so the whole night plays out.
var autotest_survive := false
## Run with `-- --touch` to show the on-screen controls on desktop.
var force_touch := false
## Dev helper: `-- --start-cell=X,Y` starts the watchman at that map cell.
var start_cell := Vector2i(-1, -1)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	autotest_survive = args.has("--survive")
	force_touch = args.has("--touch")
	for a in args:
		if a.begins_with("--night="):
			night = clampi(int(a.trim_prefix("--night=")), 1, MAX_NIGHT)
		elif a.begins_with("--start-cell="):
			var xy := a.trim_prefix("--start-cell=").split(",")
			if xy.size() == 2:
				start_cell = Vector2i(int(xy[0]), int(xy[1]))
		elif a.begins_with("--screenshot="):
			_take_screenshot_later(a.trim_prefix("--screenshot="))
	_setup_input()
	load_game()


## Dev helper: `-- --screenshot=/path/shot.png` saves a frame after 3 s and quits.
func _take_screenshot_later(path: String) -> void:
	await get_tree().create_timer(3.0, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved screenshot to ", path)
	get_tree().quit()


func settings() -> Dictionary:
	return NIGHTS[night]


func use_touch_controls() -> bool:
	return force_touch or DisplayServer.is_touchscreen_available()


func start_night(n: int) -> void:
	night = clampi(n, 1, MAX_NIGHT)
	get_tree().change_scene_to_file(GAME_SCENE)


func finish_night(result: Dictionary) -> void:
	last_result = result
	Engine.time_scale = 1.0
	if result.get("win", false):
		unlocked = maxi(unlocked, mini(night + 1, MAX_NIGHT))
		var key := str(night)
		best_scores[key] = maxi(int(best_scores.get(key, 0)), int(result.get("score", 0)))
	save_game()
	get_tree().change_scene_to_file(END_SCENE)


func go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func save_game() -> void:
	if autotest:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "best_scores", best_scores)
	cfg.set_value("settings", "sound", sound_enabled)
	cfg.save(SAVE_PATH)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, MAX_NIGHT)
	best_scores = cfg.get_value("progress", "best_scores", {})
	sound_enabled = bool(cfg.get_value("settings", "sound", true))


func _setup_input() -> void:
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("move_up", [KEY_W, KEY_UP])
	_add_keys("move_down", [KEY_S, KEY_DOWN])
	_add_keys("flashlight", [KEY_F, KEY_SPACE])
	_add_keys("interact", [KEY_E, KEY_ENTER])
	_add_keys("run", [KEY_SHIFT])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("flashlight", click)


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
