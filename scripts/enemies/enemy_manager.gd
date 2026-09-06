class_name EnemyManager
extends Node3D
## Data-oriented enemy pool. Enemies are rows in parallel arrays, never individual nodes, so a wave of
## a thousand units costs a handful of array writes plus one MultiMesh upload per visual group.
##
## Responsibilities: spawning, movement along MapPath, status effects, data-driven abilities,
## gear-break downgrades, rewards, leaks, spatial queries for towers, and MultiMesh rendering.

const CELL_SIZE := 4.0
const MAX_CAPACITY := 2200

# --- flags -------------------------------------------------------------------------------------
const F_FLYING := 1
const F_INVISIBLE := 2
const F_BOSS := 4
const F_MINI_BOSS := 8
const F_STRUCTURE := 16
const F_AIRDROP := 32
const F_CART := 64
const F_SWIFT := 128
const F_OFF_PATH := 256
const F_NO_DOWNGRADE_REWARD := 512
const F_MOUNTED := 1024

const FLAG_NAMES := {
	"flying": F_FLYING, "invisible": F_INVISIBLE, "boss": F_BOSS, "mini_boss": F_MINI_BOSS,
	"structure": F_STRUCTURE, "airdrop": F_AIRDROP, "cart": F_CART, "swift": F_SWIFT,
	"off_path": F_OFF_PATH, "no_downgrade_reward": F_NO_DOWNGRADE_REWARD, "mounted": F_MOUNTED,
}

# --- pools -------------------------------------------------------------------------------------
var capacity: int = 0
var alive: PackedByteArray = PackedByteArray()
var type_idx: PackedInt32Array = PackedInt32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var max_hp: PackedFloat32Array = PackedFloat32Array()
var dist: PackedFloat32Array = PackedFloat32Array()
var base_speed: PackedFloat32Array = PackedFloat32Array()
var lateral: PackedFloat32Array = PackedFloat32Array()
var armor: PackedFloat32Array = PackedFloat32Array()
var flags: PackedInt32Array = PackedInt32Array()
var slow_until: PackedFloat32Array = PackedFloat32Array()
var slow_mult: PackedFloat32Array = PackedFloat32Array()
var stun_until: PackedFloat32Array = PackedFloat32Array()
var flash_until: PackedFloat32Array = PackedFloat32Array()
var phase: PackedFloat32Array = PackedFloat32Array()
var y_offset: PackedFloat32Array = PackedFloat32Array()
var cd_a: PackedFloat32Array = PackedFloat32Array()
var cd_b: PackedFloat32Array = PackedFloat32Array()
var group_idx: PackedInt32Array = PackedInt32Array()
var used_once: PackedByteArray = PackedByteArray()      # totem revive / one-shot ability marker
var spawn_time: PackedFloat32Array = PackedFloat32Array()
var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var pos_z: PackedFloat32Array = PackedFloat32Array()
var scripted: PackedByteArray = PackedByteArray()       # 1 = external controller drives movement

var free_slots: PackedInt32Array = PackedInt32Array()
var active: PackedInt32Array = PackedInt32Array()
var active_pos: PackedInt32Array = PackedInt32Array()   # slot -> index within `active`

# --- defs / visuals ----------------------------------------------------------------------------
var defs: Array = []
var def_index: Dictionary = {}
var groups: Array = []                                   # {key, mmi, mm, slots, def_idx}
var group_lookup: Dictionary = {}
var path: MapPath
var faction: Dictionary = {}
var time_now: float = 0.0
var hp_scale: float = 1.0
var speed_scale: float = 1.0
var reward_scale: float = 1.0
var rng := RandomNumberGenerator.new()
var enabled: bool = true

# spatial grid
var _grid: Dictionary = {}
var _grid_dirty: bool = true

# statistics
var total_spawned: int = 0
var total_killed: int = 0
var live_count: int = 0

signal leaked(slot: int, threat: int)

func _ready() -> void:
	rng.randomize()

func setup(map_path: MapPath, faction_def: Dictionary, cap: int = 1200) -> void:
	path = map_path
	faction = faction_def
	_load_defs()
	_resize(min(cap, MAX_CAPACITY))
	hp_scale = float(faction.get("hp_mult", 1.0)) * GameState.difficulty_mult("enemy_hp")
	speed_scale = float(faction.get("speed_mult", 1.0))
	reward_scale = float(faction.get("reward_mult", 1.0)) * GameState.difficulty_mult("income")

func _load_defs() -> void:
	defs.clear()
	def_index.clear()
	for id in DataDB.enemies.keys():
		var d: Dictionary = (DataDB.enemies[id] as Dictionary).duplicate(true)
		d["flag_mask"] = _mask_from(d.get("flags", []))
		def_index[id] = defs.size()
		defs.append(d)

static func _mask_from(list) -> int:
	var m := 0
	if typeof(list) == TYPE_ARRAY:
		for f in list:
			m |= int(FLAG_NAMES.get(String(f), 0))
	return m

func _resize(n: int) -> void:
	capacity = n
	alive.resize(n); type_idx.resize(n); hp.resize(n); max_hp.resize(n); dist.resize(n)
	base_speed.resize(n); lateral.resize(n); armor.resize(n); flags.resize(n)
	slow_until.resize(n); slow_mult.resize(n); stun_until.resize(n); flash_until.resize(n)
	phase.resize(n); y_offset.resize(n); cd_a.resize(n); cd_b.resize(n); group_idx.resize(n)
	used_once.resize(n); spawn_time.resize(n); pos_x.resize(n); pos_y.resize(n); pos_z.resize(n)
	scripted.resize(n); active_pos.resize(n)
	free_slots.resize(n)
	for i in n:
		alive[i] = 0
		group_idx[i] = -1
		active_pos[i] = -1
		free_slots[i] = n - 1 - i
	active.clear()

# ================================================================================================
# Spawning
# ================================================================================================

func spawn(type_id: String, at_distance: float = 0.0, lateral_override := NAN, hp_mult: float = 1.0) -> int:
	if not def_index.has(type_id):
		push_warning("[EnemyManager] unknown enemy type: %s" % type_id)
		return -1
	if free_slots.is_empty():
		return -1
	var slot: int = free_slots[free_slots.size() - 1]
	free_slots.remove_at(free_slots.size() - 1)
	var di: int = def_index[type_id]
	var d: Dictionary = defs[di]
	var mask: int = d["flag_mask"]

	alive[slot] = 1
	type_idx[slot] = di
	var hp_value := float(d.get("hp", 10)) * hp_scale * hp_mult
	hp[slot] = hp_value
	max_hp[slot] = hp_value
	dist[slot] = at_distance
	base_speed[slot] = float(d.get("speed", 1.5)) * speed_scale
	armor[slot] = float(d.get("armor_pct", 0.0))
	flags[slot] = mask
	slow_until[slot] = 0.0
	slow_mult[slot] = 1.0
	stun_until[slot] = 0.0
	flash_until[slot] = 0.0
	phase[slot] = rng.randf()
	cd_a[slot] = 0.0
	cd_b[slot] = 0.0
	used_once[slot] = 0
	spawn_time[slot] = time_now
	scripted[slot] = 0
	var spread := float(d.get("lane_spread", 0.7))
	lateral[slot] = rng.randf_range(-spread, spread) if is_nan(lateral_override) else lateral_override
	y_offset[slot] = float(d.get("fly_height", 0.0)) if (mask & F_FLYING) != 0 else 0.0
	if (mask & F_AIRDROP) != 0:
		y_offset[slot] = float(d.get("drop_height", 12.0))
	group_idx[slot] = _resolve_group(di)
	active_pos[slot] = active.size()
	active.push_back(slot)
	live_count += 1
	total_spawned += 1
	_grid_dirty = true
	_update_position(slot)
	EventBus.enemy_spawned.emit(slot, String(d.get("id", "")))
	if (mask & (F_BOSS | F_MINI_BOSS)) != 0:
		EventBus.boss_slot_changed.emit(slot)
	return slot

## Chooses (and lazily creates) the MultiMesh group for a definition, applying faction skin overrides.
func _resolve_group(di: int) -> int:
	var d: Dictionary = defs[di]
	var model := String(d.get("model", ""))
	var skin_id := ""
	if model == "":
		var pool: Array = d.get("skin_pool", [])
		var overrides: Dictionary = faction.get("skin_overrides", {})
		var cat := String(d.get("category", ""))
		if overrides.has(cat):
			pool = overrides[cat]
		if pool.is_empty():
			skin_id = "chungie"
		else:
			skin_id = String(pool[rng.randi() % pool.size()])
	var key := "%d|%s|%s" % [di, model, skin_id]
	if group_lookup.has(key):
		return group_lookup[key]
	var g := _create_group(key, di, model, skin_id)
	group_lookup[key] = g
	return g

func _create_group(key: String, di: int, model: String, skin_id: String) -> int:
	var d: Dictionary = defs[di]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	var mat: ShaderMaterial
	if model != "":
		mm.mesh = PropBuilder.get_mesh(model)
		mat = MCMaterials.make(SkinLibrary.get_skin("chungie").get_texture(), false, true)
	else:
		var extras: Array = []
		mm.mesh = SkinLibrary.get_merged_mesh(skin_id, d.get("armor", {}), String(d.get("held", "")), extras)
		mat = SkinLibrary.get_material(skin_id, (d["flag_mask"] & F_INVISIBLE) != 0, true)
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.extra_cull_margin = 16.0
	add_child(mmi)
	var extra_node: Node3D = null
	if String(d.get("extras", "")) != "":
		# Mount / cart props ride along with their rider in a second MultiMesh.
		var emm := MultiMesh.new()
		emm.transform_format = MultiMesh.TRANSFORM_3D
		emm.use_custom_data = true
		emm.use_colors = true
		emm.mesh = PropBuilder.get_mesh(String(d["extras"]))
		emm.instance_count = 0
		var emmi := MultiMeshInstance3D.new()
		emmi.multimesh = emm
		emmi.material_override = MCMaterials.make(SkinLibrary.get_skin("chungie").get_texture(), false, true)
		emmi.extra_cull_margin = 16.0
		add_child(emmi)
		extra_node = emmi
	groups.append({"key": key, "mmi": mmi, "mm": mm, "slots": PackedInt32Array(), "def_idx": di,
		"skin": skin_id, "extra": extra_node, "tint_applied": false})
	return groups.size() - 1

# ================================================================================================
# Frame update
# ================================================================================================

func _process(delta: float) -> void:
	if not enabled or path == null:
		return
	time_now += delta
	_update_units(delta)
	_rebuild_grid()
	_upload_visuals()

func _update_units(delta: float) -> void:
	var i := 0
	while i < active.size():
		var slot: int = active[i]
		if alive[slot] == 0:
			i += 1
			continue
		var d: Dictionary = defs[type_idx[slot]]
		var mask: int = flags[slot]
		# --- status
		if slow_until[slot] <= time_now:
			slow_mult[slot] = 1.0
		var stunned: bool = stun_until[slot] > time_now
		# --- descent for airdropped units
		if y_offset[slot] > 0.0 and (mask & F_AIRDROP) != 0:
			var drop_rate: float = float(d.get("drop_height", 12.0)) / maxf(0.5, float(d.get("drop_seconds", 3.0)))
			y_offset[slot] = maxf(0.0, y_offset[slot] - drop_rate * delta)
		# --- movement
		if not stunned and scripted[slot] == 0 and (mask & F_STRUCTURE) == 0:
			var spd: float = base_speed[slot] * slow_mult[slot]
			if (mask & F_AIRDROP) != 0 and y_offset[slot] > 0.1:
				spd = 0.0
			dist[slot] += spd * delta
			phase[slot] += spd * delta * 0.55
		_update_position(slot)
		# --- abilities
		var abilities: Array = d.get("abilities", [])
		if not abilities.is_empty() and not stunned:
			_tick_abilities(slot, d, abilities, delta)
		# --- reached the base
		if dist[slot] >= path.total_length and (mask & F_STRUCTURE) == 0 and (mask & F_OFF_PATH) == 0:
			_leak(slot, d)
			i += 1
			continue
		i += 1
	_compact_active()

func _update_position(slot: int) -> void:
	var d: Dictionary = defs[type_idx[slot]]
	var clamped: float = clampf(dist[slot], 0.0, path.total_length)
	var p := path.position_offset(clamped, lateral[slot])
	pos_x[slot] = p.x
	pos_y[slot] = p.y + y_offset[slot]
	pos_z[slot] = p.z

func _compact_active() -> void:
	var w := 0
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 1:
			active[w] = slot
			active_pos[slot] = w
			w += 1
	if w != active.size():
		active.resize(w)

# ================================================================================================
# Abilities (data-driven)
# ================================================================================================

func _tick_abilities(slot: int, d: Dictionary, abilities: Array, delta: float) -> void:
	cd_a[slot] -= delta
	for a in abilities:
		var t := String(a.get("type", ""))
		match t:
			"regen":
				if hp[slot] < max_hp[slot]:
					hp[slot] = minf(max_hp[slot], hp[slot] + float(a.get("hps", 1.0)) * delta)
			"heal_aura":
				if cd_a[slot] <= 0.0:
					cd_a[slot] = 0.5
					var r := float(a.get("radius", 3.0))
					var hps := float(a.get("hps", 3.0)) * 0.5
					for other in query_range(unit_position(slot), r):
						if other != slot and hp[other] < max_hp[other]:
							hp[other] = minf(max_hp[other], hp[other] + hps)
			"command_aura":
				if cd_a[slot] <= 0.0:
					cd_a[slot] = 0.5
					var r2 := float(a.get("radius", 4.0))
					var sm := float(a.get("speed_mult", 1.2))
					for other in query_range(unit_position(slot), r2):
						if other != slot and slow_until[other] <= time_now:
							slow_mult[other] = sm
							slow_until[other] = time_now + 0.6
			"expire":
				if time_now - spawn_time[slot] >= float(a.get("seconds", 10.0)):
					kill(slot, "expire", false)
			"blink":
				if cd_b[slot] <= 0.0:
					cd_b[slot] = float(a.get("cooldown", 5.0))
					dist[slot] += float(a.get("distance", 4.0))
					EventBus.float_text.emit(unit_position(slot), "blink", Color(0.5, 0.9, 0.8))
				else:
					cd_b[slot] -= delta
			"build_wall":
				if cd_b[slot] <= 0.0:
					cd_b[slot] = float(a.get("cooldown", 8.0))
					var ahead: float = dist[slot] + float(a.get("ahead", 2.0))
					if ahead < path.total_length - 2.0:
						spawn(String(a.get("wall_id", "cobble_wall")), ahead, 0.0)
				else:
					cd_b[slot] -= delta
			_:
				pass

## Abilities that fire when the unit dies. Returns true if the unit should survive (totem revive).
func _death_abilities(slot: int, d: Dictionary) -> bool:
	for a in d.get("abilities", []):
		var t := String(a.get("type", ""))
		match t:
			"death_explosion":
				var r := float(a.get("radius", 2.5))
				var dmg := float(a.get("damage", 40.0))
				var centre := unit_position(slot)
				EventBus.camera_shake.emit(0.35, 0.25)
				AudioMgr.play_sfx_at("explosion", centre, -3.0)
				for other in query_range(centre, r):
					if other != slot:
						var falloff := DamageCalc.splash_falloff(unit_position(other).distance_to(centre), r)
						damage(other, dmg * falloff, "explosive", 0.5, "tnt")
			"death_splash_slow":
				var r2 := float(a.get("radius", 3.0))
				for other in query_range(unit_position(slot), r2):
					if other != slot:
						apply_slow(other, float(a.get("slow_mult", 0.6)), float(a.get("duration", 3.0)))
			"totem_revive":
				if used_once[slot] == 0:
					used_once[slot] = 1
					hp[slot] = max_hp[slot] * float(a.get("hp_fraction", 0.5))
					flash_until[slot] = time_now + 0.4
					EventBus.float_text.emit(unit_position(slot), "TOTEM!", Color(1.0, 0.85, 0.2))
					AudioMgr.play_sfx_at("totem", unit_position(slot), -2.0)
					return true
	return false

# ================================================================================================
# Damage / death
# ================================================================================================

## Applies damage through the armor formula. Returns damage actually dealt.
func damage(slot: int, amount: float, damage_type: String = "melee", armor_pen: float = 0.0,
		source_id: String = "", crit_chance: float = 0.0, crit_mult: float = 2.0) -> float:
	if slot < 0 or slot >= capacity or alive[slot] == 0 or amount <= 0.0:
		return 0.0
	var d: Dictionary = defs[type_idx[slot]]
	var target := {
		"armor_pct": armor[slot],
		"is_structure": (flags[slot] & F_STRUCTURE) != 0,
		"blocks_projectiles": _blocks_projectiles(d),
	}
	var res := DamageCalc.resolve(amount, damage_type, armor_pen, target, crit_chance, crit_mult, rng.randf())
	var dealt: float = minf(float(res["damage"]), hp[slot])
	hp[slot] -= float(res["damage"])
	flash_until[slot] = time_now + 0.12
	GameState.run_stats["damage_dealt"] = float(GameState.run_stats.get("damage_dealt", 0.0)) + dealt
	if bool(res["crit"]):
		EventBus.float_text.emit(unit_position(slot), "%d!" % int(res["damage"]), Color(1.0, 0.85, 0.3))
	if hp[slot] <= 0.0:
		var overflow: float = -hp[slot]
		_on_zero_hp(slot, d, overflow, source_id)
	return dealt

func _blocks_projectiles(d: Dictionary) -> bool:
	for a in d.get("abilities", []):
		if String(a.get("type", "")) == "projectile_block":
			return rng.randf() < float(a.get("chance", 0.3))
	return false

func _on_zero_hp(slot: int, d: Dictionary, overflow: float, source_id: String) -> void:
	if _death_abilities(slot, d):
		return
	var reward := int(round(float(d.get("reward", 0)) * reward_scale))
	var downgrade := String(d.get("downgrade_to", "")) if d.get("downgrade_to") != null else ""
	if (flags[slot] & F_NO_DOWNGRADE_REWARD) == 0:
		GameState.add_emeralds(reward)
	GameState.run_stats["kills"] = int(GameState.run_stats.get("kills", 0)) + 1
	SaveSystem.data["stats"]["total_kills"] = int(SaveSystem.data["stats"].get("total_kills", 0)) + 1
	if downgrade != "" and def_index.has(downgrade):
		_downgrade(slot, downgrade, overflow, source_id, String(d.get("id", "")))
	else:
		kill(slot, source_id, true)

## Converts a unit into its next gear layer down, keeping position and carrying overflow damage.
func _downgrade(slot: int, to_id: String, overflow: float, source_id: String, from_id: String) -> void:
	var di: int = def_index[to_id]
	var d: Dictionary = defs[di]
	type_idx[slot] = di
	var new_hp := float(d.get("hp", 10)) * hp_scale
	hp[slot] = new_hp
	max_hp[slot] = new_hp
	base_speed[slot] = float(d.get("speed", 1.5)) * speed_scale
	armor[slot] = float(d.get("armor_pct", 0.0))
	flags[slot] = int(d["flag_mask"])
	group_idx[slot] = _resolve_group(di)
	flash_until[slot] = time_now + 0.15
	used_once[slot] = 0
	AudioMgr.play_sfx_at("armor_break", unit_position(slot), -6.0)
	EventBus.enemy_downgraded.emit(slot, from_id, to_id)
	if overflow > 0.0:
		damage(slot, overflow, "true", 1.0, source_id)

func kill(slot: int, source_id: String = "", count_stat: bool = true) -> void:
	if slot < 0 or slot >= capacity or alive[slot] == 0:
		return
	var d: Dictionary = defs[type_idx[slot]]
	alive[slot] = 0
	live_count -= 1
	_grid_dirty = true
	if count_stat:
		total_killed += 1
	free_slots.push_back(slot)
	EventBus.enemy_killed.emit(slot, String(d.get("id", "")), source_id)
	if (flags[slot] & (F_BOSS | F_MINI_BOSS)) != 0:
		AudioMgr.play_sfx("boss_down", -2.0)

func _leak(slot: int, d: Dictionary) -> void:
	var threat := int(d.get("threat", 1))
	alive[slot] = 0
	live_count -= 1
	_grid_dirty = true
	free_slots.push_back(slot)
	GameState.damage_base(threat)
	EventBus.enemy_leaked.emit(slot, String(d.get("id", "")), threat)
	leaked.emit(slot, threat)
	AudioMgr.play_sfx("leak", -4.0)

func clear_all() -> void:
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 1:
			alive[slot] = 0
			free_slots.push_back(slot)
	active.clear()
	live_count = 0
	_grid_dirty = true

# ================================================================================================
# Status effects
# ================================================================================================

func apply_slow(slot: int, mult: float, duration: float) -> void:
	if alive[slot] == 0:
		return
	if (flags[slot] & F_BOSS) != 0:
		mult = lerpf(1.0, mult, 0.4)      # bosses are resistant, never immune
	if mult < slow_mult[slot] or slow_until[slot] <= time_now:
		slow_mult[slot] = mult
	slow_until[slot] = maxf(slow_until[slot], time_now + duration)

func apply_stun(slot: int, duration: float) -> void:
	if alive[slot] == 0:
		return
	if (flags[slot] & F_BOSS) != 0:
		duration *= 0.35
	stun_until[slot] = maxf(stun_until[slot], time_now + duration)

func push_back(slot: int, amount: float) -> void:
	if alive[slot] == 0 or (flags[slot] & F_BOSS) != 0:
		return
	dist[slot] = maxf(0.0, dist[slot] - amount)

# ================================================================================================
# Queries
# ================================================================================================

func unit_position(slot: int) -> Vector3:
	return Vector3(pos_x[slot], pos_y[slot], pos_z[slot])

func is_alive(slot: int) -> bool:
	return slot >= 0 and slot < capacity and alive[slot] == 1

func type_id_of(slot: int) -> String:
	return String(defs[type_idx[slot]].get("id", ""))

func def_of(slot: int) -> Dictionary:
	return defs[type_idx[slot]]

func is_invisible(slot: int) -> bool:
	return (flags[slot] & F_INVISIBLE) != 0

func is_flying(slot: int) -> bool:
	return (flags[slot] & F_FLYING) != 0

func _cell_key(x: float, z: float) -> int:
	var cx := int(floor(x / CELL_SIZE)) + 4096
	var cz := int(floor(z / CELL_SIZE)) + 4096
	return cx * 8192 + cz

func _rebuild_grid() -> void:
	_grid_dirty = false
	_grid.clear()
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 0:
			continue
		var key := _cell_key(pos_x[slot], pos_z[slot])
		if _grid.has(key):
			(_grid[key] as PackedInt32Array).push_back(slot)
		else:
			var arr := PackedInt32Array()
			arr.push_back(slot)
			_grid[key] = arr

## All living enemies whose centre is within `radius` of `centre` (XZ distance, y ignored).
## The grid is rebuilt once per frame; a spawn or death since then marks it dirty so queries made
## in the same frame (boss scripts, death explosions, tests) still see an accurate world.
func query_range(centre: Vector3, radius: float) -> PackedInt32Array:
	if _grid_dirty:
		_rebuild_grid()
	var out := PackedInt32Array()
	var r2 := radius * radius
	var cells := int(ceil(radius / CELL_SIZE))
	var base_cx := int(floor(centre.x / CELL_SIZE))
	var base_cz := int(floor(centre.z / CELL_SIZE))
	for ox in range(-cells, cells + 1):
		for oz in range(-cells, cells + 1):
			var key := ((base_cx + ox) + 4096) * 8192 + ((base_cz + oz) + 4096)
			if not _grid.has(key):
				continue
			for slot in (_grid[key] as PackedInt32Array):
				if alive[slot] == 0:
					continue
				var dx := pos_x[slot] - centre.x
				var dz := pos_z[slot] - centre.z
				if dx * dx + dz * dz <= r2:
					out.push_back(slot)
	return out

## Query with targeting filters applied. `opts` keys: detect_invisible, hit_air, hit_ground, ignore_structures.
func query_targets(centre: Vector3, radius: float, opts: Dictionary) -> PackedInt32Array:
	var detect: bool = opts.get("detect_invisible", false)
	var air: bool = opts.get("hit_air", true)
	var ground: bool = opts.get("hit_ground", true)
	var skip_structures: bool = opts.get("ignore_structures", true)
	var out := PackedInt32Array()
	for slot in query_range(centre, radius):
		var f: int = flags[slot]
		if (f & F_INVISIBLE) != 0 and not detect:
			continue
		if (f & F_FLYING) != 0:
			if not air:
				continue
		elif not ground:
			continue
		if skip_structures and (f & F_STRUCTURE) != 0:
			continue
		out.push_back(slot)
	return out

func boss_slot() -> int:
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 1 and (flags[slot] & F_BOSS) != 0:
			return slot
	return -1

# ================================================================================================
# Rendering
# ================================================================================================

func _upload_visuals() -> void:
	for g in groups:
		(g["slots"] as PackedInt32Array).clear()
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 0:
			continue
		var gi: int = group_idx[slot]
		if gi >= 0:
			(groups[gi]["slots"] as PackedInt32Array).push_back(slot)
	for g in groups:
		var slots: PackedInt32Array = g["slots"]
		var mm: MultiMesh = g["mm"]
		var n := slots.size()
		if mm.instance_count != n:
			mm.instance_count = n
		var extra_node = g["extra"]
		var extra_mm: MultiMesh = null
		if extra_node != null:
			extra_mm = (extra_node as MultiMeshInstance3D).multimesh
			if extra_mm.instance_count != n:
				extra_mm.instance_count = n
		if n == 0:
			continue
		var d: Dictionary = defs[g["def_idx"]]
		var scale := float(d.get("scale", 1.0))
		var tint: Color = _faction_tint()
		for k in n:
			var slot: int = slots[k]
			var yaw := _yaw_of(slot)
			var basis := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(scale, scale, scale))
			var xform := Transform3D(basis, Vector3(pos_x[slot], pos_y[slot], pos_z[slot]))
			mm.set_instance_transform(k, xform)
			var moving := 1.0 if (stun_until[slot] <= time_now and (flags[slot] & F_STRUCTURE) == 0) else 0.0
			var flash := 1.0 if flash_until[slot] > time_now else 0.0
			var ghost := 0.55 if (flags[slot] & F_INVISIBLE) != 0 else 0.0
			mm.set_instance_custom_data(k, Color(phase[slot], flash, ghost, 0.85 * moving))
			mm.set_instance_color(k, tint)
			if extra_mm != null:
				extra_mm.set_instance_transform(k, xform)
				extra_mm.set_instance_custom_data(k, Color(phase[slot], flash, 0.0, 0.0))
				extra_mm.set_instance_color(k, Color.WHITE)

func _yaw_of(slot: int) -> float:
	var t := path.tangent_at(clampf(dist[slot], 0.0, path.total_length))
	# Characters model-face -Z, so yaw = atan2(-x, -z) of the travel direction.
	return atan2(-t.x, -t.z)

func _faction_tint() -> Color:
	var t = faction.get("tint", null)
	if typeof(t) == TYPE_ARRAY and (t as Array).size() >= 3:
		return Color(t[0], t[1], t[2])
	return Color.WHITE

func node_count_estimate() -> int:
	return groups.size() * 2
