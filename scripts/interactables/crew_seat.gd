extends Interactable
## A seat on the Starfarer. Sitting is the gate on launching, so it is
## host-authoritative like every other mission fact.
##
## The seat holds one crew member. Occupancy lives in the snapshot rather than
## on this node, because a client must not be able to decide it is in a chair -
## and because a player who disconnects mid-flight has to free their seat, which
## is GameManager's job, not a level node's.

## Which crew station this is. Bridge seats are what the launch check counts;
## the rest are furniture you can also sit in.
@export var seat_id: String = ""
@export var is_bridge_seat: bool = true
## The pilot's chair. Exactly one seat on the ship has this, and it is the only
## one the launch control is within arm's reach of - so the host has to take it
## before anyone goes anywhere. Saying so on the OTHER seats is the whole point
## of the flag: a host who straps into the wrong chair would otherwise sit there
## with the checklist green, the crew seated, and no way to leave.
@export var is_pilot_seat: bool = false
## Where the occupant's body sits, relative to this node.
@export var sit_offset: Vector3 = Vector3(0.0, 0.62, 0.0)

@onready var _frame: MeshInstance3D = $Frame
@onready var _cushion: MeshInstance3D = $Cushion
@onready var _indicator: MeshInstance3D = $Indicator


func _ready() -> void:
	if seat_id.is_empty():
		seat_id = object_id
	super()
	PropBuilder.build_crew_seat(self, _frame, _cushion)


## Where a seated player's body is parked, in world space.
func sit_position() -> Vector3:
	return to_global(sit_offset)


## The direction the seat faces. A seated player may swivel about this, but not
## turn their back on it.
func sit_yaw() -> float:
	return global_rotation.y


func occupant() -> int:
	var seats: Dictionary = GameManager.snapshot.get("seats", {})
	return int(seats.get(seat_id, 0))


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	var me := NetworkManager.local_peer_id()
	if String(player.get("seated_at")) == seat_id:
		return "Press E to Stand Up"
	var holder := occupant()
	if holder != 0 and holder != me:
		return "%s is in this seat" % LobbyManager.display_name_of(holder)
	if String(player.get("seated_at")) != "":
		return "Stand up first"
	if not MissionRules.is_ship_state(GameManager.mission_state()):
		return ""
	if me == GameConfig.HOST_PEER_ID and is_bridge_seat:
		# The launch control sits on the pilot's console and nowhere else, so
		# for the host - the only peer who may pull it - which chair they take
		# decides whether the ship can leave at all.
		return "Press E to take the pilot's seat" if is_pilot_seat \
			else "Press E to Sit (the pilot's seat has the launch control)"
	return "Press E to Sit"


func can_interact(player: Node) -> bool:
	if player == null or bool(player.get("is_downed")):
		return false
	if String(player.get("seated_at")) == seat_id:
		return true
	return MissionRules.is_ship_state(GameManager.mission_state()) and occupant() == 0


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	# Sitting down and standing up arrive through the same key, so which one the
	# player meant is decided from the snapshot, not from the request.
	if MissionRules.seat_of(GameManager.snapshot, peer_id) == seat_id:
		var leave := MissionRules.can_leave_seat(GameManager.snapshot, peer_id)
		if not bool(leave["ok"]):
			return leave
		GameManager.host_apply_leave_seat(peer_id)
		AudioDirector.play(AudioDirector.Cue.UI_CLICK)
		return {"ok": true, "reason": ""}

	var verdict := MissionRules.can_take_seat(GameManager.snapshot, peer_id, seat_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_take_seat(peer_id, seat_id)
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var taken := occupant() != 0
	# Green for free, amber for taken. The colour is the only thing telling a
	# player across the bridge whether a chair is available.
	var colour := Color(1.0, 0.66, 0.22) if taken else Color(0.30, 0.95, 0.62)
	_set_emission(_indicator, colour, 1.3 if taken else 0.9)
