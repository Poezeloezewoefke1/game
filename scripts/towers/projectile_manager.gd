class_name ProjectileManager
extends Node3D
## Pooled projectiles rendered as one MultiMesh per visual kind. Projectiles are plain data rows;
## they home on their target slot and resolve damage on arrival (or immediately for hitscan/melee).

const MAX_PROJECTILES := 1400

var kinds: Dictionary = {}          # kind name -> {mm, mmi, rows}
var enemies: EnemyManager

# rows
var alive: PackedByteArray = PackedByteArray()
var kind_idx: PackedInt32Array = PackedInt32Array()
var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
var pz: PackedFloat32Array = PackedFloat32Array()
var tx: PackedFloat32Array = PackedFloat32Array()
var ty: PackedFloat32Array = PackedFloat32Array()
var tz: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var target: PackedInt32Array = PackedInt32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var payload: Array = []             # Dictionary per projectile (damage, type, splash, pen, flags)
var free_slots: PackedInt32Array = PackedInt32Array()
var active: PackedInt32Array = PackedInt32Array()
var kind_names: Array = []

const KIND_SPECS := {
	"arrow": {"size": Vector3(0.08, 0.08, 0.7), "color": Color(0.85, 0.82, 0.7), "speed": 34.0, "trail": false},
	"bolt": {"size": Vector3(0.1, 0.1, 0.6), "color": Color(0.75, 0.78, 0.85), "speed": 44.0, "trail": false},
	"tnt_cart": {"size": Vector3(0.5, 0.4, 0.6), "color": Color(0.8, 0.18, 0.12), "speed": 16.0, "trail": true},
	"cannon_shell": {"size": Vector3(0.3, 0.3, 0.3), "color": Color(0.25, 0.25, 0.28), "speed": 20.0, "trail": true},
	"bottle": {"size": Vector3(0.22, 0.3, 0.22), "color": Color(0.5, 0.75, 0.95), "speed": 18.0, "trail": false},
	"petal": {"size": Vector3(0.2, 0.05, 0.2), "color": Color(1.0, 0.95, 0.75), "speed": 22.0, "trail": false},
	"redstone_pulse": {"size": Vector3(0.3, 0.3, 0.3), "color": Color(1.0, 0.25, 0.2), "speed": 30.0, "trail": false},
	"slime_pulse": {"size": Vector3(0.35, 0.35, 0.35), "color": Color(0.5, 0.9, 0.6), "speed": 26.0, "trail": false},
	"sand_burst": {"size": Vector3(0.28, 0.28, 0.28), "color": Color(0.9, 0.82, 0.55), "speed": 24.0, "trail": false},
	"wind_charge": {"size": Vector3(0.32, 0.32, 0.32), "color": Color(0.8, 0.95, 1.0), "speed": 28.0, "trail": false},
	"skull": {"size": Vector3(0.3, 0.3, 0.3), "color": Color(0.2, 0.2, 0.18), "speed": 18.0, "trail": true},
	"melee_swing": {"size": Vector3(0.01, 0.01, 0.01), "color": Color(1, 1, 1), "speed": 999.0, "trail": false},
	"melee_slam": {"size": Vector3(0.01, 0.01, 0.01), "color": Color(1, 1, 1), "speed": 999.0, "trail": false},
}

func setup(enemy_mgr: EnemyManager) -> void:
	enemies = enemy_mgr
	var n := MAX_PROJECTILES
	alive.resize(n); kind_idx.resize(n); px.resize(n); py.resize(n); pz.resize(n)
	tx.resize(n); ty.resize(n); tz.resize(n); speed.resize(n); target.resize(n); life.resize(n)
	payload.resize(n)
	free_slots.resize(n)
	for i in n:
		alive[i] = 0
		free_slots[i] = n - 1 - i
	active.clear()
	for kind in KIND_SPECS.keys():
		_make_kind(String(kind))

func _make_kind(kind: String) -> void:
	var spec: Dictionary = KIND_SPECS[kind]
	var mesh := BoxMesh.new()
	mesh.size = spec["size"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = spec["color"]
	mat.emission_enabled = true
	mat.emission = (spec["color"] as Color) * 0.6
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
	kinds[kind] = {"mm": mm, "mmi": mmi, "index": kind_names.size(), "rows": PackedInt32Array()}
	kind_names.append(kind)

## Fires a projectile. `data` carries damage, damage_type, splash, armor_pen, crit, and special flags.
func fire(kind: String, from: Vector3, target_slot: int, data: Dictionary) -> void:
	if not kinds.has(kind):
		kind = "arrow"
	if kind.begins_with("melee"):
		_resolve_hit(target_slot, from, data)
		return
	if free_slots.is_empty():
		_resolve_hit(target_slot, from, data)
		return
	var slot: int = free_slots[free_slots.size() - 1]
	free_slots.remove_at(free_slots.size() - 1)
	alive[slot] = 1
	kind_idx[slot] = int(kinds[kind]["index"])
	px[slot] = from.x; py[slot] = from.y; pz[slot] = from.z
	target[slot] = target_slot
	var tp := enemies.unit_position(target_slot) if enemies.is_alive(target_slot) else from
	tx[slot] = tp.x; ty[slot] = tp.y; tz[slot] = tp.z
	speed[slot] = float(data.get("projectile_speed", KIND_SPECS[kind]["speed"]))
	life[slot] = 4.0
	payload[slot] = data
	active.push_back(slot)

func _process(delta: float) -> void:
	if enemies == null:
		return
	var w := 0
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 0:
			continue
		life[slot] -= delta
		if life[slot] <= 0.0:
			_despawn(slot)
			continue
		# home on the live target, else keep the last known point
		if enemies.is_alive(target[slot]):
			var tp := enemies.unit_position(target[slot])
			tx[slot] = tp.x; ty[slot] = tp.y + 0.9; tz[slot] = tp.z
		var cur := Vector3(px[slot], py[slot], pz[slot])
		var dest := Vector3(tx[slot], ty[slot], tz[slot])
		var to_target := dest - cur
		var step := speed[slot] * delta
		if to_target.length() <= step:
			_resolve_hit(target[slot], dest, payload[slot])
			_despawn(slot)
			continue
		var nxt := cur + to_target.normalized() * step
		px[slot] = nxt.x; py[slot] = nxt.y; pz[slot] = nxt.z
		active[w] = slot
		w += 1
	if w != active.size():
		active.resize(w)
	_upload()

func _despawn(slot: int) -> void:
	alive[slot] = 0
	payload[slot] = null
	free_slots.push_back(slot)

## Applies a projectile's payload at the point of impact.
func _resolve_hit(slot: int, at: Vector3, data: Dictionary) -> void:
	if data == null:
		return
	var dmg := float(data.get("damage", 0.0))
	var dtype := String(data.get("damage_type", "melee"))
	var pen := float(data.get("armor_pen", 0.0))
	var source := String(data.get("source", ""))
	var crit_chance := float(data.get("crit_chance", 0.0))
	var crit_mult := float(data.get("crit_mult", 2.0))
	var splash := float(data.get("splash", 0.0))
	var pierce := int(data.get("pierce", 1))
	var hit_any := false

	if splash > 0.0:
		var centre := at
		if enemies.is_alive(slot):
			centre = enemies.unit_position(slot)
		for other in enemies.query_range(centre, splash):
			var f := DamageCalc.splash_falloff(enemies.unit_position(other).distance_to(centre), splash)
			var actual := _boss_scaled(other, dmg * f, data)
			enemies.damage(other, actual, dtype, pen, source, crit_chance, crit_mult)
			_apply_effects(other, data)
			hit_any = true
		_spawn_impact(centre, splash)
	else:
		var hits := 0
		if enemies.is_alive(slot):
			enemies.damage(slot, _boss_scaled(slot, dmg, data), dtype, pen, source, crit_chance, crit_mult)
			_apply_effects(slot, data)
			hits += 1
			hit_any = true
		if pierce > hits:
			var centre2 := enemies.unit_position(slot) if enemies.is_alive(slot) else at
			for other in enemies.query_targets(centre2, 2.2, data.get("filter", {})):
				if hits >= pierce:
					break
				if other == slot:
					continue
				enemies.damage(other, _boss_scaled(other, dmg, data), dtype, pen, source, crit_chance, crit_mult)
				_apply_effects(other, data)
				hits += 1
				hit_any = true
	# chaining
	var chain := int(data.get("chain", 0))
	if chain > 0 and hit_any:
		var origin := at
		var jumped := 0
		var already := {slot: true}
		for other in enemies.query_range(origin, 6.0):
			if jumped >= chain:
				break
			if already.has(other):
				continue
			already[other] = true
			enemies.damage(other, dmg * 0.6, dtype, pen, source)
			_apply_effects(other, data)
			jumped += 1

func _boss_scaled(slot: int, dmg: float, data: Dictionary) -> float:
	var mult := float(data.get("boss_damage_mult", 1.0))
	if mult != 1.0 and (enemies.flags[slot] & (EnemyManager.F_BOSS | EnemyManager.F_MINI_BOSS)) != 0:
		return dmg * mult
	return dmg

func _apply_effects(slot: int, data: Dictionary) -> void:
	if not enemies.is_alive(slot):
		return
	if data.has("slow_mult"):
		enemies.apply_slow(slot, float(data["slow_mult"]), float(data.get("slow_duration", 2.0)))
	if data.has("stun_duration"):
		enemies.apply_stun(slot, float(data["stun_duration"]))
	if data.has("knockback"):
		enemies.push_back(slot, float(data["knockback"]))
	if data.has("execute_threshold"):
		var thr := float(data["execute_threshold"])
		if (enemies.flags[slot] & EnemyManager.F_BOSS) == 0 and enemies.max_hp[slot] > 0.0:
			if enemies.hp[slot] / enemies.max_hp[slot] <= thr:
				EventBus.float_text.emit(enemies.unit_position(slot), "EXECUTED", Color(1.0, 0.3, 0.3))
				enemies.damage(slot, enemies.hp[slot] + 1.0, "true", 1.0, String(data.get("source", "")))

func _spawn_impact(at: Vector3, radius: float) -> void:
	EventBus.camera_shake.emit(clampf(radius * 0.06, 0.0, 0.4), 0.15)

func _upload() -> void:
	for kind in kinds.keys():
		(kinds[kind]["rows"] as PackedInt32Array).clear()
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 0:
			continue
		var name: String = kind_names[kind_idx[slot]]
		(kinds[name]["rows"] as PackedInt32Array).push_back(slot)
	for kind in kinds.keys():
		var rows: PackedInt32Array = kinds[kind]["rows"]
		var mm: MultiMesh = kinds[kind]["mm"]
		if mm.instance_count != rows.size():
			mm.instance_count = rows.size()
		for k in rows.size():
			var slot: int = rows[k]
			var pos := Vector3(px[slot], py[slot], pz[slot])
			var dir := Vector3(tx[slot] - px[slot], ty[slot] - py[slot], tz[slot] - pz[slot])
			var b := Basis.IDENTITY
			if dir.length_squared() > 0.001:
				b = Basis.looking_at(dir.normalized(), Vector3.UP)
			mm.set_instance_transform(k, Transform3D(b, pos))

func clear_all() -> void:
	for i in active.size():
		var slot: int = active[i]
		if alive[slot] == 1:
			_despawn(slot)
	active.clear()
