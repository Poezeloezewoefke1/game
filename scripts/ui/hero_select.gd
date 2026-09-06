extends Control
## Hero selection: four 3D previews with role, difficulty, abilities, lore and unlock status.

var selected_id: String = ""
var detail_box: VBoxContainer
var cards: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.background(self)
	selected_id = GameState.selected_hero_id

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header.add_child(UITheme.spacer(0))
	var back := UITheme.button("< BACK", 15)
	back.pressed.connect(func() -> void: _back())
	header.add_child(back)
	var title := UITheme.label("CHOOSE YOUR PROTAGONIST", 28, UITheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(110, 0)
	header.add_child(spacer)

	var sub := UITheme.label("The series is told through four perspectives. You play exactly one per run.", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)

	var order := ["parrotx2", "wemmbu", "flamefrags", "spokeishere"]
	for id in order:
		if not DataDB.heroes.has(id):
			continue
		row.add_child(_make_card(DataDB.heroes[id]))

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	detail_box.custom_minimum_size = Vector2(0, 210)
	var detail_panel := UITheme.make_panel()
	detail_panel.add_child(detail_box)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_child(detail_panel)
	root.add_child(margin)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var confirm := UITheme.button("CONTINUE TO MAP SELECT", 20, UITheme.EMBER)
	confirm.pressed.connect(func() -> void:
		AudioMgr.play_sfx("click", -6.0)
		GameState.selected_hero_id = selected_id
		var main := get_parent()
		if main != null and main.has_method("go_to_map_select"):
			main.go_to_map_select())
	footer.add_child(confirm)
	root.add_child(UITheme.spacer(10))

	_select(selected_id)

func _make_card(hero: Dictionary) -> Control:
	var id := String(hero.get("id", ""))
	var panel := UITheme.make_panel()
	panel.custom_minimum_size = Vector2(230, 330)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var preview := CharacterPreview.new(Vector2i(200, 200))
	v.add_child(preview)
	preview.show_character(String(hero.get("character", id)), hero.get("armor", {}), String(hero.get("weapon", "")))

	v.add_child(UITheme.label(String(hero.get("name", id)), 20, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UITheme.label(String(hero.get("title", "")), 12, UITheme.EMBER, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UITheme.label(String(hero.get("role", "")), 13, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var meta := SaveSystem.hero_meta(id)
	var unlocked: bool = SaveSystem.data.get("unlocked_heroes", []).has(id)
	v.add_child(UITheme.label("Difficulty: %s  ·  Meta Lv %d" % [String(hero.get("difficulty", "Normal")), int(meta.get("level", 1))],
		12, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var pick := UITheme.button("SELECT" if unlocked else "LOCKED", 15, UITheme.EMBER)
	pick.disabled = not unlocked
	pick.pressed.connect(func() -> void:
		AudioMgr.play_sfx("click", -6.0)
		preview.play("attack", 0.6)
		_select(id))
	v.add_child(pick)
	cards[id] = {"panel": panel, "preview": preview, "button": pick}
	return panel

func _select(id: String) -> void:
	if not DataDB.heroes.has(id):
		id = "parrotx2"
	selected_id = id
	for key in cards.keys():
		var card: Dictionary = cards[key]
		var p: PanelContainer = card["panel"]
		p.add_theme_stylebox_override("panel", UITheme.panel_style(
			UITheme.PANEL_LIGHT if key == id else UITheme.PANEL,
			UITheme.EMBER if key == id else UITheme.BORDER,
			3 if key == id else 2))
		(card["button"] as Button).text = "SELECTED" if key == id else ("SELECT" if not (card["button"] as Button).disabled else "LOCKED")
	_fill_detail(DataDB.heroes[id])

func _fill_detail(hero: Dictionary) -> void:
	for c in detail_box.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	detail_box.add_child(head)
	head.add_child(UITheme.label(String(hero.get("name", "")), 22, UITheme.TEXT))
	var conf := String(hero.get("lore_confidence", "supported"))
	head.add_child(UITheme.label("[%s]" % UITheme.confidence_label(conf), 12, UITheme.confidence_color(conf)))

	detail_box.add_child(UITheme.label(String(hero.get("summary", "")), 14, UITheme.TEXT))
	var lore := UITheme.rich("[color=#9a9490]%s[/color]" % String(hero.get("lore", "")), 12)
	lore.custom_minimum_size = Vector2(0, 46)
	detail_box.add_child(lore)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	detail_box.add_child(cols)

	var abil := VBoxContainer.new()
	abil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abil.add_theme_constant_override("separation", 1)
	abil.add_child(UITheme.label("ABILITIES", 13, UITheme.EMBER))
	for a in hero.get("abilities", []):
		var slot := int(a.get("slot", 0))
		var key := "1234"[slot] if slot < 4 else "?"
		var name := String(a.get("name", ""))
		var prefix := "[%s]" % key
		if slot == 3:
			prefix = "[4] ULTIMATE:"
		abil.add_child(UITheme.label("%s %s  (Lv %d, %ds)" % [prefix, name, int(a.get("unlock", 1)), int(a.get("cooldown", 0))], 12, UITheme.TEXT))
		abil.add_child(UITheme.label("      %s" % String(a.get("desc", "")), 11, UITheme.TEXT_DIM))
	cols.add_child(abil)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 1)
	right.add_child(UITheme.label("PASSIVES", 13, UITheme.EMBER))
	for p in hero.get("passives", []):
		right.add_child(UITheme.label("· %s (Lv %d)" % [String(p.get("name", "")), int(p.get("unlock", 1))], 12, UITheme.TEXT))
		right.add_child(UITheme.label("   %s" % String(p.get("desc", "")), 11, UITheme.TEXT_DIM))
	right.add_child(UITheme.spacer(4))
	var sv := HBoxContainer.new()
	sv.add_theme_constant_override("separation", 16)
	var strengths := VBoxContainer.new()
	strengths.add_child(UITheme.label("STRENGTHS", 12, UITheme.EMERALD))
	for s in hero.get("strengths", []):
		strengths.add_child(UITheme.label("+ %s" % String(s), 11, UITheme.TEXT_DIM))
	sv.add_child(strengths)
	var weaknesses := VBoxContainer.new()
	weaknesses.add_child(UITheme.label("WEAKNESSES", 12, UITheme.DANGER))
	for s in hero.get("weaknesses", []):
		weaknesses.add_child(UITheme.label("− %s" % String(s), 11, UITheme.TEXT_DIM))
	sv.add_child(weaknesses)
	right.add_child(sv)
	cols.add_child(right)

func _back() -> void:
	AudioMgr.play_sfx("click", -6.0)
	var main := get_parent()
	if main != null and main.has_method("go_to_main_menu"):
		main.go_to_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()
