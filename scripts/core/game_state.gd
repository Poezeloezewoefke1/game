extends Node
## Autoload: GameState. Holds the current run configuration and live economy values.

var selected_hero_id: String = "parrotx2"
var selected_map_id: String = "fort_feather"
var difficulty: String = "normal"     # easy | normal | hard

# Live run values
var emeralds: int = 0
var lives: int = 0
var max_lives: int = 0
var wave_index: int = 0
var total_waves: int = 0
var game_speed: float = 1.0
var paused: bool = false
var run_active: bool = false
var run_stats: Dictionary = {}
var selected_tower_loadout: Array[String] = []

const DIFFICULTY := {
	"easy": {"emeralds": 1.35, "lives": 1.5, "enemy_hp": 0.8, "income": 1.2},
	"normal": {"emeralds": 1.0, "lives": 1.0, "enemy_hp": 1.0, "income": 1.0},
	"hard": {"emeralds": 0.8, "lives": 0.6, "enemy_hp": 1.25, "income": 0.9},
}

func difficulty_mult(key: String) -> float:
	return DIFFICULTY.get(difficulty, DIFFICULTY["normal"]).get(key, 1.0)

func start_run(map_def: Dictionary) -> void:
	run_active = true
	emeralds = int(round(map_def.get("start_emeralds", 650) * difficulty_mult("emeralds")))
	max_lives = int(round(map_def.get("lives", 100) * difficulty_mult("lives")))
	lives = max_lives
	wave_index = 0
	total_waves = 0
	game_speed = 1.0
	paused = false
	run_stats = {
		"kills": 0, "leaks": 0, "emeralds_earned": 0, "emeralds_spent": 0, "towers_built": 0,
		"upgrades": 0, "abilities_used": 0, "boss_defeated": false, "waves_cleared": 0, "damage_dealt": 0.0,
		"start_time": Time.get_ticks_msec(),
	}
	EventBus.emeralds_changed.emit(emeralds)
	EventBus.lives_changed.emit(lives, max_lives)

func end_run() -> void:
	run_active = false
	paused = false
	game_speed = 1.0
	Engine.time_scale = 1.0

func add_emeralds(amount: int) -> void:
	if amount == 0:
		return
	emeralds += amount
	if amount > 0:
		run_stats["emeralds_earned"] = run_stats.get("emeralds_earned", 0) + amount
	EventBus.emeralds_changed.emit(emeralds)

func can_afford(cost: int) -> bool:
	return emeralds >= cost

func spend(cost: int) -> bool:
	if emeralds < cost:
		return false
	emeralds -= cost
	run_stats["emeralds_spent"] = run_stats.get("emeralds_spent", 0) + cost
	EventBus.emeralds_changed.emit(emeralds)
	return true

func damage_base(amount: int) -> void:
	if not run_active:
		return
	lives = max(0, lives - amount)
	run_stats["leaks"] = run_stats.get("leaks", 0) + 1
	EventBus.lives_changed.emit(lives, max_lives)
	if lives <= 0:
		run_active = false
		EventBus.run_defeat.emit(run_stats)

func heal_base(amount: int) -> void:
	lives = min(max_lives, lives + amount)
	EventBus.lives_changed.emit(lives, max_lives)

func set_speed(speed: float) -> void:
	game_speed = clamp(speed, 0.0, 3.0)
	if not paused:
		Engine.time_scale = game_speed
	EventBus.game_speed_changed.emit(game_speed)

func set_paused(p: bool) -> void:
	paused = p
	Engine.time_scale = 0.0 if p else game_speed
	EventBus.paused_changed.emit(p)

func hero_def() -> Dictionary:
	return DataDB.heroes.get(selected_hero_id, {})

func map_def() -> Dictionary:
	return DataDB.maps.get(selected_map_id, {})
