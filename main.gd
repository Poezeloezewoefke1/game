extends Node
## Application shell. Owns the fixed node layout every other system depends on:
##
##   Main
##   ├── SceneRoot        <- SceneManager mounts the current scene here as "Stage"
##   └── UILayer          <- HUD / overlays (never inside the swapped scene, so a
##                           transition can never leave a duplicate HUD behind)
##
## It also owns session-level flow: where the player goes when a session starts,
## fails, ends, or is refused.

@onready var scene_root: Node = $SceneRoot
@onready var ui_layer: CanvasLayer = $UILayer
@onready var ui_root: Control = $UILayer/UIRoot


func _ready() -> void:
	SceneManager.bind_roots(scene_root, ui_layer)

	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.join_succeeded.connect(_on_join_succeeded)
	NetworkManager.session_ended.connect(_on_session_ended)

	# Deferred so every autoload has finished _ready() before the first mount.
	_boot.call_deferred()


func _boot() -> void:
	await SceneManager.local_goto(GameConfig.SCENE_MAIN_MENU)


func _on_hosting_started() -> void:
	await SceneManager.local_goto(GameConfig.SCENE_LOBBY)


func _on_join_succeeded() -> void:
	await SceneManager.local_goto(GameConfig.SCENE_LOBBY)


func _on_session_ended(reason: String) -> void:
	ui_root.close_all_overlays()
	await SceneManager.local_goto(GameConfig.SCENE_MAIN_MENU)
	if reason != NetworkManager.REASON_LOCAL_LEFT:
		ui_root.show_toast(reason)
