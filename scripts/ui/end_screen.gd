extends Control
class_name EndScreen
## Shared behaviour for the victory and failure screens.
##
## Both are host-driven: only the host can retry or return the crew to the
## lobby. Clients see the same buttons disabled with an explanation, rather than
## buttons that silently do nothing.

@export var is_victory: bool = false

@onready var _title: Label = %TitleLabel
@onready var _subtitle: Label = %SubtitleLabel
@onready var _retry: Button = %RetryButton
@onready var _lobby: Button = %LobbyButton
@onready var _quit: Button = %QuitButton
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	var host := NetworkManager.is_local_host()

	_title.text = "MISSION ACCOMPLISHED" if is_victory else "MISSION FAILED"
	_title.add_theme_color_override("font_color",
		Color(0.45, 1.0, 0.6) if is_victory else Color(1.0, 0.42, 0.36))
	_subtitle.text = "Star Map recovered from Nerava." if is_victory \
		else "The crew went down on Nerava."

	_retry.visible = not is_victory
	_retry.disabled = not host
	_lobby.disabled = not host
	_lobby.text = "Return to Lobby"
	_hint.text = "" if host else "Waiting for the host to choose. You can leave with Quit."

	_retry.pressed.connect(_on_retry)
	_lobby.pressed.connect(_on_lobby)
	_quit.pressed.connect(_on_quit)

	AudioDirector.play(AudioDirector.Cue.VICTORY if is_victory else AudioDirector.Cue.FAILURE)
	# Mouse mode is owned by UIRoot alone - see the note on its _process().
	if host:
		(_lobby if is_victory else _retry).grab_focus()
	else:
		_quit.grab_focus()


func _on_retry() -> void:
	if not NetworkManager.is_local_host():
		return
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	_set_busy()
	GameManager.host_retry_mission()


func _on_lobby() -> void:
	if not NetworkManager.is_local_host():
		return
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	_set_busy()
	GameManager.host_return_to_lobby()


func _on_quit() -> void:
	NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)


func _set_busy() -> void:
	_retry.disabled = true
	_lobby.disabled = true
	_hint.text = "Working..."
