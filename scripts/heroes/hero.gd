class_name Hero
extends Node3D
## The player's chosen protagonist. Attacks like a tower, but also levels up during the run and
## carries three actives plus an ultimate, driven by data/heroes/heroes.json.

signal level_changed(level: int)
signal ability_state_changed()

var def: Dictionary = {}
var hero_id: String = ""
var visual: MinecraftCharacter
var enemies: EnemyManager
var projectiles: ProjectileManager
var manager                                # TowerManager

var level: int = 1
var xp: int = 0
var xp_to_next: int = 105

var damage: float = 20.0
var range_r: float = 7.0
var attack_time: float = 0.8
var pierce: int = 1
var splash: float = 0.0
var armor_pen: float = 0.0
var damage_type: String = "melee"
var projectile_kind: String = "melee_swing"
var detect_invisible: bool = false
var hit_air: bool = false

var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var unlocked: Array[bool] = [false, false, false, false]
var time_now: float = 0.0
var attack_cd: float = 0.0
var current_target: int = -1
var kills: int = 0

# temporary self buffs
var buff_until: float = 0.0
var buff_rate_mult: float = 1.0
var buff_damage_mult: float = 1.0
var buff_armor_pen: float = 0.0
var stun_immune_until: float = 0.0
var lifesteal_lives: int = 0
var lifesteal_cap: int = 0
var lifesteal_used: int = 0

# global buffs granted to every tower
var global_until: float = 0.0
var global_rate_mult: float = 1.0
var global_damage_mult: float = 1.0
var global_range_add: float = 0.0
var leak_cap: int = 0

var death_saves: int = 0
var hit_counter: int = 0
var focus_target: int = -1
var focus_time: float = 0.0
var relationship_damage_mult: float = 1.0
var summons: Array = []
var selected: bool = false
var range_indicator: MeshInstance3D
var _pending_ability: int = -1

func setup(id: String, definition: Dictionary, enemy_mgr: EnemyManager, proj: ProjectileManager, mgr) -> void:
	hero_id = id
	def = definition
	enemies = enemy_mgr
	projectiles = proj
	manager = mgr
	visual = MinecraftCharacter.new()
	add_child(visual)
	visual.setup(SkinLibrary.get_skin(String(def.get("character", id))), def.get("armor", {}), String(def.get("weapon", "")))
	visual.attack_style = String(def.get("attack_style", "slash"))
	visual.attack_hit.connect(_on_attack_hit)
	visual.play("idle")
	_recompute()
	_refresh_unlocks()
	_build_range_indicator()
	var meta := SaveSystem.hero_meta(id)
	# Between-run progression: each meta level adds a small permanent bonus.
	var meta_level := int(meta.get("level", 1))
	damage *= 1.0 + 0.03 * float(meta_level - 1)

func _recompute() -> void:
	var lv := float(level - 1)
	var ls: Dictionary = def.get("level_stats", {})
	damage = float(def.get("damage", 20)) + float(ls.get("damage_per_level", 4.0)) * lv
	range_r = float(def.get("range", 7.0)) + float(ls.get("range_per_level", 0.1)) * lv
	attack_time = float(def.get("attack_time", 0.8)) * (1.0 - minf(0.55, float(ls.get("rate_per_level", 0.01)) * lv))
	pierce = int(def.get("pierce", 1))
	splash = float(def.get("splash", 0.0))
	armor_pen = float(def.get("armor_pen", 0.0))
	damage_type = String(def.get("damage_type", "melee"))
	projectile_kind = String(def.get("projectile", "melee_swing"))
	detect_invisible = bool(def.get("detect_invisible", false))
	hit_air = bool(def.get("hit_air", false))
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		match String(e.get("type", "")):
			"detect_aura":
				detect_invisible = true
			"death_save":
				death_saves = maxi(death_saves, int(e.get("uses", 1)))
	xp_to_next = xp_for_level(level)
	if is_instance_valid(range_indicator):
		range_indicator.scale = Vector3(range_r, 1.0, range_r)

static func xp_for_level(lv: int) -> int:
	return 60 + lv * 45

func _refresh_unlocks() -> void:
	for a in def.get("abilities", []):
		var slot := int(a.get("slot", 0))
		if slot >= 0 and slot < 4:
			var was := unlocked[slot]
			unlocked[slot] = level >= int(a.get("unlock", 1))
			if unlocked[slot] and not was:
				EventBus.hero_ability_ready.emit(slot)
	ability_state_changed.emit()

func add_xp(amount: int) -> void:
	if level >= 20:
		return
	xp += amount
	while xp >= xp_to_next and level < 20:
		xp -= xp_to_next
		level += 1
		_recompute()
		_refresh_unlocks()
		level_changed.emit(level)
		EventBus.hero_level_up.emit(level)
		EventBus.announce.emit("%s — Level %d" % [String(def.get("name", hero_id)), level], _level_up_note(), 2.0)
		AudioMgr.play_sfx("levelup", -2.0)
		if is_instance_valid(visual):
			visual.set_emission(Color(1.0, 0.9, 0.4), 1.5)
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(visual):
					visual.set_emission(Color(1.0, 0.9, 0.4), v), 1.5, 0.0, 1.0)
	EventBus.hero_xp_changed.emit(xp, xp_to_next)

func _level_up_note() -> String:
	for a in def.get("abilities", []):
		if int(a.get("unlock", 1)) == level:
			return "%s unlocked" % String(a.get("name", ""))
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) == level:
			return "%s unlocked" % String(p.get("name", ""))
	return "Stronger."

# ================================================================================================
# Combat
# ================================================================================================

func _process(delta: float) -> void:
	time_now += delta
	for i in 4:
		if cooldowns[i] > 0.0:
			cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
			if cooldowns[i] == 0.0:
				EventBus.hero_ability_ready.emit(i)
				ability_state_changed.emit()
	if buff_until > 0.0 and time_now > buff_until:
		buff_until = 0.0
		buff_rate_mult = 1.0
		buff_damage_mult = 1.0
		buff_armor_pen = 0.0
		lifesteal_lives = 0
		lifesteal_used = 0
	if global_until > 0.0 and time_now > global_until:
		global_until = 0.0
		global_rate_mult = 1.0
		global_damage_mult = 1.0
		global_range_add = 0.0
		leak_cap = 0
		if manager != null:
			manager.refresh_auras()
	_tick_passives(delta)
	_tick_summons(delta)
	if enemies == null:
		return
	attack_cd -= delta
	if attack_cd <= 0.0:
		var t := _acquire_target()
		if t >= 0:
			current_target = t
			attack_cd = attack_time * buff_rate_mult
			var dir := enemies.unit_position(t) - global_position
			visual.face_direction(dir)
			visual.play("attack", minf(attack_cd * 0.9, 0.45))
		elif visual.anim_state != "idle":
			visual.play("idle")

func _tick_passives(delta: float) -> void:
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		if String(e.get("type", "")) == "income":
			var interval := float(e.get("interval", 8.0))
			focus_time += 0.0   # (income uses its own accumulator below)
	# income passive accumulator
	_income_timer += delta
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		if String(e.get("type", "")) == "income":
			var interval := float(e.get("interval", 8.0))
			if _income_timer >= interval:
				var amount := int(e.get("amount", 0)) + int(e.get("per_level", 0)) * (level - 1)
				GameState.add_emeralds(amount)
				EventBus.float_text.emit(global_position + Vector3(0, 2.4, 0), "+%d" % amount, Color(0.4, 0.95, 0.5))
	if _income_timer >= 8.0:
		_income_timer = 0.0

var _income_timer: float = 0.0

func _acquire_target() -> int:
	var opts := {"detect_invisible": detect_invisible, "hit_air": hit_air, "hit_ground": true, "ignore_structures": false}
	var candidates := enemies.query_targets(global_position, range_r, opts)
	if candidates.is_empty():
		return -1
	var mode := String(def.get("targeting", "strong"))
	var best := -1
	var best_score := -INF
	for slot in candidates:
		var score: float = enemies.dist[slot]
		if mode == "strong":
			score = enemies.max_hp[slot] * 1000.0 + enemies.dist[slot]
		elif mode == "close":
			score = -global_position.distance_squared_to(enemies.unit_position(slot))
		if (enemies.flags[slot] & EnemyManager.F_STRUCTURE) != 0:
			score -= 5000.0
		if score > best_score:
			best_score = score
			best = slot
	return best

func _on_attack_hit() -> void:
	var slot := current_target
	if not enemies.is_alive(slot):
		slot = _acquire_target()
	if slot < 0:
		return
	hit_counter += 1
	var dmg := damage * buff_damage_mult * relationship_damage_mult
	var pen := armor_pen + buff_armor_pen
	var extra_splash := splash
	# passives
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		match String(e.get("type", "")):
			"mace_height":
				var height := global_position.y - enemies.unit_position(slot).y
				dmg *= DamageCalc.mace_height_bonus(height)
			"focus_ramp":
				if slot == focus_target:
					focus_time = minf(focus_time + attack_time, float(e.get("ramp_time", 4.0)))
				else:
					focus_target = slot
					focus_time = 0.0
				var ramp := focus_time / maxf(0.1, float(e.get("ramp_time", 4.0)))
				dmg *= 1.0 + float(e.get("max_bonus", 1.0)) * ramp * 0.4 + 0.4 * ramp
			"periodic_splash":
				if hit_counter % int(e.get("every", 6)) == 0:
					extra_splash = maxf(extra_splash, float(e.get("radius", 2.0)))
					dmg *= float(e.get("mult", 1.5))
			"periodic_knockback":
				if hit_counter % int(e.get("every", 3)) == 0:
					enemies.push_back(slot, float(e.get("force", 2.0)))
			"hit_knockback":
				enemies.push_back(slot, float(e.get("force", 0.3)))
	var payload := {
		"damage": dmg, "damage_type": damage_type, "armor_pen": pen, "source": hero_id,
		"splash": extra_splash, "pierce": pierce,
		"filter": {"detect_invisible": detect_invisible, "hit_air": hit_air, "hit_ground": true},
	}
	projectiles.fire(projectile_kind, global_position + Vector3(0, 1.5, 0), slot, payload)
	if lifesteal_lives > 0 and lifesteal_used < lifesteal_cap:
		lifesteal_used += 1
		GameState.heal_base(lifesteal_lives)
	AudioMgr.play_sfx_at("swing", global_position, -9.0, 0.15, 0.06)

func on_enemy_killed(slot: int, killer: String) -> void:
	if killer != hero_id:
		return
	kills += 1
	add_xp(int(enemies.def_of(slot).get("xp", 2)) if enemies.is_alive(slot) else 3)
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		match String(e.get("type", "")):
			"kill_explosion":
				var at := enemies.unit_position(slot)
				for other in enemies.query_range(at, float(e.get("radius", 2.4))):
					enemies.damage(other, float(e.get("damage", 100.0)), "explosive", 0.4, hero_id)
			"kill_mark":
				if randf() < float(e.get("chance", 0.2)):
					var at2 := enemies.unit_position(slot)
					for other in enemies.query_range(at2, float(e.get("radius", 3.5))):
						enemies.apply_slow(other, 0.8, float(e.get("duration", 4.0)))

# ================================================================================================
# Abilities
# ================================================================================================

func ability_def(slot: int) -> Dictionary:
	for a in def.get("abilities", []):
		if int(a.get("slot", -1)) == slot:
			return a
	return {}

func can_use(slot: int) -> bool:
	return unlocked[slot] and cooldowns[slot] <= 0.0 and GameState.run_active

func use_ability(slot: int) -> bool:
	if not can_use(slot):
		return false
	var a := ability_def(slot)
	if a.is_empty():
		return false
	cooldowns[slot] = float(a.get("cooldown", 20.0))
	GameState.run_stats["abilities_used"] = int(GameState.run_stats.get("abilities_used", 0)) + 1
	EventBus.hero_ability_used.emit(slot)
	ability_state_changed.emit()
	EventBus.announce.emit(String(a.get("name", "")), "", 1.4)
	AudioMgr.play_sfx("ability", -2.0)
	visual.play("cast", 0.6)
	_execute_effect(a.get("effect", {}), String(a.get("name", "")))
	return true

func _execute_effect(e: Dictionary, ability_name: String) -> void:
	var kind := String(e.get("type", ""))
	match kind:
		"strike":
			var delay := float(e.get("delay", 0.0))
			if delay > 0.0:
				var target_pos := _pick_strike_position(String(e.get("target", "strongest")), float(e.get("radius", 4.0)))
				EventBus.boss_event.emit("orbital_telegraph", {"position": target_pos, "radius": float(e.get("radius", 4.0)), "delay": delay})
				await get_tree().create_timer(delay).timeout
				_do_strike(e, target_pos)
			else:
				_do_strike(e, _pick_strike_position(String(e.get("target", "strongest")), float(e.get("radius", 4.0))))
		"area_slow":
			var centre := global_position
			for slot in enemies.query_range(centre, float(e.get("radius", 5.0))):
				enemies.apply_slow(slot, float(e.get("slow_mult", 0.4)), float(e.get("duration", 4.0)))
			EventBus.boss_event.emit("web_burst", {"position": centre, "radius": float(e.get("radius", 5.0))})
		"self_buff":
			buff_until = time_now + float(e.get("duration", 6.0))
			buff_rate_mult = float(e.get("rate_mult", 1.0))
			buff_damage_mult = float(e.get("damage_mult", 1.0))
			buff_armor_pen = float(e.get("armor_pen_add", 0.0))
			if bool(e.get("stun_immune", false)):
				stun_immune_until = buff_until
			lifesteal_lives = int(e.get("lifesteal_lives", 0))
			lifesteal_cap = int(e.get("lifesteal_cap", 0))
			lifesteal_used = 0
			visual.set_emission(Color(1.0, 0.6, 0.2), 0.8)
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(visual):
					visual.set_emission(Color(1.0, 0.6, 0.2), v), 0.8, 0.0, float(e.get("duration", 6.0)))
		"global_buff":
			global_until = time_now + float(e.get("duration", 8.0))
			global_rate_mult = float(e.get("rate_mult", 1.0))
			global_damage_mult = float(e.get("damage_mult", 1.0))
			global_range_add = float(e.get("range_add", 0.0))
			leak_cap = int(e.get("leak_cap", 0))
			if manager != null:
				manager.refresh_auras()
		"duel":
			var best := _find_elite()
			if best >= 0:
				enemies.apply_stun(best, float(e.get("stun", 3.0)))
				enemies.damage(best, float(e.get("damage", 200.0)), "true", 1.0, hero_id)
				EventBus.float_text.emit(enemies.unit_position(best), "1v1", Color(1.0, 0.5, 0.2))
		"dash":
			var forward := -global_transform.basis.z
			var hit_centre := global_position + forward * float(e.get("distance", 8.0)) * 0.5
			for slot in enemies.query_range(hit_centre, float(e.get("radius", 2.5)) + float(e.get("distance", 8.0)) * 0.5):
				enemies.damage(slot, float(e.get("damage", 150.0)), "melee", 0.4, hero_id)
				enemies.apply_stun(slot, float(e.get("stun", 1.0)))
			EventBus.camera_shake.emit(0.4, 0.2)
		"wall":
			if manager != null and enemies.path != null:
				var d := enemies.path.nearest_distance_to(global_position)
				var slot := enemies.spawn("cobble_wall", clampf(d + 2.0, 1.0, enemies.path.total_length - 2.0), 0.0)
				if slot >= 0:
					enemies.hp[slot] = float(e.get("hp", 1500.0))
					enemies.max_hp[slot] = enemies.hp[slot]
		"summon":
			_summon(int(e.get("count", 3)), float(e.get("duration", 15.0)), e)
		"convert":
			var target := _find_elite(int(e.get("max_tier", 7)))
			if target >= 0:
				_convert(target, float(e.get("duration", 10.0)))
		"area_knockback":
			var centre := global_position
			for slot in enemies.query_range(centre, float(e.get("radius", 5.5))):
				enemies.push_back(slot, float(e.get("force", 8.0)))
				enemies.damage(slot, float(e.get("damage", 120.0)), "magic", 0.3, hero_id)
			EventBus.camera_shake.emit(0.5, 0.3)
		"area_stun":
			var centre2 := global_position
			for slot in enemies.query_range(centre2, float(e.get("radius", 6.0))):
				enemies.apply_stun(slot, float(e.get("stun", 4.0)))
				enemies.apply_slow(slot, 0.5, float(e.get("vuln_duration", 8.0)))
			EventBus.boss_event.emit("purgatory", {"position": centre2, "radius": float(e.get("radius", 6.0))})
		"null_army":
			_summon(int(e.get("count", 6)), float(e.get("duration", 20.0)), e)
			for slot in enemies.active:
				if enemies.is_alive(slot):
					enemies.apply_slow(slot, float(e.get("global_slow", 0.5)), float(e.get("slow_duration", 10.0)))
					enemies.damage(slot, float(e.get("damage", 400.0)) * 0.25, "magic", 0.5, hero_id)
			EventBus.camera_shake.emit(0.8, 0.6)

func _do_strike(e: Dictionary, at: Vector3) -> void:
	var radius := float(e.get("radius", 4.0))
	var dmg := float(e.get("damage", 200.0))
	for slot in enemies.query_range(at, radius):
		var falloff := DamageCalc.splash_falloff(enemies.unit_position(slot).distance_to(at), radius, 0.55)
		enemies.damage(slot, dmg * falloff, String(e.get("damage_type", "explosive")), float(e.get("armor_pen", 0.5)), hero_id)
	EventBus.camera_shake.emit(float(e.get("shake", 0.5)), 0.4)
	EventBus.boss_event.emit("orbital_impact", {"position": at, "radius": radius})
	AudioMgr.play_sfx("explosion", -1.0)

func _pick_strike_position(mode: String, radius: float) -> Vector3:
	if enemies.active.is_empty():
		return global_position
	if mode == "densest":
		var best := global_position
		var best_count := -1
		for slot in enemies.active:
			if not enemies.is_alive(slot):
				continue
			var p := enemies.unit_position(slot)
			var c := enemies.query_range(p, radius).size()
			if c > best_count:
				best_count = c
				best = p
		return best
	var strongest := -1
	var best_hp := -1.0
	for slot in enemies.active:
		if enemies.is_alive(slot) and enemies.max_hp[slot] > best_hp:
			best_hp = enemies.max_hp[slot]
			strongest = slot
	return enemies.unit_position(strongest) if strongest >= 0 else global_position

func _find_elite(max_tier: int = 99) -> int:
	var best := -1
	var best_hp := -1.0
	for slot in enemies.active:
		if not enemies.is_alive(slot):
			continue
		var d := enemies.def_of(slot)
		if int(d.get("tier", 1)) > max_tier:
			continue
		if (enemies.flags[slot] & EnemyManager.F_STRUCTURE) != 0:
			continue
		if global_position.distance_to(enemies.unit_position(slot)) > range_r * 2.5:
			continue
		if enemies.max_hp[slot] > best_hp:
			best_hp = enemies.max_hp[slot]
			best = slot
	return best

func _convert(slot: int, duration: float) -> void:
	# The enemy is removed and replaced with a friendly summon at the same spot.
	var pos := enemies.unit_position(slot)
	var strength: float = enemies.max_hp[slot] * 0.08
	enemies.kill(slot, hero_id, false)
	var s := _make_summon(pos, duration, maxf(30.0, strength), 0.8, 6.0, String(def.get("character", hero_id)))
	if s != null:
		EventBus.float_text.emit(pos, "TURNCOAT", Color(0.6, 1.0, 0.6))

func _summon(count: int, duration: float, e: Dictionary) -> void:
	var dmg := float(e.get("summon_damage", e.get("damage", 45.0)))
	if String(e.get("type", "")) == "summon":
		dmg = float(e.get("damage", 45.0))
	var character := String(e.get("character", "royal_soldier"))
	for i in count:
		var angle := TAU * float(i) / float(maxi(1, count))
		var pos := global_position + Vector3(cos(angle), 0, sin(angle)) * 2.4
		_make_summon(pos, duration, dmg, float(e.get("rate", 0.9)), float(e.get("range", 6.0)), character)

func _make_summon(pos: Vector3, duration: float, dmg: float, rate: float, rng_r: float, character: String) -> HeroSummon:
	var s := HeroSummon.new()
	get_parent().add_child(s)
	s.setup(character, enemies, projectiles, dmg, rate, rng_r, duration, hero_id)
	s.global_position = pos
	summons.append(s)
	return s

func _tick_summons(_delta: float) -> void:
	var w := 0
	for s in summons:
		if is_instance_valid(s):
			summons[w] = s
			w += 1
	summons.resize(w)

# ================================================================================================
# Aura / interface for TowerManager
# ================================================================================================

func aura_effects() -> Dictionary:
	var out := {"radius": 0.0, "damage": 0.0, "rate": 0.0, "range_add": 0.0, "detect": false}
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		match String(e.get("type", "")):
			"aura":
				out["radius"] = maxf(float(out["radius"]), float(e.get("radius", 8.0)))
				out["damage"] = float(out["damage"]) + float(e.get("damage", 0.0)) + float(e.get("per_level_damage", 0.0)) * float(level - 1)
				out["rate"] = float(out["rate"]) + float(e.get("rate", 0.0)) + float(e.get("per_level_rate", 0.0)) * float(level - 1)
			"detect_aura":
				out["radius"] = maxf(float(out["radius"]), float(e.get("radius", 8.0)))
				out["detect"] = true
	return out

func global_buffs() -> Dictionary:
	if global_until <= time_now:
		return {}
	return {"damage_mult": global_damage_mult, "rate_mult": global_rate_mult, "range_add": global_range_add}

func apply_relationship(eff: Dictionary) -> void:
	relationship_damage_mult *= float(eff.get("damage_mult", 1.0))

func reset_relationship() -> void:
	relationship_damage_mult = 1.0

func on_wave_cleared() -> void:
	for p in def.get("passives", []):
		if int(p.get("unlock", 1)) > level:
			continue
		var e: Dictionary = p.get("effect", {})
		if String(e.get("type", "")) == "wave_repair":
			GameState.heal_base(int(e.get("lives", 3)))

func consume_death_save() -> bool:
	if death_saves > 0:
		death_saves -= 1
		EventBus.announce.emit("TOTEM OF UNDYING", "The base holds.", 2.5)
		return true
	return false

func leak_damage_cap() -> int:
	return leak_cap if global_until > time_now else 0

func apply_stun(duration: float) -> void:
	if time_now < stun_immune_until:
		return
	attack_cd = maxf(attack_cd, duration)
	visual.flash(0.6)

func _build_range_indicator() -> void:
	range_indicator = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	range_indicator.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	range_indicator.material_override = mat
	range_indicator.position = Vector3(0, 0.1, 0)
	range_indicator.visible = false
	add_child(range_indicator)
	range_indicator.scale = Vector3(range_r, 1.0, range_r)

func set_selected(v: bool) -> void:
	selected = v
	if is_instance_valid(range_indicator):
		range_indicator.visible = v
