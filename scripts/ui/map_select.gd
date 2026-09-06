extends Control
## Map selection with difficulty choice and per-map records.

var selected_map: String = ""
var difficulty: String = "normal"
var detail_box: VBoxContainer
var cards: Dictionary = {}
var diff_buttons: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.background(self)
	selected_map = GameState.selected_map_id
	difficulty = GameState.difficulty

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(UITheme.spacer(10))

	var header := HBoxContainer.new()
	root.add_child(header)
	var back := UITheme.button("< BACK", 15)
	back.pressed.connect(_back)
	header.add_child(back)
	var title := UITheme.label("SELECT A BATTLE", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var hero_label := UITheme.label("Hero: %s" % DataDB.character_display_name(GameState.selected_hero_id), 15, UITheme.EMBER)
	header.add_child(hero_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	for id in DataDB.maps.keys():
		row.add_child(_make_card(DataDB.maps[id]))

	# difficulty
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	root.add_child(diff_row)
	diff_row.add_child(UITheme.label("DIFFICULTY", 14, UITheme.TEXT_DIM))
	for d in ["easy", "normal", "hard"]:
		var b := UITheme.button(d.to_upper(), 14)
		b.pressed.connect(func() -> void:
			AudioMgr.play_sfx("click", -6.0)
			difficulty = d
			_refresh_difficulty())
		diff_row.add_child(b)
		diff_buttons[d] = b
	_refresh_difficulty()

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 3)
	var panel := UITheme.make_panel()
	panel.add_child(detail_box)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_child(panel)
	root.add_child(margin)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(footer)
	var play := UITheme.button("DEPLOY", 22, UITheme.EMBER)
	play.pressed.connect(func() -> void:
		AudioMgr.play_sfx("click", -4.0)
		GameState.selected_map_id = selected_map
		GameState.difficulty = difficulty
		var main := get_parent()
		if main != null and main.has_method("go_to_game"):
			main.go_to_game())
	footer.add_child(play)
	root.add_child(UITheme.spacer(12))
	_select(selected_map)

func _make_card(map: Dictionary) -> Control:
	var id := String(map.get("id", ""))
	var rec := SaveSystem.map_record(id)
	var unlocked := bool(map.get("unlocked", false)) or bool(rec.get("completed", false))
	if not unlocked:
		var req: Dictionary = map.get("unlock_requires", {})
		if req.has("map"):
			unlocked = bool(SaveSystem.map_record(String(req["map"])).get("completed", false))
	var panel := UITheme.make_panel()
	panel.custom_minimum_size = Vector2(320, 250)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	v.add_child(UITheme.label(String(map.get("name", id)), 24, UITheme.TEXT))
	v.add_child(UITheme.label(String(map.get("subtitle", "")), 13, UITheme.EMBER))
	v.add_child(UITheme.separator())
	var arc: Dictionary = DataDB.get_lore_entry("arcs", String(map.get("arc", "")))
	v.add_child(UITheme.label("Arc: %s" % String(arc.get("name", "—")), 12, UITheme.TEXT_DIM))
	var faction: Dictionary = DataDB.factions.get(String(map.get("faction", "")), {})
	v.add_child(UITheme.label("Enemy: %s" % String(faction.get("name", "—")), 12, UITheme.TEXT_DIM))
	var boss_id := String(map.get("boss", "")) if map.get("boss") != null else ""
	if boss_id != "":
		v.add_child(UITheme.label("Boss: %s" % DataDB.character_display_name(boss_id), 12, UITheme.DANGER))
	var wave_data: Dictionary = DataDB.waves.get(id, {})
	v.add_child(UITheme.label("Waves: %d  ·  Difficulty: %s" % [
		(wave_data.get("waves", []) as Array).size(), String(map.get("difficulty", "—"))], 12, UITheme.TEXT_DIM))
	v.add_child(UITheme.spacer(2))
	if int(rec.get("attempts", 0)) > 0:
		v.add_child(UITheme.label("Best: wave %d  ·  Wins %d" % [int(rec.get("best_waves", 0)), int(rec.get("wins", 0))], 12, UITheme.GOLD))
	else:
		v.add_child(UITheme.label("Never attempted", 12, UITheme.TEXT_DIM))
	var pick := UITheme.button("SELECT" if unlocked else "LOCKED", 15)
	pick.disabled = not unlocked
	pick.pressed.connect(func() -> void:
		AudioMgr.play_sfx("click", -6.0)
		_select(id))
	v.add_child(pick)
	cards[id] = {"panel": panel, "button": pick, "unlocked": unlocked}
	return panel

func _select(id: String) -> void:
	if not DataDB.maps.has(id) or not bool(cards.get(id, {}).get("unlocked", false)):
		for key in cards.keys():
			if bool(cards[key]["unlocked"]):
				id = key
				break
	selected_map = id
	for key in cards.keys():
		var card: Dictionary = cards[key]
		(card["panel"] as PanelContainer).add_theme_stylebox_override("panel", UITheme.panel_style(
			UITheme.PANEL_LIGHT if key == id else UITheme.PANEL,
			UITheme.EMBER if key == id else UITheme.BORDER, 3 if key == id else 2))
	_fill_detail(DataDB.maps.get(id, {}))

func _refresh_difficulty() -> void:
	for d in diff_buttons.keys():
		var b: Button = diff_buttons[d]
		b.add_theme_color_override("font_color", UITheme.EMBER if d == difficulty else UITheme.TEXT)
		b.text = ("▸ " + String(d).to_upper()) if d == difficulty else String(d).to_upper()

func _fill_detail(map: Dictionary) -> void:
	for c in detail_box.get_children():
		c.queue_free()
	if map.is_empty():
		return
	var loc: Dictionary = DataDB.get_lore_entry("locations", String(map.get("location", "")))
	detail_box.add_child(UITheme.label(String(loc.get("name", map.get("name", ""))), 18, UITheme.TEXT))
	var conf := String(loc.get("confidence", "supported"))
	detail_box.add_child(UITheme.label("[%s]" % UITheme.confidence_label(conf), 11, UITheme.confidence_color(conf)))
	var desc := UITheme.rich(String(loc.get("description", map.get("subtitle", ""))), 12)
	detail_box.add_child(desc)
	var mult: Dictionary = GameState.DIFFICULTY.get(difficulty, {})
	detail_box.add_child(UITheme.label(
		"Starting emeralds ×%.2f  ·  Lives ×%.2f  ·  Enemy HP ×%.2f  ·  Income ×%.2f" % [
			float(mult.get("emeralds", 1.0)), float(mult.get("lives", 1.0)),
			float(mult.get("enemy_hp", 1.0)), float(mult.get("income", 1.0))], 12, UITheme.TEXT_DIM))

func _back() -> void:
	AudioMgr.play_sfx("click", -6.0)
	var main := get_parent()
	if main != null and main.has_method("go_to_hero_select"):
		main.go_to_hero_select()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()
