extends Interactable
## A Star Map lying on the ground after its carrier went down or disconnected.
##
## Spawned by the HOST through the level's MultiplayerSpawner. It is in the
## SessionBound group, so every reset path (retry, victory, return-to-lobby,
## transition) removes it without any special-case code.

var spawn_position: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Glow

var _spin: float = 0.0


func _ready() -> void:
	super()
	add_to_group(GameConfig.GROUP_SESSION_BOUND)
	global_position = spawn_position
	_set_emission(_mesh, Color(1.0, 0.87, 0.42), 1.5)


func _process(delta: float) -> void:
	_spin += delta * 1.2
	_mesh.rotation.y = _spin
	_mesh.position.y = 0.6 + 0.12 * sin(_spin * 1.7)


## Marker used by SpawnManager.host_clear_dropped_star_maps().
func is_dropped_star_map() -> bool:
	return true


func get_interaction_prompt(player: Node) -> String:
	if GameManager.star_map_state() != MissionRules.MAP_DROPPED:
		return ""
	if player != null and bool(player.get("is_downed")):
		return ""
	return "Press E to Retrieve Star Map"


func can_interact(player: Node) -> bool:
	return GameManager.star_map_state() == MissionRules.MAP_DROPPED \
		and player != null and not bool(player.get("is_downed"))


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_take_star_map(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	# host_apply_star_map_pickup() clears dropped maps, which frees this node.
	GameManager.host_apply_star_map_pickup(peer_id)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var present := GameManager.star_map_state() == MissionRules.MAP_DROPPED
	visible = present
	if _light != null:
		_light.visible = present
