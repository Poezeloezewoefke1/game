extends Interactable
## The power coupling: a carryable that is not a crystal.
##
## It occupies the SAME single inventory slot a crystal does, which is the whole
## cost of the coupling lock - fetching it is a trip you cannot combine with
## carrying a crystal home. It sits far from the sealed crystal on purpose.

@onready var _cradle: MeshInstance3D = $Cradle
@onready var _part: MeshInstance3D = $Part
@onready var _light: OmniLight3D = $Glow


func _ready() -> void:
	super()
	PropBuilder.build_power_coupling(self, _cradle, _part)


func _taken() -> bool:
	return bool(GameManager.snapshot.get("coupling_taken", false))


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")) or _taken():
		return ""
	if not GameManager.carried_crystal_of(NetworkManager.local_peer_id()).is_empty():
		return "Hands full"
	return "Press E to Take Power Coupling"


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) and not _taken()


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_take_coupling(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_coupling_pickup(peer_id)
	AudioDirector.play(AudioDirector.Cue.CRYSTAL_PICKUP)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var gone := _taken()
	if _part != null:
		_part.visible = not gone
	if _light != null:
		_light.light_energy = 0.0 if gone else 1.6
