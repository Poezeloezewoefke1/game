extends Node3D
## Renders the four playable heroes side by side so the supplied skins can be eyeballed.

const HEROES := ["chungie", "cindercrest_soldier", "saparata", "shoebilly", "lettucek",
	"clownpierce", "ashswagg", "arachn1d"]
const ARMOR := [{}, {}, {}, {}, {}, {}, {}, {}]
const LABELS := ["chungie", "cindercrest", "saparata", "shoebilly", "lettucek", "clownpierce", "ashswagg", "arachn1d"]

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.4, -12.5)
	cam.look_at(Vector3(0, 1.05, 0))
	cam.fov = 38
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-45, 200, 0)
	sun.light_energy = 1.5
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.14, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.85)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	for i in HEROES.size():
		var c := MinecraftCharacter.new()
		add_child(c)
		c.setup(SkinLibrary.get_skin(HEROES[i]), ARMOR[i], "")
		c.position = Vector3(-6.3 + 1.8 * float(i), 0, 0)
		c.rotation_degrees.y = 180.0
		c.play("idle")
		var lbl := Label3D.new()
		add_child(lbl)
		lbl.text = LABELS[i]
		lbl.position = Vector3(-6.3 + 1.8 * float(i), 2.35, 0)
		lbl.font_size = 72
		lbl.pixel_size = 0.0025
		lbl.rotation_degrees.y = 180.0

func on_frame(_f: int) -> void:
	pass

func on_finish() -> void:
	print("[HEROES] rendered ", HEROES)
