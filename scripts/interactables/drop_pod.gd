extends Interactable
## Extraction point. Only a LIVING Star Map carrier can trigger it, and the
## check runs on the host against the host's own snapshot.

@onready var _ring: MeshInstance3D = $Ring
@onready var _light: OmniLight3D = $PodLight


func get_interaction_prompt(player: Node) -> String:
	if GameManager.mission_state() != MissionRules.MissionState.RETURN_TO_DROP_POD:
		return ""
	if player != null and bool(player.get("is_downed")):
		return ""
	var me := NetworkManager.local_peer_id()
	if GameManager.star_map_state() == MissionRules.MAP_CARRIED \
			and GameManager.star_map_carrier() == me:
		return "Press E to Extract"
	return "Star Map Required for Extraction"


func can_interact(player: Node) -> bool:
	return GameManager.star_map_state() == MissionRules.MAP_CARRIED \
		and GameManager.star_map_carrier() == NetworkManager.local_peer_id() \
		and player != null and not bool(player.get("is_downed"))


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_extract(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_extraction(peer_id)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var armed := GameManager.mission_state() == MissionRules.MissionState.RETURN_TO_DROP_POD
	var colour := Color(0.35, 1.0, 0.55) if armed else Color(0.4, 0.5, 0.65)
	_set_emission(_ring, colour, 2.4 if armed else 0.6)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 1.8 if armed else 0.6
