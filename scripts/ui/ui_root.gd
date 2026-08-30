extends Control
## Mounts the HUD and the modal overlays (pause / victory / failure) outside the
## swapped scene tree.
##
## WHY OUTSIDE: if the HUD lived inside a level scene it would be destroyed and
## rebuilt on every transition, and a failed transition could leave two HUDs
## alive at once. Mounting here means there is exactly one HUD instance, ever,
## and its lifetime is controlled by one place.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause_menu.tscn"
const VICTORY_SCENE := "res://scenes/ui/victory_screen.tscn"
const FAILURE_SCENE := "res://scenes/ui/failure_screen.tscn"

@onready var _hud_slot: Control = $HudSlot
@onready var _overlay_slot: Control = $OverlaySlot
@onready var _toast_label: Label = $ToastSlot/ToastLabel
@onready var _toast_timer: Timer = $ToastSlot/ToastTimer

var _hud: Control = null
var _overlay: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.text = ""
	_toast_label.visible = false
	_toast_timer.timeout.connect(_hide_toast)

	SceneManager.scene_changed.connect(_on_scene_changed)
	GameManager.mission_ended.connect(_on_mission_ended)
	GameManager.notice.connect(show_toast)
	GameManager.mission_state_changed.connect(_on_mission_state_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if not SceneManager.is_in_gameplay_scene():
		return
	# Never let the pause menu cover an end-of-mission screen.
	if _overlay != null and not _overlay.has_method("is_pause_menu"):
		return
	get_viewport().set_input_as_handled()
	if _overlay != null:
		close_overlay()
	else:
		open_overlay(PAUSE_SCENE)


# ==========================================================================
# HUD
# ==========================================================================

func _on_scene_changed(scene_key: String) -> void:
	var wants_hud := GameConfig.GAMEPLAY_SCENES.has(scene_key)
	if wants_hud and _hud == null:
		var packed: PackedScene = load(HUD_SCENE) as PackedScene
		if packed != null:
			_hud = packed.instantiate()
			_hud_slot.add_child(_hud)
	elif not wants_hud and _hud != null:
		_hud.queue_free()
		_hud = null
	if not wants_hud:
		close_all_overlays()


func hud() -> Control:
	return _hud


# ==========================================================================
# Overlays
# ==========================================================================

func open_overlay(scene_path: String) -> Control:
	close_overlay()
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		Logx.error("ui", "Missing overlay %s" % scene_path)
		return null
	_overlay = packed.instantiate()
	_overlay_slot.add_child(_overlay)
	_apply_mouse_mode()
	return _overlay


func close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_apply_mouse_mode()


func close_all_overlays() -> void:
	close_overlay()


func has_overlay() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


func _on_mission_ended(victory: bool) -> void:
	open_overlay(VICTORY_SCENE if victory else FAILURE_SCENE)


func _on_mission_state_changed(state: int) -> void:
	# A retry or a return-to-lobby must clear the end screen for everyone,
	# including clients that never pressed a button.
	if state == MissionRules.MissionState.TRANSITIONING_TO_NERAVA \
			or state == MissionRules.MissionState.RETURNING_TO_LOBBY:
		close_all_overlays()


## Captured while playing, visible while an overlay or a menu is up.
func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want_capture := SceneManager.is_in_gameplay_scene() and not has_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE


func refresh_mouse_mode() -> void:
	_apply_mouse_mode()


# ==========================================================================
# Toast
# ==========================================================================

func show_toast(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	_toast_label.text = message
	_toast_label.visible = true
	_toast_timer.start(3.0)


func _hide_toast() -> void:
	_toast_label.visible = false
	_toast_label.text = ""
