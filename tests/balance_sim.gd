extends Node3D
## Balance simulation: plays a full campaign with an AI player that obeys every rule the human does.
##
## No cheating: it starts with the map's real emerald allowance, buys and upgrades only what it can
## afford, and uses hero abilities on cooldown. If this loses, the game is too hard; if it never drops
## a life, the game is too easy.
##
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/balance_sim.gd 9000
##
## Optional user args after the frame count: <hero_id> <difficulty> <map_id>

var game
var decision_timer := 0.0
var ability_timer := 0.0
var report_wave := -1
var history: Array = []
var finished := false
var result := {}
var peak_live := 0
var first_leak_wave := -1
var run_seed: int = 12345

# How far along the path enemies get before they die, bucketed into tenths. A board that deletes
# everything at the spawn point piles up in bucket 0, which is the signature of a wave whose enemies
# are too weak for the towers regardless of how many of them there are.
var kill_depth := PackedInt32Array()
var kill_depth_sum := 0.0
var kill_depth_n := 0
var kill_source: Dictionary = {}
var deep_source: Dictionary = {}
var deep_type: Dictionary = {}

# The AI's build order. Chosen to look like a reasonable human opening: cheap DPS first, then
# economy, then coverage (detection and anti-air), then the expensive specialists.
const BUILD_ORDER := [
	"royal_guard", "royal_guard", "spepticle", "eggchan", "theobaldthebird",
	"mapicc", "lomedy", "reinadrop", "minutetech", "deputy_ace",
	"4cvit", "leow0ok", "purpled", "fymada", "royal_guard", "mapicc", "jaden_man", "royal_guard",
]

# Preferred upgrade path per tower, and how far to push it before moving on.
const UPGRADE_PLAN := {
	"royal_guard": [0, 2], "spepticle": [0, 1], "eggchan": [0, 2], "theobaldthebird": [0, 2],
	"mapicc": [0, 2], "lomedy": [1, 0], "reinadrop": [0, 1], "minutetech": [0, 1],
	"deputy_ace": [0, 1], "4cvit": [0, 1], "leow0ok": [0, 2], "purpled": [0, 1],
	"fymada": [2, 0], "jaden_man": [1, 0],
}

func _ready() -> void:
	Engine.time_scale = 10.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 2:
		GameState.selected_hero_id = String(args[2])
	if args.size() > 3:
		GameState.difficulty = String(args[3])
	if args.size() > 4:
		GameState.selected_map_id = String(args[4])
	# Optional seed. Enemy spawn jitter, crits and ability rolls otherwise vary run to run enough to
	# swing a campaign between a comfortable win and a loss two waves from the end, which makes any
	# single run useless for tuning. Seeding makes a run reproducible; sample several seeds to judge
	# a balance change rather than trusting one.
	if args.size() > 5:
		run_seed = int(String(args[5]).to_int())
	seed(run_seed)
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.enemies.rng.seed = run_seed
	game.waves.auto_start = true
	game.waves.between_delay = 3.0
	EventBus.enemy_leaked.connect(func(_s: int, _t: String, _d: int) -> void:
		if first_leak_wave < 0:
			first_leak_wave = game.waves.wave_index + 1)
	EventBus.enemy_killed.connect(_on_killed)
	game.enemies.debug_damage_by_source = true
	EventBus.run_defeat.connect(_on_defeat)
	EventBus.all_waves_cleared.connect(_on_victory)
	print("[SIM] hero=%s difficulty=%s map=%s seed=%d" % [
		GameState.selected_hero_id, GameState.difficulty, GameState.selected_map_id, run_seed])
	print("[SIM] start emeralds=%d lives=%d waves=%d zones=%d" % [
		GameState.emeralds, GameState.max_lives, game.waves.total_waves(), game.towers.zones.size()])

func _on_killed(slot: int, _id: String, _source: String) -> void:
	if game == null or game.enemies == null or game.enemies.path == null:
		return
	var total: float = game.enemies.path.total_length
	if total <= 0.0:
		return
	if kill_depth.is_empty():
		kill_depth.resize(10)
	var frac: float = clampf(game.enemies.dist[slot] / total, 0.0, 0.999)
	kill_depth[int(frac * 10.0)] += 1
	kill_depth_sum += frac
	kill_depth_n += 1
	var key: String = _source if _source != "" else "(none)"
	kill_source[key] = int(kill_source.get(key, 0)) + 1
	if frac >= 0.9:
		deep_source[key] = int(deep_source.get(key, 0)) + 1
		deep_type[_id] = int(deep_type.get(_id, 0)) + 1

func on_frame(_f: int) -> void:
	if finished:
		return
	var delta := get_process_delta_time()
	decision_timer += delta
	ability_timer += delta
	if decision_timer >= 1.0:
		decision_timer = 0.0
		_spend()
	if ability_timer >= 0.5:
		ability_timer = 0.0
		_use_abilities()
	peak_live = maxi(peak_live, game.enemies.live_count)
	if game.waves.wave_index != report_wave:
		report_wave = game.waves.wave_index
		_snapshot()

## Buys the next tower in the build order, otherwise upgrades along the plan.
## Always keeps a small reserve so it is never left unable to react.
func _spend() -> void:
	if not GameState.run_active:
		return
	var built: int = game.towers.towers.size()
	if built < BUILD_ORDER.size():
		var id: String = BUILD_ORDER[built]
		var cost := int(DataDB.towers.get(id, {}).get("cost", 999999))
		if GameState.emeralds >= cost:
			var zone := _best_zone()
			if zone >= 0 and game.towers.place(id, zone) != null:
				return
	# Upgrade: cheapest useful upgrade first, so the board improves broadly rather than spiking.
	var best: Tower = null

	var best_path := -1
	var best_cost := 1 << 30
	for t in game.towers.towers:
		if not is_instance_valid(t):
			continue
		var plan: Array = UPGRADE_PLAN.get(t.tower_id, [0, 1])
		for path: int in plan:
			if not t.can_upgrade(path):
				continue
			var cost: int = t.upgrade_cost(path)
			if cost < best_cost and GameState.emeralds >= cost:
				best = t
				best_path = path
				best_cost = cost
	if best != null:
		best.apply_upgrade(best_path)

## Picks the free build zone furthest from the towers already placed. Taking the first free zone
## instead clumps the whole board around the path's entrance, which understates what a competent
## player gets out of the same emeralds and makes the game look harder than it is.
func _best_zone() -> int:
	var best := -1
	var best_score := -INF
	for i in game.towers.zones.size():
		if not game.towers.can_place_at(i):
			continue
		var pos: Vector3 = game.towers.zones[i]["pos"]
		var nearest := INF
		for t in game.towers.towers:
			if is_instance_valid(t):
				nearest = minf(nearest, pos.distance_to(t.global_position))
		var score: float = nearest if nearest < INF else 0.0
		if score > best_score:
			best_score = score
			best = i
	return best

func _use_abilities() -> void:
	if game.hero == null or not is_instance_valid(game.hero):
		return
	# Hold the ultimate for when it is worth using; fire the rest on cooldown.
	for slot in 3:
		if game.hero.can_use(slot):
			game.hero.use_ability(slot)
	if game.hero.can_use(3) and game.enemies.live_count >= 12:
		game.hero.use_ability(3)

func _snapshot() -> void:
	if report_wave < 0:
		return
	history.append({
		"wave": report_wave + 1,
		"name": game.waves.current_wave_name(),
		"lives": GameState.lives,
		"emeralds": GameState.emeralds,
		"towers": game.towers.towers.size(),
		"upgrades": int(GameState.run_stats.get("upgrades", 0)),
		"kills": int(GameState.run_stats.get("kills", 0)),
		"leaks": int(GameState.run_stats.get("leaks", 0)),
		"hero_level": game.hero.level if game.hero else 1,
		"bonds": game.towers.active_relationships.size(),
	})

func _on_victory() -> void:
	if finished:
		return
	finished = true
	result = {"outcome": "VICTORY", "wave": game.waves.wave_index + 1}
	print("[SIM] *** VICTORY on wave %d ***" % (game.waves.wave_index + 1))

func _on_defeat(_stats: Dictionary) -> void:
	if finished:
		return
	finished = true
	result = {"outcome": "DEFEAT", "wave": game.waves.wave_index + 1}
	print("[SIM] *** DEFEAT on wave %d ***" % (game.waves.wave_index + 1))

func on_finish() -> void:
	if result.is_empty():
		result = {"outcome": "TIMEOUT", "wave": game.waves.wave_index + 1}
	print("\n[SIM] ================ WAVE-BY-WAVE ================")
	print("[SIM] wave | lives | emeralds | towers | upg | kills | leaks | hero | bonds | name")
	for h in history:
		print("[SIM] %4d | %5d | %8d | %6d | %3d | %5d | %5d | %4d | %5d | %s" % [
			int(h["wave"]), int(h["lives"]), int(h["emeralds"]), int(h["towers"]), int(h["upgrades"]),
			int(h["kills"]), int(h["leaks"]), int(h["hero_level"]), int(h["bonds"]), String(h["name"])])
	print("\n[SIM] ================ RESULT ================")
	print("[SIM] outcome        : %s" % result.get("outcome"))
	print("[SIM] reached wave   : %d / %d" % [int(result.get("wave", 0)), game.waves.total_waves()])
	print("[SIM] lives          : %d / %d" % [GameState.lives, GameState.max_lives])
	print("[SIM] first leak     : %s" % ("wave %d" % first_leak_wave if first_leak_wave > 0 else "none"))
	print("[SIM] towers built   : %d" % int(GameState.run_stats.get("towers_built", 0)))
	print("[SIM] upgrades       : %d" % int(GameState.run_stats.get("upgrades", 0)))
	print("[SIM] kills / leaks  : %d / %d" % [
		int(GameState.run_stats.get("kills", 0)), int(GameState.run_stats.get("leaks", 0))])
	print("[SIM] emeralds left  : %d (earned %d, spent %d)" % [
		GameState.emeralds, int(GameState.run_stats.get("emeralds_earned", 0)),
		int(GameState.run_stats.get("emeralds_spent", 0))])
	print("[SIM] hero level     : %d" % (game.hero.level if game.hero else 0))
	print("[SIM] bonds active   : %d" % game.towers.active_relationships.size())
	print("[SIM] boss defeated  : %s" % bool(GameState.run_stats.get("boss_defeated", false)))
	print("[SIM] peak live      : %d" % peak_live)
	if kill_depth_n > 0:
		var bars: Array[String] = []
		for i in range(10):
			bars.append("%d%%" % int(round(100.0 * float(kill_depth[i]) / float(kill_depth_n))))
		print("[SIM] kill depth     : mean %.2f of path | by tenth %s" % [
			kill_depth_sum / float(kill_depth_n), " ".join(bars)])
		print("[SIM] killers        : %s" % _top(kill_source))
		print("[SIM] killers @>90%%  : %s" % _top(deep_source))
		print("[SIM] types @>90%%    : %s" % _top(deep_type))
	if game.hero != null and is_instance_valid(game.hero):
		var el: float = game.enemies.time_now
		print("[SIM] hero attacks   : %d hits in %.0fs (%.1f/s) | damage %.1f attack_time %.2f pierce %d" % [
			game.hero.hit_counter, el, float(game.hero.hit_counter) / maxf(1.0, el),
			game.hero.damage, game.hero.attack_time, game.hero.pierce])
	var dmg: Dictionary = game.enemies.damage_by_source
	var total_dmg := 0.0
	for k in dmg.keys():
		total_dmg += float(dmg[k])
	if total_dmg > 0.0:
		var keys: Array = dmg.keys()
		keys.sort_custom(func(a, b) -> bool: return float(dmg[a]) > float(dmg[b]))
		var parts: Array[String] = []
		for k in keys:
			parts.append("%s=%.0f%%" % [k, 100.0 * float(dmg[k]) / total_dmg])
		print("[SIM] damage share   : total %.0f | %s" % [total_dmg, " ".join(parts)])
	# A one-line verdict the tuning loop can grep for.
	print("[SIM] VERDICT %s wave=%d/%d lives=%d/%d leaks=%d unspent=%d" % [
		result.get("outcome"), int(result.get("wave", 0)), game.waves.total_waves(),
		GameState.lives, GameState.max_lives, int(GameState.run_stats.get("leaks", 0)),
		GameState.emeralds])

## Formats a source_id -> count tally as a descending "id=n" list, biggest contributors first.
func _top(tally: Dictionary) -> String:
	var keys: Array = tally.keys()
	keys.sort_custom(func(a, b) -> bool: return int(tally[a]) > int(tally[b]))
	var out: Array[String] = []
	for k in keys:
		out.append("%s=%d" % [k, int(tally[k])])
	return " ".join(out)
