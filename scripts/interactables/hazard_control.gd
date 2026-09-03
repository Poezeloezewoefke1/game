extends Interactable
## The valve that shuts the surface hazard down.
##
## While the hazard is live it damages anyone standing in a hazard field, and
## one of the three crystals sits inside one. Shutting it off is a errand into
## the worst part of the map, which is the point.

@onready var _housing: MeshInstance3D = $Housing
@onready var _wheel: MeshInstance3D = $Wheel
@onready var _light: OmniLight3D = $Glow


func _ready() -> void:
	super()
	PropBuilder.build_hazard_control(self, _housing, _wheel)


func _online() -> bool:
	return bool(GameManager.snapshot.get("hazard_online", false))


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	if not _online():
		return "Vent sealed"
	return "Press E to Seal the Vent"


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) and _online()


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_shut_down_hazard(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_hazard_shutdown(peer_id)
	AudioDirector.play(AudioDirector.Cue.PEDESTAL_ACTIVATE)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var live := _online()
	var colour := Color(1.0, 0.36, 0.20) if live else Color(0.35, 0.85, 1.0)
	_set_emission(_wheel, colour, 1.5 if live else 0.6)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 1.6 if live else 0.4
