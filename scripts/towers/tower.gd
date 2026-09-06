class_name Tower
extends Node3D
## A placed character: visual MinecraftCharacter + stats resolved from its data definition and upgrades.
## Towers are ordinary nodes (there are tens of them, not thousands) while enemies are pooled rows.

signal stats_changed()

const TARGETING_MODES := ["first", "last", "close", "strong", "weak"]

var def: Dictionary = {}
var tower_id: String = ""
var display_name: String = ""
var visual: MinecraftCharacter
var enemies: EnemyManager
var projectiles: ProjectileManager
var manager                                    # TowerManager (avoids a cyclic class reference)

# upgrade state: tier per path
var tiers: Array[int] = [0, 0, 0]
var total_spent: int = 0
var targeting: String = "first"
var placed_position: Vector3 = Vector3.ZERO
var elevation: float = 0.0
var zone_index: int = -1

# resolved stats
var damage: float = 10.0
var range_r: float = 6.0
var attack_time: float = 1.0
var pierce: int = 1
var splash: float = 0.0
var armor_pen: float = 0.0
var crit_chance: float = 0.0
var crit_mult: float = 2.0
var damage_type: String = "melee"
var projectile_kind: String = "melee_swing"
var attack_style: String = "slash"
var detect_invisible: bool = false
var hit_air: bool = false
var weapon: String = ""
var armor_set: Dictionary = {}
var specials: Dictionary = {}                  # flag -> value

# runtime
var cooldown: float = 0.0
var stun_until: float = 0.0
var income_timer: float = 0.0
var repair_timer: float = 0.0
var block_timer: float = 0.0
var wall_timer: float = 0.0
var mercenary_pause_until: float = 0.0
var current_target: int = -1
var time_now: float = 0.0
var kills: int = 0
var damage_dealt: float = 0.0
var external_mults: Dictionary = {}            # from auras/relationships: damage, rate, range, armor_pen
var selected: bool = false
var range_indicator: MeshInstance3D
var _pending_shots: int = 0
var _relationship_names: Array[String] = []

func setup(id: String, definition: Dictionary, enemy_mgr: EnemyManager, proj: ProjectileManager, mgr) -> void:
	tower_id = id
	def = definition
	enemies = enemy_mgr
	projectiles = proj
	manager = mgr
	display_name = String(def.get("name", id))
	targeting = String(def.get("targeting", "first"))
	visual = MinecraftCharacter.new()
	add_child(visual)
	recompute_stats()
	visual.setup(SkinLibrary.get_skin(String(def.get("character", id))), armor_set, weapon)
	visual.attack_style = attack_style
	visual.attack_hit.connect(_on_attack_hit)
	visual.play("idle")
	_build_range_indicator()

# ================================================================================================
# Stats
# ================================================================================================

func recompute_stats() -> void:
	damage = float(def.get("damage", 10))
	range_r = float(def.get("range", 6.0))
	attack_time = float(def.get("attack_time", 1.0))
	pierce = int(def.get("pierce", 1))
	splash = float(def.get("splash", 0.0))
	armor_pen = float(def.get("armor_pen", 0.0))
	crit_chance = 0.0
	crit_mult = 2.0
	damage_type = String(def.get("damage_type", "melee"))
	projectile_kind = String(def.get("projectile", "melee_swing"))
	attack_style = String(def.get("attack_style", "slash"))
	detect_invisible = bool(def.get("detect_invisible", false))
	hit_air = bool(def.get("hit_air", false))
	weapon = String(def.get("weapon", ""))
	armor_set = (def.get("armor", {}) as Dictionary).duplicate()
	specials = {}
	if def.has("income"):
		specials["income"] = true
		specials["income_add"] = float(def.get("income", 0))
		specials["income_interval"] = float(def.get("income_interval", 8.0))
	if bool(def.get("mercenary", false)):
		specials["mercenary"] = true

	var rate_mult := 1.0
	var damage_mult := 1.0
	var range_mult := 1.0
	var paths: Array = def.get("paths", [])
	for p in range(min(3, paths.size())):
		var tier_list: Array = (paths[p] as Dictionary).get("tiers", [])
		for t in range(min(tiers[p], tier_list.size())):
			var eff: Dictionary = (tier_list[t] as Dictionary).get("effects", {})
			damage += float(eff.get("damage_add", 0.0))
			damage_mult *= float(eff.get("damage_mult", 1.0))
			range_r += float(eff.get("range_add", 0.0))
			range_mult *= float(eff.get("range_mult", 1.0))
			rate_mult *= float(eff.get("rate_mult", 1.0))
			pierce += int(eff.get("pierce_add", 0))
			splash += float(eff.get("splash_add", 0.0))
			armor_pen += float(eff.get("armor_pen_add", 0.0))
			crit_chance += float(eff.get("crit_chance_add", 0.0))
			crit_mult += float(eff.get("crit_mult_add", 0.0))
			if eff.has("weapon"):
				weapon = String(eff["weapon"])
			if eff.has("armor"):
				armor_set.merge(eff["armor"] as Dictionary, true)
			if eff.has("damage_type"):
				damage_type = String(eff["damage_type"])
			if eff.has("projectile"):
				projectile_kind = String(eff["projectile"])
			if eff.has("attack_style"):
				attack_style = String(eff["attack_style"])
			for key in eff.keys():
				var k := String(key)
				if k == "special":
					for s in (eff[key] as Array):
						specials[String(s)] = true
				elif k.begins_with("buff_") or k in ["income_add", "income_interval", "income_interval_mult", "wave_bonus",
						"bounty", "global_bounty", "execute_threshold", "boss_damage_mult", "slow_mult", "slow_duration",
						"stun_duration", "knockback", "chain", "extra_shots", "extra_attackers", "extra_attacker_mult",
						"vulnerability", "armor_strip", "repair_amount", "repair_interval", "leak_reduction",
						"lives_on_wave", "wall_hp", "wall_cooldown", "wall_thorns", "block_duration", "block_cooldown",
						"block_radius", "desperation_mult", "mark_vulnerability", "mark_spread", "discount",
						"boss_vulnerability", "xp_bonus"]:
					if k == "income_interval_mult":
						specials["income_interval"] = float(specials.get("income_interval", 8.0)) * float(eff[key])
					else:
						specials[k] = eff[key]
	damage *= damage_mult
	range_r *= range_mult
	attack_time *= rate_mult
	if specials.has("detect_invisible"):
		detect_invisible = true
	if specials.has("hit_air"):
		hit_air = true

	# external (aura / relationship) multipliers
	damage *= float(external_mults.get("damage", 1.0))
	attack_time *= float(external_mults.get("rate", 1.0))
	range_r += float(external_mults.get("range_add", 0.0))
	armor_pen += float(external_mults.get("armor_pen", 0.0))
	if specials.has("desperation") and GameState.max_lives > 0:
		if float(GameState.lives) / float(GameState.max_lives) < 0.5:
			damage *= 1.0 + float(specials.get("desperation_mult", 0.25))
	attack_time = maxf(0.05, attack_time)
	if is_instance_valid(visual):
		visual.attack_style = attack_style
		if visual.held_id != weapon:
			visual.set_held(weapon)
		if visual.armor != armor_set:
			visual.set_armor(armor_set)
	_update_range_indicator()
	stats_changed.emit()

func dps() -> float:
	var per_hit: float = damage * (1.0 + crit_chance * (crit_mult - 1.0))
	var targets := maxf(1.0, float(pierce)) if splash <= 0.0 else maxf(2.0, float(pierce))
	return per_hit * targets / attack_time

# ================================================================================================
# Upgrades
# ================================================================================================

## The Gear Rule: one path may reach 4, a second may reach 2, the third stays at 0.
func can_upgrade(path: int) -> bool:
	if path < 0 or path > 2:
		return false
	var paths: Array = def.get("paths", [])
	if path >= paths.size():
		return false
	var tier_list: Array = (paths[path] as Dictionary).get("tiers", [])
	if tiers[path] >= tier_list.size():
		return false
	var next := tiers[path] + 1
	var others: Array[int] = []
	for i in 3:
		if i != path:
			others.append(tiers[i])
	others.sort()
	others.reverse()
	var highest_other: int = others[0] if others.size() > 0 else 0
	var second_other: int = others[1] if others.size() > 1 else 0
	if second_other > 0:
		return false                     # a third path already started
	if next > 2 and highest_other > 2:
		return false                     # only one path may exceed tier 2
	if next > 2 and highest_other > 0 and highest_other > 2:
		return false
	if highest_other > 2 and next > 2:
		return false
	if next > 2:
		return highest_other <= 2
	if highest_other > 2:
		return next <= 2
	return true

func upgrade_cost(path: int) -> int:
	var paths: Array = def.get("paths", [])
	if path >= paths.size():
		return 0
	var tier_list: Array = (paths[path] as Dictionary).get("tiers", [])
	if tiers[path] >= tier_list.size():
		return 0
	var base := int((tier_list[tiers[path]] as Dictionary).get("cost", 0))
	var discount := 0.0
	if manager != null:
		discount = manager.discount_for(self)
	return int(round(base * (1.0 - discount)))

func upgrade_info(path: int) -> Dictionary:
	var paths: Array = def.get("paths", [])
	if path >= paths.size():
		return {}
	var tier_list: Array = (paths[path] as Dictionary).get("tiers", [])
	if tiers[path] >= tier_list.size():
		return {}
	return tier_list[tiers[path]]

func apply_upgrade(path: int) -> bool:
	if not can_upgrade(path):
		return false
	var cost := upgrade_cost(path)
	if not GameState.spend(cost):
		return false
	tiers[path] += 1
	total_spent += cost
	GameState.run_stats["upgrades"] = int(GameState.run_stats.get("upgrades", 0)) + 1
	recompute_stats()
	if manager != null:
		manager.refresh_auras()
	AudioMgr.play_sfx("upgrade", -3.0)
	var info: Dictionary = ((def.get("paths", [])[path] as Dictionary).get("tiers", []) as Array)[tiers[path] - 1]
	EventBus.tower_upgraded.emit(self, path, tiers[path])
	EventBus.announce.emit(display_name, String(info.get("name", "")), 1.6)
	_upgrade_flash()
	return true

func sell_value() -> int:
	return int(round((int(def.get("cost", 0)) + total_spent) * 0.75))

func tier_label() -> String:
	return "%d-%d-%d" % [tiers[0], tiers[1], tiers[2]]

# ================================================================================================
# Combat
# ================================================================================================

func _process(delta: float) -> void:
	time_now += delta
	if enemies == null or not GameState.run_active:
		return
	_tick_income(delta)
	_tick_repair(delta)
	_tick_wall(delta)
	_tick_block(delta)
	if time_now < stun_until or time_now < mercenary_pause_until:
		return
	cooldown -= delta
	if cooldown <= 0.0:
		var t := _acquire_target()
		if t >= 0:
			current_target = t
			cooldown = attack_time
			_begin_attack(t)
		else:
			current_target = -1
			if visual.anim_state == "walk":
				visual.play("idle")

func _acquire_target() -> int:
	var opts := {"detect_invisible": detect_invisible, "hit_air": hit_air, "hit_ground": true, "ignore_structures": false}
	var candidates := enemies.query_targets(global_position, range_r, opts)
	if candidates.is_empty():
		return -1
	var best := -1
	var best_score := -INF
	for slot in candidates:
		var score := 0.0
		match targeting:
			"first":
				score = enemies.dist[slot]
			"last":
				score = -enemies.dist[slot]
			"close":
				score = -global_position.distance_squared_to(enemies.unit_position(slot))
			"strong":
				score = enemies.max_hp[slot] * 1000.0 + enemies.dist[slot]
			"weak":
				score = -enemies.hp[slot] * 1000.0 + enemies.dist[slot]
			_:
				score = enemies.dist[slot]
		# structures (walls) are only worth hitting if they are actually in the way
		if (enemies.flags[slot] & EnemyManager.F_STRUCTURE) != 0:
			score -= 5000.0
		if score > best_score:
			best_score = score
			best = slot
	return best

func _begin_attack(slot: int) -> void:
	var dir := enemies.unit_position(slot) - global_position
	visual.face_direction(dir)
	_pending_shots = 1 + int(specials.get("extra_shots", 0))
	if specials.has("double_shot"):
		_pending_shots += 1
	visual.play("attack", minf(attack_time * 0.9, 0.5))

func _on_attack_hit() -> void:
	var slot := current_target
	if not enemies.is_alive(slot):
		slot = _acquire_target()
	if slot < 0:
		return
	var muzzle := global_position + Vector3(0, 1.4, 0)
	for i in _pending_shots:
		var target_slot := slot
		if i > 0:
			var alt := enemies.query_targets(global_position, range_r, {"detect_invisible": detect_invisible, "hit_air": hit_air, "hit_ground": true})
			if alt.size() > i:
				target_slot = alt[i % alt.size()]
		projectiles.fire(projectile_kind, muzzle, target_slot, _payload())
	if specials.has("extra_attackers"):
		var extra := int(specials["extra_attackers"])
		var mult := float(specials.get("extra_attacker_mult", 0.6))
		var p := _payload()
		p["damage"] = float(p["damage"]) * mult
		for i in extra:
			projectiles.fire(projectile_kind, muzzle + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), slot, p)
	_pending_shots = 0
	AudioMgr.play_sfx_at(_attack_sfx(), global_position, -8.0, 0.12, 0.05)

func _attack_sfx() -> String:
	match damage_type:
		"explosive": return "cannon"
		"ranged": return "bow"
		"magic": return "magic"
		_: return "swing"

func _payload() -> Dictionary:
	var dmg := damage
	# Mace-style height bonus: elevated build zones hit harder.
	if damage_type == "melee" and elevation > 0.5:
		dmg *= DamageCalc.mace_height_bonus(elevation)
	var p := {
		"damage": dmg, "damage_type": damage_type, "armor_pen": armor_pen, "source": tower_id,
		"crit_chance": crit_chance, "crit_mult": crit_mult, "splash": splash, "pierce": pierce,
		"filter": {"detect_invisible": detect_invisible, "hit_air": hit_air, "hit_ground": true},
	}
	for key in ["slow_mult", "slow_duration", "stun_duration", "knockback", "chain",
			"execute_threshold", "boss_damage_mult"]:
		if specials.has(key):
			p[key] = specials[key]
	return p

# ================================================================================================
# Support behaviours
# ================================================================================================

func _tick_income(delta: float) -> void:
	if not specials.has("income") and not specials.has("income_add"):
		return
	var amount := float(specials.get("income_add", 0.0))
	if amount <= 0.0:
		return
	var interval := float(specials.get("income_interval", 8.0))
	income_timer += delta
	if income_timer >= interval:
		income_timer = 0.0
		GameState.add_emeralds(int(round(amount)))
		EventBus.float_text.emit(global_position + Vector3(0, 2.2, 0), "+%d" % int(amount), Color(0.4, 0.95, 0.5))
		AudioMgr.play_sfx("coin", -12.0, 0.1, 0.4)

func _tick_repair(delta: float) -> void:
	if not specials.has("repair_base"):
		return
	var interval := float(specials.get("repair_interval", 20.0))
	repair_timer += delta
	if repair_timer >= interval:
		repair_timer = 0.0
		var amount := int(specials.get("repair_amount", 1))
		if manager != null:
			amount += manager.repair_bonus_for(self)
		if GameState.lives < GameState.max_lives:
			GameState.heal_base(amount)
			EventBus.float_text.emit(global_position + Vector3(0, 2.2, 0), "+%d ♥" % amount, Color(1.0, 0.4, 0.5))

func _tick_wall(delta: float) -> void:
	if not specials.has("wall"):
		return
	var cd := float(specials.get("wall_cooldown", 14.0))
	wall_timer += delta
	if wall_timer >= cd:
		wall_timer = 0.0
		if manager != null:
			manager.spawn_wall(self, float(specials.get("wall_hp", 250.0)), float(specials.get("wall_thorns", 0.0)))

func _tick_block(delta: float) -> void:
	if not specials.has("block_path"):
		return
	var cd := float(specials.get("block_cooldown", 3.0))
	block_timer += delta
	if block_timer >= cd:
		block_timer = 0.0
		var radius := float(specials.get("block_radius", 1.6))
		var duration := float(specials.get("block_duration", 0.6))
		for slot in enemies.query_targets(global_position, maxf(radius, 2.0), {"detect_invisible": true, "hit_air": false, "hit_ground": true}):
			enemies.apply_stun(slot, duration)

func apply_stun(duration: float) -> void:
	if specials.has("stun_immune"):
		return
	if manager != null and manager.has_stun_immunity(self):
		return
	stun_until = maxf(stun_until, time_now + duration)
	visual.flash(0.6)

func on_wave_cleared() -> void:
	if specials.has("wave_bonus"):
		var bonus := int(specials.get("wave_bonus", 0))
		GameState.add_emeralds(bonus)
		EventBus.float_text.emit(global_position + Vector3(0, 2.4, 0), "+%d" % bonus, Color(0.4, 0.95, 0.5))
	if specials.has("lives_on_wave"):
		GameState.heal_base(int(specials.get("lives_on_wave", 0)))

func on_enemy_killed_by(source: String) -> void:
	if source == tower_id and specials.has("bounty"):
		GameState.add_emeralds(int(specials.get("bounty", 0)))
	kills += 1

# ================================================================================================
# Presentation
# ================================================================================================

func _build_range_indicator() -> void:
	range_indicator = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	range_indicator.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	range_indicator.material_override = mat
	range_indicator.position = Vector3(0, 0.08, 0)
	range_indicator.visible = false
	add_child(range_indicator)
	_update_range_indicator()

func _update_range_indicator() -> void:
	if is_instance_valid(range_indicator):
		range_indicator.scale = Vector3(range_r, 1.0, range_r)

func set_selected(v: bool) -> void:
	selected = v
	if is_instance_valid(range_indicator):
		range_indicator.visible = v
	if is_instance_valid(visual):
		visual.set_emission(Color(0.3, 0.7, 1.0), 0.35 if v else 0.0)

func show_range(v: bool) -> void:
	if is_instance_valid(range_indicator):
		range_indicator.visible = v or selected

func _upgrade_flash() -> void:
	if not is_instance_valid(visual):
		return
	visual.set_emission(Color(1.0, 0.85, 0.3), 1.2)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(visual):
			visual.set_emission(Color(1.0, 0.85, 0.3), v), 1.2, 0.0, 0.8)

func set_relationship_names(names: Array[String]) -> void:
	_relationship_names = names

func relationship_names() -> Array[String]:
	return _relationship_names

func cycle_targeting(direction: int = 1) -> void:
	var i := TARGETING_MODES.find(targeting)
	if i < 0:
		i = 0
	targeting = TARGETING_MODES[(i + direction + TARGETING_MODES.size()) % TARGETING_MODES.size()]
