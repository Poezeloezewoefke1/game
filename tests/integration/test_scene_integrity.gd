extends TestCase
## Structural checks on the authored level scenes.
##
## These catch the class of mistake that a script-level test never can: a
## duplicated object_id, a pedestal that accepts a crystal nobody placed in the
## level, a missing spawn point, a level with no navigation region. Every one of
## those would present as a mysterious runtime bug rather than a load failure.

var _levels := {
	GameConfig.SCENE_HUB: "res://scenes/levels/wayfinder_hub.tscn",
	GameConfig.SCENE_NERAVA: "res://scenes/levels/nerava_landing_zone.tscn",
}


func is_async() -> bool:
	return true


func run_async() -> void:
	for key in _levels:
		set_current("level:" + String(key))
		await _check_level(String(key), String(_levels[key]))


func _check_level(key: String, path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not check(packed != null, "%s loads" % path):
		return
	var level: Node = packed.instantiate()
	tree.root.add_child(level)
	await tree.process_frame

	_check_common(key, level)
	if key == GameConfig.SCENE_HUB:
		_check_hub(level)
	else:
		_check_nerava(level)

	level.queue_free()
	await tree.process_frame
	await tree.process_frame


func _check_common(key: String, level: Node) -> void:
	check_eq(String(level.get("level_key")), key, "%s declares its level_key" % key)

	check(level.get_node_or_null("EntityRoot/EntitySpawner") != null,
		"%s has EntityRoot/EntitySpawner" % key)
	check(level.get_node_or_null("EntityRoot/Entities") != null,
		"%s has EntityRoot/Entities" % key)

	var spawns := level.get_node_or_null("PlayerSpawnPoints")
	if check(spawns != null, "%s has PlayerSpawnPoints" % key):
		check(spawns.get_child_count() >= GameConfig.MAX_PLAYERS,
			"%s has at least %d spawn points (got %d)" % [key, GameConfig.MAX_PLAYERS, spawns.get_child_count()])
		for child in spawns.get_children():
			check(child is Node3D, "%s spawn point %s is a Node3D" % [key, child.name])

	# Every interactable must have a non-empty, unique id and implement the
	# whole contract - a half-implemented interactable fails silently at runtime.
	var seen: Dictionary = {}
	for node in _collect_interactables(level):
		var oid := String(node.get("object_id"))
		check_ne(oid, "", "%s: %s has an object_id" % [key, node.name])
		check_false(seen.has(oid), "%s: object_id '%s' is unique (also on %s)" % [
			key, oid, String(seen.get(oid, ""))])
		seen[oid] = node.name
		for method in ["get_interaction_prompt", "can_interact",
				"request_interact", "host_validate_and_apply_interaction",
				"refresh_visual_state", "requires_line_of_sight"]:
			check(node.has_method(method),
				"%s: %s implements %s()" % [key, node.name, method])
		check(node.is_in_group(GameConfig.GROUP_INTERACTABLE),
			"%s: %s is in the Interactable group" % [key, node.name])
		check_eq(node.get("collision_layer"), GameConfig.LAYER_INTERACTABLE,
			"%s: %s is on the interactable physics layer" % [key, node.name])


func _check_hub(level: Node) -> void:
	var ids := _ids(level)
	check(ids.has("hub_mission_terminal"), "the hub has a Mission Terminal")
	check_eq(_count_by_property(level, "crystal_id"), 0, "the hub has no crystals")


func _check_nerava(level: Node) -> void:
	var ids := _ids(level)
	check(ids.has("nerava_drop_pod"), "Nerava has a Drop Pod")
	check(ids.has("nerava_star_map_altar"), "Nerava has the Star Map altar")

	var nav := level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if check(nav != null, "Nerava has a NavigationRegion3D"):
		check(nav.navigation_mesh != null, "the navigation region has a NavigationMesh")
		check(nav.get_child_count() > 0, "the navigation region actually contains geometry")

	check(level.get_node_or_null("GuardianAnchor") != null, "Nerava has a GuardianAnchor")
	check(level.get_node_or_null("StarMapDropAnchor") != null, "Nerava has a StarMapDropAnchor")
	check(level.get_node_or_null("TempleTrigger") != null, "Nerava has a TempleTrigger")

	# --- The puzzle must actually be solvable in this level. ---
	var crystals: Dictionary = {}
	var pedestals: Dictionary = {}
	for node in _collect_interactables(level):
		var cid := String(node.get("crystal_id")) if "crystal_id" in node else ""
		if not cid.is_empty():
			check_false(crystals.has(cid), "crystal '%s' appears exactly once" % cid)
			crystals[cid] = true
		var accepts := String(node.get("accepts_crystal_id")) if "accepts_crystal_id" in node else ""
		if not accepts.is_empty():
			var pid := String(node.get("pedestal_id"))
			check_ne(pid, "", "pedestal %s has a pedestal_id" % node.name)
			check_false(pedestals.has(accepts), "exactly one pedestal accepts '%s'" % accepts)
			pedestals[accepts] = pid

	check_eq(crystals.size(), GameConfig.REQUIRED_PEDESTAL_COUNT,
		"Nerava contains exactly %d crystals" % GameConfig.REQUIRED_PEDESTAL_COUNT)
	check_eq(pedestals.size(), GameConfig.REQUIRED_PEDESTAL_COUNT,
		"Nerava contains exactly %d pedestals" % GameConfig.REQUIRED_PEDESTAL_COUNT)
	for cid in GameConfig.ALL_CRYSTAL_IDS:
		check(crystals.has(cid), "crystal '%s' exists in the level" % cid)
		check(pedestals.has(cid), "a pedestal accepts '%s'" % cid)


func _collect_interactables(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Interactable:
			out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _ids(level: Node) -> Dictionary:
	var out: Dictionary = {}
	for node in _collect_interactables(level):
		out[String(node.get("object_id"))] = true
	return out


func _count_by_property(level: Node, property: String) -> int:
	var count := 0
	for node in _collect_interactables(level):
		if property in node and not String(node.get(property)).is_empty():
			count += 1
	return count
