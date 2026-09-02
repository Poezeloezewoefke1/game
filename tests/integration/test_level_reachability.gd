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
func _check_corridors_clear(stage: Node) -> void:
	var space := (stage as Node3D).get_world_3d().direct_space_state
	if not check(space != null, "the physics space is available"):
		return
	# Chest height: low enough to catch a crate, high enough to ignore the
	# ground itself and the shallow lips the player walks over.
	var eye := Vector3(0.0, 1.1, 0.0)
	for name in CORRIDOR_ROUTES:
		var route: Array = CORRIDOR_ROUTES[name]
		var blocked_at := ""
		for i in range(route.size() - 1):
			var from: Vector3 = (route[i] as Vector3) + eye
			var to: Vector3 = (route[i + 1] as Vector3) + eye
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = GameConfig.LAYER_WORLD
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				var node := hit.get("collider") as Node
				var who: String = node.name if node != null else "?"
				# Walk up to the dressing node, whose name says which piece it
				# is - the collider itself is an anonymous hull.
				var parent := node.get_parent() if node != null else null
				if parent != null and parent is SetDressing:
					who = parent.name
				blocked_at = "%s -> %s by %s" % [str(route[i]), str(route[i + 1]), who]
				break
		check(blocked_at.is_empty(),
			"the %s corridor is walkable in a straight line%s"
			% [name, "" if blocked_at.is_empty() else " (blocked " + blocked_at + ")"])


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
