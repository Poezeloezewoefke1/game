@tool
extends Control
## Puts the game's own sky behind a menu, slowly drifting.
##
## The menus were sitting on a flat dark rectangle while the game itself has a
## starfield, a galactic band and a ringed gas giant already written and paid
## for. Rendering it behind the interface costs one small offscreen viewport and
## makes the first screen a player sees look like the game they are about to
## play rather than like a settings dialog.
##
## Renders at a reduced resolution and a low frame rate on purpose: this is a
## slowly drifting backdrop, nobody is inspecting it, and a menu should not be
## the most expensive thing the game draws.

## Fraction of the window the offscreen viewport renders at.
const RESOLUTION_SCALE := 0.62
## Degrees per second of drift. Slow enough not to be distracting.
const DRIFT_SPEED := 0.55
## Darkened over the top, so panel text stays readable against a bright band.
const VEIL := Color(0.02, 0.03, 0.06, 0.55)

@export var sky_material_path: String = "res://resources/sky_hub.tres"
@export var field_of_view: float = 62.0

var _viewport: SubViewport
var _camera: Camera3D
var _yaw: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# A headless run has no rendering device to give a SubViewport, and the
	# automated suite mounts these menus constantly.
	if DisplayServer.get_name() == "headless":
		return
	_build()


func _build() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(_viewport)

	var sky := Sky.new()
	sky.sky_material = load(sky_material_path)
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	_camera = Camera3D.new()
	_camera.fov = field_of_view
	_viewport.add_child(_camera)
	_camera.current = true

	# The veil. Without it the galactic core drifts behind the buttons and the
	# text on them stops being readable for a few seconds at a time.
	var veil := ColorRect.new()
	veil.color = VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_resize()
	resized.connect(_resize)


func _resize() -> void:
	if _viewport == null:
		return
	var target := Vector2i(size * RESOLUTION_SCALE)
	_viewport.size = Vector2i(maxi(target.x, 64), maxi(target.y, 64))


func _process(delta: float) -> void:
	if _camera == null:
		return
	_yaw = fposmod(_yaw + delta * DRIFT_SPEED, 360.0)
	# A slight downward tilt puts the horizonless star field above the panels,
	# which is where the interesting part of the sky is.
	_camera.rotation_degrees = Vector3(6.0, _yaw, 0.0)
