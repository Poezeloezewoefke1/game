extends Area3D
## Fires once, on the host, the first time any living player is actually inside
## the temple clearing. Advances FIND_TEMPLE -> FIND_CRYSTALS.
##
## Not an Interactable: there is nothing to press, and it must not appear in the
## interaction registry or the HUD prompt.
##
## WHY THIS POLLS INSTEAD OF USING body_entered
##
## `body_entered` fired for a player who was demonstrably 20 m outside the
## volume. Measured on Cinder: "reached the temple clearing at (-3.0, 0.3, 50.0)"
## against a box that ends at z = 30, logged between the level mounting and the
## spawner placing the player. The physics server evaluates overlaps against the
## transform a body had when it was registered, so a freshly spawned player is
## matched at the origin - and Cinder's and Hallow's volumes are 30x6x30 boxes
## that reach back to it, where Nerava's is a narrow band across the approach.
## The result: the beat that opens the descent was skipped on two of the three
## planets, by nothing the player did.
##
## Filtering the bad signal does not work either, and that is the interesting
## part: reject it and the REAL entry never arrives, because as far as the
## server is concerned the body never left, so there is no second crossing to
## report. Asking the geometry ourselves, every physics frame, is immune to both
## halves of that and costs one box test per living player on the host until it
## fires exactly once.

var _fired: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_PLAYER
	monitoring = false


func _physics_process(_delta: float) -> void:
	if _fired:
		return
	# Only the host may change the mission.
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	for body in get_tree().get_nodes_in_group(GameConfig.GROUP_PLAYER):
		var player := body as Node3D
		if player == null or not is_instance_valid(player):
			continue
		if bool(player.get("is_downed")):
			continue
		if not _contains(player.global_position):
			continue
		_fired = true
		set_physics_process(false)
		Logx.info("mission", "%s reached the temple clearing at %s"
			% [player.name, str(player.global_position.snapped(Vector3.ONE * 0.1))])
		GameManager.host_report_temple_discovered()
		return


## Is this point inside one of our box shapes, by transform rather than by the
## physics server's opinion of where things are?
##
## The vertical test is generous by a metre: a player's origin is at their feet
## and these volumes are authored to sit on the ground, so a strict test would
## miss someone standing squarely in one.
func _contains(point: Vector3) -> bool:
	for child in find_children("*", "CollisionShape3D", true, false):
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var local: Vector3 = cs.global_transform.affine_inverse() * point
		var half: Vector3 = box.size * 0.5
		if absf(local.x) <= half.x and absf(local.z) <= half.z \
				and local.y >= -half.y - 1.0 and local.y <= half.y + 1.0:
			return true
	return false
