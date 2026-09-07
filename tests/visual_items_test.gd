extends Node3D
## Renders characters holding every weapon the game data uses, so the real Minecraft item art can be
## eyeballed against what Minecraft actually draws.
##   godot --path . -s tests/run_visual.gd -- res://tests/visual_items_test.gd build/items.png 8 [view]
## view: "front" (default), "side", or "board" (the in-game camera's 38-degree look-down).

const ROW_A := ["iron_sword", "diamond_sword_enchanted", "netherite_axe",
	"netherite_mace_enchanted", "bow", "crossbow", "iron_spear"]
const ROW_B := ["shield", "potion", "totem", "pearl", "book", "firework", "royal_banner"]
const SPACING := 2.05

var view: String = "front"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		view = args[3]
	var cam := Camera3D.new()
	add_child(cam)
	match view:
		"side":
			cam.position = Vector3(16.0, 2.0, -1.4)
			cam.look_at(Vector3(0, 1.25, -1.4))
			cam.fov = 34
		"board":
			# The board camera: 38 degrees above the horizon, looking down the +Z axis.
			cam.position = Vector3(0, 8.6, -11.6)
			cam.look_at(Vector3(0, 0.9, -1.4))
			cam.fov = 34
		_:
			cam.position = Vector3(0, 2.6, -8.6)
			cam.look_at(Vector3(0, 1.3, -1.4))
			cam.fov = 40
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, 200, 0)
	sun.light_energy = 1.4
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.88)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	_row(ROW_A, -3.4)
	_row(ROW_B, 0.0)

func _row(weapons: Array, z: float) -> void:
	var x0 := -SPACING * (weapons.size() - 1) * 0.5
	for i in weapons.size():
		var c := MinecraftCharacter.new()
		add_child(c)
		c.setup(SkinLibrary.get_skin("parrotx2"), {}, String(weapons[i]))
		c.position = Vector3(x0 + SPACING * float(i), 0, z)
		c.play("idle")
		var lbl := Label3D.new()
		add_child(lbl)
		lbl.text = String(weapons[i])
		lbl.position = Vector3(x0 + SPACING * float(i), 2.25, z)
		lbl.font_size = 44
		lbl.pixel_size = 0.0018
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func on_frame(_f: int) -> void:
	pass

func on_finish() -> void:
	print("[ITEMS] view=%s rendered %d weapons" % [view, ROW_A.size() + ROW_B.size()])
