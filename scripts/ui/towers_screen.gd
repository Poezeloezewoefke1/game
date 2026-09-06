extends Control
## Tower gallery: every deployable character with stats, upgrade paths and relationship bonds.

var detail_box: VBoxContainer
var preview_holder: HBoxContainer
var current_id: String = ""

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
	var title := UITheme.label("TOWERS", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	header.add_child(UITheme.label("The Gear Rule: one path to 4, a second to 2", 12, UITheme.TEXT_DIM))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(list)
	var lp := UITheme.make_panel()
	lp.add_child(left)
	body.add_child(lp)
	for id in DataDB.towers.keys():
		var t: Dictionary = DataDB.towers[id]
		var b := UITheme.button("%s — %d ⬧" % [String(t.get("name", id)), int(t.get("cost", 0))], 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tid := String(id)
		b.pressed.connect(func() -> void:
			AudioMgr.play_sfx("click", -9.0)
			_show(tid))
		list.add_child(b)

	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	right.add_child(col)
	preview_holder = HBoxContainer.new()
	preview_holder.add_theme_constant_override("separation", 12)
	col.add_child(preview_holder)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 3)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(detail_box)
	var rp := UITheme.make_panel()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.add_child(right)
	body.add_child(rp)

	root.add_child(UITheme.spacer(8))
	var keys := DataDB.towers.keys()
	if not keys.is_empty():
		_show(String(keys[0]))

func _show(id: String) -> void:
	current_id = id
	var d: Dictionary = DataDB.towers.get(id, {})
	for c in preview_holder.get_children():
		c.queue_free()
	for c in detail_box.get_children():
		c.queue_free()
	if d.is_empty():
		return
	# Base and fully-upgraded previews side by side, so gear progression is visible.
	var base_prev := CharacterPreview.new(Vector2i(180, 220))
	preview_holder.add_child(base_prev)
	base_prev.show_character(String(d.get("character", id)), d.get("armor", {}), String(d.get("weapon", "")))
	var upgraded_armor: Dictionary = (d.get("armor", {}) as Dictionary).duplicate()
	var upgraded_weapon := String(d.get("weapon", ""))
	for p in d.get("paths", []):
		for t in p.get("tiers", []):
			var eff: Dictionary = t.get("effects", {})
			if eff.has("armor"):
				upgraded_armor.merge(eff["armor"] as Dictionary, true)
			if eff.has("weapon"):
				upgraded_weapon = String(eff["weapon"])
	var up_prev := CharacterPreview.new(Vector2i(180, 220))
	preview_holder.add_child(up_prev)
	up_prev.show_character(String(d.get("character", id)), upgraded_armor, upgraded_weapon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_holder.add_child(info)
	info.add_child(UITheme.label(String(d.get("name", id)), 26))
	var conf := String(d.get("lore_confidence", "supported"))
	info.add_child(UITheme.label("%s  ·  [%s]" % [String(d.get("category", "")), UITheme.confidence_label(conf)], 12, UITheme.confidence_color(conf)))
	info.add_child(UITheme.label("Cost %d ⬧" % int(d.get("cost", 0)), 15, UITheme.EMERALD))
	info.add_child(UITheme.label("Damage %s  ·  Range %s  ·  Every %.2fs" % [
		str(d.get("damage", 0)), str(d.get("range", 0)), float(d.get("attack_time", 1.0))], 13, UITheme.TEXT_DIM))
	var tags: Array = []
	if bool(d.get("detect_invisible", false)):
		tags.append("sees invisible")
	if bool(d.get("hit_air", false)):
		tags.append("hits air")
	if d.has("income"):
		tags.append("generates income")
	if not tags.is_empty():
		info.add_child(UITheme.label(", ".join(tags), 12, UITheme.GOLD))
	var lore := UITheme.rich("[color=#9a9490]%s[/color]" % String(d.get("lore", "")), 12)
	info.add_child(lore)

	for p in d.get("paths", []):
		detail_box.add_child(UITheme.label(String(p.get("name", "")), 15, UITheme.GOLD))
		var tier := 1
		for t in p.get("tiers", []):
			detail_box.add_child(UITheme.label("  %d. %s — %d ⬧" % [tier, String(t.get("name", "")), int(t.get("cost", 0))], 13))
			detail_box.add_child(UITheme.label("      %s" % String(t.get("desc", "")), 11, UITheme.TEXT_DIM))
			tier += 1
	# relationships
	var rels: Array = []
	for r in DataDB.relationships:
		if String(r.get("a", "")) == id or String(r.get("b", "")) == id:
			rels.append(r)
	if not rels.is_empty():
		detail_box.add_child(UITheme.spacer(4))
		detail_box.add_child(UITheme.label("RELATIONSHIP BONUSES", 14, UITheme.EMBER))
		for r in rels:
			var other := String(r.get("b", "")) if String(r.get("a", "")) == id else String(r.get("a", ""))
			detail_box.add_child(UITheme.label("· %s — with %s" % [String(r.get("name", "")), DataDB.character_display_name(other)], 12, UITheme.TEXT))
			detail_box.add_child(UITheme.label("   %s" % String(r.get("basis", "")), 11, UITheme.TEXT_DIM))

func _back() -> void:
	AudioMgr.play_sfx("click", -6.0)
	var main := get_parent()
	if main != null and main.has_method("go_to_main_menu"):
		main.go_to_main_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back()
