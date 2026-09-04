extends TestCase
## Health, downed, revive, blaster validation, Star Map drop, and the failure
## condition - all against a real host session with two player entities.
##
## The second player is a genuinely spawned player node owned by peer 2. Peer 2
## has no socket, which is exactly the situation the host faces between a peer
## dropping and the disconnect being processed, so it is a useful shape to test.

const MS := MissionRules.MissionState
const P2 := 2

var _session: TestSession = null
var _p1: Node = null
var _p2: Node = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("CombatTester", 7650)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	if not await _reach_nerava():
		_session.stop()
		return

	await _test_blaster_validation()
	await _test_blaster_cannot_hurt_teammates()
	await _test_damage_and_downed()
	await _test_revive()
	await _test_revive_cancels_when_the_reviver_goes_down()
	await _test_altar_restores_the_crew()
	await _test_star_map_drop()
	await _test_the_warden_can_be_aimed_at()
	await _test_total_failure()

	_session.stop()
	await tree.process_frame


func _reach_nerava() -> bool:
	set_current("setup")
	# A second crew member, added to the roster before the session starts so the
	# spawner gives them a real spawn point.
	LobbyManager.host_add_player(P2, "Second")
	check_eq(LobbyManager.player_count(), 2, "two players are on the roster")

	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_SHIP), "the hub mounts"):
		return false
	await GameManager.host_start_expedition()
	if not check(await _session.await_scene(GameConfig.SCENE_NERAVA), "Nerava mounts"):
		return false
	await wait_frames(2)

	_p1 = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	_p2 = SpawnManager.player_node(P2)
	check(_p1 != null, "the host player spawned")
	check(_p2 != null, "the second player spawned")
	return _p1 != null and _p2 != null


# --------------------------------------------------------------------------

func _test_blaster_validation() -> void:
	set_current("blaster")
	var epoch := GameManager.session_epoch
	var origin: Vector3 = _p1.authoritative_position() + Vector3.UP * 1.4
	var dir := Vector3.FORWARD

	check(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, origin, dir, epoch),
		"a valid shot is accepted")
	check_near(float(_p1.get("heat")), GameConfig.BLASTER_HEAT_PER_SHOT, 2.0,
		"a shot adds heat")

	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, origin, dir, epoch),
		"an immediate second shot is refused by the host's own cadence clock")

	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, origin, dir, epoch + 99),
		"a shot from a stale session epoch is refused")

	# A client claiming to shoot from across the map must be refused.
	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, Vector3(500, 0, 500), dir, epoch),
		"a shot whose origin is nowhere near the shooter is refused")

	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, origin, Vector3.ZERO, epoch),
		"a zero direction is refused")
	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID,
		Vector3(NAN, 0, 0), dir, epoch), "a non-finite origin is refused")

	# Overheat: push heat to the cap directly (host-owned field) and confirm the
	# host refuses regardless of what the client believes.
	_p1.set("heat", GameConfig.BLASTER_HEAT_MAX)
	_p1.set("overheated", true)
	check_false(_p1.host_process_fire_request(GameConfig.HOST_PEER_ID, origin, dir, epoch),
		"an overheated blaster refuses to fire")
	_p1.set("heat", 0.0)
	_p1.set("overheated", false)


func _test_blaster_cannot_hurt_teammates() -> void:
	set_current("friendly fire")
	# Stand P1 right behind P2 and shoot straight through them. The blaster is
	# specified to contribute only to Sentinel stagger, so a teammate in the
	# line of fire must be completely unaffected.
	_p1.global_position = Vector3(0, 0, 4)
	_p1.set("sync_position", Vector3(0, 0, 4))
	_p2.global_position = Vector3(0, 0, 0)
	_p2.set("sync_position", Vector3(0, 0, 0))
	await tree.physics_frame

	# The previous phase fired a shot, so wait out the host's fire cadence -
	# otherwise this is testing the cooldown, not friendly fire.
	await wait_seconds(GameConfig.BLASTER_FIRE_INTERVAL + 0.2)
	var before := int(_p2.get("health"))
	var origin: Vector3 = _p1.authoritative_position() + Vector3.UP * 1.4
	var direction := Vector3(0, 0, -1)
	var fired: bool = _p1.host_process_fire_request(
		GameConfig.HOST_PEER_ID, origin, direction, GameManager.session_epoch)
	check(fired, "the shot at a teammate was accepted (it is a legal shot)")
	await wait_frames(3)
	check_eq(int(_p2.get("health")), before, "a teammate in the line of fire takes no damage")
	check_false(bool(_p2.get("is_downed")), "a teammate cannot be downed by a blaster")
	_p1.set("heat", 0.0)
	_p1.set("overheated", false)


func _test_revive_cancels_when_the_reviver_goes_down() -> void:
	set_current("revive cancels on reviver downed")
	# P2 is downed and P1 is reviving when P1 is downed too. The revive must
	# stop, and the mission must fail because nobody is left standing.
	_p2.host_set_downed()
	await wait_frames(2)
	_p1.global_position = Vector3(1.5, 0, 0)
	_p1.set("sync_position", Vector3(1.5, 0, 0))
	_p2.global_position = Vector3(0, 0, 0)
	_p2.set("sync_position", Vector3(0, 0, 0))
	await tree.physics_frame

	GameManager.request_revive_start(P2)
	await wait_frames(3)
	check(bool(_p2.get("revive_active")), "the revive started")

	_p1.host_set_downed()
	await wait_frames(4)
	check_false(bool(_p2.get("revive_active")), "the revive stops when the reviver goes down")
	check(bool(_p2.get("is_downed")), "the target is still downed")
	check_eq(GameManager.debug_active_revives(), 0, "no revive entry survives the reviver going down")

	# Both are down, so the mission must have failed - and then be retryable.
	check_eq(GameManager.mission_state(), MS.MISSION_FAILED,
		"downing the last reviver fails the mission")
	await GameManager.host_retry_mission()
	check(await _session.await_scene(GameConfig.SCENE_NERAVA), "the retry re-enters Nerava")
	await wait_frames(3)
	_p1 = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	_p2 = SpawnManager.player_node(P2)
	check(_p1 != null and _p2 != null, "both players respawned after the retry")
	check_false(bool(_p1.get("is_downed")), "the reviver is no longer downed after a retry")


func _test_damage_and_downed() -> void:
	set_current("damage")
	check_eq(int(_p2.get("health")), GameConfig.MAX_HEALTH, "the second player starts at full health")

	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	check_eq(int(_p2.get("health")), GameConfig.MAX_HEALTH - GameConfig.GUARDIAN_PROJECTILE_DAMAGE,
		"one hit removes exactly the projectile damage")
	check_false(bool(_p2.get("is_downed")), "one hit does not down a player")

	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	check_false(bool(_p2.get("is_downed")), "two hits do not down a player")

	# NOTE: with the specified constants (100 health, 33 damage) three hits
	# leave the player on 1 HP - it takes FOUR. This is asserted deliberately so
	# that changing either constant fails here instead of silently altering how
	# survivable the Sentinel is. See docs/KNOWN_LIMITATIONS.md (BAL-001).
	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	check_false(bool(_p2.get("is_downed")), "three 33-damage hits leave 1 HP, not a downed player")
	check_eq(int(_p2.get("health")),
		GameConfig.MAX_HEALTH - 3 * GameConfig.GUARDIAN_PROJECTILE_DAMAGE,
		"health after three hits is exactly 100 - 3x33")

	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	check(bool(_p2.get("is_downed")), "the fourth hit downs a player")
	check_eq(int(_p2.get("health")), 0, "a downed player is at zero health")

	# Damage on a downed player must be inert - no negative health, no second
	# "downed" event.
	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	check_eq(int(_p2.get("health")), 0, "damage on a downed player does nothing")
	check_eq(GameManager.mission_state(), MS.FIND_TEMPLE,
		"one player down does not fail a two-player mission")


func _test_revive() -> void:
	set_current("revive")
	# Out of range: the revive must not even start.
	_p1.global_position = Vector3(30, 0, 0)
	_p1.set("sync_position", Vector3(30, 0, 0))
	_p2.set("sync_position", Vector3(0, 0, 0))
	await tree.physics_frame
	GameManager.request_revive_start(P2)
	await wait_frames(2)
	check_false(bool(_p2.get("revive_active")), "a revive out of range does not start")

	# In range: it starts and progresses.
	_p1.global_position = Vector3(1.5, 0, 0)
	_p1.set("sync_position", Vector3(1.5, 0, 0))
	await tree.physics_frame
	GameManager.request_revive_start(P2)
	await wait_frames(3)
	check(bool(_p2.get("revive_active")), "a revive in range starts")
	check(float(_p2.get("revive_progress")) > 0.0, "the revive makes progress")

	# Walking away cancels it.
	_p1.global_position = Vector3(40, 0, 0)
	_p1.set("sync_position", Vector3(40, 0, 0))
	await wait_frames(4)
	check_false(bool(_p2.get("revive_active")), "walking out of range cancels the revive")
	check(bool(_p2.get("is_downed")), "the cancelled revive left the player downed")

	# A full, uninterrupted revive completes.
	_p1.global_position = Vector3(1.5, 0, 0)
	_p1.set("sync_position", Vector3(1.5, 0, 0))
	await tree.physics_frame
	GameManager.request_revive_start(P2)
	await wait_seconds(GameConfig.REVIVE_DURATION + 0.6)
	check_false(bool(_p2.get("is_downed")), "an uninterrupted revive brings the player back")
	check_eq(int(_p2.get("health")), GameConfig.REVIVED_HEALTH,
		"a revived player returns at exactly %d health" % GameConfig.REVIVED_HEALTH)
	check_false(bool(_p2.get("revive_active")), "the revive bar clears on completion")

	# Reviving someone who is not downed must be refused.
	GameManager.request_revive_start(P2)
	await wait_frames(2)
	check_false(bool(_p2.get("revive_active")), "a standing player cannot be revived")

	# Self-revive must be refused.
	GameManager.request_revive_start(GameConfig.HOST_PEER_ID)
	await wait_frames(2)
	check_false(bool(_p1.get("revive_active")), "a player cannot revive themselves")


func _test_star_map_drop() -> void:
	set_current("star map drop")
	# Put the mission into a state where the Star Map is genuinely carried.
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MS.RETRIEVE_STAR_MAP
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(P2)
	await wait_frames(2)

	check_eq(GameManager.star_map_carrier(), P2, "the second player carries the Star Map")
	# The WARDEN, not a Sentinel. This assertion read `guardian_count() == 1` and
	# was labelled "spawns the Sentinel", and it passed for the wrong reason: the
	# counter lumped every guardian together, so the one it found was the boss.
	# Separating the roles in the harness made the mislabel visible.
	check_eq(_session.boss_count(), 1, "taking the Star Map wakes the Warden")
	check_eq(_session.temple_sentinel_count(), 0, "and does not also spawn a temple Sentinel")

	var dropped_before := _dropped_star_maps()
	check_eq(dropped_before, 0, "nothing is on the ground while the map is carried")

	# Down the carrier - the map must drop exactly once. The carrier has to be
	# STANDING first: this used to assert only that they ended up downed, which
	# a player who was already downed satisfies without any drop ever happening.
	check_false(bool(_p2.get("is_downed")), "the carrier is on their feet to begin with")
	for i in 4:
		_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	await wait_frames(3)
	check(bool(_p2.get("is_downed")), "the carrier is downed")
	check_eq(GameManager.star_map_state(), MissionRules.MAP_DROPPED, "the Star Map drops")
	check_eq(GameManager.star_map_carrier(), 0, "no one carries a dropped Star Map")
	check_eq(_dropped_star_maps(), 1, "exactly one dropped Star Map exists")

	# Repeated damage and a repeated downed event must not duplicate the drop.
	_p2.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	_p2.host_set_downed()
	GameManager.host_on_player_downed(P2)
	await wait_frames(3)
	check_eq(_dropped_star_maps(), 1, "repeated damage cannot duplicate the dropped Star Map")

	# A living player recovers it.
	var dropped := _first_dropped_star_map()
	if check(dropped != null, "the dropped Star Map is a real interactable"):
		_p1.global_position = dropped.global_position + Vector3(1.5, 0, 0)
		_p1.set("sync_position", _p1.global_position)
		await tree.physics_frame
		GameManager.request_interact(String(dropped.get("object_id")))
		await wait_frames(3)
		check_eq(GameManager.star_map_state(), MissionRules.MAP_CARRIED,
			"a living player recovers the dropped Star Map")
		check_eq(GameManager.star_map_carrier(), GameConfig.HOST_PEER_ID, "the recoverer becomes the carrier")
		check_eq(_dropped_star_maps(), 0, "the ground copy is removed on recovery")
		check_eq(_session.boss_count(), 1, "recovering the map does not wake a second Warden")


## The Warden has to be SHOOTABLE from the ground it drives you onto.
##
## It hovers, the player's pitch is clamped at 65 degrees up, and the enraged
## phase drives it to a 3 m stand-off - so how high it hovers is not a cosmetic
## number, it decides whether the fight can be won at all. It was wrong: the
## spawner offset the anchor by BOSS_HOVER_HEIGHT so the Warden would appear at
## its hover height, and the height hold then added the same offset again, so it
## settled 3.4 m higher than authored. At the enraged stand-off that needs 70
## degrees of upward pitch against a 65 degree clamp: a measured run sat at the
## clamp for 84 volleys with the boss frozen on 50 health and the player
## untouched, which is a stalemate, not a fight.
func _test_the_warden_can_be_aimed_at() -> void:
	set_current("warden geometry")
	var boss := _session.boss_node()
	if not check(boss != null, "the Warden is awake"):
		return
	# Let the height hold settle wherever it is going to settle.
	await wait_seconds(1.2)
	var spawn_y := float((boss.get("spawn_position") as Vector3).y)
	# The height hold is proportional, so it settles asymptotically and sits a
	# few centimetres under its target for ever. The tolerance is there for that
	# and nothing else: the error this guards against was 3.4 m.
	var drift: float = absf(boss.global_position.y - spawn_y)
	check(drift < 0.25,
		"the Warden holds the height it spawned at (%.2f m from %.2f, drift %.2f m)"
			% [boss.global_position.y, spawn_y, drift])

	# The angle a player on the ground below would need, at the closest the
	# enraged Warden ever comes.
	var above_eye: float = boss.global_position.y - GameConfig.EYE_HEIGHT
	var needed := rad_to_deg(atan2(above_eye, GameConfig.BOSS_ENRAGED_STAND_OFF))
	check(needed <= GameConfig.PITCH_MAX_DEG,
		"a player can look up far enough to aim at the Warden at its enraged stand-off (needs %.0f deg, clamp is %.0f)"
			% [needed, GameConfig.PITCH_MAX_DEG])

	# Contact damage has to be a PUNISHMENT, not an aura. The enraged ring was
	# 3.0 against a contact range of 3.2, so the Warden parked inside its own
	# damage radius and dealt 18 a second for the whole phase unconditionally -
	# which killed a solo player from full in four seconds however well they
	# played, measured on two different drivers. It must hold station outside
	# the radius, so contact is what happens when it CATCHES you.
	check(GameConfig.BOSS_ENRAGED_STAND_OFF > GameConfig.BOSS_CONTACT_RANGE,
		"the enraged Warden holds station outside its own contact range (%.1f m ring vs %.1f m reach)"
			% [GameConfig.BOSS_ENRAGED_STAND_OFF, GameConfig.BOSS_CONTACT_RANGE])
	check(GameConfig.BOSS_ENRAGED_STAND_OFF < GameConfig.BOSS_STAND_OFF,
		"enraging still brings it closer than the ring it trades fire from")


func _test_total_failure() -> void:
	set_current("failure")
	check_ne(GameManager.mission_state(), MS.MISSION_FAILED, "the mission is still live")
	# P2 is already downed; downing the last standing player must fail it.
	_p1.host_set_downed()
	await wait_frames(3)
	check_eq(GameManager.mission_state(), MS.MISSION_FAILED,
		"the mission fails once every player is downed")
	await wait_frames(3)
	check_eq(_session.guardian_count(), 0, "the Sentinel is removed on failure")
	check_eq(_session.projectile_count(), 0, "projectiles are removed on failure")


# --------------------------------------------------------------------------

func _dropped_star_maps() -> int:
	var count := 0
	for n in tree.get_nodes_in_group(GameConfig.GROUP_SESSION_BOUND):
		if (n as Node).has_method("is_dropped_star_map"):
			count += 1
	return count


func _first_dropped_star_map() -> Node3D:
	for n in tree.get_nodes_in_group(GameConfig.GROUP_SESSION_BOUND):
		if (n as Node).has_method("is_dropped_star_map"):
			return n as Node3D
	return null


## The altar pays the crew back before it summons the Warden.
##
## Health was one-way across the whole mission - nothing restored it - so every
## point lost fetching crystals was a point missing at the boss, and a solo run
## that fought a crystal guard on the way arrived hurt and was downed having
## done nothing wrong. A difficulty curve decided by attrition rather than play.
func _test_altar_restores_the_crew() -> void:
	set_current("altar restore")
	# Hurt one player, down another, and leave a third untouched.
	_p1.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "test")
	var hurt_to := int(_p1.get("health"))
	check(hurt_to < GameConfig.MAX_HEALTH, "the first player is hurt (%d hp)" % hurt_to)
	_p2.host_set_downed()
	await wait_frames(2)
	check(bool(_p2.get("is_downed")), "the second player is down")

	# Place the last crystal, which is what activates the altar.
	GameManager.snapshot["state"] = MS.FIND_CRYSTALS
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["pedestals"] = {
		"pedestal_a": GameConfig.CRYSTAL_RUINS,
		"pedestal_b": GameConfig.CRYSTAL_CAVE,
	}
	GameManager.snapshot["crystals_carried"] = {
		GameConfig.HOST_PEER_ID: GameConfig.CRYSTAL_GROVE}
	GameManager.host_apply_crystal_placement(
		GameConfig.HOST_PEER_ID, "pedestal_c", GameConfig.CRYSTAL_GROVE)
	await wait_frames(2)

	check(GameManager.is_altar_active(), "the altar activated")
	check_eq(int(_p1.get("health")), GameConfig.MAX_HEALTH,
		"a hurt player is restored to full when the altar wakes")
	check(bool(_p2.get("is_downed")),
		"a DOWNED player is not quietly revived by it - that is what reviving is for")

	# Stand the second player back up. Leaving them down was not a detail: the
	# next test needs a carrier who can BE downed, and a player who is already
	# down cannot be downed again, so the drop it exists to prove never fired.
	_p2.host_revive()
	await wait_frames(2)
	check_false(bool(_p2.get("is_downed")), "the second player is back on their feet")
