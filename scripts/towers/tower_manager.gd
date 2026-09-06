class_name TowerManager
extends Node3D
## Owns placement, selection, aura/relationship recalculation and tower-spawned walls.

signal selection_changed(tower)

var enemies: EnemyManager
var projectiles: ProjectileManager
var towers: Array[Tower] = []
var zones: Array = []                    # {pos, radius, type, elevation, occupied_by}
var selected: Tower = null
var hero = null                          # Hero (set by GameController)
var relationship_defs: Array = []
var active_relationships: Array = []     # {id, name, a, b, flavor}
var _stun_immune: Dictionary = {}
var _discounts: Dictionary = {}
var _repair_bonus: Dictionary = {}
var leak_reduction: int = 0
var global_bounty: int = 0
var _vulnerability_sources: Array = []   # towers granting a vulnerability aura

func setup(enemy_mgr: EnemyManager, proj: ProjectileManager, zone_data: Array) -> void:
	enemies = enemy_mgr
	projectiles = proj
	zones = []
	for z in zone_data:
		var pos_arr: Array = z.get("pos", [0, 0, 0])
		zones.append({
			"pos": Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			"radius": float(z.get("radius", 3.0)),
			"type": String(z.get("type", "ground")),
			"elevation": float(z.get("elevation", 0.0)),
			"occupied_by": null,
		})
	relationship_defs = DataDB.relationships
	EventBus.enemy_killed.connect(_on_enemy_killed)

# ================================================================================================
# Placement
# ================================================================================================

func zone_at(point: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in zones.size():
		var z: Dictionary = zones[i]
		var d: float = Vector2(point.x - (z["pos"] as Vector3).x, point.z - (z["pos"] as Vector3).z).length()
		if d <= float(z["radius"]) and d < best_d:
			best_d = d
			best = i
	return best

func can_place_at(zone_index: int) -> bool:
	if zone_index < 0 or zone_index >= zones.size():
		return false
	return zones[zone_index]["occupied_by"] == null

func place(tower_id: String, zone_index: int, free: bool = false) -> Tower:
	if not can_place_at(zone_index):
		return null
	var def: Dictionary = DataDB.towers.get(tower_id, {})
	if def.is_empty():
		push_warning("[TowerManager] unknown tower: %s" % tower_id)
		return null
	var cost := int(def.get("cost", 0))
	if not free and not GameState.spend(cost):
		return null
	var z: Dictionary = zones[zone_index]
	var t := Tower.new()
	add_child(t)
	t.setup(tower_id, def, enemies, projectiles, self)
	t.position = (z["pos"] as Vector3) + Vector3(0, float(z["elevation"]), 0)
	t.elevation = float(z["elevation"])
	t.zone_index = zone_index
	t.placed_position = t.position
	t.total_spent = 0 if free else 0
	z["occupied_by"] = t
	towers.append(t)
	GameState.run_stats["towers_built"] = int(GameState.run_stats.get("towers_built", 0)) + 1
	refresh_auras()
	AudioMgr.play_sfx("place", -4.0)
	EventBus.tower_placed.emit(t)
	return t

func sell(t: Tower) -> void:
	if t == null or not is_instance_valid(t):
		return
	GameState.add_emeralds(t.sell_value())
	if t.zone_index >= 0 and t.zone_index < zones.size():
		zones[t.zone_index]["occupied_by"] = null
	towers.erase(t)
	if selected == t:
		select(null)
	EventBus.tower_sold.emit(t)
	t.queue_free()
	call_deferred("refresh_auras")
	AudioMgr.play_sfx("sell", -4.0)

func select(t) -> void:
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = t
	if is_instance_valid(t):
		t.set_selected(true)
		EventBus.tower_selected.emit(t)
	else:
		EventBus.tower_deselected.emit()
	selection_changed.emit(t)

func tower_at_screen(camera: Camera3D, screen_pos: Vector2) -> Tower:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best: Tower = null
	var best_t := INF
	for t in towers:
		if not is_instance_valid(t):
			continue
		var centre: Vector3 = t.global_position + Vector3(0, 0.9, 0)
		var to_centre := centre - from
		var proj := to_centre.dot(dir)
		if proj < 0.0:
			continue
		var perp := (to_centre - dir * proj).length()
		if perp < 0.85 and proj < best_t:
			best_t = proj
			best = t
	return best

func show_all_ranges(v: bool) -> void:
	for t in towers:
		if is_instance_valid(t):
			t.show_range(v)

# ================================================================================================
# Auras and relationships
# ================================================================================================

func refresh_auras() -> void:
	_stun_immune.clear()
	_discounts.clear()
	_repair_bonus.clear()
	_vulnerability_sources.clear()
	leak_reduction = 0
	global_bounty = 0
	for t in towers:
		if is_instance_valid(t):
			t.external_mults = {"damage": 1.0, "rate": 1.0, "range_add": 0.0, "armor_pen": 0.0}
	# 1. tower auras
	for src in towers:
		if not is_instance_valid(src):
			continue
		var s: Dictionary = src.specials
		leak_reduction += int(s.get("leak_reduction", 0))
		global_bounty += int(s.get("global_bounty", 0))
		var radius := float(s.get("buff_radius", 0.0))
		if radius <= 0.0:
			continue
		for dst in towers:
			if not is_instance_valid(dst) or dst == src:
				continue
			if src.global_position.distance_to(dst.global_position) > radius:
				continue
			if s.has("buff_filter") and dst.tower_id != String(s["buff_filter"]):
				continue
			var m: Dictionary = dst.external_mults
			m["damage"] = float(m["damage"]) * (1.0 + float(s.get("buff_damage", 0.0)))
			m["rate"] = float(m["rate"]) * (1.0 - float(s.get("buff_rate", 0.0)))
			m["range_add"] = float(m["range_add"]) + float(s.get("buff_range", 0.0))
			m["armor_pen"] = float(m["armor_pen"]) + float(s.get("buff_armor_pen", 0.0))
			if s.has("detect_aura"):
				dst.detect_invisible = true
			if s.has("stun_immunity_aura"):
				_stun_immune[dst] = true
			if s.has("discount"):
				_discounts[dst] = maxf(float(_discounts.get(dst, 0.0)), float(s.get("discount", 0.0)))
		if s.has("vulnerability") or s.has("boss_vulnerability"):
			_vulnerability_sources.append(src)
	# 2. hero aura
	if hero != null and is_instance_valid(hero):
		var ha: Dictionary = hero.aura_effects()
		var hr := float(ha.get("radius", 0.0))
		if hr > 0.0:
			for dst in towers:
				if is_instance_valid(dst) and hero.global_position.distance_to(dst.global_position) <= hr:
					var m: Dictionary = dst.external_mults
					m["damage"] = float(m["damage"]) * (1.0 + float(ha.get("damage", 0.0)))
					m["rate"] = float(m["rate"]) * (1.0 - float(ha.get("rate", 0.0)))
					m["range_add"] = float(m["range_add"]) + float(ha.get("range_add", 0.0))
					if ha.get("detect", false):
						dst.detect_invisible = true
	# 3. global hero buffs (Royal Decree / ultimates)
	if hero != null and is_instance_valid(hero):
		var gb: Dictionary = hero.global_buffs()
		if not gb.is_empty():
			for dst in towers:
				if not is_instance_valid(dst):
					continue
				var m: Dictionary = dst.external_mults
				m["damage"] = float(m["damage"]) * float(gb.get("damage_mult", 1.0))
				m["rate"] = float(m["rate"]) * float(gb.get("rate_mult", 1.0))
				m["range_add"] = float(m["range_add"]) + float(gb.get("range_add", 0.0))
	# 4. relationships
	_apply_relationships()
	for t in towers:
		if is_instance_valid(t):
			t.recompute_stats()

func _apply_relationships() -> void:
	var previous: Array = active_relationships.duplicate()
	active_relationships.clear()
	var present: Dictionary = {}
	for t in towers:
		if is_instance_valid(t):
			present[t.tower_id] = t
	var hero_id := ""
	if hero != null and is_instance_valid(hero):
		hero_id = hero.hero_id
		if not present.has(hero_id):
			present[hero_id] = hero
	for rel in relationship_defs:
		var a := String(rel.get("a", ""))
		var b := String(rel.get("b", ""))
		if not present.has(a) or not present.has(b):
			continue
		var eff: Dictionary = rel.get("effects", {})
		var applies := String(eff.get("applies_to", "both"))
		var targets: Array = []
		if applies == "both":
			targets = [present[a], present[b]]
		elif applies == "a":
			targets = [present[a]]
		else:
			targets = [present[b]]
		for node in targets:
			if node is Tower:
				var m: Dictionary = (node as Tower).external_mults
				m["damage"] = float(m["damage"]) * float(eff.get("damage_mult", 1.0))
				m["rate"] = float(m["rate"]) * float(eff.get("rate_mult", 1.0))
				m["range_add"] = float(m["range_add"]) + float(eff.get("range_add", 0.0))
				m["armor_pen"] = float(m["armor_pen"]) + float(eff.get("armor_pen_add", 0.0))
				if eff.has("repair_bonus"):
					_repair_bonus[node] = int(_repair_bonus.get(node, 0)) + int(eff["repair_bonus"])
			elif node != null and node.has_method("apply_relationship"):
				node.apply_relationship(eff)
		if eff.has("leak_reduction"):
			leak_reduction += int(eff["leak_reduction"])
		if eff.has("income_add"):
			# a one-off recurring bonus is handled by the pair's own income tick; record for UI
			pass
		active_relationships.append({
			"id": String(rel.get("id", "")), "name": String(rel.get("name", "")),
			"a": a, "b": b, "flavor": String(rel.get("flavor", "")), "basis": String(rel.get("basis", "")),
		})
	# announce newly formed bonds
	var known: Dictionary = {}
	for r in previous:
		known[r["id"]] = true
	for r in active_relationships:
		if not known.has(r["id"]):
			EventBus.relationship_activated.emit(r["a"], r["b"], r)
			EventBus.announce.emit(String(r["name"]), String(r["flavor"]), 2.6)
			AudioMgr.play_sfx("relationship", -3.0)
	# push names down to towers for the info panel
	var by_tower: Dictionary = {}
	for r in active_relationships:
		for id in [r["a"], r["b"]]:
			if not by_tower.has(id):
				by_tower[id] = []
			(by_tower[id] as Array).append(r["name"])
	for t in towers:
		if is_instance_valid(t):
			var names: Array[String] = []
			for n in by_tower.get(t.tower_id, []):
				names.append(String(n))
			t.set_relationship_names(names)

func has_stun_immunity(t: Tower) -> bool:
	return _stun_immune.has(t)

func discount_for(t: Tower) -> float:
	return float(_discounts.get(t, 0.0))

func repair_bonus_for(t: Tower) -> int:
	return int(_repair_bonus.get(t, 0))

## Extra damage multiplier applied to an enemy standing inside a vulnerability aura.
func vulnerability_at(position: Vector3, is_boss: bool) -> float:
	var mult := 1.0
	for src in _vulnerability_sources:
		if not is_instance_valid(src):
			continue
		var radius: float = maxf(float(src.specials.get("buff_radius", 0.0)), src.range_r)
		if src.global_position.distance_to(position) <= radius:
			mult += float(src.specials.get("vulnerability", 0.0))
			if is_boss:
				mult += float(src.specials.get("boss_vulnerability", 0.0))
	return mult

func spawn_wall(source: Tower, hp: float, thorns: float) -> void:
	if enemies == null or enemies.path == null:
		return
	var d := enemies.path.nearest_distance_to(source.global_position)
	if d <= 1.0 or d >= enemies.path.total_length - 2.0:
		return
	var slot := enemies.spawn("cobble_wall", d, 0.0)
	if slot >= 0:
		enemies.hp[slot] = hp
		enemies.max_hp[slot] = hp

func _on_enemy_killed(_slot: int, _type_id: String, killer_id: String) -> void:
	if global_bounty > 0:
		GameState.add_emeralds(global_bounty)
	for t in towers:
		if is_instance_valid(t) and t.tower_id == killer_id:
			t.on_enemy_killed_by(killer_id)

func on_wave_cleared() -> void:
	for t in towers:
		if is_instance_valid(t):
			t.on_wave_cleared()

func clear_all() -> void:
	for t in towers:
		if is_instance_valid(t):
			t.queue_free()
	towers.clear()
	for z in zones:
		z["occupied_by"] = null
	selected = null
