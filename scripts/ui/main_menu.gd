extends Control
## Entry screen: name, host, join, quit.
##
## Owns no gameplay state. Every button either asks NetworkManager to do
## something or navigates locally; the resulting screen change is driven by
## NetworkManager signals in main.gd, never by this script assuming success.

@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_button: Button = %SettingsButton
@onready var _status_label: Label = %StatusLabel
@onready var _version_label: Label = %VersionLabel
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _invert_check: CheckBox = %InvertCheck
@onready var _settings_close: Button = %SettingsCloseButton


func _ready() -> void:
	_name_edit.text = SettingsManager.display_name
	_name_edit.max_length = GameConfig.NAME_MAX_LENGTH
	_address_edit.text = SettingsManager.last_host_address
	_port_edit.text = str(SettingsManager.last_port)
	_version_label.text = "v%s  ·  Godot %s  ·  protocol %d" % [
		GameConfig.GAME_VERSION,
		Engine.get_version_info().get("string", "?"),
		GameConfig.PROTOCOL_VERSION]
	_status_label.text = ""

	_sensitivity_slider.value = SettingsManager.mouse_sensitivity_scale
	_volume_slider.value = SettingsManager.master_volume
	_invert_check.button_pressed = SettingsManager.invert_look
	_settings_panel.visible = false

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_button.pressed.connect(func() -> void: _settings_panel.visible = true)
	_settings_close.pressed.connect(_on_settings_closed)
	_name_edit.text_changed.connect(_on_name_changed)

	NetworkManager.host_failed.connect(_show_error)
	NetworkManager.join_failed.connect(_show_error)
	NetworkManager.join_started.connect(func() -> void: _set_busy(true, "Connecting..."))

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_name_edit.grab_focus()


func _on_name_changed(_text: String) -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.text = ""


func _collect_name() -> String:
	var raw := _name_edit.text
	var safe := NameSanitizer.sanitize(raw, 0)
	if safe.is_empty():
		return ""
	return safe


func _on_host_pressed() -> void:
	var safe := _collect_name()
	if safe.is_empty():
		_show_error("Enter a name of %d-%d characters." % [
			GameConfig.NAME_MIN_LENGTH, GameConfig.NAME_MAX_LENGTH])
		return
	var port := SettingsManager.sanitize_port(_port_edit.text.to_int())
	_persist(safe, _address_edit.text, port)
	_set_busy(true, "Starting host...")
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	var result := NetworkManager.host_game(port, safe)
	if not bool(result["ok"]):
		_show_error(String(result["error"]))


func _on_join_pressed() -> void:
	var safe := _collect_name()
	if safe.is_empty():
		_show_error("Enter a name of %d-%d characters." % [
			GameConfig.NAME_MIN_LENGTH, GameConfig.NAME_MAX_LENGTH])
		return
	var address := _address_edit.text.strip_edges()
	if NetworkManager.resolve_address(address).is_empty():
		_show_error("'%s' is not a reachable address." % address)
		return
	var port := SettingsManager.sanitize_port(_port_edit.text.to_int())
	_persist(safe, address, port)
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	var result := NetworkManager.join_game(address, port, safe)
	if not bool(result["ok"]):
		_show_error(String(result["error"]))


func _on_quit_pressed() -> void:
	AudioDirector.play(AudioDirector.Cue.UI_BACK)
	get_tree().quit()


func _on_settings_closed() -> void:
	SettingsManager.mouse_sensitivity_scale = _sensitivity_slider.value
	SettingsManager.master_volume = _volume_slider.value
	SettingsManager.invert_look = _invert_check.button_pressed
	SettingsManager.save_settings()
	_settings_panel.visible = false
	AudioDirector.play(AudioDirector.Cue.UI_BACK)


func _persist(safe_name: String, address: String, port: int) -> void:
	SettingsManager.display_name = safe_name
	SettingsManager.last_host_address = address.strip_edges()
	SettingsManager.last_port = port
	SettingsManager.save_settings()


func _set_busy(busy: bool, message: String) -> void:
	_host_button.disabled = busy
	_join_button.disabled = busy
	_status_label.remove_theme_color_override("font_color")
	_status_label.text = message


func _show_error(message: String) -> void:
	_set_busy(false, message)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	AudioDirector.play(AudioDirector.Cue.UI_ERROR)
