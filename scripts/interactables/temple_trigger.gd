extends Area3D
## Fires once, on the host, the first time any living player reaches the temple
## clearing. Advances FIND_TEMPLE -> FIND_CRYSTALS.
##
## Not an Interactable: there is nothing to press, and it must not appear in the
## interaction registry or the HUD prompt.


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_PLAYER
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Every peer runs this, but only the host is allowed to change the mission.
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	if not body.is_in_group(GameConfig.GROUP_PLAYER):
		return
	if bool(body.get("is_downed")):
		return
	GameManager.host_report_temple_discovered()
