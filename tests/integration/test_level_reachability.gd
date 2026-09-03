extends TestCase
## Proves the mission is actually completable in the authored geometry.
##
## WHY THIS EXISTS: the first version of Nerava had a solid temple back wall
## spanning the whole grove corridor. Every structural check passed - the
## crystal existed, the pedestal accepted it, the ids were unique - and the
## mission was still unwinnable, because no player could physically reach the
## Grove Crystal. Node-presence tests cannot see that; a path query can.
##
## The navigation mesh is the same one the Sentinel navigates on, so this also
## covers "the guardian can actually chase a player into every branch".

const REACH_TOLERANCE := 6.0

## Every place a player must be able to get to, and get back from.
const KEY_POINTS := {
	"drop pod": Vector3(0, 0, 43),
	"temple clearing": Vector3(0, 0, 6),
	"altar": Vector3(0, 0, 1),
	"pedestal A": Vector3(-3, 0, 3),
	"pedestal B": Vector3(3, 0, 3),
	"pedestal C": Vector3(0, 0, -6),
	"ruins crystal": Vector3(-42, 0, 0),
	"cave crystal": Vector3(42, 0, 0),
	"grove crystal": Vector3(0, 0, -42),
	"guardian anchor": Vector3(0, 0, -10),
	# The lock objects are objectives too: a coupling you cannot walk to is a
	# crystal you can never unseal, and the mission becomes unwinnable with no
	# error anywhere.
	"power coupling": Vector3(-5, 0, 24),
	"coupling socket": Vector3(36, 0, -3),
}

var _session: TestSession = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("ReachTester", 7730)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_SHIP), "the hub mounts"):
		_session.stop()
		return
	await GameManager.host_start_expedition()
	if not check(await _session.await_scene(GameConfig.SCENE_NERAVA), "Nerava mounts"):
		_session.stop()
		return

	var stage := SceneManager.current_stage()
	var region := stage.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if not check(region != null, "the navigation region is present"):
		_session.stop()
		return

	var map := region.get_navigation_map()
	if not check(map.is_valid(), "the navigation map is valid"):
		_session.stop()
		return

	_check_corridors_clear(stage)
	_check_spawn_exits(stage)
	await _check_ship_is_walkable()

	# Ask the map a real question rather than trusting the iteration counter -
	# see NavUtil for why the counter lies on a second visit to a level.
	var synced: bool = await NavUtil.await_map_usable(tree, map, KEY_POINTS["drop pod"], 300)
	if not check(synced, "the navigation map became queryable"):
		_session.stop()
		return

	var origin: Vector3 = KEY_POINTS["drop pod"]
	for label in KEY_POINTS:
		if label == "drop pod":
			continue
		var target: Vector3 = KEY_POINTS[label]
		_check_reachable(map, origin, target, "drop pod -> %s" % label)
		_check_reachable(map, target, origin, "%s -> drop pod" % label)

	# Branch-to-branch, so a route that only works via the spawn is still caught.
	_check_reachable(map, KEY_POINTS["ruins crystal"], KEY_POINTS["cave crystal"],
		"ruins crystal -> cave crystal")
	_check_reachable(map, KEY_POINTS["cave crystal"], KEY_POINTS["grove crystal"],
		"cave crystal -> grove crystal")

	_check_bounded(map)

	_session.stop()
	await tree.process_frame


## The three authored routes to the crystals, matching tests/net_probe.gd. The
## probe WALKS these as straight legs, and so does a player heading for an
## objective without thinking about it.
const CORRIDOR_ROUTES := {
	"ruins": [Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, 4),
		Vector3(-10, 0, 0), Vector3(-42, 0, 0)],
	"cave": [Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, 4),
		Vector3(10, 0, 0), Vector3(42, 0, 0)],
	# The route a player actually takes to unseal the cave crystal: collect the
	# coupling in the canyon, fit it at the socket, then take the crystal. The
	# dog-leg to z = -3 is not decoration - the straight line walks into the
	# cave stalagmite, which is exactly how the multiplayer probe first failed.
	"coupling errand": [Vector3(0, 0, 34), Vector3(-5, 0, 25), Vector3(0, 0, 14),
		Vector3(0, 0, 4), Vector3(14, 0, 0), Vector3(24, 0, -2),
		Vector3(34, 0, -3), Vector3(42, 0, 0)],
	"grove": [Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, 4),
		Vector3(0, 0, -18), Vector3(0, 0, -42)],
}


## Walks each corridor's centre-line and asserts nothing solid stands in it.
##
## THIS IS NOT THE SAME PROPERTY AS REACHABILITY, and the difference is what let
## a bug through: set dressing placed in the middle of the grove corridor left
## the navigation mesh perfectly happy - the corridor is 12 m wide, so a path
## simply routed around the obstacle - while a client walking the authored route
## in a straight line drove into a brazier and never reached the crystal. A path
## existing and a corridor being clear are different claims, and only the second
## one describes what a player actually does.
## Lanes either side of the centre-line, because a player does not walk down
## the exact middle of a 12 m corridor and the props are not placed there.
## Sweeping all three answers two different questions at once: can anyone get
## through at all, and is the obvious line the one that works.
const CORRIDOR_LANES: Array = [-2.5, 0.0, 2.5]


func _check_corridors_clear(stage: Node) -> void:
	var space := (stage as Node3D).get_world_3d().direct_space_state
	if not check(space != null, "the physics space is available"):
		return
	# Chest height: low enough to catch a crate, high enough to ignore the
	# ground itself and the shallow lips the player walks over.
	var eye := Vector3(0.0, 1.1, 0.0)
	for name in CORRIDOR_ROUTES:
		var route: Array = CORRIDOR_ROUTES[name]
		var blocked: Array = []
		for lane in CORRIDOR_LANES:
			var lane_offset := Vector3(float(lane), 0.0, 0.0)
			var blocked_at := ""
			for i in range(route.size() - 1):
				var from: Vector3 = (route[i] as Vector3) + eye + lane_offset
				var to: Vector3 = (route[i + 1] as Vector3) + eye + lane_offset
				var query := PhysicsRayQueryParameters3D.create(from, to)
				query.collision_mask = GameConfig.LAYER_WORLD
				query.collide_with_areas = false
				var hit := space.intersect_ray(query)
				if hit.is_empty():
					continue
				var node := hit.get("collider") as Node
				var who: String = node.name if node != null else "?"
				# Walk up to the dressing node, whose name says which piece it
				# is - the collider itself is an anonymous hull.
				var parent := node.get_parent() if node != null else null
				if parent != null and parent is SetDressing:
					who = parent.name
				blocked_at = "%s -> %s by %s" % [str(route[i]), str(route[i + 1]), who]
				break
			if not blocked_at.is_empty():
				blocked.append("x=%+.1f %s" % [float(lane), blocked_at])

		# EVERY lane, not just one. The first version of this check accepted a
		# corridor as long as some lane got through, on the theory that a pillar
		# beside a route is scenery. The automated playtest then walked back
		# from the coupling socket, cut the corner the way a player does, and
		# was stopped dead by exactly such a pillar - so "a lane is clear" is
		# not the property that matters. A player does not walk the centre-line;
		# they walk the line between where they are and where they are going,
		# and that line has to be clear across the width of the corridor.
		check(blocked.is_empty(),
			"the %s corridor is walkable in every lane%s"
			% [name, "" if blocked.is_empty() else " (blocked " + "; ".join(blocked) + ")"])


func _check_reachable(map: RID, from: Vector3, to: Vector3, label: String) -> void:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if not check(path.size() >= 2, "%s: a navigation path exists (%d points)" % [label, path.size()]):
		return
	# A partial path stops at the edge of the reachable region, so "the path
	# ends near the target" is what actually proves connectivity.
	var arrival: Vector3 = path[path.size() - 1]
	var gap := Vector2(arrival.x - to.x, arrival.z - to.z).length()
	check(gap <= REACH_TOLERANCE,
		"%s: the path reaches the target (stops %.1fm away)" % [label, gap])


## The playable area must be enclosed: a point far outside the level must NOT be
## reachable, or players can walk off the map.
func _check_bounded(map: RID) -> void:
	var inside: Vector3 = KEY_POINTS["temple clearing"]
	for outside in [Vector3(0, 0, 200), Vector3(200, 0, 0), Vector3(-200, 0, 0), Vector3(0, 0, -200)]:
		var path := NavigationServer3D.map_get_path(map, inside, outside, true)
		var arrival: Vector3 = path[path.size() - 1] if path.size() > 0 else inside
		var gap := Vector2(arrival.x - outside.x, arrival.z - outside.z).length()
		check(gap > 60.0,
			"the map is enclosed towards %s (path stopped %.0fm short)" % [str(outside), gap])


# ==========================================================================
# The ship
#
# The Starfarer has no navigation mesh - nothing pathfinds on it - so none of
# the checks above apply to it, and it went out with its ONLY fore-to-aft
# corridor blocked by the mess table. Three of the four pre-flight stations
# were unreachable, which made the launch lever unarmable and the game
# unwinnable from a fresh start. Every existing test passed: the structure was
# valid, the ids were unique, and the mission tests teleport the player instead
# of walking.
#
# So this sweeps a PLAYER-SIZED CAPSULE rather than casting a ray. A ray at
# chest height passes straight over a dining table and reports a clear lane.
# ==========================================================================

## Player capsule, from scenes/entities/player.tscn.
const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.8
## Fore and aft ends of the WALKABLE deck. The bow stops aft of the flight
## seats: the consoles across the front of the bridge are furniture you stand
## at, not corridor you walk through, and requiring a lane through them would
## be testing the sweep's own bounds rather than the ship.
const SHIP_BOW := -19.0
const SHIP_STERN := 22.0
const SHIP_STEP := 0.5


func _check_ship_is_walkable() -> void:
	set_current("ship spine")
	var packed: PackedScene = load(GameConfig.scene_path(GameConfig.SCENE_SHIP)) as PackedScene
	if not check(packed != null, "the ship scene loads"):
		return
	var level := packed.instantiate()
	tree.root.add_child(level)
	await tree.physics_frame
	await tree.physics_frame

	var space := (level as Node3D).get_world_3d().direct_space_state
	if not check(space != null, "the ship has a physics space"):
		level.queue_free()
		return

	var shape := CapsuleShape3D.new()
	shape.radius = PLAYER_RADIUS
	shape.height = PLAYER_HEIGHT

	# At least one lane must run the whole length of the ship. Which lane does
	# not matter - a player will find it - but if none does, the crew is sealed
	# into whichever compartment they spawned in.
	var lanes: Array = []
	var best_blocker := ""
	var best_x := 0.0
	var x := -3.0
	while x <= 3.01:
		var blocker := _first_blocker_along(space, shape, x)
		if blocker == "":
			lanes.append(x)
		elif best_blocker == "":
			best_blocker = blocker
			best_x = x
		x += SHIP_STEP

	check(not lanes.is_empty(),
		"a player-sized capsule can walk bow to stern somewhere in the spine "
		+ ("(clear lanes at x = %s)" % str(lanes) if not lanes.is_empty()
			else "- every lane is blocked, first at x=%.1f by %s" % [best_x, best_blocker]))

	# Every LEG of every authored route must admit a player-sized capsule.
	#
	# "A clear lane exists somewhere in the spine" and "the route to the fuel
	# station is walkable" are different claims. Moving a cable spool out of the
	# corridor once put it beside the fuel station instead, where it pinched the
	# approach shut - the lane check still passed, and the playtest still could
	# not finish the checklist. This sweeps what a player actually walks.
	for leg in ShipRoutes.legs():
		var from: Vector3 = leg[0]
		var to: Vector3 = leg[1]
		var blocker := _blocker_along_leg(space, shape, from, to)
		check(blocker == "", "the route to %s is clear from %s to %s%s"
			% [String(leg[2]), str(from), str(to),
				"" if blocker == "" else " - blocked by " + blocker])

	# Every station must have somewhere to stand.
	#
	# This is the property that actually broke, and it is stronger than picking
	# one point per room and hoping: for each interactable aboard, look for a
	# free player-sized spot within interaction range of it. A station you can
	# see but cannot stand at is as unusable as one behind a wall, and a room
	# sample point can pass while the thing in the room is unreachable.
	for node in level.find_children("*", "", true, false):
		var oid: Variant = node.get("object_id")
		if oid == null or String(oid) == "":
			continue
		var target := node as Node3D
		if target == null:
			continue
		check(_has_standing_room(space, shape, target.global_position),
			"a player can stand within reach of %s" % String(oid))

	_check_pilot_can_launch(level)

	level.queue_free()
	await tree.process_frame


## How far the interact ray reaches, and how far a seated player may swivel.
## Both are properties of the PLAYER, checked here against the LEVEL, because
## that is where the two can disagree.
const INTERACT_RAY_LENGTH := 3.2
const SEATED_SWIVEL_LIMIT_DEG := 105.0
## The camera pivot rides this far above the seated body.
const EYE_ABOVE_SEAT := 0.6


## Can a strapped-in pilot actually launch the ship?
##
## This is the check that would have caught the worst defect in the build. The
## launch lever refuses to fire while any crew member is standing, and the lever
## stood 3.9 m behind the nearest chair - past the 3.2 m interact ray, and 168
## degrees round from a seat that only swivels 105. Every gate was green: the
## rules were right, the routes were walkable, there was standing room at the
## lever, and the ship could not be launched by playing the game.
##
## Nothing that asks about the level alone can see it, because it is not a fact
## about the level: it is the level and the player's reach disagreeing. So this
## asserts the disagreement directly, from the seat, using the same two numbers
## the player uses.
func _check_pilot_can_launch(level: Node) -> void:
	set_current("the pilot's reach")
	var lever: Node3D = null
	var seats: Array = []
	for node in level.find_children("*", "", true, false):
		if String(node.get("object_id") if node.get("object_id") != null else "") \
				== "ship_launch_lever":
			lever = node as Node3D
		if node.get("is_pilot_seat") != null and bool(node.get("is_pilot_seat")):
			seats.append(node)
	if not check(lever != null, "the ship has a launch control"):
		return
	if not check(not seats.is_empty(), "exactly one seat is marked as the pilot's"):
		return
	check(seats.size() == 1, "exactly one seat is the pilot's (found %d)" % seats.size())

	for seat in seats:
		var node3d := seat as Node3D
		var sit: Vector3 = node3d.call("sit_position") if node3d.has_method("sit_position") \
			else node3d.global_position
		var eye: Vector3 = sit + Vector3(0.0, EYE_ABOVE_SEAT, 0.0)
		# Aim at the lever's body, not its origin on the floor.
		var to_lever: Vector3 = lever.global_position + Vector3(0.0, 0.9, 0.0) - eye
		check(to_lever.length() <= INTERACT_RAY_LENGTH,
			"the launch control is within the %.1f m interact ray of %s (it is %.2f m)"
			% [INTERACT_RAY_LENGTH, String(seat.name), to_lever.length()])

		var flat := Vector3(to_lever.x, 0.0, to_lever.z)
		var seat_yaw: float = node3d.call("sit_yaw") if node3d.has_method("sit_yaw") \
			else node3d.global_rotation.y
		var swivel: float = rad_to_deg(absf(wrapf(atan2(-flat.x, -flat.z) - seat_yaw, -PI, PI)))
		check(swivel <= SEATED_SWIVEL_LIMIT_DEG,
			"the launch control is within the %.0f deg seated swivel of %s (it is %.0f deg)"
			% [SEATED_SWIVEL_LIMIT_DEG, String(seat.name), swivel])


## The first thing standing in one leg of a walking route, or "" if it is clear.
func _blocker_along_leg(space: PhysicsDirectSpaceState3D, shape: Shape3D,
		from: Vector3, to: Vector3) -> String:
	var span: float = from.distance_to(to)
	if span < 0.01:
		return ""
	var steps: int = maxi(int(span / 0.4), 1)
	for i in range(steps + 1):
		var at: Vector3 = from.lerp(to, float(i) / float(steps))
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(),
			Vector3(at.x, PLAYER_HEIGHT * 0.5 + 0.05, at.z))
		params.collision_mask = GameConfig.LAYER_WORLD
		var hits := space.intersect_shape(params, 1)
		if not hits.is_empty():
			var node: Node = hits[0]["collider"]
			var owner_node: Node = node.get_parent() if node.get_parent() != null else node
			return "%s at %s" % [owner_node.name, str(at.snapped(Vector3.ONE * 0.1))]
	return ""


## Is there a free player-sized spot within interaction range of this object?
## Sampled on a ring rather than at one offset, because which SIDE a console is
## approachable from is a level-design detail the test should not care about.
func _has_standing_room(space: PhysicsDirectSpaceState3D, shape: Shape3D,
		at: Vector3) -> bool:
	var reach: float = GameConfig.INTERACT_VALIDATE_DISTANCE * 0.6
	for ring in [reach * 0.55, reach * 0.8]:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			var spot := at + Vector3(sin(angle) * ring, 0.0, cos(angle) * ring)
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(Basis(),
				Vector3(spot.x, PLAYER_HEIGHT * 0.5 + 0.05, spot.z))
			params.collision_mask = GameConfig.LAYER_WORLD
			if space.intersect_shape(params, 1).is_empty():
				return true
	return false


## The first thing standing in one fore-aft lane, or "" if the lane is clear.
func _first_blocker_along(space: PhysicsDirectSpaceState3D, shape: Shape3D, x: float) -> String:
	var z := SHIP_BOW
	while z <= SHIP_STERN:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(), Vector3(x, PLAYER_HEIGHT * 0.5 + 0.05, z))
		params.collision_mask = GameConfig.LAYER_WORLD
		var hits := space.intersect_shape(params, 1)
		if not hits.is_empty():
			var node: Node = hits[0]["collider"]
			var owner_node: Node = node.get_parent() if node.get_parent() != null else node
			return "%s at z=%.1f" % [owner_node.name, z]
		z += SHIP_STEP
	return ""


## Every spawn point must have somewhere to stand and a clear way out.
##
## The landing pad had a supply pallet three and a half metres in front of one
## spawn and a crate stack in front of another, both solid, both squarely on the
## only route off the pad. The navmesh routed around them happily and the
## corridor-clearance check only sweeps the centre-line, so nothing noticed -
## but a player pressing W on their first frame walked straight into a crate.
func _check_spawn_exits(stage: Node) -> void:
	set_current("spawn exits")
	var root := stage.get_node_or_null("PlayerSpawnPoints")
	if not check(root != null, "the level has PlayerSpawnPoints"):
		return
	var space := (stage as Node3D).get_world_3d().direct_space_state
	if not check(space != null, "the physics space is available"):
		return

	var shape := CapsuleShape3D.new()
	shape.radius = PLAYER_RADIUS
	shape.height = PLAYER_HEIGHT

	# Not straight -Z. A player leaving the pad walks at the temple, so the leg
	# that has to be clear is spawn -> clearing, and they do not walk it as a
	# laser line: this sweeps three parallel lines 0.9 m apart, which is roughly
	# how far a player wanders while looking around on a first landing.
	#
	# The straight -Z version passed this level while a 5 m rock stood four
	# metres in front of Spawn1, because the capsule cleared its corner by
	# 0.1 m. The automated playtest walked into it on the second run and not the
	# first, which is exactly what a 0.1 m margin buys you.
	var clearing := Vector3(0.0, 0.0, 13.0)
	for point in root.get_children():
		var at := (point as Node3D).global_position
		var name := String(point.name)
		var to_clearing: Vector3 = clearing - at
		to_clearing.y = 0.0
		var side: Vector3 = to_clearing.normalized().cross(Vector3.UP)
		for lane in [-0.9, 0.0, 0.9]:
			var offset: Vector3 = side * lane
			var blocker := _blocker_along_leg(space, shape, at + offset,
				at + offset + to_clearing.normalized() * 14.0)
			check(blocker == "", "%s has a clear 14 m run at the clearing (lane %+.1f)%s"
				% [name, lane, "" if blocker == "" else " - blocked by " + blocker])
