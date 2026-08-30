extends Interactable
## One of the three temple pedestals. Accepts exactly one crystal id and can
## never be filled twice - both rules are enforced by MissionRules on the host.

@export var pedestal_id: String = ""
@export var accepts_crystal_id: String = ""

@onready var _socket: MeshInstance3D = $Socket
@onready var _crystal_mesh: MeshInstance3D = $PlacedCrystal
@onready var _beam: MeshInstance3D = $Beam
@onready var _light: OmniLight3D = $PedestalLight


func _ready() -> void:
	super()
	if pedestal_id.is_empty():
		Logx.error("pedestal", "%s has no pedestal_id" % object_id)
	if not GameConfig.ALL_CRYSTAL_IDS.has(accepts_crystal_id):
		Logx.error("pedestal", "%s accepts invalid crystal '%s'" % [object_id, accepts_crystal_id])


func get_interaction_prompt(player: Node) -> String:
	if is_filled():
		return ""
	if player != null and bool(player.get("is_downed")):
		return ""
	var held := GameManager.carried_crystal_of(NetworkManager.local_peer_id())
	if held.is_empty():
		return "Bring a Power Crystal"
	if held != accepts_crystal_id:
		return "This pedestal needs a different Crystal"
	return "Press E to Place Crystal"


func can_interact(player: Node) -> bool:
	return not is_filled() \
		and GameManager.carried_crystal_of(NetworkManager.local_peer_id()) == accepts_crystal_id \
		and player != null and not bool(player.get("is_downed"))


func is_filled() -> bool:
	return not GameManager.pedestal_content(pedestal_id).is_empty()


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_place_crystal(
		GameManager.snapshot, peer_id, pedestal_id, accepts_crystal_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_crystal_placement(peer_id, pedestal_id, accepts_crystal_id)
	_rpc_place_feedback.rpc()
	return {"ok": true, "reason": ""}


@rpc("authority", "call_local", "reliable")
func _rpc_place_feedback() -> void:
	AudioDirector.play(AudioDirector.Cue.PEDESTAL_ACTIVATE)


func refresh_visual_state() -> void:
	var filled := is_filled()
	var colour := PowerCrystal.crystal_colour(accepts_crystal_id)
	if _crystal_mesh != null:
		_crystal_mesh.visible = filled
		_set_emission(_crystal_mesh, colour, 3.0)
	if _beam != null:
		_beam.visible = filled
		_set_emission(_beam, colour, 2.0)
	if _light != null:
		_light.visible = filled
		_light.light_color = colour
	# The socket hints which crystal belongs here even before it is filled.
	_set_emission(_socket, colour, 1.4 if filled else 0.35)
