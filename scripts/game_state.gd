extends Node
## Autoload: locations, difficulty, progress, save data, scene flow and input map.

const SAVE_PATH := "user://night_watchman.cfg"

## Locations to guard, in menu order (scripts/maps/<id>.gd).
const LOCATIONS := ["museum", "apartment", "mall", "factory"]
const DIFFICULTY_NAMES := {1: "Easy", 2: "Normal", 3: "Hard"}

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const END_SCENE := "res://scenes/end_screen.tscn"

## Settings for each difficulty (1 = Easy, 2 = Normal, 3 = Hard).
const DIFFICULTY := {
	1: {
		"intruder_max": 2, "intruder_interval": 35.0, "first_intruder": 20.0,
		"intruder_speed": 70.0, "expose_time": 1.3,
		"battery_drain": 0.8, "fear_dark": 1.6,
		"shadows": 0, "shadow_speed": 0.0, "event_mult": 1.0,
		"sabotage_chance": 0.35, "lockpick_time": 8.0,
		"radio_hours": 1, "rooms_per_check": 1, "late_interval_mult": 0.55, "crew_size": 2,
		"window_break_time": 1.5, "pry_time": 6.0,
	},
	2: {
		"intruder_max": 3, "intruder_interval": 28.0, "first_intruder": 15.0,
		"intruder_speed": 82.0, "expose_time": 1.5,
		"battery_drain": 1.0, "fear_dark": 2.2,
		"shadows": 1, "shadow_speed": 55.0, "event_mult": 1.3,
		"sabotage_chance": 0.5, "lockpick_time": 6.5,
		"radio_hours": 1, "rooms_per_check": 2, "late_interval_mult": 0.5, "crew_size": 3,
		"window_break_time": 1.5, "pry_time": 6.0,
	},
	3: {
		"intruder_max": 4, "intruder_interval": 22.0, "first_intruder": 10.0,
		"intruder_speed": 95.0, "expose_time": 1.7,
		"battery_drain": 1.3, "fear_dark": 2.8,
		"shadows": 2, "shadow_speed": 70.0, "event_mult": 1.6,
		"sabotage_chance": 0.6, "lockpick_time": 5.0,
		"radio_hours": 1, "rooms_per_check": 3, "late_interval_mult": 0.45, "crew_size": 3,
		"window_break_time": 1.2, "pry_time": 5.0,
	},
}

var difficulty := 2
var location := "museum"
## Best score per "location:difficulty".
var best_scores := {}
var sound_enabled := true
## The objectives panel opens by itself on the first shift of each session.
var seen_objectives := false
var last_result := {}

## Run with `-- --autotest` for a short, self-playing shift (used for CI/smoke tests).
var autotest := false
## With --autotest: ignore fear/theft losses so the whole night plays out.
var autotest_survive := false
## Run with `-- --touch` to show the on-screen controls on desktop.
var force_touch := false
## Dev helper: `-- --start-cell=X,Y` starts the watchman at that map cell.
var start_cell := Vector2i(-1, -1)
## Dev/test overrides of difficulty settings (e.g. --radio-hours=2 --rooms=1).
var overrides := {}
## Play harness (see README "Automated playtesting").
var seed_value := -1
var inputs_path := ""
var snap_times: Array = []
var out_dir := ""
var until_time := -1.0
var fast := false
var log_windows := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	autotest_survive = args.has("--survive")
	force_touch = args.has("--touch")
	for a in args:
		if a.begins_with("--night="):   # old alias for difficulty
			difficulty = clampi(int(a.trim_prefix("--night=")), 1, 3)
		elif a.begins_with("--difficulty="):
			var want := a.trim_prefix("--difficulty=").to_lower()
			for k in DIFFICULTY_NAMES:
				if DIFFICULTY_NAMES[k].to_lower() == want:
					difficulty = k
		elif a.begins_with("--location="):
			var loc := a.trim_prefix("--location=")
			if loc in LOCATIONS:
				location = loc
		elif a.begins_with("--start-cell="):
			var xy := a.trim_prefix("--start-cell=").split(",")
			if xy.size() == 2:
				start_cell = Vector2i(int(xy[0]), int(xy[1]))
		elif a.begins_with("--radio-hours="):
			overrides["radio_hours"] = clampi(int(a.get_slice("=", 1)), 1, 4)
		elif a.begins_with("--rooms="):
			overrides["rooms_per_check"] = clampi(int(a.get_slice("=", 1)), 1, 5)
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--inputs="):
			inputs_path = a.get_slice("=", 1)
		elif a.begins_with("--snap="):
			for t in a.get_slice("=", 1).split(","):
				snap_times.append(float(t))
			snap_times.sort()
		elif a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--until="):
			until_time = float(a.get_slice("=", 1))
		elif a == "--fast":
			fast = true
		elif a == "--log-windows":
			log_windows = true
		elif a.begins_with("--screenshot="):
			_take_screenshot_later(a.trim_prefix("--screenshot="))
	_setup_input()
	var cli_difficulty := difficulty
	var cli_location := location
	load_game()
	var arg_list := Array(args)
	if arg_list.any(func(x): return x.begins_with("--night=") or x.begins_with("--difficulty=")):
		difficulty = cli_difficulty
	if arg_list.any(func(x): return x.begins_with("--location=")):
		location = cli_location


## Dev helper: `-- --screenshot=/path/shot.png` saves a frame after 3 s and quits.
func _take_screenshot_later(path: String) -> void:
	await get_tree().create_timer(3.0, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved screenshot to ", path)
	get_tree().quit()


func settings() -> Dictionary:
	var s: Dictionary = DIFFICULTY[difficulty].duplicate()
	s.merge(overrides, true)
	return s


func harness_active() -> bool:
	return inputs_path != "" or not snap_times.is_empty() or until_time > 0.0


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func location_def(loc_id := ""):
	if loc_id == "":
		loc_id = location
	return load("res://scripts/maps/%s.gd" % loc_id).new()


func best_score(loc_id: String, diff: int) -> int:
	return int(best_scores.get("%s:%d" % [loc_id, diff], 0))


func use_touch_controls() -> bool:
	return force_touch or DisplayServer.is_touchscreen_available()


func start_shift(loc_id := "", diff := 0) -> void:
	if loc_id != "":
		location = loc_id
	if diff > 0:
		difficulty = clampi(diff, 1, 3)
	save_game()
	get_tree().change_scene_to_file(GAME_SCENE)


func finish_night(result: Dictionary) -> void:
	last_result = result
	Engine.time_scale = 1.0
	if result.get("win", false):
		var key := "%s:%d" % [location, difficulty]
		best_scores[key] = maxi(int(best_scores.get(key, 0)), int(result.get("score", 0)))
	save_game()
	if harness_active():
		# Scripted runs end here: print the result and exit cleanly.
		print("HARNESS shift over: ", result)
		get_tree().quit()
		return
	get_tree().call_deferred("change_scene_to_file", END_SCENE)


func go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func save_game() -> void:
	if autotest:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best_scores", best_scores)
	cfg.set_value("settings", "location", location)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "sound", sound_enabled)
	cfg.save(SAVE_PATH)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# Old saves stored best scores per night number; keep only the new keys.
	var saved: Dictionary = cfg.get_value("progress", "best_scores", {})
	best_scores = {}
	for k in saved:
		if str(k).contains(":"):
			best_scores[k] = saved[k]
	var loc: String = cfg.get_value("settings", "location", "museum")
	location = loc if loc in LOCATIONS else "museum"
	difficulty = clampi(int(cfg.get_value("settings", "difficulty", 2)), 1, 3)
	sound_enabled = bool(cfg.get_value("settings", "sound", true))


func _setup_input() -> void:
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("move_up", [KEY_W, KEY_UP])
	_add_keys("move_down", [KEY_S, KEY_DOWN])
	_add_keys("flashlight", [KEY_F, KEY_SPACE])
	_add_keys("interact", [KEY_E, KEY_ENTER])
	_add_keys("run", [KEY_SHIFT])
	_add_keys("objectives", [KEY_TAB, KEY_O])
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
