extends Node
## Automated test suite. Run:
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/test_suite.gd 4
## Covers: skin parser, skin UV mapping, character generation, tower stats, enemy stats,
## wave generation, damage calculation, armor calculation, currency, upgrade paths,
## boss phases, save data, path maths, relationships and the enemy pool.

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var current_section: String = ""

func _ready() -> void:
	print("\n================ UNSTABLE: LAST STAND — TEST SUITE ================")
	_section("Skin parser")
	test_skin_parser()
	_section("Skin UV mapping")
	test_skin_uv()
	_section("Character generation")
	test_character_generation()
	_section("Armor system")
	test_armor()
	_section("Weapons")
	test_weapons()
	_section("Damage calculation")
	test_damage()
	_section("Path")
	test_path()
	_section("Enemy pool")
	test_enemy_pool()
	_section("Enemy data")
	test_enemy_data()
	_section("Gear progression")
	test_gear_progression()
	_section("Tower stats and upgrades")
	test_tower_stats()
	_section("Upgrade path rule")
	test_gear_rule()
	_section("Hero data")
	test_hero_data()
	_section("Wave generation")
	test_waves()
	_section("Boss phases")
	test_boss_phases()
	_section("Currency")
	test_currency()
	_section("Save data")
	test_save()
	_section("Relationships")
	test_relationships()
	_section("Lore database integrity")
	test_lore()
	_report()

# ================================================================================================
# helpers
# ================================================================================================

func _section(name: String) -> void:
	current_section = name
	print("\n--- %s" % name)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  %s" % label)
	else:
		failed += 1
		failures.append("%s :: %s" % [current_section, label])
		print("  FAIL  %s" % label)

func check_eq(a, b, label: String) -> void:
	check(a == b, "%s (got %s, expected %s)" % [label, str(a), str(b)])

func check_near(a: float, b: float, tol: float, label: String) -> void:
	check(absf(a - b) <= tol, "%s (got %.4f, expected %.4f ±%.4f)" % [label, a, b, tol])

func _report() -> void:
	print("\n================ RESULTS ================")
	print("PASSED: %d" % passed)
	print("FAILED: %d" % failed)
	for f in failures:
		print("  ! %s" % f)
	print("=========================================")
	if failed == 0:
		print("ALL TESTS PASSED")

func on_finish() -> void:
	pass

# ================================================================================================
# tests
# ================================================================================================

func test_skin_parser() -> void:
	var uv := SkinLibrary.get_skin("uv_test")
	check(uv != null, "uv_test skin loads")
	check_eq(uv.image.get_width(), 64, "width is 64")
	check_eq(uv.image.get_height(), 64, "height is 64")
	check_eq(uv.legacy, false, "64x64 is not legacy")
	check_eq(uv.slim, false, "uv_test detected as classic")

	var legacy := SkinLibrary.get_skin("uv_test_legacy")
	check(legacy != null, "legacy skin loads")
	check_eq(legacy.legacy, true, "64x32 flagged legacy")
	check_eq(legacy.image.get_height(), 64, "legacy expanded to 64x64")
	check_eq(legacy.image.get_width(), 64, "legacy width preserved")

	var slim := SkinParser.generate_placeholder("t_slim", Color.RED, Color.BLUE, Color.GREEN, true)
	check_eq(slim.slim, true, "generated slim skin detected as slim")
	var classic := SkinParser.generate_placeholder("t_classic", Color.RED, Color.BLUE, Color.GREEN, false)
	check_eq(classic.slim, false, "generated classic skin detected as classic")
	check_eq(classic.placeholder, true, "placeholder flag set")

	# HD skin (128x128) must be accepted and report scale 2
	var hd := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	hd.fill(Color(1, 0, 0, 1))
	var hd_data := SkinParser.from_image(hd, "hd_test")
	check_eq(hd_data.scale, 2, "128x128 skin reports scale 2")
	check_eq(hd_data.image.get_width(), 128, "HD skin keeps its resolution")

	# A real supplied skin resolves from disk rather than a placeholder
	check(SkinLibrary.has_supplied_skin("wemmbu"), "wemmbu skin file present")
	var missing := SkinLibrary.get_skin("definitely_not_a_real_character_xyz")
	check_eq(missing.placeholder, true, "unknown character falls back to a placeholder")
	check(SkinLibrary.missing_assets.has("definitely_not_a_real_character_xyz"), "missing asset is recorded")

func test_skin_uv() -> void:
	# The UV test skin paints each face of each part a distinct colour. Verify the mesh builder
	# samples the right region by checking the UVs of each face against the expected net rects.
	var skin := SkinLibrary.get_skin("uv_test")
	var defs := MCGeometry.part_defs(skin.slim, skin.legacy)
	check_eq(defs.size(), 6, "six body parts defined")
	var names: Array[String] = []
	for d in defs:
		names.append(String(d["name"]))
	check(names.has("Head") and names.has("Body") and names.has("RightArm")
		and names.has("LeftArm") and names.has("RightLeg") and names.has("LeftLeg"), "all six parts present")

	var head := MCGeometry.part_def(defs, MCGeometry.Part.HEAD)
	check_eq(head["size"], Vector3i(8, 8, 8), "head is 8x8x8")
	check_eq(head["uv"], Vector2i(0, 0), "head UV origin is (0,0)")
	check_eq(head["uv_outer"], Vector2i(32, 0), "hat layer UV origin is (32,0)")

	var rects := MCGeometry.face_rects(Vector2i(0, 0), Vector3i(8, 8, 8), false)
	check_eq(rects["front"], Rect2(8, 8, 8, 8), "head front face rect")
	check_eq(rects["top"], Rect2(8, 0, 8, 8), "head top face rect")
	check_eq(rects["right"], Rect2(0, 8, 8, 8), "head right face rect")
	check_eq(rects["left"], Rect2(16, 8, 8, 8), "head left face rect")
	check_eq(rects["back"], Rect2(24, 8, 8, 8), "head back face rect")
	check_eq(rects["bottom"], Rect2(16, 0, 8, 8), "head bottom face rect")

	var body := MCGeometry.part_def(defs, MCGeometry.Part.BODY)
	var brects := MCGeometry.face_rects(body["uv"], body["size"], false)
	check_eq(brects["front"], Rect2(20, 20, 8, 12), "body front face rect")

	# Mirroring swaps left and right (used for legacy left limbs)
	var mrects := MCGeometry.face_rects(Vector2i(0, 0), Vector3i(8, 8, 8), true)
	check_eq(mrects["right"], rects["left"], "mirrored right face uses the left rect")

	# Slim arms are 3 wide
	var slim_defs := MCGeometry.part_defs(true, false)
	var slim_arm := MCGeometry.part_def(slim_defs, MCGeometry.Part.RIGHT_ARM)
	check_eq((slim_arm["size"] as Vector3i).x, 3, "slim arm is 3 pixels wide")
	var classic_arm := MCGeometry.part_def(MCGeometry.part_defs(false, false), MCGeometry.Part.RIGHT_ARM)
	check_eq((classic_arm["size"] as Vector3i).x, 4, "classic arm is 4 pixels wide")

	# Legacy skins mirror the left limbs and drop the second layer on the body
	var legacy_defs := MCGeometry.part_defs(false, true)
	var legacy_left_arm := MCGeometry.part_def(legacy_defs, MCGeometry.Part.LEFT_ARM)
	check_eq(legacy_left_arm["mirror"], true, "legacy left arm is mirrored")
	check_eq(legacy_left_arm["uv"], Vector2i(40, 16), "legacy left arm reuses the right arm UVs")
	check(MCGeometry.part_def(legacy_defs, MCGeometry.Part.BODY)["uv_outer"] == null, "legacy body has no outer layer")

	# Every part's UV rectangles must stay inside the 64x64 texture
	for d in MCGeometry.part_defs(false, false):
		for uv_key in ["uv", "uv_outer"]:
			if d[uv_key] == null:
				continue
			var r := MCGeometry.face_rects(d[uv_key], d["size"], false)
			for face in r.keys():
				var rect: Rect2 = r[face]
				check(rect.position.x >= 0 and rect.position.y >= 0
					and rect.position.x + rect.size.x <= 64 and rect.position.y + rect.size.y <= 64,
					"%s %s %s stays inside the skin" % [d["name"], uv_key, face])

func test_character_generation() -> void:
	var skin := SkinLibrary.get_skin("uv_test")
	var mesh := MCMeshBuilder.build_merged_character(skin, {}, "")
	check(mesh != null, "merged character mesh builds")
	check_eq(mesh.get_surface_count(), 1, "merged mesh has a single surface")
	# 6 parts x 6 faces x 4 verts = 144, plus the outer layer on head/body/limbs
	var verts: int = mesh.surface_get_array_len(0)
	check(verts >= 144, "mesh has at least 144 vertices (got %d)" % verts)
	var arrays := mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_CUSTOM0] != null, "CUSTOM0 (part id) present for GPU animation")
	check(arrays[Mesh.ARRAY_CUSTOM1] != null, "CUSTOM1 (pivot) present for GPU animation")
	check(arrays[Mesh.ARRAY_TEX_UV] != null, "UVs present")
	check(arrays[Mesh.ARRAY_NORMAL] != null, "normals present")

	var armored := MCMeshBuilder.build_merged_character(skin,
		{"helmet": "netherite", "chestplate": "netherite", "leggings": "netherite", "boots": "netherite"}, "netherite_mace")
	check(armored.surface_get_array_len(0) > verts, "armored + armed character has more geometry")

	# Node-based character
	var mc := MinecraftCharacter.new()
	add_child(mc)
	mc.setup(skin, {"helmet": "iron", "chestplate": "iron"}, "iron_sword")
	check_eq(mc.parts.size(), 6, "node character has six part nodes")
	check(mc.armor_nodes.size() > 0, "armor nodes attached")
	check(is_instance_valid(mc.held_node), "weapon node attached")
	check(mc.parts["Head"].position.y > 1.0, "head sits above the body")
	check_near(mc.parts["Head"].position.y, 24.0 * MCGeometry.PX, 0.001, "head pivot at 24 px")
	check_near(mc.parts["RightLeg"].position.y, 12.0 * MCGeometry.PX, 0.001, "leg pivot at 12 px")
	# right side is +X
	check(mc.parts["RightArm"].position.x > 0.0, "right arm is on +X")
	check(mc.parts["LeftArm"].position.x < 0.0, "left arm is on -X")
	# animation
	mc.play("walk")
	check_eq(mc.anim_state, "walk", "walk animation state set")
	mc.play("attack", 0.5)
	check_eq(mc.anim_state, "attack", "attack animation state set")
	check(mc.is_one_shot(), "attack is a one-shot animation")
	var hit_fired := [false]
	mc.attack_hit.connect(func() -> void: hit_fired[0] = true)
	for i in 40:
		mc._process(0.02)
	check(hit_fired[0], "attack emits its hit frame")
	mc.face_direction(Vector3(0, 0, -1))
	check_near(mc.rotation.y, 0.0, 0.01, "facing -Z gives yaw 0 (model faces -Z)")
	mc.queue_free()

func test_armor() -> void:
	check_eq(ArmorBuilder.parse_tier("netherite")["base"], "netherite", "tier parses")
	check_eq(ArmorBuilder.parse_tier("diamond_enchanted")["glint"], 1.0, "enchanted suffix sets glint")
	check_eq(ArmorBuilder.parse_tier("diamond_enchanted")["base"], "diamond", "enchanted suffix strips to base tier")

	var full := {"helmet": "netherite", "chestplate": "netherite", "leggings": "netherite", "boots": "netherite"}
	var leather := {"helmet": "leather", "chestplate": "leather", "leggings": "leather", "boots": "leather"}
	var netherite_pts := ArmorBuilder.armor_points(full)
	var leather_pts := ArmorBuilder.armor_points(leather)
	check(netherite_pts > leather_pts, "netherite scores above leather (%d > %d)" % [netherite_pts, leather_pts])
	check(ArmorBuilder.armor_points({}) == 0, "no armor scores zero")
	var enchanted := {"helmet": "netherite_enchanted", "chestplate": "netherite_enchanted",
		"leggings": "netherite_enchanted", "boots": "netherite_enchanted"}
	check(ArmorBuilder.armor_points(enchanted) > netherite_pts, "enchanting adds armor points")

	# every tier in the catalog must produce geometry and a real colour
	for tier in ArmorBuilder.TIER_COLORS.keys():
		var boxes := ArmorBuilder.boxes_for_set({"helmet": tier, "chestplate": tier, "leggings": tier, "boots": tier}, false)
		check(boxes.size() > 0, "%s armor produces boxes" % tier)
		check((boxes[0]["color"] as Color) != Color.MAGENTA, "%s has a defined colour" % tier)
	# helmet leaves the face open (no box covers the front-centre of the head)
	var helm := ArmorBuilder.boxes_for_set({"helmet": "iron"}, false)
	var covers_face := false
	for b in helm:
		var bmin: Vector3 = b["min"]
		var size: Vector3 = b["size"]
		if bmin.x < -1.0 and bmin.x + size.x > 1.0 and bmin.z < -4.0 and bmin.y < 28.0 and bmin.y + size.y > 26.0:
			if size.x > 4.0 and size.y > 3.0:
				covers_face = true
	check(not covers_face, "helmet does not seal the face shut")
	# slim characters get narrower pauldrons
	var slim_boxes := ArmorBuilder.boxes_for_set({"chestplate": "iron"}, true)
	var classic_boxes := ArmorBuilder.boxes_for_set({"chestplate": "iron"}, false)
	check(slim_boxes.size() == classic_boxes.size(), "slim and classic chestplates have the same piece count")

func test_weapons() -> void:
	for id in DataDB.weapons_catalog.get("weapons", {}).keys():
		var boxes := WeaponBuilder.boxes_for(String(id))
		check(boxes.size() > 0, "weapon %s builds geometry" % id)
	var mace := WeaponBuilder.build_mesh("netherite_mace_enchanted")
	check(mace.get_surface_count() == 1, "mace mesh builds")
	check(mace.surface_get_array_len(0) > 0, "mace mesh has vertices")
	var glinted := false
	for b in WeaponBuilder.boxes_for("netherite_mace_enchanted"):
		if float(b.get("glint", 0.0)) > 0.5:
			glinted = true
	check(glinted, "enchanted weapon carries the glint flag")

func test_damage() -> void:
	check_near(DamageCalc.apply_armor(100.0, 0.0, 0.0), 100.0, 0.001, "no armor = full damage")
	check_near(DamageCalc.apply_armor(100.0, 0.5, 0.0), 50.0, 0.001, "50% armor halves damage")
	check_near(DamageCalc.apply_armor(100.0, 0.5, 1.0), 100.0, 0.001, "full pierce ignores armor")
	check_near(DamageCalc.apply_armor(100.0, 0.5, 0.5), 75.0, 0.001, "half pierce halves the armor")
	check_near(DamageCalc.apply_armor(100.0, 0.95, 0.0), 10.0, 0.001, "armor floor is 10% of raw damage")
	check(DamageCalc.apply_armor(100.0, 1.5, 0.0) >= 10.0, "over-cap armor still lets damage through")

	var target := {"armor_pct": 0.5, "is_structure": false, "blocks_projectiles": false}
	var res := DamageCalc.resolve(100.0, "melee", 0.0, target)
	check_near(float(res["damage"]), 50.0, 0.001, "melee vs 50% armor")
	var true_res := DamageCalc.resolve(100.0, "true", 0.0, target)
	check_near(float(true_res["damage"]), 100.0, 0.001, "true damage ignores armor")
	var shield_target := {"armor_pct": 0.0, "is_structure": false, "blocks_projectiles": true}
	check_near(float(DamageCalc.resolve(100.0, "ranged", 0.0, shield_target)["damage"]), 65.0, 0.001, "shields blunt ranged damage")
	check_near(float(DamageCalc.resolve(100.0, "explosive", 0.0, shield_target)["damage"]), 130.0, 0.001, "explosives beat shields")
	var structure := {"armor_pct": 0.0, "is_structure": true, "blocks_projectiles": false}
	check_near(float(DamageCalc.resolve(100.0, "explosive", 0.0, structure)["damage"]), 150.0, 0.001, "explosives break walls faster")
	check_near(float(DamageCalc.resolve(100.0, "ranged", 0.0, structure)["damage"]), 40.0, 0.001, "arrows are poor against walls")

	var crit := DamageCalc.resolve(100.0, "melee", 1.0, {"armor_pct": 0.0}, 1.0, 3.0, 0.0)
	check(bool(crit["crit"]), "guaranteed crit rolls")
	check_near(float(crit["damage"]), 300.0, 0.001, "crit multiplier applies")
	var no_crit := DamageCalc.resolve(100.0, "melee", 1.0, {"armor_pct": 0.0}, 0.0, 3.0, 0.5)
	check(not bool(no_crit["crit"]), "zero crit chance never crits")

	check_near(DamageCalc.splash_falloff(0.0, 4.0), 1.0, 0.001, "splash centre is full damage")
	check_near(DamageCalc.splash_falloff(4.0, 4.0), 0.4, 0.001, "splash rim is 40%")
	check_near(DamageCalc.splash_falloff(2.0, 4.0), 0.7, 0.001, "splash midpoint interpolates")
	check_near(DamageCalc.mace_height_bonus(0.0), 1.0, 0.001, "no height, no mace bonus")
	check(DamageCalc.mace_height_bonus(3.0) > 1.0, "height gives a mace bonus")
	check_near(DamageCalc.mace_height_bonus(100.0), 2.5, 0.001, "mace bonus is capped")

func test_path() -> void:
	var p := MapPath.new()
	p.build(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)]))
	check_near(p.total_length, 20.0, 0.001, "path length is the sum of segments")
	check(p.position_at(0.0).is_equal_approx(Vector3(0, 0, 0)), "start of path")
	check(p.position_at(20.0).is_equal_approx(Vector3(10, 0, 10)), "end of path")
	check(p.position_at(5.0).is_equal_approx(Vector3(5, 0, 0)), "midpoint of first segment")
	check(p.position_at(15.0).is_equal_approx(Vector3(10, 0, 5)), "midpoint of second segment")
	check(p.position_at(-5.0).is_equal_approx(Vector3(0, 0, 0)), "before the start clamps")
	check(p.position_at(500.0).is_equal_approx(Vector3(10, 0, 10)), "past the end clamps")
	check(p.tangent_at(2.0).is_equal_approx(Vector3(1, 0, 0)), "tangent along +X")
	var offset := p.position_offset(5.0, 1.0)
	check(not offset.is_equal_approx(p.position_at(5.0)), "lateral offset moves off the centreline")
	check_near(offset.distance_to(p.position_at(5.0)), 1.0, 0.001, "lateral offset is exact")
	var ranges := p.ranges_within(Vector3(5, 0, 0), 2.0)
	check(ranges.size() >= 1, "range query finds the covered stretch")
	check_near(p.nearest_distance_to(Vector3(5, 0, 3)), 5.0, 0.6, "nearest distance projects onto the path")

func test_enemy_pool() -> void:
	var mgr := EnemyManager.new()
	add_child(mgr)
	var p := MapPath.new()
	p.build(PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)]))
	mgr.setup(p, DataDB.factions.get("cindercrest", {}), 200)
	check_eq(mgr.capacity, 200, "pool sized to request")
	check_eq(mgr.live_count, 0, "pool starts empty")

	var slot := mgr.spawn("chungie_t1", 0.0, 0.0)
	check(slot >= 0, "spawn returns a slot")
	check(mgr.is_alive(slot), "spawned enemy is alive")
	check_eq(mgr.live_count, 1, "live count tracks spawns")
	check_eq(mgr.type_id_of(slot), "chungie_t1", "type id round-trips")
	check(mgr.unit_position(slot).is_equal_approx(Vector3(0, 0, 0)), "spawn sits at the path start")

	mgr.dist[slot] = 50.0
	mgr._update_position(slot)
	check_near(mgr.unit_position(slot).x, 50.0, 0.01, "position follows path distance")

	# spatial query
	var found := mgr.query_range(Vector3(50, 0, 0), 3.0)
	check(found.has(slot), "spatial query finds a nearby enemy")
	var far := mgr.query_range(Vector3(0, 0, 0), 3.0)
	check_eq(far.size(), 0, "spatial query excludes distant enemies")

	# damage and death
	var dealt := mgr.damage(slot, 10.0, "true", 1.0, "test")
	check(dealt > 0.0, "damage is applied")
	mgr.damage(slot, 10000.0, "true", 1.0, "test")
	check(not mgr.is_alive(slot), "lethal damage kills")
	check_eq(mgr.live_count, 0, "live count decremented on death")

	# slot reuse
	var slot2 := mgr.spawn("chungie_t1", 0.0, 0.0)
	check(slot2 >= 0, "pool reuses freed slots")

	# pool exhaustion is graceful
	var spawned := 0
	for i in 500:
		if mgr.spawn("chungie_t1", 0.0, 0.0) >= 0:
			spawned += 1
	check(spawned <= 200, "pool never exceeds capacity (spawned %d)" % spawned)
	check(mgr.live_count <= mgr.capacity, "live count stays within capacity")

	# status effects
	mgr.clear_all()
	var s3 := mgr.spawn("chungie_t1", 0.0, 0.0)
	mgr.apply_slow(s3, 0.5, 2.0)
	check_near(mgr.slow_mult[s3], 0.5, 0.001, "slow applies")
	mgr.apply_stun(s3, 1.0)
	check(mgr.stun_until[s3] > mgr.time_now, "stun applies")
	mgr.dist[s3] = 40.0
	mgr.push_back(s3, 10.0)
	check_near(mgr.dist[s3], 30.0, 0.001, "knockback pushes back along the path")
	mgr.dist[s3] = 2.0
	mgr.push_back(s3, 10.0)
	check_near(mgr.dist[s3], 0.0, 0.001, "knockback never goes below the path start")

	# bosses resist control
	mgr.clear_all()
	var boss := mgr.spawn("saparata", 0.0, 0.0)
	mgr.apply_slow(boss, 0.2, 2.0)
	check(mgr.slow_mult[boss] > 0.2, "bosses resist slows")
	var before := mgr.dist[boss]
	mgr.dist[boss] = 40.0
	mgr.push_back(boss, 10.0)
	check_near(mgr.dist[boss], 40.0, 0.001, "bosses cannot be knocked back")
	mgr.queue_free()

func test_enemy_data() -> void:
	check(DataDB.enemies.size() >= 25, "at least 25 enemy definitions (%d)" % DataDB.enemies.size())
	for id in DataDB.enemies.keys():
		var d: Dictionary = DataDB.enemies[id]
		check(d.has("hp") and float(d["hp"]) > 0.0, "%s has positive HP" % id)
		check(d.has("speed"), "%s defines speed" % id)
		check(float(d.get("armor_pct", 0.0)) >= 0.0 and float(d.get("armor_pct", 0.0)) <= 0.95, "%s armor is in range" % id)
		check(String(d.get("codex", "")) != "", "%s has a codex entry" % id)
		check(String(d.get("gameplay_reason", "")) != "", "%s documents why it exists" % id)
		var down = d.get("downgrade_to", null)
		if down != null and String(down) != "":
			check(DataDB.enemies.has(String(down)), "%s downgrades into a real enemy (%s)" % [id, down])
	# every special enemy asked for by the design brief exists
	for required in ["elytra_glider", "archer", "potion_brewer", "tnt_runner", "speedster",
			"invisible_player", "builder", "shield_bearer", "assassin", "horse_rider",
			"minecart_rider", "totem_carrier", "wither", "paratrooper"]:
		check(DataDB.enemies.has(required), "special enemy '%s' is defined" % required)

func test_gear_progression() -> void:
	var chain := ["chungie_t7", "chungie_t6", "chungie_t5", "chungie_t4", "chungie_t3", "chungie_t2", "chungie_t1"]
	for id in chain:
		check(DataDB.enemies.has(id), "%s exists" % id)
	# HP, armor and reward must increase monotonically up the chain
	for i in range(chain.size() - 1, 0, -1):
		var lower: Dictionary = DataDB.enemies[chain[i]]
		var higher: Dictionary = DataDB.enemies[chain[i - 1]]
		check(float(higher["hp"]) > float(lower["hp"]), "%s has more HP than %s" % [chain[i - 1], chain[i]])
		check(float(higher.get("armor_pct", 0)) >= float(lower.get("armor_pct", 0)), "%s is at least as armored as %s" % [chain[i - 1], chain[i]])
		check(int(higher.get("reward", 0)) > int(lower.get("reward", 0)), "%s pays more than %s" % [chain[i - 1], chain[i]])
	# the chain links downward correctly
	for i in range(0, chain.size() - 1):
		check_eq(String(DataDB.enemies[chain[i]].get("downgrade_to", "")), chain[i + 1], "%s breaks into %s" % [chain[i], chain[i + 1]])
	check(DataDB.enemies["chungie_t1"].get("downgrade_to", null) == null, "the base Chungie has nothing left to break")
	# armor tiers must actually differ visually
	var t2_armor: Dictionary = DataDB.enemies["chungie_t2"].get("armor", {})
	var t5_armor: Dictionary = DataDB.enemies["chungie_t5"].get("armor", {})
	check(t2_armor.get("chestplate", "") != t5_armor.get("chestplate", ""), "iron and netherite Chungies wear different gear")
	check(ArmorBuilder.armor_points(t5_armor) > ArmorBuilder.armor_points(t2_armor), "netherite outscores iron")

	# a live gear break carries overflow damage into the next layer
	var mgr := EnemyManager.new()
	add_child(mgr)
	var p := MapPath.new()
	p.build(PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)]))
	mgr.setup(p, {}, 20)
	var slot := mgr.spawn("chungie_t2", 0.0, 0.0)
	var start_hp := mgr.hp[slot]
	mgr.damage(slot, start_hp + 5.0, "true", 1.0, "test")
	check(mgr.is_alive(slot), "breaking iron leaves the Chungie alive")
	check_eq(mgr.type_id_of(slot), "chungie_t1", "iron Chungie becomes a plain Chungie")
	check(mgr.hp[slot] < mgr.max_hp[slot], "overflow damage carried into the next layer")
	mgr.queue_free()

func test_tower_stats() -> void:
	check(DataDB.towers.size() >= 12, "at least 12 towers (%d)" % DataDB.towers.size())
	for id in DataDB.towers.keys():
		var d: Dictionary = DataDB.towers[id]
		check(int(d.get("cost", 0)) > 0, "%s costs something" % id)
		check(float(d.get("damage", 0)) >= 0.0, "%s has damage defined" % id)
		check(float(d.get("range", 0)) > 0.0, "%s has range" % id)
		check(float(d.get("attack_time", 0)) > 0.0, "%s has an attack interval" % id)
		check(String(d.get("lore", "")) != "", "%s has a lore description" % id)
		check(String(d.get("character", "")) != "", "%s maps to a character skin" % id)
		var paths: Array = d.get("paths", [])
		check_eq(paths.size(), 3, "%s has three upgrade paths" % id)
		for p in paths:
			var tiers: Array = (p as Dictionary).get("tiers", [])
			check_eq(tiers.size(), 4, "%s path '%s' has four tiers" % [id, String((p as Dictionary).get("name", ""))])
			var last_cost := 0
			for t in tiers:
				var cost := int((t as Dictionary).get("cost", 0))
				check(cost > last_cost, "%s tier costs increase (%d > %d)" % [id, cost, last_cost])
				last_cost = cost
				check(String((t as Dictionary).get("desc", "")) != "", "%s tier has a description" % id)

	# live stat resolution
	var mgr := EnemyManager.new()
	add_child(mgr)
	var p := MapPath.new()
	p.build(PackedVector3Array([Vector3(0, 0, 0), Vector3(50, 0, 0)]))
	mgr.setup(p, {}, 20)
	var proj := ProjectileManager.new()
	add_child(proj)
	proj.setup(mgr)
	var t := Tower.new()
	add_child(t)
	t.setup("royal_guard", DataDB.towers["royal_guard"], mgr, proj, null)
	var base_damage := t.damage
	var base_dps := t.dps()
	check(base_damage > 0.0, "tower resolves base damage")
	check(base_dps > 0.0, "tower reports DPS")
	t.tiers[0] = 1
	t.recompute_stats()
	check(t.damage > base_damage, "first upgrade raises damage (%.1f -> %.1f)" % [base_damage, t.damage])
	t.tiers[0] = 4
	t.recompute_stats()
	check(t.damage > base_damage * 2.0, "the signature upgrade is a large jump")
	check(t.dps() > base_dps, "DPS rises with upgrades")
	# external buffs
	t.tiers = [0, 0, 0]
	t.recompute_stats()
	var unbuffed := t.damage
	t.external_mults = {"damage": 1.5, "rate": 1.0, "range_add": 0.0, "armor_pen": 0.0}
	t.recompute_stats()
	check_near(t.damage, unbuffed * 1.5, 0.01, "aura damage multiplier applies")
	# sell value
	t.total_spent = 1000
	check_eq(t.sell_value(), int(round((int(DataDB.towers["royal_guard"]["cost"]) + 1000) * 0.75)), "sell returns 75%")
	t.queue_free()
	proj.queue_free()
	mgr.queue_free()

func test_gear_rule() -> void:
	var mgr := EnemyManager.new()
	add_child(mgr)
	var p := MapPath.new()
	p.build(PackedVector3Array([Vector3(0, 0, 0), Vector3(50, 0, 0)]))
	mgr.setup(p, {}, 10)
	var proj := ProjectileManager.new()
	add_child(proj)
	proj.setup(mgr)
	var t := Tower.new()
	add_child(t)
	t.setup("mapicc", DataDB.towers["mapicc"], mgr, proj, null)

	check(t.can_upgrade(0), "a fresh tower can start any path")
	t.tiers = [4, 0, 0]
	check(not t.can_upgrade(0), "a maxed path cannot go past tier 4")
	check(t.can_upgrade(1), "a second path may be started")
	t.tiers = [4, 2, 0]
	check(not t.can_upgrade(1), "the second path stops at tier 2")
	check(not t.can_upgrade(2), "a third path cannot be started")
	t.tiers = [2, 2, 0]
	check(t.can_upgrade(0), "two paths at tier 2 can still advance one of them")
	t.tiers = [3, 0, 0]
	check(t.can_upgrade(1), "a second path may start while the first is above tier 2")
	t.tiers = [3, 2, 0]
	check(not t.can_upgrade(1), "and it still stops at 2")
	t.tiers = [1, 1, 0]
	check(not t.can_upgrade(2), "no third path once two are open")
	t.queue_free()
	proj.queue_free()
	mgr.queue_free()

func test_hero_data() -> void:
	check_eq(DataDB.heroes.size(), 4, "exactly four heroes")
	for id in ["wemmbu", "flamefrags", "parrotx2", "spokeishere"]:
		check(DataDB.heroes.has(id), "hero %s exists" % id)
	for id in DataDB.heroes.keys():
		var h: Dictionary = DataDB.heroes[id]
		var abilities: Array = h.get("abilities", [])
		check_eq(abilities.size(), 4, "%s has three actives and an ultimate" % id)
		var slots: Array = []
		for a in abilities:
			slots.append(int(a.get("slot", -1)))
			check(float(a.get("cooldown", 0)) > 0.0, "%s ability '%s' has a cooldown" % [id, String(a.get("name", ""))])
			check(String(a.get("desc", "")) != "", "%s ability '%s' is described" % [id, String(a.get("name", ""))])
			check(not (a.get("effect", {}) as Dictionary).is_empty(), "%s ability '%s' has an effect" % [id, String(a.get("name", ""))])
		slots.sort()
		check_eq(slots, [0, 1, 2, 3], "%s ability slots are 0-3" % id)
		check(int((abilities[3] as Dictionary).get("cooldown", 0)) >= 60, "%s ultimate has a long cooldown" % id)
		check((h.get("passives", []) as Array).size() >= 3, "%s has at least three passives" % id)
		check(String(h.get("lore", "")) != "", "%s has lore" % id)
		check(String(h.get("summary", "")) != "", "%s has a summary" % id)
		check((h.get("strengths", []) as Array).size() > 0, "%s lists strengths" % id)
		check((h.get("weaknesses", []) as Array).size() > 0, "%s lists weaknesses" % id)
	# XP curve rises with level
	check(Hero.xp_for_level(1) < Hero.xp_for_level(10), "XP curve grows with level")
	check(Hero.xp_for_level(1) > 0, "level 1 needs positive XP")

func test_waves() -> void:
	for map_id in DataDB.maps.keys():
		var wave_data: Dictionary = DataDB.waves.get(map_id, {})
		var waves: Array = wave_data.get("waves", [])
		check(waves.size() >= 10, "%s has at least 10 waves (%d)" % [map_id, waves.size()])
		var total_enemies := 0
		var prev_strength := 0.0
		var strengths: Array = []
		for i in waves.size():
			var w: Dictionary = waves[i]
			check(String(w.get("name", "")) != "", "%s wave %d is named" % [map_id, i + 1])
			check(int(w.get("reward", 0)) > 0, "%s wave %d pays a reward" % [map_id, i + 1])
			var strength := 0.0
			for g in w.get("groups", []):
				var enemy_id := String(g.get("enemy", ""))
				check(DataDB.enemies.has(enemy_id), "%s wave %d references a real enemy (%s)" % [map_id, i + 1, enemy_id])
				var count := int(g.get("count", 0))
				check(count > 0, "%s wave %d group has a positive count" % [map_id, i + 1])
				check(float(g.get("interval", 1.0)) > 0.0, "%s wave %d group has a spawn interval" % [map_id, i + 1])
				total_enemies += count
				if DataDB.enemies.has(enemy_id):
					strength += float(DataDB.enemies[enemy_id].get("hp", 0)) * count
			strengths.append(strength)
			for e in w.get("events", []):
				check(String(e.get("type", "")) != "", "%s wave %d event has a type" % [map_id, i + 1])
				check(e.has("at"), "%s wave %d event has a time" % [map_id, i + 1])
		check(total_enemies > 100, "%s spawns a meaningful number of enemies (%d)" % [map_id, total_enemies])
		# difficulty must trend upward: the last third should be much harder than the first third
		var third := maxi(1, strengths.size() / 3)
		var early := 0.0
		var late := 0.0
		for i in third:
			early += float(strengths[i])
		for i in range(strengths.size() - third, strengths.size()):
			late += float(strengths[i])
		check(late > early * 2.0, "%s difficulty ramps up (early %.0f -> late %.0f)" % [map_id, early, late])
	# the campaign map ends on a boss wave
	var ff: Array = DataDB.waves.get("fort_feather", {}).get("waves", [])
	check(bool((ff[ff.size() - 1] as Dictionary).get("boss", false)), "Fort Feather ends with a boss wave")

func test_boss_phases() -> void:
	check_eq(SaparataEncounter.PHASES.size(), 5, "Saparata has five phases")
	for p in SaparataEncounter.PHASES:
		check(String(p["name"]) != "", "phase is named")
		check(String(p["desc"]) != "", "phase is described")
	var bosses: Array = DataDB.bosses.values() if DataDB.bosses is Dictionary else []
	check(DataDB.bosses.has("saparata"), "Saparata boss data exists")
	var sap: Dictionary = DataDB.bosses.get("saparata", {})
	check_eq((sap.get("phases", []) as Array).size(), 5, "boss data lists five phases")
	for p in sap.get("phases", []):
		check(String(p.get("basis", "")) != "", "phase '%s' cites its basis in the story" % String(p.get("name", "")))
		check(String(p.get("mechanic", "")) != "", "phase '%s' documents its mechanic" % String(p.get("name", "")))
	check(DataDB.enemies.has(String(sap.get("enemy", ""))), "boss maps to an enemy definition")
	check(DataDB.enemies.has(String(sap.get("mini_boss", ""))), "mini-boss maps to an enemy definition")
	var boss_enemy: Dictionary = DataDB.enemies.get("saparata", {})
	check(float(boss_enemy.get("hp", 0)) > 1000.0, "the boss has boss-sized health")
	check((boss_enemy.get("flags", []) as Array).has("boss"), "the boss carries the boss flag")

func test_currency() -> void:
	var before := GameState.emeralds
	GameState.emeralds = 0
	GameState.run_stats = {}
	GameState.add_emeralds(100)
	check_eq(GameState.emeralds, 100, "emeralds are added")
	check(GameState.can_afford(100), "exact amount is affordable")
	check(not GameState.can_afford(101), "over budget is not affordable")
	check(GameState.spend(60), "spending succeeds when affordable")
	check_eq(GameState.emeralds, 40, "spending deducts")
	check(not GameState.spend(100), "spending fails when unaffordable")
	check_eq(GameState.emeralds, 40, "a failed spend changes nothing")
	check_eq(int(GameState.run_stats.get("emeralds_earned", 0)), 100, "earnings are tracked")
	check_eq(int(GameState.run_stats.get("emeralds_spent", 0)), 60, "spending is tracked")
	# lives
	GameState.max_lives = 100
	GameState.lives = 100
	GameState.run_active = true
	GameState.damage_base(10)
	check_eq(GameState.lives, 90, "leaks cost lives")
	GameState.heal_base(5)
	check_eq(GameState.lives, 95, "repairs restore lives")
	GameState.heal_base(1000)
	check_eq(GameState.lives, 100, "healing is capped at max")
	GameState.damage_base(1000)
	check_eq(GameState.lives, 0, "lives cannot go negative")
	check(not GameState.run_active, "running out of lives ends the run")
	# difficulty
	GameState.difficulty = "hard"
	check(GameState.difficulty_mult("enemy_hp") > 1.0, "hard raises enemy HP")
	GameState.difficulty = "easy"
	check(GameState.difficulty_mult("enemy_hp") < 1.0, "easy lowers enemy HP")
	GameState.difficulty = "normal"
	check_near(GameState.difficulty_mult("enemy_hp"), 1.0, 0.001, "normal is the baseline")
	GameState.emeralds = before

func test_save() -> void:
	var backup := SaveSystem.data.duplicate(true)
	SaveSystem.data = SaveSystem.default_data()
	check(SaveSystem.data.has("version"), "save has a version")
	check_eq((SaveSystem.data["unlocked_heroes"] as Array).size(), 4, "all four heroes start unlocked")
	var meta := SaveSystem.hero_meta("wemmbu")
	check_eq(int(meta["level"]), 1, "hero meta starts at level 1")
	var rec := SaveSystem.map_record("fort_feather")
	check_eq(bool(rec["completed"]), false, "map starts uncompleted")
	SaveSystem.record_run_result("fort_feather", "wemmbu", true, 25, 500, 200)
	check(bool(SaveSystem.map_record("fort_feather")["completed"]), "a win completes the map")
	check_eq(int(SaveSystem.map_record("fort_feather")["best_waves"]), 25, "best wave recorded")
	check(int(SaveSystem.hero_meta("wemmbu")["level"]) > 1, "hero meta levels up from XP")
	check_eq(int(SaveSystem.data["xp_bottles"]), 200, "bottles are banked")
	SaveSystem.unlock_codex("test_entry")
	check(SaveSystem.is_codex_unlocked("test_entry"), "codex unlocks persist in memory")
	check(SaveSystem.save_game(), "save writes to disk")
	var written := SaveSystem.data.duplicate(true)
	SaveSystem.data = {}
	SaveSystem.load_game()
	check_eq(int(SaveSystem.data.get("xp_bottles", -1)), int(written["xp_bottles"]), "save round-trips through disk")
	check(SaveSystem.is_codex_unlocked("test_entry"), "codex survives a reload")
	check(SaveSystem.data.has("settings"), "settings survive a reload")
	SaveSystem.data = backup
	SaveSystem.save_game()

func test_relationships() -> void:
	check(DataDB.relationships.size() >= 10, "at least 10 relationships (%d)" % DataDB.relationships.size())
	var ids: Dictionary = {}
	for r in DataDB.relationships:
		var rid := String(r.get("id", ""))
		check(rid != "", "relationship has an id")
		check(not ids.has(rid), "relationship id '%s' is unique" % rid)
		ids[rid] = true
		var a := String(r.get("a", ""))
		var b := String(r.get("b", ""))
		check(a != "" and b != "", "relationship %s names both members" % rid)
		check(a != b, "relationship %s links two different characters" % rid)
		var a_known: bool = DataDB.towers.has(a) or DataDB.heroes.has(a)
		var b_known: bool = DataDB.towers.has(b) or DataDB.heroes.has(b)
		check(a_known, "relationship %s member '%s' is a placeable character" % [rid, a])
		check(b_known, "relationship %s member '%s' is a placeable character" % [rid, b])
		check(String(r.get("basis", "")) != "", "relationship %s cites its basis in the story" % rid)
		check((r.get("sources", []) as Array).size() > 0, "relationship %s cites sources" % rid)
		check(String(r.get("confidence", "")) != "", "relationship %s states its confidence" % rid)
		check(not (r.get("effects", {}) as Dictionary).is_empty(), "relationship %s has an effect" % rid)

func test_lore() -> void:
	for category in ["characters", "arcs", "factions", "locations", "events", "weapons", "bosses"]:
		var entries: Array = DataDB.lore.get(category, [])
		check(entries.size() > 0, "lore category '%s' is populated (%d)" % [category, entries.size()])
		for e in entries:
			var eid := String(e.get("id", ""))
			check(eid != "", "%s entry has an id" % category)
			check(String(e.get("confidence", "")) != "", "%s/%s states a confidence level" % [category, eid])
			var srcs = e.get("research_sources", e.get("sources", []))
			check(typeof(srcs) == TYPE_ARRAY and (srcs as Array).size() > 0, "%s/%s cites at least one source" % [category, eid])
	# the four protagonists must be present and flagged
	for id in ["wemmbu", "flamefrags", "parrotx2", "spokeishere"]:
		var entry := DataDB.get_lore_entry("characters", id)
		check(not entry.is_empty(), "lore has %s" % id)
		check(bool(entry.get("protagonist", false)), "%s is flagged as a protagonist" % id)
	# Saparata must be an antagonist with the boss role
	var sap := DataDB.get_lore_entry("characters", "saparata")
	check(bool(sap.get("antagonist", false)), "Saparata is flagged as an antagonist")
	# arcs that overlap must say so, rather than being forced into one line
	var concurrent := 0
	for a in DataDB.lore.get("arcs", []):
		if (a.get("concurrent_with", []) as Array).size() > 0:
			concurrent += 1
	check(concurrent >= 3, "overlapping arcs are recorded as concurrent (%d)" % concurrent)
	# no entry may claim a theory as canon
	for e in DataDB.lore.get("characters", []):
		var c := String(e.get("confidence", ""))
		check(c in ["canon_confirmed", "supported", "uncertain", "fan_theory"],
			"%s uses a known confidence tier (%s)" % [String(e.get("id", "")), c])
