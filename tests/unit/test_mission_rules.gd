extends TestCase
## Exercises the authoritative rule surface directly.
##
## These are the rules a malicious client would attack, so each one is tested
## both for the case it must ALLOW and for every case it must DENY - including
## the reason, so a rule that starts denying for an accidental reason is caught.

const MS := MissionRules.MissionState

const ALIVE := {"alive": true, "downed": false, "in_mission_scene": true}
const DOWNED := {"alive": true, "downed": true, "in_mission_scene": true}
const OFFSCENE := {"alive": true, "downed": false, "in_mission_scene": false}
const DEAD := {"alive": false, "downed": false, "in_mission_scene": true}


func _snap() -> Dictionary:
	var s := MissionRules.fresh_snapshot(7)
	s["state"] = MS.FIND_CRYSTALS
	return s


# --- Actor eligibility ----------------------------------------------------

func test_actor_gate() -> void:
	check_allowed(MissionRules.actor_can_act(ALIVE), "a living player may act")
	check_denied(MissionRules.actor_can_act(DOWNED), "actor_downed", "a downed player may not act")
	check_denied(MissionRules.actor_can_act(OFFSCENE), "actor_wrong_scene", "a player outside the mission may not act")
	check_denied(MissionRules.actor_can_act(DEAD), "actor_not_alive", "a despawned player may not act")


# --- Crystals -------------------------------------------------------------

func test_crystal_pickup_happy_path() -> void:
	var s := _snap()
	check_allowed(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"a free crystal can be picked up")


func test_crystal_cannot_be_taken_twice() -> void:
	var s := _snap()
	s["crystals_in_world"] = [GameConfig.CRYSTAL_CAVE, GameConfig.CRYSTAL_GROVE]
	check_denied(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"crystal_not_available", "a crystal already out of the world cannot be taken")


func test_only_one_crystal_carried() -> void:
	var s := _snap()
	s["crystals_carried"] = {2: GameConfig.CRYSTAL_CAVE}
	check_denied(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"inventory_full", "a player carrying a crystal cannot take a second")


func test_crystal_cannot_be_double_owned() -> void:
	# Defence in depth: even if the world list is wrong, two peers must never
	# both end up holding the same crystal id.
	var s := _snap()
	s["crystals_carried"] = {3: GameConfig.CRYSTAL_RUINS}
	check_denied(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"crystal_already_carried", "a crystal held by another peer cannot be taken")


func test_star_map_carrier_cannot_also_take_a_crystal() -> void:
	var s := _snap()
	s["star_map_state"] = MissionRules.MAP_CARRIED
	s["star_map_carrier"] = 2
	check_denied(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"hands_full_star_map", "the Star Map carrier has no free hands")


func test_unknown_crystal_id_rejected() -> void:
	var s := _snap()
	check_denied(MissionRules.can_pick_up_crystal(s, 2, "crystal_of_infinite_power", ALIVE),
		"unknown_crystal", "an invented crystal id is rejected")


func test_crystal_pickup_needs_a_nerava_state() -> void:
	var s := _snap()
	s["state"] = MS.SHIP_IDLE
	check_denied(MissionRules.can_pick_up_crystal(s, 2, GameConfig.CRYSTAL_RUINS, ALIVE),
		"wrong_mission_state", "crystals cannot be taken outside the descent")


func test_downed_player_cannot_take_a_crystal() -> void:
	check_denied(MissionRules.can_pick_up_crystal(_snap(), 2, GameConfig.CRYSTAL_RUINS, DOWNED),
		"actor_downed", "a downed player cannot take a crystal")


# --- Pedestals ------------------------------------------------------------

func test_pedestal_accepts_matching_crystal() -> void:
	var s := _snap()
	s["crystals_carried"] = {2: GameConfig.CRYSTAL_RUINS}
	check_allowed(MissionRules.can_place_crystal(s, 2, "pedestal_a", GameConfig.CRYSTAL_RUINS, ALIVE),
		"the matching crystal is accepted")


func test_pedestal_rejects_wrong_crystal() -> void:
	var s := _snap()
	s["crystals_carried"] = {2: GameConfig.CRYSTAL_CAVE}
	check_denied(MissionRules.can_place_crystal(s, 2, "pedestal_a", GameConfig.CRYSTAL_RUINS, ALIVE),
		"wrong_crystal", "a mismatched crystal is rejected")


func test_pedestal_rejects_empty_hands() -> void:
	check_denied(MissionRules.can_place_crystal(_snap(), 2, "pedestal_a", GameConfig.CRYSTAL_RUINS, ALIVE),
		"no_crystal_carried", "an empty-handed player cannot fill a pedestal")


func test_pedestal_cannot_activate_twice() -> void:
	var s := _snap()
	s["pedestals"] = {"pedestal_a": GameConfig.CRYSTAL_RUINS}
	s["crystals_carried"] = {2: GameConfig.CRYSTAL_RUINS}
	check_denied(MissionRules.can_place_crystal(s, 2, "pedestal_a", GameConfig.CRYSTAL_RUINS, ALIVE),
		"pedestal_already_active", "a filled pedestal refuses a second crystal")


# --- Altar ----------------------------------------------------------------

func test_altar_needs_all_three_distinct_pedestals() -> void:
	var s := _snap()
	check_false(MissionRules.altar_should_activate(s), "an empty altar stays shut")
	s["pedestals"] = {"pedestal_a": GameConfig.CRYSTAL_RUINS}
	check_false(MissionRules.altar_should_activate(s), "one pedestal is not enough")
	s["pedestals"] = {
		"pedestal_a": GameConfig.CRYSTAL_RUINS,
		"pedestal_b": GameConfig.CRYSTAL_CAVE,
	}
	check_false(MissionRules.altar_should_activate(s), "two pedestals are not enough")
	s["pedestals"] = {
		"pedestal_a": GameConfig.CRYSTAL_RUINS,
		"pedestal_b": GameConfig.CRYSTAL_CAVE,
		"pedestal_c": GameConfig.CRYSTAL_GROVE,
	}
	check(MissionRules.altar_should_activate(s), "three distinct crystals open the altar")


func test_altar_rejects_duplicate_crystals() -> void:
	# Should be unreachable through the pedestal rule, but if it ever became
	# reachable the altar must still refuse to open.
	var s := _snap()
	s["pedestals"] = {
		"pedestal_a": GameConfig.CRYSTAL_RUINS,
		"pedestal_b": GameConfig.CRYSTAL_RUINS,
		"pedestal_c": GameConfig.CRYSTAL_GROVE,
	}
	check_false(MissionRules.altar_should_activate(s), "duplicate crystals do not open the altar")


func test_altar_rejects_unknown_crystal() -> void:
	var s := _snap()
	s["pedestals"] = {"a": "x", "b": "y", "c": "z"}
	check_false(MissionRules.altar_should_activate(s), "unknown crystal ids do not open the altar")


# --- Star Map -------------------------------------------------------------

func test_star_map_locked_before_altar() -> void:
	var s := _snap()
	check_denied(MissionRules.can_take_star_map(s, 2, ALIVE),
		"shield_active", "the Star Map is shielded until the altar opens")


func test_star_map_available_after_altar() -> void:
	var s := _snap()
	s["altar_active"] = true
	s["star_map_state"] = MissionRules.MAP_AVAILABLE
	check_allowed(MissionRules.can_take_star_map(s, 2, ALIVE), "the Star Map can be taken once unlocked")


func test_star_map_cannot_be_taken_twice() -> void:
	var s := _snap()
	s["altar_active"] = true
	s["star_map_state"] = MissionRules.MAP_CARRIED
	s["star_map_carrier"] = 3
	check_denied(MissionRules.can_take_star_map(s, 2, ALIVE),
		"already_carried", "a carried Star Map cannot be taken by someone else")


func test_dropped_star_map_can_be_recovered() -> void:
	var s := _snap()
	s["altar_active"] = true
	s["star_map_state"] = MissionRules.MAP_DROPPED
	check_allowed(MissionRules.can_take_star_map(s, 4, ALIVE), "a dropped Star Map can be recovered")


func test_extracted_star_map_is_terminal() -> void:
	var s := _snap()
	s["altar_active"] = true
	s["star_map_state"] = MissionRules.MAP_EXTRACTED
	check_denied(MissionRules.can_take_star_map(s, 2, ALIVE),
		"already_extracted", "an extracted Star Map cannot be re-taken")


# --- Extraction -----------------------------------------------------------

func test_extraction_requires_the_carrier() -> void:
	var s := _snap()
	s["state"] = MS.RETURN_TO_DROP_POD
	s["star_map_state"] = MissionRules.MAP_CARRIED
	s["star_map_carrier"] = 3
	check_allowed(MissionRules.can_extract(s, 3, ALIVE), "the carrier can extract")
	check_denied(MissionRules.can_extract(s, 2, ALIVE),
		"not_star_map_carrier", "a non-carrier cannot extract")


func test_extraction_requires_a_carried_map() -> void:
	var s := _snap()
	s["state"] = MS.RETURN_TO_DROP_POD
	s["star_map_state"] = MissionRules.MAP_DROPPED
	check_denied(MissionRules.can_extract(s, 3, ALIVE),
		"star_map_not_carried", "extraction fails while the map is on the ground")


func test_extraction_requires_the_right_state() -> void:
	var s := _snap()
	s["star_map_state"] = MissionRules.MAP_CARRIED
	s["star_map_carrier"] = 3
	check_denied(MissionRules.can_extract(s, 3, ALIVE),
		"wrong_mission_state", "extraction is impossible before the return leg")


func test_downed_carrier_cannot_extract() -> void:
	var s := _snap()
	s["state"] = MS.RETURN_TO_DROP_POD
	s["star_map_state"] = MissionRules.MAP_CARRIED
	s["star_map_carrier"] = 3
	check_denied(MissionRules.can_extract(s, 3, DOWNED), "actor_downed",
		"a downed carrier cannot extract")


# --- Mission terminal -----------------------------------------------------

func test_only_the_host_starts_the_expedition() -> void:
	var s := _snap()
	s["state"] = MS.SHIP_IDLE
	check_allowed(MissionRules.can_start_expedition(s, GameConfig.HOST_PEER_ID, ALIVE),
		"the host may start")
	check_denied(MissionRules.can_start_expedition(s, 42, ALIVE),
		"not_host", "a client may not start the expedition")


func test_expedition_cannot_start_twice() -> void:
	var s := _snap()
	s["state"] = MS.FIND_TEMPLE
	check_denied(MissionRules.can_start_expedition(s, GameConfig.HOST_PEER_ID, ALIVE),
		"wrong_mission_state", "the expedition cannot be restarted mid-mission")


# --- Failure condition ----------------------------------------------------

func test_failure_requires_every_player_down() -> void:
	check_false(MissionRules.should_fail({}), "no players is not a failure")
	check_false(MissionRules.should_fail({1: {"downed": false}}), "a standing player is not a failure")
	check(MissionRules.should_fail({1: {"downed": true}}), "solo downed is a failure")
	check_false(MissionRules.should_fail({1: {"downed": true}, 2: {"downed": false}}),
		"one player still standing is not a failure")
	check(MissionRules.should_fail({1: {"downed": true}, 2: {"downed": true}}),
		"everyone downed is a failure")


func test_disconnected_players_do_not_wedge_failure() -> void:
	# A peer that left is simply absent from the dictionary. If the only
	# standing player disconnects, the remaining downed players must fail.
	check(MissionRules.should_fail({2: {"downed": true}}),
		"the last standing player leaving completes the failure condition")


# --- The Warden, sized to the crew ----------------------------------------

## Pins the property that made the game unfinishable for one player: the boss
## was tuned for four, and a solo crew reaches it with 100 health, no revive,
## and 51 hits to land through a blaster that overheats after twelve. The
## automated playtest broke every shield node, took the body to 525 of 900, and
## went down - which alone ends the mission.
##
## What matters is not the exact numbers but the shape: strictly increasing with
## crew size, exactly 1.0 at the full crew of four, never zero or negative, and
## the same answer for a nonsense crew size as for a legal one, because a boss
## that divides by a bad crew count is worse than one that is mistuned.
func test_boss_scales_with_crew() -> void:
	check_eq(MissionRules.boss_scale(4), 1.0, "a full crew fights the boss at full strength")
	var previous := 0.0
	for crew in [1, 2, 3, 4]:
		var scale: float = MissionRules.boss_scale(crew)
		check(scale > previous, "crew %d faces a bigger Warden than crew %d" % [crew, crew - 1])
		check(scale > 0.0 and scale <= 1.0, "crew %d scale %.2f is in range" % [crew, scale])
		previous = scale

	# Out-of-range crew sizes clamp rather than misbehave. Nothing should ever
	# pass 0 or 9 here, and if something does the fight must still be winnable.
	check_eq(MissionRules.boss_scale(0), MissionRules.boss_scale(1), "crew 0 is treated as solo")
	check_eq(MissionRules.boss_scale(-3), MissionRules.boss_scale(1), "a negative crew is treated as solo")
	check_eq(MissionRules.boss_scale(9), MissionRules.boss_scale(4), "a crew above four clamps to four")


func test_boss_volleys_come_slower_for_a_smaller_crew() -> void:
	var solo: float = MissionRules.boss_volley_interval(1, false)
	var full: float = MissionRules.boss_volley_interval(4, false)
	check(solo > full, "a solo player gets longer between volleys (%.2f s vs %.2f s)" % [solo, full])
	check_eq(full, GameConfig.BOSS_VOLLEY_INTERVAL,
		"a full crew faces the configured volley interval unchanged")
	check(MissionRules.boss_volley_interval(1, true) < solo,
		"an enraged Warden still volleys faster than a calm one, at every crew size")
	for crew in [1, 2, 3, 4]:
		check(MissionRules.boss_volley_interval(crew, false) > 0.0,
			"crew %d has a positive volley interval" % crew)
