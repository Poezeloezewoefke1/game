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


## The point on this object that the player's interact ray actually hits: the
## centre of its collision shape.
##
## The host validates line of sight to an interactable before allowing a press,
## and it used to aim at `global_position + 0.6 m` - the object's ORIGIN, which
## for anything standing on the ground is its feet, the most obstructed point on
## it and the one least like where the player is looking. The client's ray hits
## the collision SHAPE. So the two could disagree, and when they did the player
## was shown "Press E to Fit Power Coupling" for something the host would refuse
## every single time - measured on Cinder, where a piece of set dressing 0.2 m
## in front of the coupling socket sealed the cave crystal permanently and made
## the mission unfinishable.
##
## Aiming at the same thing the client's ray hits makes them agree by
## construction, on every level and every prop, rather than one escape hatch at
## a time.
func interaction_point() -> Vector3:
	for child in find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape != null and shape.shape != null:
			return shape.global_position
	return global_position + Vector3.UP * 0.6


## Is this node part of a mounted level, as opposed to a prefab someone loaded
## on its own to look at? SceneManager owns the level root; anything under it is
## in the game, anything else is being inspected.
func _is_in_a_level() -> bool:
	var root: Node = SceneManager.scene_root if SceneManager != null else null
	if root == null or not is_instance_valid(root):
		return false
	return root.is_ancestor_of(self)


func _ready() -> void:
	add_to_group(GameConfig.GROUP_INTERACTABLE)
	collision_layer = GameConfig.LAYER_INTERACTABLE
	collision_mask = 0
	if object_id.is_empty():
		# An interactable PREFAB has no id until a level places it and sets one;
		# instantiating the .tscn on its own is exactly what the scene-integrity
		# check does, and it did it twice on every validation run. An error that
		# always fires is an error people learn to scroll past, which is worse
		# than no error at all - so this only complains when the node is inside
		# a mounted level, where a missing id really is a broken interactable.
		if _is_in_a_level():
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
	# A mesh already carrying one of the effect shaders keeps it: those shaders
	# take the same two values through named parameters, and quietly replacing
	# them with a StandardMaterial3D here would silently undo every crystal and
	# hologram in the level the first time its state refreshed.
	var shaded := mesh.material_override as ShaderMaterial
	if shaded != null:
		_set_shader_glow(shaded, colour, energy)
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = colour
	mat.emission_enabled = energy > 0.0
	mat.emission = colour
	mat.emission_energy_multiplier = energy


## Applies a colour and an energy to whichever effect shader a mesh is using.
## Each of them names its own parameters, so the mapping lives here rather than
## being repeated at every call site.
func _set_shader_glow(material: ShaderMaterial, colour: Color, energy: float) -> void:
	var shader_path: String = material.shader.resource_path if material.shader != null else ""
	if shader_path.ends_with("crystal.gdshader"):
		material.set_shader_parameter("core_colour", colour)
		material.set_shader_parameter("edge_colour", colour.lightened(0.55))
		material.set_shader_parameter("emission_energy", energy)
	elif shader_path.ends_with("hologram.gdshader") \
			or shader_path.ends_with("energy_field.gdshader"):
		material.set_shader_parameter("colour", colour)
		material.set_shader_parameter("energy", energy)


## Gives a mesh one of the effect shaders. Returns the material so the caller
## can set anything else it needs.
func _apply_effect_shader(mesh: MeshInstance3D, shader_path: String,
		colour: Color, energy: float) -> ShaderMaterial:
	if mesh == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = load(shader_path)
	mesh.material_override = material
	_set_shader_glow(material, colour, energy)
	return material
