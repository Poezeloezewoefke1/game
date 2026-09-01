extends Interactable
class_name PowerCrystal
## A collectable Power Crystal.
##
## The node always exists in the level; whether it is COLLECTABLE is decided
## solely by the authoritative snapshot. That is what makes replay clean: a
## reset snapshot instantly restores every crystal with no respawning logic.

@export var crystal_id: String = ""

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _glow: OmniLight3D = $Glow
@onready var _collision: CollisionShape3D = $CollisionShape3D

## Where the floating spike sits when it is not bobbing. The scene puts the
## Mesh node here, and `_process` used to assign an ABSOLUTE y - which threw
## that away on the first frame and dropped the crystal to the ground, buried
## in its own bedrock. Keeping the rest height in one named place makes the
## animation obviously relative to it.
const HOVER_Y := 0.9

var _spin: float = 0.0


func _ready() -> void:
	super()
	if not GameConfig.ALL_CRYSTAL_IDS.has(crystal_id):
		Logx.error("crystal", "%s has invalid crystal_id '%s'" % [object_id, crystal_id])
	# Big enough to be the thing you walk toward from across the alcove. At the
	# first size it was a pebble you had to already know about to find.
	_mesh.mesh = MeshFactory.crystal(1.45, 0.36, 6)
	# The bedrock it grew out of, so it reads as found rather than placed.
	ModelKit.part(self, MeshFactory.rock(Vector3(1.35, 0.52, 1.35), object_id.hash()),
		Vector3(0.0, 0.16, 0.0), Color(0.30, 0.28, 0.26), 0.05, 0.95)
	# Smaller shards around the main spike. A crystal formation is a cluster;
	# one lone spike reads as a prop someone stood upright.
	var colour := crystal_colour(crystal_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = object_id.hash()
	for i in 4:
		var angle := TAU * float(i) / 4.0 + rng.randf_range(-0.4, 0.4)
		var radius := rng.randf_range(0.32, 0.46)
		var shard := ModelKit.emissive(self,
			MeshFactory.crystal(rng.randf_range(0.3, 0.55), rng.randf_range(0.09, 0.14), 5),
			Vector3(cos(angle) * radius, 0.36, sin(angle) * radius), colour, 0.7,
			Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(0.0, 360.0),
				rng.randf_range(-22.0, 22.0)))
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Emission of 1.4 clipped every channel and the crystal rendered as a white
	# blob with no colour left in it; the light below does the glowing.
	_set_emission(_mesh, colour, 0.85)
	if _glow != null:
		# The crystal lights its own alcove, in its own colour. Each dead end
		# then reads differently from a distance, and the reward at the end of a
		# corridor is not sitting in the dark. The scene's light had NO colour
		# set, so it was a white lamp washing out the crystal it belongs to.
		_glow.light_color = colour
		_glow.light_energy = 2.4
		_glow.omni_range = 16.0


func _process(delta: float) -> void:
	if not visible:
		return
	_spin += delta * 1.4
	_mesh.rotation.y = _spin
	_mesh.position.y = HOVER_Y + 0.12 * sin(_spin * 1.6)


func get_interaction_prompt(player: Node) -> String:
	if not GameManager.is_crystal_in_world(crystal_id):
		return ""
	var me := NetworkManager.local_peer_id()
	if not GameManager.carried_crystal_of(me).is_empty():
		return "Inventory Full - Place Your Current Crystal First"
	if player != null and bool(player.get("is_downed")):
		return ""
	return "Press E to Pick Up Crystal"


func can_interact(player: Node) -> bool:
	return GameManager.is_crystal_in_world(crystal_id) \
		and GameManager.carried_crystal_of(NetworkManager.local_peer_id()).is_empty() \
		and player != null and not bool(player.get("is_downed"))


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_pick_up_crystal(GameManager.snapshot, peer_id, crystal_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_crystal_pickup(peer_id, crystal_id)
	_rpc_pickup_feedback.rpc()
	return {"ok": true, "reason": ""}


@rpc("authority", "call_local", "reliable")
func _rpc_pickup_feedback() -> void:
	AudioDirector.play(AudioDirector.Cue.CRYSTAL_PICKUP)


func refresh_visual_state() -> void:
	var present := GameManager.is_crystal_in_world(crystal_id)
	visible = present
	if _collision != null:
		# Disabling the shape (deferred - we may be inside a physics callback)
		# stops the interaction ray from focusing a crystal nobody can take.
		_collision.set_deferred("disabled", not present)
	if _glow != null:
		_glow.visible = present


static func crystal_colour(id: String) -> Color:
	match id:
		GameConfig.CRYSTAL_RUINS: return Color(1.0, 0.62, 0.25)
		GameConfig.CRYSTAL_CAVE: return Color(0.35, 0.72, 1.0)
		GameConfig.CRYSTAL_GROVE: return Color(0.45, 1.0, 0.52)
		_: return Color(0.9, 0.9, 0.9)
