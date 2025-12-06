extends Node

var ui_click: AudioStream
var ui_hover: AudioStream
var ui_back: AudioStream
var ui_success: AudioStream
var ui_error: AudioStream

var hit_sound: AudioStream
var death_sound: AudioStream
var kill_sound: AudioStream
var throw_sound: AudioStream
var impact_sound: AudioStream
var spawn_sound: AudioStream
var cart_enter_sound: AudioStream
var cart_exit_sound: AudioStream
var cart_loop_sound: AudioStream
var footstep_sounds: Array[AudioStream] = []
var game_start_sound: AudioStream
var game_end_sound: AudioStream
var countdown_tick: AudioStream
var menu_music: AudioStream
var explosion_sound: AudioStream
var launch_sound: AudioStream
var bounce_sound: AudioStream
var drift_sound: AudioStream
var drift_player: AudioStreamPlayer

var sfx_players: Array[AudioStreamPlayer] = []
var cart_loop_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
const MAX_SFX_PLAYERS = 8

var engine_player: AudioStreamPlayer
var engine_stream: AudioStreamGenerator
var engine_playback: AudioStreamGeneratorPlayback
var engine_phase: float = 0.0
var engine_target_pitch: float = 1.0
var engine_current_pitch: float = 1.0
var engine_running: bool = false
var engine_last_sample: float = 0.0  # low-pass filter state

const ENGINE_SAMPLE_RATE = 22050.0
const ENGINE_BASE_FREQ = 80.0  # Base engine frequency in Hz
const ENGINE_VOLUME = -12.0

func _ready():
	_load_sounds()
	_create_audio_players()

func _process(delta):
	if engine_running:
		_fill_engine_buffer()
		# Smoothly interpolate pitch
		engine_current_pitch = lerp(engine_current_pitch, engine_target_pitch, delta * 8.0)

func _load_sounds():
	ui_click = load("res://assets/sounds/UI Soundpack/WAV/Minimalist1.wav")
	ui_hover = load("res://assets/sounds/UI Soundpack/WAV/Minimalist7.wav")
	ui_back = load("res://assets/sounds/UI Soundpack/WAV/Minimalist2.wav")
	ui_success = load("res://assets/sounds/UI Soundpack/WAV/Modern9.wav")
	ui_error = load("res://assets/sounds/UI Soundpack/WAV/Modern4.wav")
	
	hit_sound = load("res://assets/sounds/Free Sounds Pack/Hit Generic 2-1.wav")
	death_sound = load("res://assets/sounds/Free Sounds Pack/Creature 1-21.wav")
	kill_sound = load("res://assets/sounds/Free Sounds Pack/Special Collectible 26-1.wav")
	throw_sound = load("res://assets/sounds/Free Sounds Pack/Whoosh 1-1.wav")
	impact_sound = load("res://assets/sounds/Free Sounds Pack/Rock Impact 11.wav")
	spawn_sound = load("res://assets/sounds/Free Sounds Pack/Coins 2-1.wav")
	cart_enter_sound = load("res://assets/sounds/Free Sounds Pack/Door Close 4-1.wav")
	cart_exit_sound = load("res://assets/sounds/Free Sounds Pack/Door Open 4-1.wav")
	cart_loop_sound = load("res://assets/sounds/Free Sounds Pack/Ambient Wind Loop 1.wav")
	game_start_sound = load("res://assets/sounds/Free Sounds Pack/Interface 1-1.wav")
	game_end_sound = load("res://assets/sounds/Free Sounds Pack/Magical Interface 5-1.wav")
	countdown_tick = load("res://assets/sounds/UI Soundpack/WAV/Minimalist6.wav")
	menu_music = load("res://assets/sounds/Elevation.mp3")
	explosion_sound = load("res://assets/sounds/Free Sounds Pack/Explosion Large 1-1.wav")
	launch_sound = load("res://assets/sounds/Free Sounds Pack/Whoosh 4-1.wav")
	bounce_sound = load("res://assets/sounds/Free Sounds Pack/Hit Generic 2-1.wav")
	drift_sound = load("res://assets/sounds/Free Sounds Pack/Ambient Wind Loop 1.wav")
	
	footstep_sounds.append(load("res://assets/sounds/Free Footsteps Pack/Grass 1.wav"))
	footstep_sounds.append(load("res://assets/sounds/Free Footsteps Pack/Concrete 1.wav"))
	footstep_sounds.append(load("res://assets/sounds/Free Footsteps Pack/Concrete 2.wav"))

func _create_audio_players():
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	
	cart_loop_player = AudioStreamPlayer.new()
	cart_loop_player.bus = "SFX"
	cart_loop_player.volume_db = -10.0
	add_child(cart_loop_player)
	
	drift_player = AudioStreamPlayer.new()
	drift_player.bus = "SFX"
	drift_player.volume_db = -8.0
	drift_player.pitch_scale = 1.5
	add_child(drift_player)
	
	engine_stream = AudioStreamGenerator.new()
	engine_stream.mix_rate = ENGINE_SAMPLE_RATE
	engine_stream.buffer_length = 0.1
	
	engine_player = AudioStreamPlayer.new()
	engine_player.bus = "SFX"
	engine_player.volume_db = ENGINE_VOLUME
	engine_player.stream = engine_stream
	add_child(engine_player)
	
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -5.0
	add_child(music_player)

func _get_available_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]

func play_sound(sound: AudioStream, volume_db: float = 0.0, pitch: float = 1.0):
	if sound == null:
		return
	var player = _get_available_player()
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

func play_ui_click():
	play_sound(ui_click, -5.0)

func play_ui_hover():
	play_sound(ui_hover, -10.0)

func play_ui_back():
	play_sound(ui_back, -5.0)

func play_ui_success():
	play_sound(ui_success, -3.0)

func play_ui_error():
	play_sound(ui_error, -3.0)

func play_hit():
	play_sound(hit_sound, 0.0, randf_range(0.9, 1.1))

func play_death():
	play_sound(death_sound, -5.0, randf_range(0.8, 1.0))

func play_kill():
	play_sound(kill_sound, 0.0)

func play_throw():
	play_sound(throw_sound, -5.0, randf_range(0.9, 1.1))

func play_impact():
	play_sound(impact_sound, -8.0, randf_range(0.8, 1.2))

func play_spawn():
	play_sound(spawn_sound, -5.0, randf_range(0.9, 1.1))

func play_cart_enter():
	play_sound(cart_enter_sound, -5.0)

func play_cart_exit():
	play_sound(cart_exit_sound, -5.0)

func start_cart_loop():
	if cart_loop_sound and cart_loop_player and not cart_loop_player.playing:
		cart_loop_player.stream = cart_loop_sound
		cart_loop_player.play()

func stop_cart_loop():
	if cart_loop_player:
		cart_loop_player.stop()

func play_footstep():
	if footstep_sounds.size() > 0:
		var sound = footstep_sounds[randi() % footstep_sounds.size()]
		play_sound(sound, -15.0, randf_range(0.9, 1.1))

func play_game_start():
	play_sound(game_start_sound, 0.0)

func play_game_end():
	play_sound(game_end_sound, 0.0)

func play_countdown_tick():
	play_sound(countdown_tick, -5.0)

func start_menu_music():
	if menu_music and music_player and not music_player.playing:
		music_player.stream = menu_music
		music_player.play()

func stop_menu_music():
	if music_player:
		music_player.stop()

func is_menu_music_playing() -> bool:
	return music_player and music_player.playing

func play_explosion():
	play_sound(explosion_sound, 0.0, randf_range(0.9, 1.1))

func play_launch():
	play_sound(launch_sound, -3.0, randf_range(0.9, 1.1))

func play_bounce():
	play_sound(bounce_sound, -5.0, randf_range(0.8, 1.2))

func start_drift_sound():
	if drift_sound and drift_player and not drift_player.playing:
		drift_player.stream = drift_sound
		drift_player.play()

func stop_drift_sound():
	if drift_player:
		drift_player.stop()

# ====================
# Engine sound functions (smoothed) (ai generated btw lmao)
# ====================

func start_engine_sound():
	if engine_player and not engine_running:
		engine_running = true
		engine_phase = 0.0
		engine_last_sample = 0.0
		engine_current_pitch = 0.8
		engine_target_pitch = 0.8
		engine_player.play()
		engine_playback = engine_player.get_stream_playback()

func stop_engine_sound():
	if engine_player:
		engine_running = false
		engine_player.stop()

func set_engine_pitch(speed_ratio: float):
	# speed_ratio is 0.0 to 1.0
	# Narrower pitch range so high revs don't scream
	# Idle ~0.8, max ~1.7
	engine_target_pitch = 0.8 + speed_ratio * 0.9

func _fill_engine_buffer():
	if not engine_playback:
		return
	
	var frames_available = engine_playback.get_frames_available()
	if frames_available <= 0:
		return
	
	var freq = ENGINE_BASE_FREQ * engine_current_pitch
	var increment = freq / ENGINE_SAMPLE_RATE
	
	# One-pole low-pass filter to smooth harsh highs
	var lp_amount = 0.15  # smaller = more smoothing / more muffled
	var last_sample = engine_last_sample
	
	for i in range(frames_available):
		var phase = engine_phase
		
		var sample = 0.0
		
		# Fundamental
		sample += sin(phase * TAU) * 0.45
		
		# Light body
		sample += sin(phase * TAU * 2.0) * 0.25
		
		# Gentle growl
		sample += sin(phase * TAU * 3.0) * 0.12
		
		# Very soft brightness
		sample += sin(phase * TAU * 4.0) * 0.06
		
		# Softer “chug” with slower modulation
		var chug_freq = freq * 0.4
		var chug_phase = phase * (chug_freq / freq)
		var chug_mod = 0.3 + 0.2 * sin(phase * TAU * 0.15)
		sample += sin(chug_phase * TAU) * 0.18 * chug_mod
		
		# Much less noise
		sample += (randf() - 0.5) * 0.02
		
		# Low-pass filter
		last_sample = last_sample + lp_amount * (sample - last_sample)
		sample = last_sample
		
		# Softer clip, less drive
		sample = tanh(sample * 0.7)
		
		# Global gain trim
		sample *= 0.75
		
		engine_playback.push_frame(Vector2(sample, sample))
		
		engine_phase += increment
		if engine_phase >= 1.0:
			engine_phase -= 1.0
	
	engine_last_sample = last_sample
