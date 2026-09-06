class_name HeroSummon
extends Node3D
## A temporary allied fighter created by a hero ability (Royal Army, the NULL, Turncoat).

var enemies: EnemyManager
var projectiles: ProjectileManager
var visual: MinecraftCharacter
var damage: float = 45.0
var attack_time: float = 0.9
var range_r: float = 6.0
var life: float = 15.0
var source_id: String = ""
var cd: float = 0.0
var current_target: int = -1

func setup(character: String, enemy_mgr: EnemyManager, proj: ProjectileManager,
		dmg: float, rate: float, rng_r: float, duration: float, source: String) -> void:
	enemies = enemy_mgr
	projectiles = proj
	damage = dmg
	attack_time = rate
	range_r = rng_r
	life = duration
	source_id = source
	visual = MinecraftCharacter.new()
	add_child(visual)
	visual.setup(SkinLibrary.get_skin(character), {"chestplate": "iron", "helmet": "iron"}, "iron_sword")
	visual.attack_style = "slash"
	visual.attack_hit.connect(_on_hit)
	visual.play("idle")
	visual.set_emission(Color(0.4, 0.8, 1.0), 0.4)
	scale = Vector3(0.92, 0.92, 0.92)

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if life < 1.0 and is_instance_valid(visual):
		visual.set_ghost(1.0 - life)
	if enemies == null:
		return
	cd -= delta
	if cd <= 0.0:
		var t := _acquire()
		if t >= 0:
			current_target = t
			cd = attack_time
			visual.face_direction(enemies.unit_position(t) - global_position)
			visual.play("attack", minf(attack_time * 0.9, 0.4))

func _acquire() -> int:
	var candidates := enemies.query_targets(global_position, range_r, {"detect_invisible": true, "hit_air": false, "hit_ground": true})
	var best := -1
	var best_d := -INF
	for slot in candidates:
		if enemies.dist[slot] > best_d:
			best_d = enemies.dist[slot]
			best = slot
	return best

func _on_hit() -> void:
	if not enemies.is_alive(current_target):
		current_target = _acquire()
	if current_target < 0:
		return
	projectiles.fire("melee_swing", global_position + Vector3(0, 1.4, 0), current_target, {
		"damage": damage, "damage_type": "melee", "armor_pen": 0.2, "source": source_id, "pierce": 1,
	})
