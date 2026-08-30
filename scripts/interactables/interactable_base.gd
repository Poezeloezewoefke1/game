extends StaticBody3D
class_name Interactable
## Base contract every world interactable implements.
##
## THE CONTRACT
##   get_interaction_prompt(player)          -> what the local HUD shows
##   can_interact(player)                    -> local, presentation-only guess
##   request_interact(player)                -> asks the host (never decides)
##   host_validate_and_apply_interaction(..) -> the ONLY place an outcome happens
##
## can_interact() and get_interaction_prompt() run on the requesting machine and
## are therefore UNTRUSTED. They exist so the prompt reads correctly; the host
## re-derives every decision from its own snapshot. A client that patches
## can_interact() to always return true gains nothing.

## Stable, hand-authored id. Must be unique within a level - tests/unit checks
## every level scene for duplicates.
@export var object_id: String = ""

## Some interactables (a floor-level drop pod pad, a recessed pedestal) can be
## legitimately used from an angle where a strict eye-to-origin ray clips
## geometry. Those opt out of the line-of-sight requirement.
@export var needs_line_of_sight: bool = true

var _registered_id: String = ""


func _ready() -> void:
	add_to_group(GameConfig.GROUP_INTERACTABLE)
	collision_layer = GameConfig.LAYER_INTERACTABLE
	collision_mask = 0
	if object_id.is_empty():
		Logx.error("interactable", "%s has no object_id" % get_path())
	else:
		_registered_id = object_id
		SpawnManager.register_interactable(_registered_id, self)
	if GameManager.snapshot_changed.connect(_on_snapshot_changed) != OK:
		Logx.warn("interactable", "Could not connect snapshot for %s" % object_id)
	refresh_visual_state()


func _exit_tree() -> void:
	if not _registered_id.is_empty():
		SpawnManager.unregister_interactable(_registered_id, self)
	if GameManager.snapshot_changed.is_connected(_on_snapshot_changed):
		GameManager.snapshot_changed.disconnect(_on_snapshot_changed)


func _on_snapshot_changed(_snap: Dictionary) -> void:
	refresh_visual_state()


func requires_line_of_sight() -> bool:
	return needs_line_of_sight


# --- Virtuals -------------------------------------------------------------

## Text the local player sees. Empty string hides the prompt entirely.
func get_interaction_prompt(_player: Node) -> String:
	return ""


## Local, untrusted guess used only to decide whether to grey the prompt out.
func can_interact(_player: Node) -> bool:
	return true


## Convenience for callers that already hold the node.
func request_interact(_player: Node) -> void:
	GameManager.request_interact(object_id)


## HOST ONLY. Returns {"ok": bool, "reason": String}. Must not mutate anything
## when returning ok == false.
func host_validate_and_apply_interaction(_peer_id: int, _player: Node) -> Dictionary:
	return {"ok": false, "reason": "not_implemented"}


## Re-derive appearance from the authoritative snapshot. Called on every
## snapshot change, so a client that missed an event still converges.
func refresh_visual_state() -> void:
	pass


# --- Shared helpers -------------------------------------------------------

func _set_emission(mesh: MeshInstance3D, colour: Color, energy: float) -> void:
	if mesh == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = colour
	mat.emission_enabled = energy > 0.0
	mat.emission = colour
	mat.emission_energy_multiplier = energy
