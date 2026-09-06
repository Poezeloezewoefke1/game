extends Control
## In-game Codex: the research database, presented with sources and confidence tiers.

const CATEGORIES := [
	{"id": "heroes", "name": "Heroes"},
	{"id": "characters", "name": "Characters"},
	{"id": "villains", "name": "Villains"},
	{"id": "towers", "name": "Towers"},
	{"id": "enemies", "name": "Enemies"},
	{"id": "bosses", "name": "Bosses"},
	{"id": "factions", "name": "Factions"},
	{"id": "locations", "name": "Locations"},
	{"id": "arcs", "name": "Arcs"},
	{"id": "events", "name": "Events"},
	{"id": "weapons", "name": "Weapons"},
	{"id": "relationships", "name": "Relationships"},
]

var current_category: String = "heroes"
var list_box: VBoxContainer
var detail_box: VBoxContainer
var cat_buttons: Dictionary = {}
var preview: CharacterPreview

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.background(self)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(UITheme.spacer(8))

	var header := HBoxContainer.new()
	root.add_child(header)
	var back := UITheme.button("< BACK", 15)
	back.pressed.connect(_back)
	header.add_child(back)
	var title := UITheme.label("CODEX", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var note := UITheme.label("Sources and confidence shown per entry", 12, UITheme.TEXT_DIM)
	header.add_child(note)

	var cat_row := HBoxContainer.new()
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cat_row.add_theme_constant_override("separation", 3)
	root.add_child(cat_row)
	for c in CATEGORIES:
		var b := UITheme.button(String(c["name"]), 13)
		var cid := String(c["id"])
		b.pressed.connect(func() -> void:
			AudioMgr.play_sfx("click", -8.0)
			_set_category(cid))
		cat_row.add_child(b)
		cat_buttons[cid] = b

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(300, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 2)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(list_box)
	var left_panel := UITheme.make_panel()
	left_panel.add_child(left_scroll)
	body.add_child(left_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(detail_box)
	var right_panel := UITheme.make_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_scroll)
	body.add_child(right_panel)

	root.add_child(UITheme.spacer(8))
	_set_category("heroes")

func _set_category(cid: String) -> void:
	current_category = cid
	for key in cat_buttons.keys():
		(cat_buttons[key] as Button).add_theme_color_override("font_color", UITheme.EMBER if key == cid else UITheme.TEXT)
	for c in list_box.get_children():
		c.queue_free()
	for entry in _entries_for(cid):
		var b := UITheme.button(String(entry["title"]), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var payload: Dictionary = entry
		b.pressed.connect(func() -> void:
			AudioMgr.play_sfx("click", -9.0)
			_show_entry(payload))
		list_box.add_child(b)
	var first := _entries_for(cid)
	if not first.is_empty():
		_show_entry(first[0])
	else:
		for c in detail_box.get_children():
			c.queue_free()
		detail_box.add_child(UITheme.label("No entries.", 15, UITheme.TEXT_DIM))

func _entries_for(cid: String) -> Array:
	var out: Array = []
	match cid:
		"heroes":
			for id in DataDB.heroes.keys():
				out.append({"title": String(DataDB.heroes[id].get("name", id)), "kind": "hero", "data": DataDB.heroes[id]})
		"characters":
			for e in DataDB.lore.get("characters", []):
				if not bool(e.get("antagonist", false)):
					out.append({"title": String(e.get("name", "")), "kind": "lore_char", "data": e})
		"villains":
			for e in DataDB.lore.get("characters", []):
				if bool(e.get("antagonist", false)):
					out.append({"title": String(e.get("name", "")), "kind": "lore_char", "data": e})
		"towers":
			for id in DataDB.towers.keys():
				out.append({"title": String(DataDB.towers[id].get("name", id)), "kind": "tower", "data": DataDB.towers[id]})
		"enemies":
			for id in DataDB.enemies.keys():
				out.append({"title": String(DataDB.enemies[id].get("name", id)), "kind": "enemy", "data": DataDB.enemies[id]})
		"bosses":
			for e in DataDB.lore.get("bosses", []):
				out.append({"title": DataDB.character_display_name(String(e.get("character", ""))), "kind": "boss", "data": e})
		"factions":
			for e in DataDB.lore.get("factions", []):
				out.append({"title": String(e.get("name", "")), "kind": "generic", "data": e})
		"locations":
			for e in DataDB.lore.get("locations", []):
				out.append({"title": String(e.get("name", "")), "kind": "generic", "data": e})
		"arcs":
			for e in DataDB.lore.get("arcs", []):
				out.append({"title": String(e.get("name", "")), "kind": "arc", "data": e})
		"events":
			for e in DataDB.lore.get("events", []):
				out.append({"title": String(e.get("name", "")), "kind": "generic", "data": e})
		"weapons":
			for e in DataDB.lore.get("weapons", []):
				out.append({"title": String(e.get("name", "")), "kind": "generic", "data": e})
		"relationships":
			for e in DataDB.relationships:
				out.append({"title": String(e.get("name", "")), "kind": "relationship", "data": e})
	return out

func _show_entry(entry: Dictionary) -> void:
	for c in detail_box.get_children():
		c.queue_free()
	var data: Dictionary = entry["data"]
	var kind := String(entry["kind"])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	detail_box.add_child(head)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text_col)
	text_col.add_child(UITheme.label(String(entry["title"]), 26, UITheme.TEXT))
	var conf := String(data.get("confidence", data.get("lore_confidence", "")))
	if conf != "":
		text_col.add_child(UITheme.label("[%s]" % UITheme.confidence_label(conf), 12, UITheme.confidence_color(conf)))

	# 3D preview where the entry maps to a character
	var skin_id := ""
	match kind:
		"hero":
			skin_id = String(data.get("character", ""))
		"tower":
			skin_id = String(data.get("character", ""))
		"lore_char":
			skin_id = String(data.get("id", ""))
		"boss":
			skin_id = String(data.get("character", ""))
		"enemy":
			var pool: Array = data.get("skin_pool", [])
			if not pool.is_empty():
				skin_id = String(pool[0])
	if skin_id != "" and SkinLibrary.has_supplied_skin(skin_id):
		var p := CharacterPreview.new(Vector2i(170, 210))
		head.add_child(p)
		var armor: Dictionary = data.get("armor", {})
		p.show_character(skin_id, armor, String(data.get("held", data.get("weapon", ""))))

	match kind:
		"hero":
			_hero_body(data)
		"tower":
			_tower_body(data)
		"enemy":
			_enemy_body(data)
		"lore_char":
			_character_body(data)
		"arc":
			_arc_body(data)
		"relationship":
			_relationship_body(data)
		"boss":
			_boss_body(data)
		_:
			_generic_body(data)
	_sources(data)

func _field(title: String, value: String) -> void:
	if value.strip_edges() == "":
		return
	detail_box.add_child(UITheme.label(title, 13, UITheme.EMBER))
	detail_box.add_child(UITheme.rich("[color=#e0dcd8]%s[/color]" % value, 13))

func _list_field(title: String, items) -> void:
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return
	detail_box.add_child(UITheme.label(title, 13, UITheme.EMBER))
	for i in items:
		if typeof(i) == TYPE_DICTIONARY:
			var d: Dictionary = i
			var with := DataDB.character_display_name(String(d.get("with", "")))
			detail_box.add_child(UITheme.label("· %s — %s [%s]" % [with, String(d.get("type", "")),
				UITheme.confidence_label(String(d.get("confidence", "")))], 12, UITheme.TEXT_DIM))
		else:
			detail_box.add_child(UITheme.label("· %s" % String(i), 12, UITheme.TEXT_DIM))

func _hero_body(d: Dictionary) -> void:
	_field("ROLE", "%s  ·  Difficulty %s" % [String(d.get("role", "")), String(d.get("difficulty", ""))])
	_field("SUMMARY", String(d.get("summary", "")))
	_field("LORE", String(d.get("lore", "")))
	detail_box.add_child(UITheme.label("ABILITIES", 13, UITheme.EMBER))
	for a in d.get("abilities", []):
		detail_box.add_child(UITheme.label("%s (Lv %d, %ds)" % [String(a.get("name", "")), int(a.get("unlock", 1)), int(a.get("cooldown", 0))], 12, UITheme.TEXT))
		detail_box.add_child(UITheme.label("   %s" % String(a.get("desc", "")), 11, UITheme.TEXT_DIM))
	detail_box.add_child(UITheme.label("PASSIVES", 13, UITheme.EMBER))
	for p in d.get("passives", []):
		detail_box.add_child(UITheme.label("%s (Lv %d)" % [String(p.get("name", "")), int(p.get("unlock", 1))], 12, UITheme.TEXT))
		detail_box.add_child(UITheme.label("   %s" % String(p.get("desc", "")), 11, UITheme.TEXT_DIM))

func _tower_body(d: Dictionary) -> void:
	_field("GAMEPLAY ROLE", "%s  ·  %d emeralds" % [String(d.get("category", "")), int(d.get("cost", 0))])
	_field("LORE", String(d.get("lore", "")))
	detail_box.add_child(UITheme.label("BASE STATS", 13, UITheme.EMBER))
	detail_box.add_child(UITheme.label("Damage %s  ·  Range %s  ·  Attack every %.2fs  ·  %s" % [
		str(d.get("damage", 0)), str(d.get("range", 0)), float(d.get("attack_time", 1.0)), String(d.get("damage_type", ""))], 12, UITheme.TEXT_DIM))
	for p in d.get("paths", []):
		detail_box.add_child(UITheme.label(String(p.get("name", "")), 13, UITheme.GOLD))
		var tier := 1
		for t in p.get("tiers", []):
			detail_box.add_child(UITheme.label("  %d. %s — %d ⬧" % [tier, String(t.get("name", "")), int(t.get("cost", 0))], 12, UITheme.TEXT))
			detail_box.add_child(UITheme.label("     %s" % String(t.get("desc", "")), 11, UITheme.TEXT_DIM))
			tier += 1

func _enemy_body(d: Dictionary) -> void:
	_field("CODEX", String(d.get("codex", "")))
	_field("WHY IT EXISTS", String(d.get("gameplay_reason", "")))
	detail_box.add_child(UITheme.label("STATS", 13, UITheme.EMBER))
	detail_box.add_child(UITheme.label("Tier %d  ·  HP %s  ·  Speed %s  ·  Armor %d%%  ·  Threat %s  ·  Reward %s ⬧" % [
		int(d.get("tier", 1)), str(d.get("hp", 0)), str(d.get("speed", 0)),
		int(float(d.get("armor_pct", 0.0)) * 100.0), str(d.get("threat", 1)), str(d.get("reward", 0))], 12, UITheme.TEXT_DIM))
	var armor: Dictionary = d.get("armor", {})
	if not armor.is_empty():
		var parts: Array = []
		for slot in armor.keys():
			parts.append("%s: %s" % [String(slot), String(armor[slot]).replace("_", " ")])
		detail_box.add_child(UITheme.label("Gear — " + ", ".join(parts), 12, UITheme.TEXT_DIM))
	if d.get("downgrade_to") != null and String(d.get("downgrade_to", "")) != "":
		detail_box.add_child(UITheme.label("Breaks into: %s" % DataDB.character_display_name(String(d["downgrade_to"])), 12, UITheme.GOLD))

func _character_body(d: Dictionary) -> void:
	_field("ROLE", String(d.get("role", "")))
	_list_field("FACTIONS", d.get("faction", []))
	_field("FIRST APPEARANCE", String(d.get("first_appearance", "")))
	_list_field("MAJOR ARCS", d.get("major_arcs", []))
	_list_field("IMPORTANT EVENTS", d.get("important_events", []))
	_list_field("KNOWN EQUIPMENT", d.get("known_equipment", []))
	_list_field("KNOWN ABILITIES", d.get("known_abilities", []))
	_list_field("RELATIONSHIPS", d.get("important_relationships", []))
	_field("GAMEPLAY ROLE", String(d.get("potential_gameplay_role", "")))

func _arc_body(d: Dictionary) -> void:
	_field("SEASON", String(d.get("season", "")))
	_list_field("POV", d.get("pov", []))
	_field("SUMMARY", String(d.get("summary", "")))
	_list_field("CONCURRENT WITH", d.get("concurrent_with", []))
	_field("MAP POTENTIAL", String(d.get("map_potential", "")))

func _relationship_body(d: Dictionary) -> void:
	detail_box.add_child(UITheme.label("%s  +  %s" % [
		DataDB.character_display_name(String(d.get("a", ""))),
		DataDB.character_display_name(String(d.get("b", "")))], 16, UITheme.GOLD))
	_field("BASIS IN THE STORY", String(d.get("basis", "")))
	_field("IN GAME", "Placing both grants: " + _describe_effects(d.get("effects", {})))
	_field("", String(d.get("flavor", "")))

func _boss_body(d: Dictionary) -> void:
	_field("TIER", String(d.get("tier", "")))
	_list_field("CANON BASIS", d.get("canon_basis", []))
	if not (d.get("phases", []) as Array).is_empty():
		detail_box.add_child(UITheme.label("PHASES", 13, UITheme.EMBER))
		for p in d.get("phases", []):
			detail_box.add_child(UITheme.label("%d. %s" % [int(p.get("index", 0)), String(p.get("name", ""))], 13, UITheme.GOLD))
			detail_box.add_child(UITheme.label("   Basis: %s" % String(p.get("basis", "")), 11, UITheme.TEXT_DIM))
			detail_box.add_child(UITheme.label("   Mechanic: %s" % String(p.get("mechanic", "")), 11, UITheme.TEXT))

func _generic_body(d: Dictionary) -> void:
	_field("TYPE", String(d.get("type", "")))
	_field("DESCRIPTION", String(d.get("description", d.get("summary", d.get("outcome", "")))))
	_field("IDEOLOGY", String(d.get("ideology", "")))
	_list_field("ASSETS", d.get("assets", []))
	_list_field("HISTORY", d.get("history", []))
	_list_field("MEMBERS", d.get("members", []))
	_list_field("PARTICIPANTS", d.get("participants", []))
	_list_field("FEATURES", d.get("features", []))
	_list_field("HISTORICAL VERSIONS", d.get("historical_versions", []))
	_field("MAP POTENTIAL", String(d.get("map_potential", "")))
	_field("GAMEPLAY NOTE", String(d.get("gameplay_note", "")))

func _describe_effects(eff: Dictionary) -> String:
	var parts: Array = []
	if eff.has("damage_mult"):
		parts.append("+%d%% damage" % int((float(eff["damage_mult"]) - 1.0) * 100.0))
	if eff.has("rate_mult"):
		parts.append("+%d%% attack speed" % int((1.0 - float(eff["rate_mult"])) * 100.0))
	if eff.has("range_add"):
		parts.append("+%.1f range" % float(eff["range_add"]))
	if eff.has("armor_pen_add"):
		parts.append("+%d%% armor pierce" % int(float(eff["armor_pen_add"]) * 100.0))
	if eff.has("income_add"):
		parts.append("+%d emeralds per payout" % int(eff["income_add"]))
	if eff.has("repair_bonus"):
		parts.append("+%d base repair" % int(eff["repair_bonus"]))
	if eff.has("leak_reduction"):
		parts.append("−%d leak damage" % int(eff["leak_reduction"]))
	if eff.has("lives_bonus"):
		parts.append("+%d lives per wave" % int(eff["lives_bonus"]))
	return ", ".join(parts) if not parts.is_empty() else "a bonus"

func _sources(d: Dictionary) -> void:
	var srcs = d.get("research_sources", d.get("sources", null))
	if typeof(srcs) != TYPE_ARRAY or (srcs as Array).is_empty():
		return
	detail_box.add_child(UITheme.spacer(6))
	detail_box.add_child(UITheme.label("SOURCES", 12, UITheme.TEXT_DIM))
	for s in srcs:
		detail_box.add_child(UITheme.label("· %s" % String(s), 10, UITheme.TEXT_DIM.darkened(0.15)))

func _back() -> void:
	AudioMgr.play_sfx("click", -6.0)
	var main := get_parent()
	if main != null and main.has_method("go_to_main_menu"):
		main.go_to_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()
