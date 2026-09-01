extends Node3D
## The pop of light at the end of the barrel when a shot leaves it.
##
## Purely cosmetic, which is the important part: it is driven by the host's
## tracer RPC, not by the local trigger press, so it can never make a client
## believe it fired a shot the host rejected. Every player sees every other
## player's flash for the same reason - one signal, one visual.
##
## Three pieces do the work together:
##   - a short forward cone, which gives the flash a direction;
##   - two crossed flares, which give it a bright core;
##   - an OmniLight3D, which is what actually sells it, because it briefly
##     lights the walls and the shooter's own hands.
##
## Everything visible hangs off a `_burst` child rather than off this node, so
## the per-shot roll and scale live there and this node's own transform stays
## free to be snapped onto a moving barrel tip - see `set_follow`.
##
## It lives for a few frames. `_process` is disabled while it is idle, so an
## idle flash costs nothing on the other three players' machines.

const FLASH_TIME: float = 0.055
const LIGHT_ENERGY: float = 5.0
const LIGHT_RANGE: float = 5.5

var colour: Color = Color(0.62, 0.92, 1.0)

var _time_left: float = 0.0
var _frames_shown: int = 0
var _burst: Node3D = null
var _light: OmniLight3D = null
var _parts: Array[MeshInstance3D] = []
var _follow: Node3D = null


func _ready() -> void:
	_build()
	_set_visible(false)
	set_process(false)


func _build() -> void:
	_burst = Node3D.new()
	_burst.name = "Burst"
	add_child(_burst)

	# Forward cone. `crystal` is a spike about its own Y, so it is rotated to
	# point down -Z, which is the direction the weapon is aimed.
	_add_part(MeshFactory.crystal(0.13, 0.042, 4), Vector3(0.0, 0.0, -0.05),
		Vector3(-90.0, 0.0, 0.0))

	# Crossed flares. Two quads at right angles read as a star from most angles
	# without needing a billboard, and cost two triangles each. They carry a
	# radial falloff texture - an untextured additive quad is a hard white
	# SQUARE stuck on the barrel, which is exactly how the first version looked.
	var flare := QuadMesh.new()
	flare.size = Vector2(0.13, 0.13)
	_add_part(flare, Vector3.ZERO, Vector3(0.0, 0.0, 18.0), _flare_texture())
	_add_part(flare, Vector3.ZERO, Vector3(0.0, 90.0, -22.0), _flare_texture())

	_light = OmniLight3D.new()
	_light.light_color = colour
	_light.light_energy = 0.0
	_light.omni_range = LIGHT_RANGE
	# A light this brief cannot afford a shadow map update per shot, and nobody
	# would see the difference in the two frames it exists.
	_light.shadow_enabled = false
	_burst.add_child(_light)


func _add_part(mesh: Mesh, offset: Vector3, rotation_degrees_value: Vector3,
		texture: Texture2D = null) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.rotation_degrees = rotation_degrees_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 4.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Additive geometry that writes depth punches a hole in whatever is drawn
	# after it, which shows up as a square of missing wall behind the flash.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	if texture != null:
		material.albedo_texture = texture
		material.emission_texture = texture
	instance.material_override = material

	_burst.add_child(instance)
	_parts.append(instance)


## A soft round blob, built once and shared by every flash in the game. Sixteen
## pixels is plenty: it is only ever a few centimetres across on screen, and the
## point is the falloff, not the detail.
static var _flare: ImageTexture = null


static func _flare_texture() -> Texture2D:
	if _flare != null:
		return _flare
	var size := 32
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBAF)
	var centre := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - centre, float(y) - centre).length() / centre
			# Squared falloff with a hot core, which is what a flash looks like.
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.35 + 0.65 * a)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_flare = ImageTexture.create_from_image(image)
	return _flare


## Pin the flash to a point that moves - the viewmodel's barrel tip, which bobs,
## sways and recoils. Without this the flash stays welded to the fixed fire
## origin and visibly detaches from the gun the moment the player moves.
## Remote players have no viewmodel, so they simply never call this and keep the
## fixed muzzle position, which is correct for a gun seen from outside.
func set_follow(target: Node3D) -> void:
	_follow = target
	if is_instance_valid(_follow):
		top_level = true
		_snap_to_follow()


func _snap_to_follow() -> void:
	if not is_instance_valid(_follow):
		return
	global_transform = Transform3D(_follow.global_basis.orthonormalized(),
		_follow.global_position)


## Fire the flash. Safe to call again while one is still fading - it restarts.
func flash() -> void:
	_time_left = FLASH_TIME
	# A fixed flash shape repeated ten times a second reads as a flicker rather
	# than a muzzle; rolling and resizing it each shot breaks the pattern.
	_burst.rotation.z = randf() * TAU
	_burst.scale = Vector3.ONE * randf_range(0.85, 1.2)
	_frames_shown = 0
	_snap_to_follow()
	_set_visible(true)
	_apply_intensity(1.0)
	set_process(true)


func _process(delta: float) -> void:
	_snap_to_follow()
	_time_left -= delta
	# A 55 ms flash is shorter than one frame on a machine below ~18 fps, and
	# `_process` runs before the frame is drawn - so a purely time-based flash
	# expires without ever being rendered, and the player sees no feedback at
	# all for their own shots precisely when the game is struggling. Guarantee
	# one drawn frame before it is allowed to go out.
	if _time_left <= 0.0 and _frames_shown >= 1:
		_set_visible(false)
		set_process(false)
		return
	_frames_shown += 1
	_apply_intensity(maxf(_time_left, 0.0) / FLASH_TIME if _frames_shown > 1 else 1.0)


func _apply_intensity(ratio: float) -> void:
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * ratio
	for instance in _parts:
		var material := instance.material_override as StandardMaterial3D
		if material == null:
			continue
		material.albedo_color = Color(colour.r, colour.g, colour.b, ratio)
		material.emission_energy_multiplier = 4.0 * ratio


func _set_visible(value: bool) -> void:
	if _burst != null:
		_burst.visible = value
	if _light != null and not value:
		_light.light_energy = 0.0
