extends Area3D
class_name HazardField
## A volume that hurts you while the surface hazard is running.
##
## HOST-AUTHORITATIVE. The area exists on every peer so the visual haze is
## local, but only the host reads bodies out of it and applies damage - a client
## deciding it had been burned would be a client deciding its own health.
##
## It stops hurting the moment the hazard is sealed, without needing to be told:
## the tick reads `hazard_online` out of the snapshot every time rather than
## caching it, so there is no path where the field and the valve disagree.

@onready var _haze: MeshInstance3D = $Haze

var _tick: float = 0.0


## Tint of the haze. Set from the destination's hazard so a heat vent and a
## cryo vent do not look identical.
func _haze_colour() -> Color:
	match MissionCatalog.hazard(String(GameManager.snapshot.get("mission_id", ""))):
		MissionCatalog.HAZARD_COLD:
			return Color(0.62, 0.86, 1.0)
		_:
			return Color(1.0, 0.44, 0.16)


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_PLAYER
	monitoring = true
	if _haze != null:
		# Transparent and unshaded, and it must not cast a shadow: a shadow from
		# a gas cloud reads as a solid block sitting on the ground.
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tint := _haze_colour()
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.17)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.5
		_haze.material_override = mat
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if GameManager.snapshot_changed.connect(_on_snapshot) != OK:
		Logx.warn("hazard", "could not connect snapshot")
	_refresh()


func _exit_tree() -> void:
	if GameManager.snapshot_changed.is_connected(_on_snapshot):
		GameManager.snapshot_changed.disconnect(_on_snapshot)


func _on_snapshot(_snap: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	if _haze != null:
		_haze.visible = bool(GameManager.snapshot.get("hazard_online", false))


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if not bool(GameManager.snapshot.get("hazard_online", false)):
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = GameConfig.HAZARD_TICK_INTERVAL
	for body in get_overlapping_bodies():
		if not body.is_in_group(GameConfig.GROUP_PLAYER):
			continue
		if bool(body.get("is_downed")):
			continue
		if body.has_method("host_apply_damage"):
			body.host_apply_damage(GameConfig.HAZARD_DAMAGE_PER_TICK, "hazard")
