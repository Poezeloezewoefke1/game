class_name WaveManager
extends Node
## Drives wave composition, spawn timing and scripted wave events.

signal wave_finished_spawning(index: int)

var enemies: EnemyManager
var waves: Array = []
var wave_index: int = -1
var running: bool = false
var auto_start: bool = true
var time_in_wave: float = 0.0
var between_timer: float = 0.0
var between_delay: float = 6.0
var spawn_queue: Array = []          # {enemy, remaining, interval, next_at, lateral, hp_mult}
var event_queue: Array = []
var boss_controller = null
var blimp_controller = null
var _spawned_this_wave: int = 0
var _all_spawned: bool = false
var awaiting_clear: bool = false
var map_def: Dictionary = {}

func setup(enemy_mgr: EnemyManager, wave_data: Dictionary, map_definition: Dictionary) -> void:
	enemies = enemy_mgr
	waves = wave_data.get("waves", [])
	map_def = map_definition
	GameState.total_waves = waves.size()
	wave_index = -1
	running = false

func total_waves() -> int:
	return waves.size()

func current_wave_name() -> String:
	if wave_index >= 0 and wave_index < waves.size():
		return String((waves[wave_index] as Dictionary).get("name", "Wave %d" % (wave_index + 1)))
	return ""

func next_wave_name() -> String:
	var i := wave_index + 1
	if i < waves.size():
		return String((waves[i] as Dictionary).get("name", "Wave %d" % (i + 1)))
	return ""

func start_next_wave() -> bool:
	if running or wave_index + 1 >= waves.size():
		return false
	wave_index += 1
	GameState.wave_index = wave_index
	var w: Dictionary = waves[wave_index]
	running = true
	awaiting_clear = false
	time_in_wave = 0.0
	_spawned_this_wave = 0
	_all_spawned = false
	spawn_queue.clear()
	event_queue.clear()
	for g in w.get("groups", []):
		spawn_queue.append({
			"enemy": String(g.get("enemy", "chungie_t1")),
			"remaining": int(g.get("count", 1)),
			"interval": float(g.get("interval", 1.0)),
			"next_at": float(g.get("delay", 0.0)),
			"lateral": g.get("lateral", null),
			"hp_mult": float(g.get("hp_mult", 1.0)),
		})
	for e in w.get("events", []):
		event_queue.append((e as Dictionary).duplicate())
	EventBus.wave_started.emit(wave_index, waves.size(), current_wave_name())
	var announce_lines: Array = enemies.faction.get("announcer", {}).get("wave_start", [])
	if wave_index % 4 == 0 and not announce_lines.is_empty():
		EventBus.announce.emit("WAVE %d" % (wave_index + 1), String(announce_lines[wave_index % announce_lines.size()]), 2.2)
	else:
		EventBus.announce.emit("WAVE %d — %s" % [wave_index + 1, current_wave_name()], "", 1.8)
	AudioMgr.play_sfx("wave_start", -4.0)
	return true

func _process(delta: float) -> void:
	if not GameState.run_active:
		return
	if running:
		time_in_wave += delta
		_process_events()
		_process_spawns()
		if _all_spawned and not awaiting_clear:
			awaiting_clear = true
			wave_finished_spawning.emit(wave_index)
		if awaiting_clear and _wave_cleared():
			_complete_wave()
	elif auto_start and wave_index + 1 < waves.size():
		between_timer += delta
		if between_timer >= between_delay:
			between_timer = 0.0
			start_next_wave()

func _process_spawns() -> void:
	var pending := 0
	for g in spawn_queue:
		if int(g["remaining"]) <= 0:
			continue
		pending += int(g["remaining"])
		if time_in_wave >= float(g["next_at"]):
			var lateral: float = NAN
			if g["lateral"] != null:
				lateral = float(g["lateral"])
			var slot := enemies.spawn(String(g["enemy"]), 0.0, lateral, float(g["hp_mult"]))
			if slot >= 0:
				g["remaining"] = int(g["remaining"]) - 1
				_spawned_this_wave += 1
				g["next_at"] = float(g["next_at"]) + float(g["interval"])
			else:
				g["next_at"] = time_in_wave + 0.25      # pool full, retry shortly
	# A wave is only "done spawning" once its scripted events have fired too — otherwise a wave
	# whose entire content is an event (the boss wave) would complete before the event ran.
	_all_spawned = pending == 0 and event_queue.is_empty()

func _process_events() -> void:
	var i := 0
	while i < event_queue.size():
		var e: Dictionary = event_queue[i]
		if time_in_wave >= float(e.get("at", 0.0)):
			_fire_event(e)
			event_queue.remove_at(i)
		else:
			i += 1

func _fire_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"dialogue":
			EventBus.dialogue.emit(String(e.get("speaker", "")), String(e.get("text", "")), 5.0)
		"announce":
			EventBus.announce.emit(String(e.get("text", "")), String(e.get("subtitle", "")), 2.6)
		"minibossintro":
			EventBus.announce.emit(String(e.get("name", "")), String(e.get("title", "")), 3.0)
			AudioMgr.play_sfx("boss_intro", -2.0)
		"blimp":
			if blimp_controller != null:
				blimp_controller.launch(int(e.get("paratroopers", 8)), float(e.get("interval", 1.2)))
		"boss":
			if boss_controller != null:
				boss_controller.begin(String(e.get("boss_id", "saparata")))

func _wave_cleared() -> bool:
	if not event_queue.is_empty():
		return false
	if blimp_controller != null and blimp_controller.active:
		return false
	if enemies.live_count > 0:
		# Structures (walls) do not keep a wave alive.
		for slot in enemies.active:
			if enemies.is_alive(slot) and (enemies.flags[slot] & EnemyManager.F_STRUCTURE) == 0:
				return false
	if boss_controller != null and boss_controller.active:
		return false
	return true

func _complete_wave() -> void:
	running = false
	awaiting_clear = false
	var w: Dictionary = waves[wave_index]
	var reward := int(round(float(w.get("reward", 50)) * GameState.difficulty_mult("income")))
	GameState.add_emeralds(reward)
	GameState.run_stats["waves_cleared"] = wave_index + 1
	EventBus.wave_cleared.emit(wave_index)
	EventBus.float_text.emit(Vector3.ZERO, "", Color.WHITE)
	if wave_index + 1 >= waves.size():
		EventBus.all_waves_cleared.emit()
	else:
		between_timer = 0.0

func remaining_in_wave() -> int:
	var n := 0
	for g in spawn_queue:
		n += maxi(0, int(g["remaining"]))
	return n + enemies.live_count

func is_boss_wave(index: int = -1) -> bool:
	var i := index if index >= 0 else wave_index
	if i < 0 or i >= waves.size():
		return false
	return bool((waves[i] as Dictionary).get("boss", false))

func skip_to_wave(index: int) -> void:
	wave_index = clampi(index - 1, -1, waves.size() - 1)
	running = false
	between_timer = between_delay
