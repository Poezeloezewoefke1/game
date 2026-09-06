extends Node
## Autoload: AudioMgr. Plays generated (original) music and SFX from res://assets/audio.
## Missing files degrade silently so the game never depends on audio being present.

const AUDIO_DIR := "res://assets/audio/"
const MAX_SFX_PLAYERS := 24

var _music_player: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_3d_players: Array[AudioStreamPlayer3D] = []
var _cache: Dictionary = {}
var current_music: String = ""
var _sfx_cooldowns: Dictionary = {}

func _ready() -> void:
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = "Music"
	add_child(_music_player_b)
	for i in MAX_SFX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.max_distance = 80.0
		p3.unit_size = 8.0
		add_child(p3)
		_sfx_3d_players.append(p3)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _load(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var stream: AudioStream = null
	for ext: String in [".ogg", ".wav"]:
		var path: String = AUDIO_DIR + name + ext
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	_cache[name] = stream
	return stream

func play_music(name: String, fade: float = 1.0) -> void:
	if name == current_music:
		return
	current_music = name
	var stream := _load(name)
	if stream == null:
		_music_player.stop()
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.data.size() / 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else stream.data.size()
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	# crossfade
	var old := _music_player
	_music_player = _music_player_b
	_music_player_b = old
	_music_player.stream = stream
	_music_player.volume_db = -30.0
	_music_player.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_music_player, "volume_db", 0.0, fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -30.0, fade)
		tw.chain().tween_callback(old.stop)

func stop_music(fade: float = 0.8) -> void:
	current_music = ""
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -30.0, fade)
	tw.tween_callback(_music_player.stop)

func play_sfx(name: String, volume_db: float = 0.0, pitch_variation: float = 0.08, min_interval: float = 0.03) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _sfx_cooldowns.has(name) and now - _sfx_cooldowns[name] < min_interval:
		return
	_sfx_cooldowns[name] = now
	var stream := _load(name)
	if stream == null:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
			p.play()
			return

func play_sfx_at(name: String, position: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.1, min_interval: float = 0.04) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _sfx_cooldowns.has(name) and now - _sfx_cooldowns[name] < min_interval:
		return
	_sfx_cooldowns[name] = now
	var stream := _load(name)
	if stream == null:
		return
	for p in _sfx_3d_players:
		if not p.playing:
			p.stream = stream
			p.global_position = position
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
			p.play()
			return
