extends Node3D
## Renders every armour tier plus the pieces vanilla has no equipment layer for (cape, elytra,
## crown) and this project's own liveries, front and back, so they can be eyeballed against what
## Minecraft actually draws.
##   godot --path . -s tests/run_visual.gd -- res://tests/visual_armor_test.gd build/armor.png 8 [back]

const SETS := [
	["leather", {"helmet": "leather", "chestplate": "leather", "leggings": "leather", "boots": "leather"}],
	["chainmail", {"helmet": "chainmail", "chestplate": "chainmail", "leggings": "chainmail", "boots": "chainmail"}],
	["iron", {"helmet": "iron", "chestplate": "iron", "leggings": "iron", "boots": "iron"}],
	["gold", {"helmet": "gold", "chestplate": "gold", "leggings": "gold", "boots": "gold"}],
	["diamond+glint", {"helmet": "diamond_enchanted", "chestplate": "diamond_enchanted",
		"leggings": "diamond_enchanted", "boots": "diamond_enchanted"}],
	["netherite", {"helmet": "netherite", "chestplate": "netherite", "leggings": "netherite", "boots": "netherite"}],
	["royal livery", {"chestplate": "royal", "leggings": "royal", "boots": "royal"}],
	["cinder livery", {"chestplate": "cinder", "leggings": "cinder", "boots": "cinder"}],
	["cape (royal)", {"chestplate": "iron", "cape": "royal"}],
	["cape (cinder)", {"chestplate": "netherite", "cape": "cinder"}],
	["elytra", {"boots": "leather", "elytra": "elytra"}],
	["crown", {"chestplate": "royal", "cape": "royal", "crown": "gold"}],
]
const SPACING := 1.5

var view: String = "front"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		view = args[3]
	var cam := Camera3D.new()
	add_child(cam)
	var z := -14.0 if view == "front" else 14.0
	cam.position = Vector3(0, 2.2, z)
	cam.look_at(Vector3(0, 1.15, 0))
	cam.fov = 42
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-45, 200 if view == "front" else 20, 0)
	sun.light_energy = 1.4
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.82, 0.82, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var x0 := -SPACING * (SETS.size() - 1) * 0.5
	for i in SETS.size():
		var c := MinecraftCharacter.new()
		add_child(c)
		c.setup(SkinLibrary.get_skin("chungie"), SETS[i][1], "")
		c.position = Vector3(x0 + SPACING * float(i), 0, 0)
		if view == "back":
			c.rotation_degrees.y = 180.0
		c.play("idle")
		var lbl := Label3D.new()
		add_child(lbl)
		lbl.text = String(SETS[i][0])
		lbl.position = Vector3(x0 + SPACING * float(i), 2.35, 0)
		lbl.font_size = 40
		lbl.pixel_size = 0.0018
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func on_frame(_f: int) -> void:
	pass

func on_finish() -> void:
	var left: Array = []
	for s in SETS:
		for k in ArmorBuilder.slots_without_layers(s[1]).keys():
			if not left.has(k):
				left.append(k)
	print("[ARMOR] view=%s sets=%d slots still on shell boxes: %s" % [view, SETS.size(), left])
