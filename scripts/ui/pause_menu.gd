extends Control
## Pause overlay.
##
## NOTE ON "RETURN TO LOBBY": there is no host migration, so only the host can
## move the whole party back to the lobby. A client pressing the same button
## leaves the session, which is what actually happens - the label says so rather
## than pretending otherwise.

@onready var _resume: Button = %ResumeButton
@onready var _lobby: Button = %LobbyButton
@onready var _quit: Button = %QuitButton
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	_resume.pressed.connect(_on_resume)
	_lobby.pressed.connect(_on_lobby)
	_quit.pressed.connect(_on_quit)
	var host := NetworkManager.is_local_host()
	_lobby.text = "Return to Lobby (all players)" if host else "Leave Session"
	_hint.text = "" if host else "Only the host can return the whole crew to the lobby."
	_resume.grab_focus()


## Identifies this overlay to UIRoot so Escape can toggle it.
func is_pause_menu() -> bool:
	return true


func _on_resume() -> void:
	AudioDirector.play(AudioDirector.Cue.UI_BACK)
	_close()


func _on_lobby() -> void:
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	if NetworkManager.is_local_host():
		_close()
		GameManager.host_return_to_lobby()
	else:
		NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)


func _on_quit() -> void:
	NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)
	get_tree().quit()


func _close() -> void:
	var root := get_parent()
	while root != null and not root.has_method("close_overlay"):
		root = root.get_parent()
	if root != null:
		root.close_overlay()
	else:
		queue_free()
