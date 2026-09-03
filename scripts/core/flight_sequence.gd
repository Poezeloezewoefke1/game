extends Node3D
class_name FlightSequence
## The launch and landing you actually SEE.
##
## GameManager owns the flight as three states on the host clock; this is the
## presentation of them, and it is deliberately a pure view - it reads the
## mission state and the phase start time and renders. It never sets state,
## never sends anything, and runs identically on the host and on every client,
## because both are driving from the same two replicated numbers.
##
## That split is what keeps four players' launches in sync without a single
## extra RPC: everyone knows the phase and when it began, so everyone is at the
## same point in the same animation.

## Engine bells at the stern, lit during burn.
@onready var _engine_glow: Node3D = $EngineGlow
## A cage of streaks around the hull, visible only in transit. It sits OUTSIDE
## the windows, so it reads as the stars going past rather than as an effect
## drawn over the room.
@onready var _streaks: Node3D = $Streaks
@onready var _rumble: OmniLight3D = $RumbleLight

const MS := MissionRules.MissionState

var _streak_meshes: Array[MeshInstance3D] = []
var _engine_meshes: Array[MeshInstance3D] = []
var _last_state: int = -1
var _thud_played: bool = false


func _ready() -> void:
	_build_engines()
	_build_streaks()
	_apply(MS.SHIP_IDLE, 0.0)


func _build_engines() -> void:
	# Four bells across the stern. They only glow during a burn, which is the
	# clearest single cue that the ship is under power.
	for i in 4:
		var x: float = -5.4 + i * 3.6
		var bell := MeshInstance3D.new()
		bell.mesh = MeshFactory.tapered_column(1.6, 1.15, 0.75, 10)
		bell.position = Vector3(x, 1.6, 26.4)
		bell.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		add_child(bell)
		ModelKit.set_albedo(bell, Color(0.20, 0.21, 0.26))

		var flame := MeshInstance3D.new()
		flame.mesh = MeshFactory.tapered_column(3.2, 0.72, 0.10, 8)
		flame.position = Vector3(x, 1.6, 28.6)
		flame.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_engine_glow.add_child(flame)
		ModelKit.set_emission(flame, Color(0.55, 0.82, 1.0), 0.0)
		_engine_meshes.append(flame)


func _build_streaks() -> void:
	# Long thin bars scattered on a cylinder around the ship. Cheap, and at
	# speed a bar IS a streaked star - there is nothing to gain from particles.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in 120:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(13.0, 34.0)
		var bar := MeshInstance3D.new()
		bar.mesh = MeshFactory.beveled_box(
			Vector3(0.12, 0.12, rng.randf_range(6.0, 22.0)), 0.02)
		bar.position = Vector3(sin(angle) * radius,
			rng.randf_range(-14.0, 18.0), rng.randf_range(-40.0, 40.0))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_streaks.add_child(bar)
		ModelKit.set_emission(bar, Color(0.72, 0.86, 1.0), 2.4)
		_streak_meshes.append(bar)
	_streaks.visible = false


func _process(delta: float) -> void:
	var state := GameManager.mission_state()
	var started := int(GameManager.snapshot.get("flight_started_ms", 0))
	var elapsed := 0.0
	if started > 0:
		elapsed = float(Time.get_ticks_msec() - started) / 1000.0
	if state != _last_state:
		_last_state = state
		_thud_played = false
	_apply(state, elapsed)
	_advance(state, delta)


## Everything the sequence looks like, as a function of phase and elapsed time.
## Written as one function on purpose: the alternative is a scatter of flags
## that can disagree with each other about which part of the flight it is.
func _apply(state: int, elapsed: float) -> void:
	var burn := 0.0
	var streak := 0.0
	var shake := 0.0

	match state:
		MS.LAUNCHING:
			var t: float = clampf(elapsed / GameConfig.FLIGHT_LAUNCH_TIME, 0.0, 1.0)
			# Engines spin up over the first third, then hold; the shake peaks
			# as the ship breaks away and eases once it is clear.
			burn = clampf(t * 3.0, 0.0, 1.0)
			shake = sin(clampf(t * 2.2, 0.0, 1.0) * PI) * 0.55 + 0.10
			streak = clampf((t - 0.72) / 0.28, 0.0, 1.0)
		MS.IN_TRANSIT:
			burn = 1.0
			streak = 1.0
			shake = 0.06
		MS.LANDING:
			var t: float = clampf(elapsed / GameConfig.FLIGHT_LANDING_TIME, 0.0, 1.0)
			streak = clampf(1.0 - t * 2.4, 0.0, 1.0)
			burn = clampf(1.0 - t * 0.7, 0.15, 1.0)
			# Two bumps: hitting atmosphere, then the gear touching down.
			shake = 0.14 + 0.42 * exp(-pow((t - 0.35) * 7.0, 2.0)) \
				+ 0.75 * exp(-pow((t - 0.94) * 16.0, 2.0))
			if t > 0.93 and not _thud_played:
				_thud_played = true
				AudioDirector.play(AudioDirector.Cue.PLAYER_HURT)
		_:
			pass

	for mesh in _engine_meshes:
		ModelKit.set_emission(mesh, Color(0.55, 0.82, 1.0).lerp(
			Color(1.0, 0.86, 0.62), burn * 0.5), burn * 5.0)
		mesh.visible = burn > 0.02
		mesh.scale = Vector3(0.6 + burn * 0.5, 1.0, 0.6 + burn * 0.5)

	_streaks.visible = streak > 0.02
	if _streaks.visible:
		for mesh in _streak_meshes:
			ModelKit.set_emission(mesh, Color(0.72, 0.86, 1.0), streak * 3.2)

	if _rumble != null:
		_rumble.light_energy = burn * 1.4
		_rumble.visible = burn > 0.02

	if shake > 0.0:
		var player: Node = SpawnManager.local_player()
		if player != null and player.has_method("shake_view"):
			# Scaled per frame rather than applied whole: shake_view accumulates
			# towards a cap, and dumping the full amount every frame would peg
			# it there for the entire sequence.
			player.call("shake_view", shake * 0.09)


func _advance(state: int, delta: float) -> void:
	if not _streaks.visible:
		return
	# Streaks fly past towards the stern and wrap. The speed sells the transit
	# far more than their brightness does.
	var speed := 120.0 if state == MS.IN_TRANSIT else 60.0
	for mesh in _streak_meshes:
		mesh.position.z += speed * delta
		if mesh.position.z > 44.0:
			mesh.position.z -= 88.0
