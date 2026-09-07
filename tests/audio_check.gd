extends Node
## Verifies music and every recorded voice line load through AudioMgr.

func _ready() -> void:
	var music := AudioMgr._load("music_main")
	print("[AUDIO] music_main: %s" % ("OK " + music.get_class() if music != null else "MISSING"))
	var keys := ["select", "placed", "ability_1", "ability_2", "ability_3", "ultimate",
		"level_2", "level_15", "wave_clear", "low_lives", "boss_enter", "victory", "defeat"]
	for who in ["parrotx2", "wemmbu"]:
		var ok := 0
		for k in keys:
			if AudioMgr._load("voice/%s_%s" % [who, k]) != null:
				ok += 1
			else:
				print("[AUDIO]   MISSING voice/%s_%s" % [who, k])
		print("[AUDIO] %s voice lines: %d / %d" % [who, ok, keys.size()])
	print("[AUDIO] a character with no lines returns false: %s"
		% str(not AudioMgr.play_voice("saparata", "select")))
	print("[AUDIO] buses: %s" % str(AudioServer.get_bus_index("Voice") >= 0))

func on_frame(_f: int) -> void:
	pass

func on_finish() -> void:
	pass
