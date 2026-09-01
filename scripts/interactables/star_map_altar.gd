extends Interactable
## The altar at the centre of the temple. Holds the Star Map behind a shield
## until all three pedestals are powered.
##
## The Star Map is NOT a separate spawned entity while it sits on the altar -
## it is part of this authored node, driven by the snapshot. Only a DROPPED Star
## Map is a spawned entity, because only then does it need a position the level
## author did not choose.

@onready var _base: MeshInstance3D = $Base
@onready var _shield: MeshInstance3D = $Shield
@onready var _map_mesh: MeshInstance3D = $StarMap
@onready var _altar_light: OmniLight3D = $AltarLight
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _spin: float = 0.0


func _ready() -> void:
	super()
	PropBuilder.build_altar(self, _base)
	PropBuilder.build_star_map(_map_mesh, Color(1.0, 0.87, 0.42))
	_map_mesh.position = Vector3(0.0, 2.05, 0.0)


func _process(delta: float) -> void:
	_spin += delta
	if _map_mesh != null and _map_mesh.visible:
		_map_mesh.rotation.y = _spin * 0.9
	if _shield != null and _shield.visible:
		var pulse := 0.55 + 0.2 * sin(_spin * 2.2)
		var mat := _shield.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = pulse


func get_interaction_prompt(player: Node) -> String:
	var state := GameManager.star_map_state()
	if state == MissionRules.MAP_EXTRACTED:
		return ""
	if state == MissionRules.MAP_CARRIED or state == MissionRules.MAP_DROPPED:
		return ""
	if player != null and bool(player.get("is_downed")):
		return ""
	if not GameManager.is_altar_active():
		return "Star Map Shield Active"
	return "Press E to Retrieve Star Map"


func can_interact(player: Node) -> bool:
	return GameManager.is_altar_active() \
		and GameManager.star_map_state() == MissionRules.MAP_AVAILABLE \
		and player != null and not bool(player.get("is_downed"))


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_take_star_map(GameManager.snapshot, peer_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_star_map_pickup(peer_id)
	_rpc_take_feedback.rpc()
	return {"ok": true, "reason": ""}


@rpc("authority", "call_local", "reliable")
func _rpc_take_feedback() -> void:
	AudioDirector.play(AudioDirector.Cue.STAR_MAP_PICKUP)
	AudioDirector.play(AudioDirector.Cue.SENTINEL_SPAWN)


func refresh_visual_state() -> void:
	var altar_open := GameManager.is_altar_active()
	var map_state := GameManager.star_map_state()
	if _shield != null:
		_shield.visible = not altar_open
	if _map_mesh != null:
		_map_mesh.visible = map_state == MissionRules.MAP_LOCKED or map_state == MissionRules.MAP_AVAILABLE
		_set_emission(_map_mesh, Color(1.0, 0.87, 0.42), 1.6 if altar_open else 0.7)
	if _altar_light != null:
		_altar_light.light_color = Color(1.0, 0.85, 0.45) if altar_open else Color(0.3, 0.6, 1.0)
		_altar_light.light_energy = 2.4 if altar_open else 1.0
	if _collision != null:
		# Stays interactable while locked so the player gets the "shield active"
		# prompt rather than silence.
		var usable := map_state == MissionRules.MAP_LOCKED or map_state == MissionRules.MAP_AVAILABLE
		_collision.set_deferred("disabled", not usable)
