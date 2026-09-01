extends Interactable
## Hub terminal that begins the descent to Nerava. Host-only by design: there is
## no host migration, so allowing a client to start the mission would let any
## peer drag the session into a level the host may not be ready for.

@onready var _case: MeshInstance3D = $Case
@onready var _screen: MeshInstance3D = $Screen
@onready var _light: OmniLight3D = $ScreenLight


func _ready() -> void:
	super()
	PropBuilder.build_terminal(self, _case, _screen)
	if _light != null:
		_light.position = Vector3(0.0, 1.45, -0.6)


func get_interaction_prompt(player: Node) -> String:
	if GameManager.mission_state() != MissionRules.MissionState.HUB_IDLE:
		return ""
	if NetworkManager.local_peer_id() != GameConfig.HOST_PEER_ID:
		return "Only the host can begin the expedition"
	if player != null and not bool(player.get("is_downed")):
		return "Press E to Start Mission"
	return ""


func can_interact(player: Node) -> bool:
	return NetworkManager.local_peer_id() == GameConfig.HOST_PEER_ID \
		and GameManager.mission_state() == MissionRules.MissionState.HUB_IDLE \
		and player != null and not bool(player.get("is_downed"))


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_start_expedition(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	GameManager.host_start_expedition()
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var ready_to_use := GameManager.mission_state() == MissionRules.MissionState.HUB_IDLE
	var colour := Color(0.25, 0.95, 0.75) if ready_to_use else Color(0.35, 0.4, 0.5)
	_set_emission(_screen, colour, 1.1 if ready_to_use else 0.3)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 1.4 if ready_to_use else 0.4
