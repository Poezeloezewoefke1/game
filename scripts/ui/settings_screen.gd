extends Control
## Settings: audio, graphics, gameplay toggles and save management.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.background(self)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(UITheme.spacer(12))

	var header := HBoxContainer.new()
	root.add_child(header)
	var back := UITheme.button("< BACK", 15)
	back.pressed.connect(_back)
	header.add_child(back)
	var title := UITheme.label("SETTINGS", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	header.add_child(UITheme.spacer(0))

	var centre := HBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(centre)
	var panel := UITheme.make_panel()
	panel.custom_minimum_size = Vector2(620, 0)
	centre.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(UITheme.label("AUDIO", 16, UITheme.EMBER))
	_slider(v, "Master volume", "master_volume")
	_slider(v, "Music volume", "music_volume")
	_slider(v, "Sound effects", "sfx_volume")
	v.add_child(UITheme.separator())

	v.add_child(UITheme.label("GRAPHICS", 16, UITheme.EMBER))
	_toggle(v, "Fullscreen", "fullscreen")
	_toggle(v, "V-Sync", "vsync")
	_toggle(v, "Shadows", "shadows")
	_options(v, "Quality", "graphics_quality", ["Low", "Medium", "High"])
	v.add_child(UITheme.separator())

	v.add_child(UITheme.label("GAMEPLAY", 16, UITheme.EMBER))
	_toggle(v, "Show damage numbers", "show_damage_numbers")
	_toggle(v, "Camera edge panning", "camera_edge_pan")
	v.add_child(UITheme.separator())

	v.add_child(UITheme.label("CONTROLS", 16, UITheme.EMBER))
	var controls := "WASD / arrows — pan camera   ·   Q / E — rotate   ·   wheel — zoom\n" \
		+ "Left click — select or place   ·   right click — cancel   ·   Tab — show all ranges\n" \
		+ "1 / 2 / 3 — hero abilities   ·   4 or R — ultimate   ·   Space — start next wave\n" \
		+ "F — game speed   ·   Backspace — sell selected   ·   Esc — pause"
	v.add_child(UITheme.label(controls, 12, UITheme.TEXT_DIM))
	v.add_child(UITheme.separator())

	v.add_child(UITheme.label("SAVE DATA", 16, UITheme.EMBER))
	var stats: Dictionary = SaveSystem.data.get("stats", {})
	v.add_child(UITheme.label("Runs %d · Wins %d · Kills %d · Bosses %d · XP Bottles %d" % [
		int(stats.get("total_runs", 0)), int(stats.get("total_wins", 0)), int(stats.get("total_kills", 0)),
		int(stats.get("boss_kills", 0)), int(SaveSystem.data.get("xp_bottles", 0))], 12, UITheme.TEXT_DIM))
	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 8)
	v.add_child(reset_row)
	var reset := UITheme.button("RESET PROGRESS", 14, UITheme.DANGER)
	var confirm_label := UITheme.label("", 12, UITheme.DANGER)
	var armed := [false]
	reset.pressed.connect(func() -> void:
		if armed[0]:
			SaveSystem.reset()
			confirm_label.text = "Progress reset."
			armed[0] = false
			reset.text = "RESET PROGRESS"
		else:
			armed[0] = true
			reset.text = "CONFIRM RESET"
			confirm_label.text = "This clears all unlocks and records.")
	reset_row.add_child(reset)
	reset_row.add_child(confirm_label)
	v.add_child(UITheme.label("Skins: drop Minecraft-compatible PNGs into user://skins/<id>.png to replace placeholders.", 11, UITheme.TEXT_DIM))
	v.add_child(UITheme.label(ProjectSettings.globalize_path("user://skins/"), 10, UITheme.TEXT_DIM.darkened(0.2)))

func _slider(parent: Node, label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UITheme.label(label_text, 14)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(SaveSystem.get_setting(key, 1.0))
	s.custom_minimum_size = Vector2(280, 0)
	var value_label := UITheme.label("%d%%" % int(s.value * 100.0), 13, UITheme.TEXT_DIM)
	s.value_changed.connect(func(v: float) -> void:
		SaveSystem.set_setting(key, v)
		value_label.text = "%d%%" % int(v * 100.0))
	row.add_child(s)
	row.add_child(value_label)
	parent.add_child(row)

func _toggle(parent: Node, label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UITheme.label(label_text, 14)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = bool(SaveSystem.get_setting(key, false))
	c.toggled.connect(func(v: bool) -> void:
		SaveSystem.set_setting(key, v)
		AudioMgr.play_sfx("click", -8.0))
	row.add_child(c)
	parent.add_child(row)

func _options(parent: Node, label_text: String, key: String, items: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UITheme.label(label_text, 14)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	for i in items.size():
		ob.add_item(String(items[i]), i)
	ob.selected = clampi(int(SaveSystem.get_setting(key, 2)), 0, items.size() - 1)
	ob.item_selected.connect(func(idx: int) -> void:
		SaveSystem.set_setting(key, idx)
		_apply_quality(idx))
	row.add_child(ob)
	parent.add_child(row)

func _apply_quality(level: int) -> void:
	var vp := get_viewport()
	match level:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.75
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.scaling_3d_scale = 1.0

func _back() -> void:
	AudioMgr.play_sfx("click", -6.0)
	SaveSystem.save_game()
	var main := get_parent()
	if main != null and main.has_method("go_to_main_menu"):
		main.go_to_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()
