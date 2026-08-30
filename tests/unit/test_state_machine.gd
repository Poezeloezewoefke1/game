extends TestCase
## The mission state machine. Every legal edge is asserted, and - more
## importantly - the illegal ones, because an unchecked transition is how a
## mission ends up "complete" without anybody extracting.

const MS := MissionRules.MissionState


func test_happy_path_edges_are_legal() -> void:
	var path := [
		MS.LOBBY_READY, MS.TRANSITIONING_TO_HUB, MS.HUB_IDLE,
		MS.TRANSITIONING_TO_NERAVA, MS.FIND_TEMPLE, MS.FIND_CRYSTALS,
		MS.ACTIVATE_ALTAR, MS.RETRIEVE_STAR_MAP, MS.RETURN_TO_DROP_POD,
		MS.MISSION_COMPLETE, MS.RETURNING_TO_LOBBY, MS.LOBBY_READY,
	]
	for i in path.size() - 1:
		check(MissionRules.is_valid_transition(path[i], path[i + 1]),
			"%s -> %s must be legal" % [
				MissionRules.state_name(path[i]), MissionRules.state_name(path[i + 1])])


func test_self_transition_is_illegal() -> void:
	for state in MS.values():
		check_false(MissionRules.is_valid_transition(state, state),
			"%s must not transition to itself" % MissionRules.state_name(state))


func test_cannot_skip_the_mission() -> void:
	check_false(MissionRules.is_valid_transition(MS.HUB_IDLE, MS.MISSION_COMPLETE),
		"the hub cannot jump straight to victory")
	check_false(MissionRules.is_valid_transition(MS.FIND_TEMPLE, MS.RETURN_TO_DROP_POD),
		"the puzzle cannot be skipped")
	check_false(MissionRules.is_valid_transition(MS.LOBBY_READY, MS.FIND_CRYSTALS),
		"the lobby cannot jump into the middle of the mission")
	check_false(MissionRules.is_valid_transition(MS.FIND_CRYSTALS, MS.RETRIEVE_STAR_MAP),
		"the altar step cannot be skipped")


func test_failure_is_reachable_from_every_nerava_state() -> void:
	for state in MissionRules.NERAVA_STATES:
		check(MissionRules.is_valid_transition(state, MS.MISSION_FAILED),
			"%s must be able to fail" % MissionRules.state_name(state))


func test_failure_is_not_reachable_off_nerava() -> void:
	check_false(MissionRules.is_valid_transition(MS.LOBBY_READY, MS.MISSION_FAILED),
		"the lobby cannot fail the mission")
	check_false(MissionRules.is_valid_transition(MS.HUB_IDLE, MS.MISSION_FAILED),
		"the hub cannot fail the mission")


func test_retry_and_lobby_exits() -> void:
	check(MissionRules.is_valid_transition(MS.MISSION_FAILED, MS.TRANSITIONING_TO_NERAVA),
		"failure can retry")
	check(MissionRules.is_valid_transition(MS.MISSION_FAILED, MS.RETURNING_TO_LOBBY),
		"failure can return to the lobby")
	check_false(MissionRules.is_valid_transition(MS.MISSION_COMPLETE, MS.TRANSITIONING_TO_NERAVA),
		"victory does not retry - it returns to the lobby first")


func test_every_state_has_objective_text() -> void:
	for state in MS.values():
		check_ne(MissionRules.objective_text(state), "",
			"%s must have objective text" % MissionRules.state_name(state))


func test_required_objective_wording() -> void:
	# These exact strings are part of the design spec.
	check_eq(MissionRules.objective_text(MS.HUB_IDLE),
		"Use the Mission Terminal to begin the expedition.", "hub objective wording")
	check_eq(MissionRules.objective_text(MS.FIND_TEMPLE), "Locate the Temple.", "temple objective wording")
	check_eq(MissionRules.objective_text(MS.FIND_CRYSTALS),
		"Find 3 Power Crystals to power the altar.", "crystal objective wording")
	check_eq(MissionRules.objective_text(MS.ACTIVATE_ALTAR),
		"Place the remaining Power Crystals into the altar.", "altar objective wording")
	check_eq(MissionRules.objective_text(MS.RETRIEVE_STAR_MAP), "Retrieve the Star Map.", "star map objective wording")
	check_eq(MissionRules.objective_text(MS.RETURN_TO_DROP_POD), "Return to the Drop Pod.", "return objective wording")
	check_eq(MissionRules.objective_text(MS.MISSION_COMPLETE), "Mission accomplished.", "victory wording")
	check_eq(MissionRules.objective_text(MS.MISSION_FAILED), "Mission failed.", "failure wording")


func test_progression_from_a_fresh_snapshot() -> void:
	var s := MissionRules.fresh_snapshot(1)
	s["state"] = MS.FIND_TEMPLE
	check_eq(MissionRules.next_progress_state(s), -1, "no progress before the temple is found")
	s["temple_discovered"] = true
	check_eq(MissionRules.next_progress_state(s), MS.FIND_CRYSTALS, "finding the temple advances the objective")


func test_progression_to_altar_when_crystals_leave_the_world() -> void:
	var s := MissionRules.fresh_snapshot(1)
	s["state"] = MS.FIND_CRYSTALS
	check_eq(MissionRules.next_progress_state(s), -1, "no progress with crystals still loose")
	s["crystals_in_world"] = []
	check_eq(MissionRules.next_progress_state(s), MS.ACTIVATE_ALTAR,
		"collecting every crystal advances to the altar step")


func test_progression_to_altar_on_first_placement() -> void:
	var s := MissionRules.fresh_snapshot(1)
	s["state"] = MS.FIND_CRYSTALS
	s["pedestals"] = {"pedestal_a": GameConfig.CRYSTAL_RUINS}
	check_eq(MissionRules.next_progress_state(s), MS.ACTIVATE_ALTAR,
		"the first placement advances to the altar step")


func test_no_progress_out_of_terminal_states() -> void:
	for state in [MS.MISSION_COMPLETE, MS.MISSION_FAILED, MS.RETURNING_TO_LOBBY, MS.LOBBY_READY]:
		var s := MissionRules.fresh_snapshot(1)
		s["state"] = state
		check_eq(MissionRules.next_progress_state(s), -1,
			"%s must not auto-progress" % MissionRules.state_name(state))
