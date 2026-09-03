extends Interactable
## The socket beside a sealed crystal. Fitting the coupling here clears that
## crystal's lock - it is the second half of the fetch, and the only thing the
## coupling is for.

## Which crystal this socket unseals. Set in the level, and checked against the
## snapshot's lock table so a socket wired to the wrong crystal fails loudly at
## the point of use rather than silently unlocking nothing.
@export var unlocks_crystal_id: String = ""

@onready var _housing: MeshInstance3D = $Housing
@onready var _slot: MeshInstance3D = $Slot
@onready var _light: OmniLight3D = $Glow


func _ready() -> void:
	super()
	PropBuilder.build_coupling_socket(self, _housing, _slot)


func _still_locked() -> bool:
	return MissionRules.crystal_lock(GameManager.snapshot, unlocks_crystal_id) \
		== MissionRules.LOCK_COUPLING


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	if not _still_locked():
		return "Coupling fitted"
	if GameManager.carried_crystal_of(NetworkManager.local_peer_id()) != GameConfig.ITEM_COUPLING:
		return "Needs the Power Coupling"
	return "Press E to Fit Power Coupling"


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) and _still_locked() \
		and GameManager.carried_crystal_of(NetworkManager.local_peer_id()) == GameConfig.ITEM_COUPLING


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_fit_coupling(
		GameManager.snapshot, peer_id, unlocks_crystal_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_coupling_fitted(peer_id, unlocks_crystal_id)
	AudioDirector.play(AudioDirector.Cue.PEDESTAL_ACTIVATE)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var open := not _still_locked()
	var colour := Color(0.30, 0.95, 0.55) if open else Color(1.0, 0.42, 0.28)
	_set_emission(_slot, colour, 1.6 if open else 0.8)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 1.4 if open else 0.7
