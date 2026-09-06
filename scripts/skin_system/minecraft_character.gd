class_name MinecraftCharacter
extends Node3D
## Node-based Minecraft-style character: six articulated body parts, optional armor pieces and a held item,
## all generated from a SkinData. Procedural animation lives here (idle / walk / attack styles / hurt / death).
##
## Tree:  MinecraftCharacter
##          ├── Head (MeshInstance3D)  [+ Helmet]
##          ├── Body                     [+ Chestplate, Leggings hip, Cape, Elytra]
##          ├── RightArm                 [+ Pauldron, Held (weapon)]
##          ├── LeftArm
##          ├── RightLeg                 [+ Legging, Boot]
##          └── LeftLeg

signal attack_hit()          # emitted at the "impact" frame of an attack animation
signal animation_finished(anim_name: String)

var skin: SkinData
var parts: Dictionary = {}          # part name -> MeshInstance3D
var armor_nodes: Array = []
var held_node: MeshInstance3D
var material: ShaderMaterial
var armor: Dictionary = {}
var held_id: String = ""
var attack_style: String = "slash"  # slash | slam | point | throw | shoot | cast

var anim_state: String = "idle"
var anim_time: float = 0.0
var walk_speed_factor: float = 1.0
var one_shot_duration: float = 0.0
var _hit_emitted: bool = false
var _flash: float = 0.0
var _dead: bool = false
var _base_y: float = 0.0
var _rng_offset: float = 0.0

func setup(skin_data: SkinData, armor_set: Dictionary = {}, held: String = "", ghost: bool = false) -> void:
	skin = skin_data
	_rng_offset = randf() * TAU
	for c in get_children():
		c.queue_free()
	parts.clear()
	armor_nodes.clear()
	material = MCMaterials.make(skin.get_texture(), ghost, false)
	var defs := MCGeometry.part_defs(skin.slim, skin.legacy)
	for def in defs:
		var mi := MeshInstance3D.new()
		mi.name = def["name"]
		mi.mesh = MCMeshBuilder.build_part_mesh(skin, def)
		mi.material_override = material
		mi.position = Vector3(def["pivot"]) * MCGeometry.PX
		add_child(mi)
		parts[def["name"]] = mi
	set_armor(armor_set)
	set_held(held)

func set_armor(armor_set: Dictionary) -> void:
	armor = armor_set.duplicate()
	for n in armor_nodes:
		if is_instance_valid(n):
			n.queue_free()
	armor_nodes.clear()
	if skin == null:
		return
	var defs := MCGeometry.part_defs(skin.slim, skin.legacy)
	var by_part: Dictionary = {}
	for box in ArmorBuilder.boxes_for_set(armor, skin.slim):
		var p: int = box["part"]
		if not by_part.has(p):
			by_part[p] = []
		by_part[p].append(box)
	for p in by_part.keys():
		var def := MCGeometry.part_def(defs, p)
		var mi := MeshInstance3D.new()
		mi.name = "Armor_" + def["name"]
		mi.mesh = ArmorBuilder.build_piece_mesh(by_part[p], def["pivot"])
		mi.material_override = material
		parts[def["name"]].add_child(mi)
		armor_nodes.append(mi)

func set_held(weapon_id: String) -> void:
	held_id = weapon_id
	if is_instance_valid(held_node):
		held_node.queue_free()
		held_node = null
	if weapon_id == "" or skin == null:
		return
	held_node = MeshInstance3D.new()
	held_node.name = "Held"
	held_node.mesh = WeaponBuilder.build_mesh(weapon_id)
	held_node.material_override = material
	held_node.position = MCGeometry.held_item_offset(skin.slim) * MCGeometry.PX
	held_node.basis = MCGeometry.held_item_basis()
	parts["RightArm"].add_child(held_node)

func set_tint(c: Color) -> void:
	if material:
		material.set_shader_parameter("tint", c)

func set_ghost(g: float) -> void:
	if material:
		material.set_shader_parameter("ghost", g)

func set_emission(color: Color, strength: float) -> void:
	if material:
		material.set_shader_parameter("emission_color", color)
		material.set_shader_parameter("emission_boost", strength)

func flash(strength: float = 1.0) -> void:
	_flash = strength

## Animation API -------------------------------------------------------------------------------

func play(state: String, duration: float = 0.45) -> void:
	if _dead and state != "die":
		return
	if state == anim_state and state in ["idle", "walk"]:
		return
	anim_state = state
	anim_time = 0.0
	_hit_emitted = false
	one_shot_duration = duration
	if state == "die":
		_dead = true

func is_one_shot() -> bool:
	return anim_state in ["attack", "hurt", "cast", "victory", "die"]

func _process(delta: float) -> void:
	if skin == null:
		return
	anim_time += delta
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta * 4.0)
		material.set_shader_parameter("flash", _flash)
	match anim_state:
		"idle":
			_anim_idle()
		"walk":
			_anim_walk()
		"attack":
			_anim_attack()
		"cast":
			_anim_cast()
		"hurt":
			_anim_hurt()
		"victory":
			_anim_victory()
		"die":
			_anim_die()
	if is_one_shot() and anim_state != "die" and anim_time >= one_shot_duration:
		var finished := anim_state
		anim_state = "idle"
		anim_time = 0.0
		animation_finished.emit(finished)

func _set_rot(part: String, x: float, y: float = 0.0, z: float = 0.0) -> void:
	var p: MeshInstance3D = parts.get(part)
	if p:
		p.rotation = Vector3(x, y, z)

func _anim_idle() -> void:
	var t := anim_time * 1.5 + _rng_offset
	var sway := sin(t) * 0.05
	_set_rot("RightArm", sway, 0, 0.04)
	_set_rot("LeftArm", -sway, 0, -0.04)
	_set_rot("RightLeg", 0)
	_set_rot("LeftLeg", 0)
	_set_rot("Head", sin(t * 0.5) * 0.04, sin(t * 0.3) * 0.15, 0)
	_set_rot("Body", 0)
	position.y = _base_y + sin(t) * 0.01

func _anim_walk() -> void:
	var t := anim_time * 8.0 * walk_speed_factor
	var swing := sin(t) * 0.8
	_set_rot("RightArm", swing)
	_set_rot("LeftArm", -swing)
	_set_rot("RightLeg", -swing)
	_set_rot("LeftLeg", swing)
	_set_rot("Head", 0, sin(t * 0.5) * 0.05, 0)
	position.y = _base_y + abs(sin(t)) * 0.03

func _anim_attack() -> void:
	var p: float = clamp(anim_time / max(one_shot_duration, 0.01), 0.0, 1.0)
	match attack_style:
		"slam":
			# both arms overhead, then crash down (mace)
			var a: float = -3.0
			if p >= 0.35 and p < 0.7:
				a = lerpf(-3.0, 0.9, _ease_out((p - 0.35) / 0.35))
			elif p >= 0.7:
				a = lerpf(0.9, 0.0, (p - 0.7) / 0.3)
			_set_rot("RightArm", a)
			_set_rot("LeftArm", a * 0.8)
			_set_rot("Body", 0.25 * sin(p * PI), 0, 0)
			position.y = _base_y + (0.25 * sin(p * PI) if p < 0.6 else 0.0)
			if p >= 0.55:
				_emit_hit()
		"point":
			_set_rot("RightArm", -1.6, 0, -0.1)
			_set_rot("LeftArm", -2.6 * sin(p * PI), 0, 0.3)
			_set_rot("Head", -0.1, 0, 0)
			if p >= 0.3:
				_emit_hit()
		"throw":
			var a: float = lerpf(0.8, -2.2, _ease_out(p)) if p < 0.5 else lerpf(-2.2, -0.3, (p - 0.5) / 0.5)
			_set_rot("RightArm", a, 0, -0.2)
			_set_rot("LeftArm", -0.4, 0, 0.2)
			_set_rot("Body", 0, -0.35 * sin(p * PI), 0)
			if p >= 0.5:
				_emit_hit()
		"shoot":
			_set_rot("RightArm", -1.55, -0.25, 0)
			_set_rot("LeftArm", -1.55, 0.45, 0)
			_set_rot("Body", 0, 0.35, 0)
			_set_rot("Head", 0, 0.35, 0)
			if p >= 0.4:
				_emit_hit()
		"cast":
			_set_rot("RightArm", -2.8, 0, -0.35)
			_set_rot("LeftArm", -2.8, 0, 0.35)
			position.y = _base_y + 0.1 * sin(p * PI)
			if p >= 0.5:
				_emit_hit()
		_:
			# slash: raise then sweep
			var a: float = lerpf(-0.2, -2.4, _ease_out(p / 0.3))
			if p >= 0.3 and p < 0.65:
				a = lerpf(-2.4, 0.6, _ease_out((p - 0.3) / 0.35))
			elif p >= 0.65:
				a = lerpf(0.6, 0.0, (p - 0.65) / 0.35)
			_set_rot("RightArm", a, 0, -0.2)
			_set_rot("LeftArm", 0.3 * sin(p * PI), 0, 0.15)
			_set_rot("Body", 0, -0.3 * sin(p * PI), 0)
			if p >= 0.5:
				_emit_hit()

func _anim_cast() -> void:
	var p: float = clamp(anim_time / max(one_shot_duration, 0.01), 0.0, 1.0)
	_set_rot("RightArm", -2.9, 0, -0.3)
	_set_rot("LeftArm", -2.9, 0, 0.3)
	_set_rot("Head", -0.25, 0, 0)
	position.y = _base_y + 0.15 * sin(p * PI)
	if p >= 0.5:
		_emit_hit()

func _anim_hurt() -> void:
	var p: float = clamp(anim_time / max(one_shot_duration, 0.01), 0.0, 1.0)
	_set_rot("Body", -0.3 * sin(p * PI), 0, 0)
	_set_rot("Head", -0.4 * sin(p * PI), 0, 0)
	_set_rot("RightArm", 0.6 * sin(p * PI), 0, 0.3)
	_set_rot("LeftArm", 0.6 * sin(p * PI), 0, -0.3)

func _anim_victory() -> void:
	var t := anim_time * 6.0
	_set_rot("RightArm", -3.0 + sin(t) * 0.2, 0, -0.3)
	_set_rot("LeftArm", -3.0 - sin(t) * 0.2, 0, 0.3)
	position.y = _base_y + abs(sin(t * 0.5)) * 0.25

func _anim_die() -> void:
	var p: float = clamp(anim_time / 0.6, 0.0, 1.0)
	rotation.x = lerpf(0.0, -PI * 0.5, _ease_out(p))
	position.y = _base_y + 0.15 * p - (p * p) * 0.6
	_set_rot("RightArm", -0.5, 0, 0)
	_set_rot("LeftArm", -0.5, 0, 0)
	if anim_time > 0.9:
		var fade: float = clamp((anim_time - 0.9) / 0.4, 0.0, 1.0)
		material.set_shader_parameter("tint", Color(1, 1, 1, 1).darkened(fade * 0.8))
		if fade >= 1.0:
			animation_finished.emit("die")
			anim_state = "dead"

func _emit_hit() -> void:
	if not _hit_emitted:
		_hit_emitted = true
		attack_hit.emit()

static func _ease_out(x: float) -> float:
	x = clamp(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

func face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	# Model faces -Z, so look_at target = position - dir.
	rotation.y = atan2(-flat.x, -flat.z)

func set_base_height(y: float) -> void:
	_base_y = y
	position.y = y
