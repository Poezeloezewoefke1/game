extends Control
## Entry screen: name, session name, host, join by code or address, and a live
## browser of sessions on the local network.
##
## Owns no gameplay state. Every button either asks NetworkManager to do
## something or navigates locally; the resulting screen change is driven by
## NetworkManager signals in main.gd, never by this script assuming success.

@onready var _name_edit: LineEdit = %NameEdit
@onready var _session_edit: LineEdit = %SessionEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _code_hint: Label = %CodeHint
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_button: Button = %SettingsButton
@onready var _status_label: Label = %StatusLabel
@onready var _version_label: Label = %VersionLabel
@onready var _session_list: VBoxContainer = %SessionList
@onready var _browser_status: Label = %BrowserStatus
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _invert_check: CheckBox = %InvertCheck
@onready var _settings_close: Button = %SettingsCloseButton


func _ready() -> void:
	_name_edit.text = SettingsManager.display_name
	_name_edit.max_length = GameConfig.NAME_MAX_LENGTH
	_session_edit.text = SettingsManager.session_name
	_session_edit.max_length = GameConfig.SESSION_NAME_MAX_LENGTH
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
	_address_edit.text_changed.connect(_on_address_changed)

	NetworkManager.host_failed.connect(_show_error)
	NetworkManager.join_failed.connect(_show_error)
	NetworkManager.join_started.connect(func() -> void: _set_busy(true, "Connecting..."))

	LanDiscovery.sessions_changed.connect(_refresh_sessions)
	_start_browser()
	_refresh_sessions()
	_on_address_changed(_address_edit.text)

	# Mouse mode is owned by UIRoot alone - see the note on its _process().
	_name_edit.grab_focus()


func _exit_tree() -> void:
	# The browser holds a bound UDP socket. Hand it back when leaving the menu,
	# or a second copy of the game on this machine cannot open its own.
	LanDiscovery.stop_listening()
	if LanDiscovery.sessions_changed.is_connected(_refresh_sessions):
		LanDiscovery.sessions_changed.disconnect(_refresh_sessions)


# ==========================================================================
# LAN browser
# ==========================================================================

func _start_browser() -> void:
	if LanDiscovery.start_listening():
		_browser_status.text = "Looking for sessions..."
		_browser_status.remove_theme_color_override("font_color")
		return
	# Almost always a second instance on this machine. Say so plainly instead of
	# showing an empty list that looks like nobody is hosting.
	_browser_status.text = LanDiscovery.listen_error
	_browser_status.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))


func _refresh_sessions() -> void:
	for child in _session_list.get_children():
		child.queue_free()

	var found: Array = LanDiscovery.sessions()
	if not LanDiscovery.is_listening():
		return
	if found.is_empty():
		_browser_status.text = "No sessions found yet. They appear here a second after someone hosts."
		return
	_browser_status.text = "%d session%s found." % [found.size(), "" if found.size() == 1 else "s"]

	for entry in found:
		_session_list.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var title := Label.new()
	# Plain Label, never rich text: a session name arrives over an
	# unauthenticated broadcast and must not be able to carry markup.
	title.text = String(entry["name"])
	title.add_theme_font_size_override("font_size", 15)
	row.add_child(title)

	var detail := Label.new()
	detail.text = "%s  ·  %d/%d players" % [
		String(entry["host_name"]), int(entry["players"]), GameConfig.MAX_PLAYERS]
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	row.add_child(detail)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 30)
	if not bool(entry["compatible"]):
		button.text = "Different game version"
		button.disabled = true
	elif int(entry["players"]) >= GameConfig.MAX_PLAYERS:
		button.text = "Full"
		button.disabled = true
	elif not bool(entry["accepting"]):
		button.text = "Mission in progress"
		button.disabled = true
	else:
		button.text = "Join"
		button.pressed.connect(_on_session_row_pressed.bind(entry))
	row.add_child(button)

	row.add_child(HSeparator.new())
	return row


func _on_session_row_pressed(entry: Dictionary) -> void:
	# Fill the fields too, so the player can see exactly what was joined and can
	# retry by hand if it fails.
	_address_edit.text = String(entry["address"])
	_port_edit.text = str(int(entry["port"]))
	_on_address_changed(_address_edit.text)
	_attempt_join(String(entry["address"]), int(entry["port"]))


# ==========================================================================
# Input handling
# ==========================================================================

func _on_name_changed(_text: String) -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.text = ""


## Live feedback on the one field that accepts two different things.
func _on_address_changed(text: String) -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.text = ""
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_code_hint.text = ""
		return
	if not JoinCode.looks_like_code(trimmed):
		_code_hint.text = ""
		_port_edit.editable = true
		return
	var decoded := JoinCode.decode(trimmed)
	if bool(decoded["ok"]):
		_code_hint.text = "Code reads as %s:%d" % [decoded["address"], int(decoded["port"])]
		_code_hint.add_theme_color_override("font_color", Color(0.5, 0.9, 0.65))
		# The port lives inside the code, so an editable port field would be a
		# lie about which value is actually used.
		_port_edit.editable = false
	else:
		_code_hint.text = String(decoded["reason"])
		_code_hint.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
		_port_edit.editable = true


func _collect_name() -> String:
	var safe := NameSanitizer.sanitize(_name_edit.text, 0)
	return safe


func _on_host_pressed() -> void:
	var safe := _collect_name()
	if safe.is_empty():
		_show_error("Enter a name of %d-%d characters." % [
			GameConfig.NAME_MIN_LENGTH, GameConfig.NAME_MAX_LENGTH])
		return
	var port := SettingsManager.sanitize_port(_port_edit.text.to_int())
	var session := LanDiscovery.sanitize_session_name(
		_session_edit.text if not _session_edit.text.strip_edges().is_empty() else safe + "'s crew")
	_persist(safe, _address_edit.text, port, session)
	_set_busy(true, "Starting host...")
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	# Free the browser socket first: on this machine the host does not need it,
	# and holding it would stop another local instance from browsing.
	LanDiscovery.stop_listening()
	var result := NetworkManager.host_game(port, safe, session)
	if not bool(result["ok"]):
		_start_browser()
		_show_error(String(result["error"]))


func _on_join_pressed() -> void:
	var raw := _address_edit.text.strip_edges()
	if raw.is_empty():
		_show_error("Enter a join code or the host's address.")
		return

	var address := raw
	var port := SettingsManager.sanitize_port(_port_edit.text.to_int())

	if JoinCode.looks_like_code(raw):
		var decoded := JoinCode.decode(raw)
		if not bool(decoded["ok"]):
			_show_error(String(decoded["reason"]))
			return
		address = String(decoded["address"])
		port = int(decoded["port"])

	_attempt_join(address, port)


func _attempt_join(address: String, port: int) -> void:
	var safe := _collect_name()
	if safe.is_empty():
		_show_error("Enter a name of %d-%d characters." % [
			GameConfig.NAME_MIN_LENGTH, GameConfig.NAME_MAX_LENGTH])
		return
	if NetworkManager.resolve_address(address).is_empty():
		_show_error("'%s' is not a reachable address." % address)
		return
	_persist(safe, _address_edit.text.strip_edges(), port, _session_edit.text)
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	LanDiscovery.stop_listening()
	var result := NetworkManager.join_game(address, port, safe)
	if not bool(result["ok"]):
		_start_browser()
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


func _persist(safe_name: String, address: String, port: int, session: String) -> void:
	SettingsManager.display_name = safe_name
	SettingsManager.last_host_address = address
	SettingsManager.last_port = port
	SettingsManager.session_name = session.strip_edges()
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
