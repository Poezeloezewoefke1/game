extends Control
## Networked lobby. Shows the authoritative roster and lets the host start.
##
## The list is rebuilt from LobbyManager.players on every roster_changed, so a
## client can never show a player the host does not have.

@onready var _list: VBoxContainer = %PlayerList
@onready var _start_button: Button = %StartButton
@onready var _ready_button: Button = %ReadyButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel
@onready var _capacity_label: Label = %CapacityLabel
@onready var _address_hint: Label = %AddressHint


func _ready() -> void:
	LobbyManager.roster_changed.connect(_refresh)
	SceneManager.barrier_progress.connect(_on_barrier_progress)
	_start_button.pressed.connect(_on_start_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = ""
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var me := NetworkManager.local_peer_id()
	for peer_id in LobbyManager.sorted_peer_ids():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_label := Label.new()
		# Plain Label, not RichTextLabel: a display name must never be able to
		# carry markup into the UI.
		name_label.text = LobbyManager.display_name_of(int(peer_id))
		name_label.custom_minimum_size = Vector2(220, 0)
		if int(peer_id) == me:
			name_label.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
		row.add_child(name_label)

		var role := Label.new()
		role.text = "HOST" if LobbyManager.is_host_peer(int(peer_id)) else "CREW"
		role.custom_minimum_size = Vector2(70, 0)
		row.add_child(role)

		var state := Label.new()
		if LobbyManager.is_host_peer(int(peer_id)):
			state.text = "Ready to launch"
		else:
			state.text = "Ready" if LobbyManager.is_ready(int(peer_id)) else "Standing by"
		state.add_theme_color_override("font_color",
			Color(0.5, 0.95, 0.6) if LobbyManager.is_ready(int(peer_id)) or LobbyManager.is_host_peer(int(peer_id))
			else Color(0.75, 0.75, 0.8))
		row.add_child(state)

		_list.add_child(row)

	_capacity_label.text = "%d / %d explorers" % [LobbyManager.player_count(), GameConfig.MAX_PLAYERS]

	var host := NetworkManager.is_local_host()
	_start_button.visible = host
	_start_button.disabled = not host
	_ready_button.visible = not host
	_ready_button.text = "Stand By" if LobbyManager.is_ready(me) else "Mark Ready"
	_back_button.text = "Close Session" if host else "Leave Session"
	_address_hint.text = "Others join with your LAN IP on UDP port %d." % SettingsManager.last_port if host else ""


func _on_barrier_progress(ready_count: int, expected: int) -> void:
	_status_label.text = "Loading level: %d/%d ready" % [ready_count, expected]


func _on_start_pressed() -> void:
	if not NetworkManager.is_local_host():
		return
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	_start_button.disabled = true
	_status_label.text = "Boarding the Wayfinder Station..."
	var ok: bool = await GameManager.host_start_session()
	if not ok:
		_start_button.disabled = false
		_status_label.text = "Could not start the session."


func _on_ready_pressed() -> void:
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	LobbyManager.request_toggle_ready()
	_refresh()


func _on_back_pressed() -> void:
	AudioDirector.play(AudioDirector.Cue.UI_BACK)
	NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)
