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
	if not check(await _session.await_scene(GameConfig.SCENE_HUB), "the hub mounts"):
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
