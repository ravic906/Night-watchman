extends Node
## Autoload: the adaptive score.
## Four synced loops (composed by tools/compose_music.py) cross-fade with the
## watchman's fear and the danger around him; stingers punctuate events.

const LOOP_NAMES := ["drone", "heartbeat", "tension", "musicbox"]
const STINGER_NAMES := ["scare", "theft", "spotted", "dawn", "fail", "punch",
		"door_creak", "door_swing", "door_slam",
		"step_1", "step_2", "step_3", "step_4", "sneak_1", "sneak_2", "sneak_3",
		"alarm_arm", "alarm_chime", "alarm_cut", "breaker", "lockpick", "lock",
		"glass_break", "radio", "board", "pry",
		"intercom", "shutter", "shutter_force", "overheat"]
## Names that pick a random take, so repeated sounds do not feel mechanical.
const VARIANTS := {"step": 4, "sneak": 3}
const FADE_SPEED := 1.5
const MUSIC_BASE_DB := -3.0
const SFX_BASE_DB := -1.0
const MIN_LINEAR := 0.001

var enabled := true

var _loops := {}       # name -> AudioStreamPlayer
var _targets := {}     # name -> target linear volume (0..1)
var _stingers := {}    # name -> AudioStream
var _heart_rate := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Music", MUSIC_BASE_DB)
	_make_bus("SFX", SFX_BASE_DB)
	for n in LOOP_NAMES:
		var stream: AudioStreamOggVorbis = load("res://audio/%s.ogg" % n)
		stream.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Music"
		p.volume_db = linear_to_db(MIN_LINEAR)
		add_child(p)
		_loops[n] = p
		_targets[n] = 0.0
	for n in STINGER_NAMES:
		_stingers[n] = load("res://audio/%s.ogg" % n)
	set_enabled(GameState.sound_enabled)   # also applies the volume sliders


func _make_bus(bus_name: String, db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, db)


func _start_loops() -> void:
	if (_loops["drone"] as AudioStreamPlayer).playing:
		return
	# Started on the same frame so the layers stay in sync.
	for n in LOOP_NAMES:
		_loops[n].play()


func play_menu() -> void:
	_start_loops()
	_targets = {"drone": 0.7, "heartbeat": 0.0, "tension": 0.0, "musicbox": 0.75}
	_heart_rate = 1.0


func play_game() -> void:
	_start_loops()
	set_mood(0.0, 0.0)


## fear and danger are 0..1. Calm patrols get the music box; fear brings in
## the heartbeat (and speeds it up); danger brings in the strings.
func set_mood(fear: float, danger: float) -> void:
	fear = clampf(fear, 0.0, 1.0)
	danger = clampf(danger, 0.0, 1.0)
	_targets["drone"] = 0.7 + 0.3 * fear
	_targets["musicbox"] = 0.45 * clampf(1.0 - fear * 2.2, 0.0, 1.0) * (1.0 - danger)
	_targets["heartbeat"] = clampf((fear - 0.15) / 0.55, 0.0, 1.0) * 0.9
	_targets["tension"] = maxf(danger, clampf((fear - 0.55) / 0.45, 0.0, 1.0)) * 0.85
	_heart_rate = 1.0 + 0.4 * fear


func end_shift(win: bool) -> void:
	_targets = {"drone": 0.35, "heartbeat": 0.0, "tension": 0.0, "musicbox": 0.0}
	_heart_rate = 1.0
	stinger("dawn" if win else "fail")


func stinger(stinger_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _resolve(stinger_name)
	if not enabled or stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	_play_one_shot(p)


## A sound effect from a world position: louder when close to the camera
## (which follows the watchman), silent beyond max_distance.
func sfx_at(sound_name: String, pos: Vector2, volume_db := 0.0, pitch := 1.0, max_distance := 900.0) -> void:
	var stream := _resolve(sound_name)
	if not enabled or stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.attenuation = 1.6
	p.position = pos
	_play_one_shot(p)


func _resolve(sound_name: String) -> AudioStream:
	if VARIANTS.has(sound_name):
		sound_name = "%s_%d" % [sound_name, randi_range(1, VARIANTS[sound_name])]
	return _stingers.get(sound_name)


## Plays a fire-and-forget sound player and makes sure it is cleaned up:
## normally by "finished"; as a safety net, a timer for the sound's real
## length (pitch-adjusted) that frees it only once it has stopped playing,
## re-checking a few times so paused or slowed sounds are never cut short.
func _play_one_shot(p: Node) -> void:
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	var length: float = p.stream.get_length() / maxf(p.pitch_scale, 0.05)
	_check_one_shot(p, length + 0.5, 3)


func _check_one_shot(p: Node, wait: float, tries_left: int) -> void:
	var t := get_tree().create_timer(wait, true, false, true)
	# The handler checks is_instance_valid, since the player may be gone by then.
	t.timeout.connect(_on_one_shot_check.bind(p, tries_left))


func _on_one_shot_check(p, tries_left: int) -> void:   # untyped: p may already be freed
	if not is_instance_valid(p) or p.is_queued_for_deletion():
		return
	if p.playing and tries_left > 0:
		_check_one_shot(p, 1.0, tries_left - 1)
	else:
		p.queue_free()


## Applies the Settings sliders (0..1) to the Music and SFX buses.
func apply_volumes() -> void:
	for pair in [["Music", MUSIC_BASE_DB, GameState.music_volume], ["SFX", SFX_BASE_DB, GameState.sfx_volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		var v: float = pair[2]
		AudioServer.set_bus_volume_db(i, pair[1] + linear_to_db(maxf(v, 0.001)))
		AudioServer.set_bus_mute(i, v <= 0.01 or not enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	apply_volumes()


func _process(delta: float) -> void:
	var k := clampf(delta * FADE_SPEED, 0.0, 1.0)
	for n in LOOP_NAMES:
		var p: AudioStreamPlayer = _loops[n]
		var current := db_to_linear(p.volume_db)
		var next := lerpf(current, float(_targets[n]), k)
		p.volume_db = linear_to_db(maxf(next, MIN_LINEAR))
	var heart: AudioStreamPlayer = _loops["heartbeat"]
	heart.pitch_scale = lerpf(heart.pitch_scale, _heart_rate, k)


func _exit_tree() -> void:
	# Stop playback before shutdown so the audio server releases the streams.
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			child.stop()
			child.stream = null
	_loops.clear()
	_stingers.clear()
