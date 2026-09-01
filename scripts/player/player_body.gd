extends Node3D
## Builds the visible explorer from MeshFactory parts.
##
## Replaces the single capsule that other players used to appear as. It is
## assembled in code rather than authored in the scene so the whole thing can be
## recoloured per player from one place, and so proportions live next to the
## comments explaining them.
##
## HIDDEN FOR THE LOCAL PLAYER: in first person you are inside this, so the
## owning player's copy is switched off entirely. Remote players see it.

const HELMET_COLOUR := Color(0.86, 0.88, 0.92)
const SUIT_DARK := Color(0.16, 0.18, 0.23)
const VISOR_COLOUR := Color(0.16, 0.85, 1.0)

var _team_colour: Color = Color(0.29, 0.71, 0.94)
var _visor: MeshInstance3D = null
var _accent_parts: Array[MeshInstance3D] = []


func build(team_colour: Color) -> void:
	_team_colour = team_colour
	ModelKit.clear(self)
	_accent_parts.clear()

	# Legs -------------------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.17, 0.72, 0.19), 0.03),
		Vector3(-0.12, 0.36, 0.0), SUIT_DARK)
	_part(MeshFactory.beveled_box(Vector3(0.17, 0.72, 0.19), 0.03),
		Vector3(0.12, 0.36, 0.0), SUIT_DARK)
	# Boots
	_part(MeshFactory.beveled_box(Vector3(0.2, 0.14, 0.28), 0.03),
		Vector3(-0.12, 0.07, 0.03), SUIT_DARK)
	_part(MeshFactory.beveled_box(Vector3(0.2, 0.14, 0.28), 0.03),
		Vector3(0.12, 0.07, 0.03), SUIT_DARK)

	# Torso ------------------------------------------------------------------
	_accent(MeshFactory.beveled_box(Vector3(0.52, 0.58, 0.32), 0.05),
		Vector3(0.0, 1.02, 0.0))
	# Chest panel, so the front and back read differently at a glance
	_part(MeshFactory.beveled_box(Vector3(0.26, 0.2, 0.06), 0.02),
		Vector3(0.0, 1.12, -0.17), SUIT_DARK)

	# Backpack ---------------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.4, 0.44, 0.2), 0.04),
		Vector3(0.0, 1.05, 0.24), SUIT_DARK)
	# Tanks - the silhouette cue that says "spacesuit" from behind
	_part(MeshFactory.tapered_column(0.44, 0.07, 0.07, 8),
		Vector3(-0.12, 1.05, 0.34), HELMET_COLOUR)
	_part(MeshFactory.tapered_column(0.44, 0.07, 0.07, 8),
		Vector3(0.12, 1.05, 0.34), HELMET_COLOUR)

	# Shoulders and arms -----------------------------------------------------
	_accent(MeshFactory.beveled_box(Vector3(0.18, 0.18, 0.24), 0.04),
		Vector3(-0.34, 1.2, 0.0))
	_accent(MeshFactory.beveled_box(Vector3(0.18, 0.18, 0.24), 0.04),
		Vector3(0.34, 1.2, 0.0))
	_part(MeshFactory.beveled_box(Vector3(0.14, 0.5, 0.16), 0.03),
		Vector3(-0.34, 0.9, 0.0), SUIT_DARK)
	_part(MeshFactory.beveled_box(Vector3(0.14, 0.5, 0.16), 0.03),
		Vector3(0.34, 0.9, 0.0), SUIT_DARK)

	# Helmet -----------------------------------------------------------------
	_part(MeshFactory.beveled_box(Vector3(0.36, 0.34, 0.36), 0.09),
		Vector3(0.0, 1.52, 0.0), HELMET_COLOUR)
	_visor = _emissive(MeshFactory.beveled_box(Vector3(0.28, 0.15, 0.06), 0.02),
		Vector3(0.0, 1.52, -0.18), VISOR_COLOUR, 1.6)
	# Helmet lamp
	_emissive(MeshFactory.beveled_box(Vector3(0.08, 0.05, 0.05), 0.015),
		Vector3(0.0, 1.66, -0.16), Color(1.0, 0.95, 0.8), 2.0)


func _part(mesh: Mesh, position: Vector3, colour: Color) -> MeshInstance3D:
	return ModelKit.part(self, mesh, position, colour)


## A part that carries the player's team colour, so a glance tells you who is
## who without reading a nameplate.
func _accent(mesh: Mesh, position: Vector3) -> MeshInstance3D:
	var instance := _part(mesh, position, _team_colour)
	_accent_parts.append(instance)
	return instance


func _emissive(mesh: Mesh, position: Vector3, colour: Color, energy: float) -> MeshInstance3D:
	return ModelKit.emissive(self, mesh, position, colour, energy)


## Downed players wash out to a warning colour, which has to be readable across
## a dark jungle clearing.
func set_downed(downed: bool) -> void:
	for instance in _accent_parts:
		ModelKit.set_albedo(instance, Color(0.62, 0.16, 0.18) if downed else _team_colour)
	ModelKit.set_emission(_visor, Color(1.0, 0.3, 0.25) if downed else VISOR_COLOUR, 1.6)
