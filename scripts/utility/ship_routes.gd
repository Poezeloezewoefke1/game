extends RefCounted
class_name ShipRoutes
## The canonical walking routes around the Starfarer's crew deck.
##
## WHY THIS EXISTS IN ONE PLACE. The deck is five compartments separated by
## bulkheads with 4 m doorways on the centre-line, so getting from the bridge to
## the cargo hold is a sequence of waypoints, not a straight line. Both the
## automated playtest (tools/playtest.gd) and the walkability gate
## (tests/integration/test_level_reachability.gd) need those routes, and if each
## kept its own copy they would drift - the gate would pass on a route nobody
## walks while the playtest failed on the route everybody does.
##
## These are also the honest definition of "the ship is navigable": if a
## player-sized capsule fits along every leg here, the crew can reach every
## station, and the pre-flight checklist is completable.

## Bulkheads sit at these z values; the doorway is x in [-2, 2] at each.
const BULKHEAD_Z: Array = [-15.0, -4.0, 5.0, 15.0]
const DOORWAY_HALF_WIDTH: float = 2.0

## Spawn area (crew quarters) to each station.
##
## Every bulkhead is crossed SQUARELY on the centre-line - go to (0, 0, z) at
## the bulkhead, pass through, then turn. Cutting the corner diagonally clips
## the doorway edge, which is a route bug that looks exactly like a level bug.
##
## The med bay (port) and engineering (starboard) share a divider at x = 0 from
## z = 6.5 to 8.5 and 11.5 to 13.5, so anything crossing that band stays on one
## side of it.
const TO_NAV_CONSOLE: Array = [
	Vector3(0, 0, -13.0), Vector3(0, 0, -14.6),
]
## Ends in FRONT of the reactor station, not behind it. The station sits at
## (2.3, 0, 8.4) facing starboard, and a route that stops on its blind side
## leaves the player pressing E into the back of a console.
const TO_REACTOR: Array = [
	Vector3(0, 0, -10.0), Vector3(0, 0, -4.0), Vector3(0, 0, 2.0),
	Vector3(0, 0, 5.0), Vector3(1.0, 0, 6.4), Vector3(3.4, 0, 7.2),
	Vector3(3.6, 0, 8.4),
]
## Around the reactor, not through it: the core stands mid-compartment at
## (5.4, 0, 10) and the direct diagonal to the fuel station clips it.
## Around the reactor core, which stands mid-compartment at (5.4, 0, 10).
const TO_FUEL: Array = [
	Vector3(2.8, 0, 9.8), Vector3(2.6, 0, 12.6), Vector3(4.8, 0, 13.6),
	Vector3(6.4, 0, 13.8),
]
const TO_HATCH: Array = [
	Vector3(4.0, 0, 12.4), Vector3(1.6, 0, 14.4), Vector3(0, 0, 15.0),
	Vector3(0, 0, 17.5), Vector3(0, 0, 20.8),
]
const TO_LEVER: Array = [
	Vector3(0, 0, 17.0), Vector3(0, 0, 15.0), Vector3(2.4, 0, 13.0),
	Vector3(2.4, 0, 10.0), Vector3(2.4, 0, 6.4), Vector3(0, 0, 5.0),
	Vector3(0, 0, 0.0), Vector3(0, 0, -4.0), Vector3(0, 0, -10.0),
	Vector3(0, 0, -15.0), Vector3(0, 0, -16.6), Vector3(4.6, 0, -16.6),
]
const TO_SEAT: Array = [
	Vector3(0, 0, -17.4), Vector3(-5.2, 0, -18.8),
]

## Every route, by the station it serves. Order is the order a crew works the
## checklist in, which is also the order the playtest walks.
const ALL: Dictionary = {
	"ship_nav_console": TO_NAV_CONSOLE,
	"ship_task_reactor": TO_REACTOR,
	"ship_task_fuel": TO_FUEL,
	"ship_task_hatch": TO_HATCH,
	"ship_launch_lever": TO_LEVER,
	"ship_seat_1": TO_SEAT,
}


## Every leg of every route, as [from, to] pairs, starting from the spawn area.
static func legs() -> Array:
	var out: Array = []
	var here := Vector3(0.0, 0.0, -8.0)   # the crew quarters, where players spawn
	for object_id in ALL:
		for point in ALL[object_id]:
			out.append([here, point, String(object_id)])
			here = point
	return out
