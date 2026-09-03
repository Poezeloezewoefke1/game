extends Node

## Can a seated pilot actually reach the launch lever?
##
## The playtest could not answer this, because it launches by calling
## GameManager.host_begin_launch() directly - and a harness that bypasses the
## control it is meant to test proves nothing about the control.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var level: Node3D = (load("res://scenes/levels/starfarer_deck.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var lever: Node3D = level.get_node_or_null("Interactables/LaunchLever")
	print("lever at %s" % str(lever.global_position))
	print("interact ray length 3.2 m; seated yaw limit +/- 105 deg")
	for i in range(1, 5):
		var seat: Node3D = level.get_node_or_null("Interactables/CrewSeat%d" % i)
		if seat == null:
			continue
		var sit: Vector3 = seat.call("sit_position") if seat.has_method("sit_position") \
			else seat.global_position
		# The camera pivot rides at the player's eye height above the body.
		var eye: Vector3 = sit + Vector3(0.0, 0.6, 0.0)
		var to_lever: Vector3 = lever.global_position + Vector3(0, 0.9, 0) - eye
		var flat := Vector3(to_lever.x, 0.0, to_lever.z)
		var seat_yaw: float = seat.call("sit_yaw") if seat.has_method("sit_yaw") \
			else seat.global_rotation.y
		var bearing: float = atan2(-flat.x, -flat.z)
		var swivel: float = rad_to_deg(absf(wrapf(bearing - seat_yaw, -PI, PI)))
		print("  CrewSeat%d sit=%s  range=%.2f m  swivel needed=%.0f deg  -> %s"
			% [i, str(sit.snapped(Vector3.ONE * 0.01)), to_lever.length(), swivel,
				"REACHABLE" if to_lever.length() <= 3.2 and swivel <= 105.0 else "OUT OF REACH"])

	print("=== floor ahead of the bridge seats (x = -5.6) ===")
	var space := level.get_world_3d().direct_space_state
	var z := -16.0
	while z >= -28.0:
		var from := Vector3(-5.6, 3.0, z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0)
		q.collision_mask = 0xFFFFFFFF
		var h := space.intersect_ray(q)
		print("  z=%.1f  %s" % [z, "NO FLOOR" if h.is_empty()
			else "y=%.2f %s" % [(h["position"] as Vector3).y, String((h["collider"] as Node).name)]])
		z -= 1.0
	get_tree().quit()
