extends Control
## Main menu: PLAY / HEROES / TOWERS / MAPS / CODEX / SETTINGS / EXIT with a live 3D hero line-up.

var previews: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.background(self)
	AudioMgr.play_music("menu")

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(UITheme.spacer(46))
	root.add_child(UITheme.title_block())
	root.add_child(UITheme.spacer(6))
	var tag := UITheme.label("Four protagonists. One server. Hold the line.", 16, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(tag)
	root.add_child(UITheme.spacer(18))

	# 3D hero line-up
	var lineup := HBoxContainer.new()
	lineup.alignment = BoxContainer.ALIGNMENT_CENTER
	lineup.add_theme_constant_override("separation", 4)
	root.add_child(lineup)
	var showcase := [
		["parrotx2", {"helmet": "gold", "chestplate": "royal", "cape": "royal", "crown": "gold"}, "royal_banner"],
		["wemmbu", {"chestplate": "netherite_enchanted", "leggings": "netherite", "boots": "netherite"}, "netherite_mace_enchanted"],
		["flamefrags", {"helmet": "diamond", "chestplate": "diamond", "leggings": "diamond", "boots": "diamond"}, "netherite_sword_enchanted"],
		["spokeishere", {"chestplate": "netherite", "boots": "netherite"}, "totem"],
	]
	for entry in showcase:
		var p := CharacterPreview.new(Vector2i(190, 240))
		lineup.add_child(p)
		p.show_character(String(entry[0]), entry[1], String(entry[2]))
		p.spin_speed = randf_range(0.4, 0.75)
		previews.append(p)

	root.add_child(UITheme.spacer(14))

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	buttons.custom_minimum_size = Vector2(340, 0)
	var centre := HBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(buttons)
	root.add_child(centre)

	_add_button(buttons, "PLAY", func() -> void: _go("go_to_hero_select"), 24, UITheme.EMBER)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(row)
	_add_button(row, "HEROES", func() -> void: _go("go_to_hero_select"), 16)
	_add_button(row, "TOWERS", func() -> void: _go("go_to_towers"), 16)
	_add_button(row, "MAPS", func() -> void: _go("go_to_map_select"), 16)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(row2)
	_add_button(row2, "CODEX", func() -> void: _go("go_to_codex"), 16)
	_add_button(row2, "SETTINGS", func() -> void: _go("go_to_settings"), 16)
	_add_button(buttons, "EXIT", func() -> void: get_tree().quit(), 16, UITheme.DANGER)

	root.add_child(UITheme.spacer(10))
	var stats := SaveSystem.data.get("stats", {})
	var foot := UITheme.label("Runs %d  ·  Wins %d  ·  Kills %d  ·  XP Bottles %d" % [
		int(stats.get("total_runs", 0)), int(stats.get("total_wins", 0)),
		int(stats.get("total_kills", 0)), int(SaveSystem.data.get("xp_bottles", 0))],
		13, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(foot)
	var version := UITheme.label("v%s  ·  Godot %s  ·  fan project, not affiliated with the creators" % [
		ProjectSettings.get_setting("application/config/version", "0.1.0"),
		Engine.get_version_info().get("string", "4.x")],
		11, UITheme.TEXT_DIM.darkened(0.2), HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(version)

func _add_button(parent: Node, text: String, cb: Callable, size: int = 18, accent: Color = UITheme.EMBER) -> void:
	var b := UITheme.button(text, size, accent)
	b.pressed.connect(func() -> void:
		AudioMgr.play_sfx("click", -6.0)
		cb.call())
	parent.add_child(b)

func _go(method: String) -> void:
	var main := get_parent()
	if main != null and main.has_method(method):
		main.call(method)
