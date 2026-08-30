extends Node
## Central, named audio hooks. Autoload name: AudioDirector
##
## The vertical slice ships with ORIGINAL, procedurally-synthesised placeholder
## tones rather than third-party audio, so the repository stays free of any
## asset licence question. Every cue the design calls for already has a named
## entry point here, so replacing a placeholder with a real asset is a
## one-line change and never a code change at the call sites.

enum Cue {
	UI_CLICK,
	UI_BACK,
	UI_ERROR,
	STATION_AMBIENCE,
	JUNGLE_AMBIENCE,
	CRYSTAL_PICKUP,
	PEDESTAL_ACTIVATE,
	ALTAR_ACTIVATE,
	STAR_MAP_PICKUP,
	BLASTER_FIRE,
	BLASTER_OVERHEAT,
	SENTINEL_SPAWN,
	SENTINEL_PROJECTILE,
	PLAYER_HURT,
	PLAYER_DOWNED,
	REVIVE_START,
	REVIVE_COMPLETE,
	VICTORY,
	FAILURE,
}

## Cue -> [frequency_hz, seconds, volume_db]. Deliberately simple: these are
## placeholders whose only job is to be audibly distinct.
const _CUE_TONES: Dictionary = {
	Cue.UI_CLICK:            [880.0, 0.05, -14.0],
	Cue.UI_BACK:             [440.0, 0.06, -16.0],
	Cue.UI_ERROR:            [180.0, 0.18, -12.0],
	Cue.STATION_AMBIENCE:    [70.0, 2.40, -28.0],
	Cue.JUNGLE_AMBIENCE:     [95.0, 2.40, -28.0],
	Cue.CRYSTAL_PICKUP:      [1320.0, 0.16, -10.0],
	Cue.PEDESTAL_ACTIVATE:   [660.0, 0.28, -10.0],
	Cue.ALTAR_ACTIVATE:      [330.0, 0.70, -8.0],
	Cue.STAR_MAP_PICKUP:     [1560.0, 0.35, -8.0],
	Cue.BLASTER_FIRE:        [1180.0, 0.07, -16.0],
	Cue.BLASTER_OVERHEAT:    [220.0, 0.30, -12.0],
	Cue.SENTINEL_SPAWN:      [110.0, 1.10, -8.0],
	Cue.SENTINEL_PROJECTILE: [520.0, 0.12, -18.0],
	Cue.PLAYER_HURT:         [260.0, 0.14, -10.0],
	Cue.PLAYER_DOWNED:       [140.0, 0.60, -8.0],
	Cue.REVIVE_START:        [700.0, 0.10, -14.0],
	Cue.REVIVE_COMPLETE:     [1040.0, 0.30, -9.0],
	Cue.VICTORY:             [780.0, 1.00, -7.0],
	Cue.FAILURE:             [150.0, 1.20, -7.0],
}

const _VOICE_COUNT: int = 10
const _SAMPLE_RATE: int = 22050

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _ambience: AudioStreamPlayer = null
var _cache: Dictionary = {}
var _enabled: bool = true


func _ready() -> void:
	# A headless run has no audio device; synthesising streams there is pure
	# waste and can emit driver warnings into CI logs.
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for i in _VOICE_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Master"
	add_child(_ambience)


func play(cue: Cue) -> void:
	if not _enabled or _voices.is_empty():
		return
	var stream := _stream_for(cue)
	if stream == null:
		return
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = stream
	v.volume_db = float((_CUE_TONES[cue] as Array)[2]) + linear_to_db(maxf(SettingsManager.master_volume, 0.0001))
	v.play()


func play_ambience(cue: Cue) -> void:
	if not _enabled or _ambience == null:
		return
	var stream := _stream_for(cue)
	if stream == null:
		return
	_ambience.stream = stream
	_ambience.volume_db = float((_CUE_TONES[cue] as Array)[2]) + linear_to_db(maxf(SettingsManager.master_volume, 0.0001))
	_ambience.play()


func stop_ambience() -> void:
	if _ambience != null:
		_ambience.stop()


func _stream_for(cue: Cue) -> AudioStream:
	if _cache.has(cue):
		return _cache[cue]
	var spec: Variant = _CUE_TONES.get(cue)
	if spec == null:
		return null
	var stream := _synthesise(float((spec as Array)[0]), float((spec as Array)[1]))
	_cache[cue] = stream
	return stream


## Original placeholder tone: a sine with a short attack and an exponential
## decay so it reads as a "blip" rather than a click.
func _synthesise(frequency: float, seconds: float) -> AudioStreamWAV:
	var frames := int(_SAMPLE_RATE * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var attack := maxi(int(_SAMPLE_RATE * 0.005), 1)
	for i in frames:
		var t := float(i) / float(_SAMPLE_RATE)
		var env := minf(float(i) / float(attack), 1.0) * exp(-3.5 * t / maxf(seconds, 0.001))
		var sample := sin(TAU * frequency * t) * env
		var v := int(clampf(sample, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
