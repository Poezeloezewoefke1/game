extends Interactable
## The lever that commits the crew to a flight.
##
## Host-only, for the same reason the mission terminal always was: there is no
## host migration, so letting any peer start a scripted sequence would let one
## player drag everyone into a level the host is not ready to run.
##
## It refuses far more often than it accepts, and the prompt says exactly which
## gate is closed - "Launch" on a lever that silently does nothing is the worst
## possible feedback for a four-player checklist.

@onready var _housing: MeshInstance3D = $Housing
@onready var _handle: MeshInstance3D = $Handle
@onready var _lamp: OmniLight3D = $Lamp


func _ready() -> void:
	super()
	PropBuilder.build_launch_lever(self, _housing, _handle)


func _blocker() -> String:
	var snap := GameManager.snapshot
	var remaining: Array = MissionRules.ship_tasks_remaining(snap)
	if not remaining.is_empty():
		if remaining.size() == 1:
			return MissionRules.ship_task_hint(String(remaining[0]))
		return "%d stations still red" % remaining.size()
	var waiting: Array = []
	for peer_id in LobbyManager.sorted_peer_ids():
		var node: Node = SpawnManager.player_node(int(peer_id))
		if node == null or bool(node.get("is_downed")):
			continue
		if MissionRules.seat_of(snap, int(peer_id)) == "":
			waiting.append(LobbyManager.display_name_of(int(peer_id)))
	if not waiting.is_empty():
		if waiting.size() == 1:
			return "%s is not seated" % waiting[0]
		return "%d crew not seated" % waiting.size()
	return ""


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	if not MissionRules.is_ship_state(GameManager.mission_state()):
		return ""
	var blocker := _blocker()
	if blocker != "":
		return "Cannot launch: %s" % blocker
	if NetworkManager.local_peer_id() != GameConfig.HOST_PEER_ID:
		return "Ready to launch - the host pulls the lever"
	return "Press E to Launch for %s" % MissionCatalog.display_name(
		String(GameManager.snapshot.get("mission_id", "")))


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) \
		and NetworkManager.local_peer_id() == GameConfig.HOST_PEER_ID \
		and MissionRules.is_ship_state(GameManager.mission_state()) \
		and _blocker() == ""


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var crew: Dictionary = {}
	for other in LobbyManager.sorted_peer_ids():
		var node: Node = SpawnManager.player_node(int(other))
		if node == null:
			continue
		crew[int(other)] = {
			"alive": bool(node.get("is_alive")),
			"downed": bool(node.get("is_downed")),
		}
	var verdict := MissionRules.can_launch(GameManager.snapshot, peer_id, crew, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_begin_launch()
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var armed := MissionRules.is_ship_state(GameManager.mission_state()) and _blocker() == ""
	var colour := Color(0.35, 1.0, 0.55) if armed else Color(1.0, 0.35, 0.28)
	_set_emission(_handle, colour, 1.6 if armed else 0.7)
	if _lamp != null:
		_lamp.light_color = colour
		_lamp.light_energy = 1.5 if armed else 0.6
