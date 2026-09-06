class_name SaparataEncounter
extends Node
## Five-phase Saparata encounter. Each phase is built on a sourced event from the Kingdoms Saga
## (see data/lore/bosses.json); the mechanics themselves are game design.
##
##  1 Cindercrest Vanguard  – the ground assault Fort Feather first repelled
##  2 Elite Strike          – ShoeBilly, the assassin of Skymore
##  3 The Redstone Blimp    – slow-falling paratroopers behind the walls
##  4 Saparata Enters       – the king takes the field himself
##  5 The Usurper King      – Persuasion turns the Royal Army; below 25% he is enraged

signal phase_changed(index: int)
signal defeated()

const PHASES := [
	{"name": "Cindercrest Vanguard", "desc": "The ground assault begins."},
	{"name": "Elite Strike", "desc": "ShoeBilly_ leads the assassins."},
	{"name": "The Redstone Blimp", "desc": "Paratroopers behind the walls."},
	{"name": "Saparata Enters", "desc": "The King of Unstable takes the field."},
	{"name": "The Usurper King", "desc": "He turns your own army against you."},
]

var enemies: EnemyManager
var towers                                    # TowerManager
var blimp: BlimpController
var active: bool = false
var phase: int = -1
var phase_time: float = 0.0
var boss_slot: int = -1
var boss_def: Dictionary = {}
var spawn_timer: float = 0.0
var ability_timer: float = 0.0
var persuade_timer: float = 0.0
var enraged: bool = false
var crowned: bool = false
var minion_budget: int = 0
var _shoebilly_slot: int = -1
var _phase4_entered: bool = false
var _last_hp_report: float = -1.0
var _persuaded: Dictionary = {}

func setup(enemy_mgr: EnemyManager, tower_mgr, blimp_ctrl: BlimpController) -> void:
	enemies = enemy_mgr
	towers = tower_mgr
	blimp = blimp_ctrl

func begin(boss_id: String = "saparata") -> void:
	if active:
		return
	active = true
	boss_def = DataDB.enemies.get(boss_id, {})
	phase = -1
	_advance_phase()
	AudioMgr.play_music(String(enemies.faction.get("boss_music", "boss_saparata")))
	EventBus.announce.emit("SAPARATA", "Leader of Cindercrest. King of Unstable.", 3.5)
	EventBus.dialogue.emit("saparata", "You gave the server to the new players, Parrot. I'm taking it back.", 6.0)
	AudioMgr.play_sfx("boss_intro", 0.0)

func _advance_phase() -> void:
	phase += 1
	phase_time = 0.0
	spawn_timer = 0.0
	if phase >= PHASES.size():
		return
	var p: Dictionary = PHASES[phase]
	EventBus.boss_phase_changed.emit(phase, String(p["name"]), String(p["desc"]))
	EventBus.announce.emit("PHASE %d — %s" % [phase + 1, String(p["name"])], String(p["desc"]), 2.8)
	phase_changed.emit(phase)
	match phase:
		0:
			minion_budget = 22
		1:
			minion_budget = 10
			_shoebilly_slot = enemies.spawn("shoebilly", 0.0, 0.0)
			EventBus.dialogue.emit("parrotx2", "ShoeBilly. He's the one who emptied Skymore.", 5.0)
		2:
			minion_budget = 12
			if blimp != null:
				blimp.launch(10, 1.0)
			EventBus.dialogue.emit("theobaldthebird", "The blimp! That's how they took the fort the first time.", 5.0)
		3:
			minion_budget = 14
			_spawn_boss()
		4:
			minion_budget = 18
			crowned = true
			if boss_slot >= 0 and enemies.is_alive(boss_slot):
				var armor: Dictionary = (boss_def.get("armor", {}) as Dictionary).duplicate()
				armor["crown"] = "gold"
				enemies.group_idx[boss_slot] = enemies._resolve_group(enemies.type_idx[boss_slot])
			EventBus.dialogue.emit("saparata", "Your own army, Parrot. Watch them choose.", 5.0)

func _spawn_boss() -> void:
	if _phase4_entered:
		return
	_phase4_entered = true
	boss_slot = enemies.spawn("saparata", 0.0, 0.0)
	if boss_slot >= 0:
		EventBus.boss_spawned.emit(boss_slot)
		EventBus.boss_health_changed.emit(enemies.hp[boss_slot], enemies.max_hp[boss_slot])
	EventBus.camera_shake.emit(0.7, 0.8)

func _process(delta: float) -> void:
	if not active or not GameState.run_active:
		return
	phase_time += delta
	spawn_timer -= delta
	ability_timer -= delta
	_report_boss_hp()
	match phase:
		0:
			_phase_vanguard(delta)
		1:
			_phase_elite(delta)
		2:
			_phase_blimp(delta)
		3:
			_phase_saparata(delta)
		4:
			_phase_king(delta)

func _report_boss_hp() -> void:
	if boss_slot >= 0 and enemies.is_alive(boss_slot):
		var hp := enemies.hp[boss_slot]
		if absf(hp - _last_hp_report) > 1.0:
			_last_hp_report = hp
			EventBus.boss_health_changed.emit(hp, enemies.max_hp[boss_slot])

func _spawn_minion(id: String, lateral := NAN) -> void:
	if minion_budget <= 0:
		return
	minion_budget -= 1
	enemies.spawn(id, 0.0, lateral)

func _phase_vanguard(_delta: float) -> void:
	if spawn_timer <= 0.0:
		spawn_timer = 0.7
		_spawn_minion("chungie_t5" if randf() < 0.6 else "chungie_t6")
	if minion_budget <= 0 and _clear_of_minions():
		_advance_phase()

func _phase_elite(_delta: float) -> void:
	if spawn_timer <= 0.0:
		spawn_timer = 1.3
		_spawn_minion("assassin")
	var shoe_alive := _shoebilly_slot >= 0 and enemies.is_alive(_shoebilly_slot)
	if not shoe_alive and minion_budget <= 0:
		_advance_phase()

func _phase_blimp(_delta: float) -> void:
	if spawn_timer <= 0.0:
		spawn_timer = 1.0
		_spawn_minion("chungie_t6" if randf() < 0.4 else "chungie_t5")
	var blimp_busy := blimp != null and blimp.active
	if not blimp_busy and minion_budget <= 0 and _clear_of_minions():
		_advance_phase()

func _phase_saparata(delta: float) -> void:
	if boss_slot < 0 or not enemies.is_alive(boss_slot):
		if _phase4_entered:
			_on_boss_dead()
		return
	if spawn_timer <= 0.0:
		spawn_timer = 1.6
		_spawn_minion("chungie_t6")
	# Ember Strike: stuns the nearest tower.
	if ability_timer <= 0.0:
		ability_timer = 6.0
		_ember_strike()
	# Revanchist Call: heals when Cindercrest soldiers die near him.
	_revanchist_heal(delta)
	var frac := enemies.hp[boss_slot] / maxf(1.0, enemies.max_hp[boss_slot])
	if frac <= 0.5:
		_advance_phase()

func _phase_king(delta: float) -> void:
	if boss_slot < 0 or not enemies.is_alive(boss_slot):
		_on_boss_dead()
		return
	if spawn_timer <= 0.0:
		spawn_timer = 1.1
		_spawn_minion("royal_defector" if randf() < 0.5 else "chungie_t6")
	if ability_timer <= 0.0:
		ability_timer = 5.0
		_ember_strike()
	persuade_timer -= delta
	if persuade_timer <= 0.0:
		persuade_timer = 9.0
		_persuade()
	_revanchist_heal(delta)
	var frac := enemies.hp[boss_slot] / maxf(1.0, enemies.max_hp[boss_slot])
	if frac <= 0.25 and not enraged:
		enraged = true
		enemies.base_speed[boss_slot] *= 1.45
		enemies.armor[boss_slot] = minf(0.8, enemies.armor[boss_slot] + 0.12)
		EventBus.announce.emit("OLD PLAYERS' WRATH", "Saparata is enraged.", 2.6)
		EventBus.dialogue.emit("saparata", "Every new player who joined after your crown. Every one of them.", 5.0)
		EventBus.camera_shake.emit(0.6, 0.5)

func _ember_strike() -> void:
	if boss_slot < 0 or not enemies.is_alive(boss_slot) or towers == null:
		return
	var pos := enemies.unit_position(boss_slot)
	var nearest: Tower = null
	var best := INF
	for t in towers.towers:
		if not is_instance_valid(t):
			continue
		var d: float = t.global_position.distance_to(pos)
		if d < best and d < 12.0:
			best = d
			nearest = t
	if nearest != null:
		nearest.apply_stun(3.0)
		EventBus.float_text.emit(nearest.global_position + Vector3(0, 2.2, 0), "STUNNED", Color(1.0, 0.4, 0.2))
		EventBus.boss_event.emit("ember_strike", {"position": nearest.global_position})
		AudioMgr.play_sfx_at("ember", nearest.global_position, -4.0)

func _revanchist_heal(delta: float) -> void:
	if boss_slot < 0 or not enemies.is_alive(boss_slot):
		return
	# Heals slowly while his soldiers are still on the field — the revanchist ideal made mechanical.
	var nearby := enemies.query_range(enemies.unit_position(boss_slot), 8.0).size()
	if nearby > 1:
		enemies.hp[boss_slot] = minf(enemies.max_hp[boss_slot], enemies.hp[boss_slot] + float(nearby) * 3.0 * delta)

func _persuade() -> void:
	if towers == null or towers.towers.is_empty():
		return
	var candidates: Array = []
	for t in towers.towers:
		if is_instance_valid(t) and not _persuaded.has(t):
			candidates.append(t)
	if candidates.is_empty():
		return
	var target: Tower = candidates[randi() % candidates.size()]
	_persuaded[target] = true
	target.apply_stun(5.0)
	if is_instance_valid(target.visual):
		target.visual.set_tint(Color(1.0, 0.5, 0.45))
	EventBus.float_text.emit(target.global_position + Vector3(0, 2.4, 0), "PERSUADED", Color(1.0, 0.3, 0.3))
	EventBus.announce.emit("PERSUASION", "%s has been turned — for now." % target.display_name, 2.4)
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(target):
		if is_instance_valid(target.visual):
			target.visual.set_tint(Color.WHITE)
		_persuaded.erase(target)

func _clear_of_minions() -> bool:
	for slot in enemies.active:
		if enemies.is_alive(slot) and (enemies.flags[slot] & EnemyManager.F_STRUCTURE) == 0:
			if (enemies.flags[slot] & EnemyManager.F_BOSS) == 0:
				return false
	return true

func _on_boss_dead() -> void:
	if not active:
		return
	active = false
	boss_slot = -1
	GameState.run_stats["boss_defeated"] = true
	SaveSystem.data["stats"]["boss_kills"] = int(SaveSystem.data["stats"].get("boss_kills", 0)) + 1
	EventBus.announce.emit("SAPARATA DEFEATED", "Fort Feather holds.", 4.0)
	EventBus.dialogue.emit("parrotx2", "History says this fort fell. Today it didn't.", 6.0)
	EventBus.boss_defeated.emit(boss_slot)
	EventBus.camera_shake.emit(1.0, 1.0)
	defeated.emit()

func current_phase_name() -> String:
	if phase >= 0 and phase < PHASES.size():
		return String((PHASES[phase] as Dictionary)["name"])
	return ""
