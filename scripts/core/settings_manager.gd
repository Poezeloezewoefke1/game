extends Node
## Local, per-machine preferences. Autoload name: SettingsManager
##
## Deliberately NOT networked and deliberately NOT authoritative: nothing here
## may influence a gameplay outcome. It stores the last used display name, host
## address and port so the player does not retype them every launch, plus local
## comfort options.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "player"

var display_name: String = ""
var last_host_address: String = "127.0.0.1"
var last_port: int = GameConfig.DEFAULT_PORT
var mouse_sensitivity_scale: float = 1.0
var master_volume: float = 1.0
var invert_look: bool = false

var _loaded: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		# Missing file on first launch is normal, not an error.
		_loaded = true
		return
	display_name = String(cfg.get_value(SECTION, "display_name", display_name))
	last_host_address = String(cfg.get_value(SECTION, "last_host_address", last_host_address))
	last_port = int(cfg.get_value(SECTION, "last_port", last_port))
	mouse_sensitivity_scale = clampf(float(cfg.get_value(SECTION, "mouse_sensitivity_scale", 1.0)), 0.1, 5.0)
	master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", 1.0)), 0.0, 1.0)
	invert_look = bool(cfg.get_value(SECTION, "invert_look", false))
	_loaded = true


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "display_name", display_name)
	cfg.set_value(SECTION, "last_host_address", last_host_address)
	cfg.set_value(SECTION, "last_port", last_port)
	cfg.set_value(SECTION, "mouse_sensitivity_scale", mouse_sensitivity_scale)
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "invert_look", invert_look)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		Logx.warn("settings", "Could not save settings: %d" % err)


func effective_mouse_sensitivity() -> float:
	return GameConfig.MOUSE_SENSITIVITY * mouse_sensitivity_scale


## Validates a user supplied port, falling back to the default rather than
## letting an out-of-range value reach ENet.
static func sanitize_port(raw: Variant) -> int:
	var p := int(raw)
	if p < GameConfig.MIN_PORT or p > GameConfig.MAX_PORT:
		return GameConfig.DEFAULT_PORT
	return p
