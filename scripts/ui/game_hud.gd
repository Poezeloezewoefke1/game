extends CanvasLayer
## In-run HUD: resources, wave control, tower shop, upgrade panel, hero abilities, boss bar,
## announcements, dialogue, pause menu and the results screen.

var game                                   # GameController
var emerald_label: Label
var lives_label: Label
var lives_bar: ProgressBar
var wave_label: Label
var speed_button: Button
var start_button: Button
var shop_box: VBoxContainer
var info_panel: PanelContainer
var info_box: VBoxContainer
var hero_panel: PanelContainer
var hero_box: VBoxContainer
var ability_buttons: Array = []
var announce_label: Label
var announce_sub: Label
var dialogue_panel: PanelContainer
var dialogue_name: Label
var dialogue_text: Label
var boss_panel: PanelContainer
var boss_name: Label
var boss_bar: ProgressBar
var boss_phase: Label
var pause_menu: PanelContainer
var results_panel: PanelContainer
var relationship_box: VBoxContainer
var _announce_timer: float = 0.0
var _dialogue_timer: float = 0.0
var _shop_buttons: Dictionary = {}

const SHOP_ORDER := ["royal_guard", "theobaldthebird", "eggchan", "lomedy", "mapicc", "spepticle",
	"deputy_ace", "minutetech", "4cvit", "reinadrop", "leow0ok", "fymada", "purpled", "jaden_man"]

func setup(controller) -> void:
	game = controller
	layer = 10
	_build_top_bar()
	_build_shop()
	_build_info_panel()
	_build_hero_panel()
	_build_announce()
	_build_dialogue()
	_build_boss_bar()
	_build_relationship_box()
	_connect()
	_refresh_shop()
	_update_wave_label()

# ================================================================================================
# Construction
# ================================================================================================

func _build_top_bar() -> void:
	var bar := UITheme.make_panel(Color(0.07, 0.06, 0.07, 0.92))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 52
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	bar.add_child(h)

	emerald_label = UITheme.label("⬧ 0", 22, UITheme.EMERALD)
	emerald_label.custom_minimum_size = Vector2(150, 0)
	h.add_child(emerald_label)

	var lives_box := VBoxContainer.new()
	lives_box.custom_minimum_size = Vector2(190, 0)
	lives_box.add_theme_constant_override("separation", 0)
	lives_label = UITheme.label("♥ 100 / 100", 16, UITheme.HEALTH)
	lives_box.add_child(lives_label)
	lives_bar = UITheme.progress(UITheme.HEALTH)
	lives_bar.custom_minimum_size = Vector2(180, 8)
	lives_bar.max_value = 100
	lives_bar.value = 100
	lives_box.add_child(lives_bar)
	h.add_child(lives_box)

	wave_label = UITheme.label("WAVE 0 / 0", 18, UITheme.TEXT)
	wave_label.custom_minimum_size = Vector2(300, 0)
	h.add_child(wave_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	start_button = UITheme.button("START WAVE  [Space]", 15, UITheme.EMBER)
	start_button.pressed.connect(func() -> void:
		if not game.waves.running:
			game.waves.start_next_wave())
	h.add_child(start_button)

	speed_button = UITheme.button("1×  [F]", 15)
	speed_button.pressed.connect(func() -> void:
		GameState.set_speed(1.0 if GameState.game_speed >= 2.0 else GameState.game_speed + 1.0)
		_update_speed_button())
	h.add_child(speed_button)

	var menu := UITheme.button("☰", 15)
	menu.pressed.connect(toggle_pause_menu)
	h.add_child(menu)

func _build_shop() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_top = 56
	scroll.offset_bottom = -8
	scroll.offset_left = 8
	scroll.custom_minimum_size = Vector2(228, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := UITheme.make_panel()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(panel)
	shop_box = VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 3)
	panel.add_child(shop_box)
	shop_box.add_child(UITheme.label("RECRUIT", 15, UITheme.EMBER))
	shop_box.add_child(UITheme.separator())
	for id in SHOP_ORDER:
		if not DataDB.towers.has(id):
			continue
		var d: Dictionary = DataDB.towers[id]
		var b := UITheme.button("", 13)
		b.custom_minimum_size = Vector2(200, 42)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 0)
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var name_l := UITheme.label(String(d.get("name", id)), 14)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_l)
		var cost_l := UITheme.label("%s  ·  ⬧ %d" % [String(d.get("category", "")), int(d.get("cost", 0))], 11, UITheme.TEXT_DIM)
		cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(cost_l)
		b.add_child(vb)
		var tid := String(id)
		b.pressed.connect(func() -> void:
			AudioMgr.play_sfx("click", -8.0)
			game.begin_placement(tid))
		b.tooltip_text = "%s\n%s" % [String(d.get("lore", "")), _tower_tooltip(d)]
		shop_box.add_child(b)
		_shop_buttons[id] = {"button": b, "cost": int(d.get("cost", 0)), "cost_label": cost_l}

func _tower_tooltip(d: Dictionary) -> String:
	return "Damage %s · Range %s · every %.2fs · %s" % [
		str(d.get("damage", 0)), str(d.get("range", 0)), float(d.get("attack_time", 1.0)), String(d.get("damage_type", ""))]

func _build_info_panel() -> void:
	info_panel = UITheme.make_panel()
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info_panel.offset_left = -340
	info_panel.offset_top = -400
	info_panel.offset_right = -8
	info_panel.offset_bottom = -150
	info_panel.visible = false
	add_child(info_panel)
	var scroll := ScrollContainer.new()
	info_panel.add_child(scroll)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 3)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(info_box)

func _build_hero_panel() -> void:
	hero_panel = UITheme.make_panel()
	hero_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hero_panel.offset_top = -128
	hero_panel.offset_left = 240
	hero_panel.offset_right = -352
	hero_panel.offset_bottom = -8
	add_child(hero_panel)
	hero_box = VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 3)
	hero_panel.add_child(hero_box)

func _build_announce() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	v.offset_top = 90
	v.offset_left = -420
	v.offset_right = 420
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	announce_label = UITheme.label("", 42, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	announce_label.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.02))
	announce_label.add_theme_constant_override("outline_size", 8)
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(announce_label)
	announce_sub = UITheme.label("", 17, UITheme.EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	announce_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(announce_sub)

func _build_dialogue() -> void:
	dialogue_panel = UITheme.make_panel(Color(0.08, 0.07, 0.08, 0.95), UITheme.EMBER_DIM)
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.offset_left = -380
	dialogue_panel.offset_right = 380
	dialogue_panel.offset_top = -210
	dialogue_panel.offset_bottom = -140
	dialogue_panel.visible = false
	add_child(dialogue_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	dialogue_panel.add_child(v)
	dialogue_name = UITheme.label("", 15, UITheme.EMBER)
	v.add_child(dialogue_name)
	dialogue_text = UITheme.label("", 15, UITheme.TEXT)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size = Vector2(740, 0)
	v.add_child(dialogue_text)

func _build_boss_bar() -> void:
	boss_panel = UITheme.make_panel(Color(0.1, 0.05, 0.05, 0.93), UITheme.DANGER)
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_top = 58
	boss_panel.offset_left = -320
	boss_panel.offset_right = 320
	boss_panel.offset_bottom = 122
	boss_panel.visible = false
	add_child(boss_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	boss_panel.add_child(v)
	boss_name = UITheme.label("SAPARATA", 20, UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(boss_name)
	boss_bar = UITheme.progress(UITheme.DANGER)
	boss_bar.custom_minimum_size = Vector2(600, 14)
	v.add_child(boss_bar)
	boss_phase = UITheme.label("", 13, UITheme.EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(boss_phase)

func _build_relationship_box() -> void:
	relationship_box = VBoxContainer.new()
	relationship_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	relationship_box.offset_left = -320
	relationship_box.offset_top = 58
	relationship_box.offset_right = -8
	relationship_box.add_theme_constant_override("separation", 2)
	relationship_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relationship_box)

# ================================================================================================
# Signals
# ================================================================================================

func _connect() -> void:
	EventBus.emeralds_changed.connect(_on_emeralds)
	EventBus.lives_changed.connect(_on_lives)
	EventBus.wave_started.connect(func(_i: int, _t: int, _n: String) -> void: _update_wave_label())
	EventBus.wave_cleared.connect(func(_i: int) -> void: _update_wave_label())
	EventBus.announce.connect(_on_announce)
	EventBus.dialogue.connect(_on_dialogue)
	EventBus.boss_health_changed.connect(_on_boss_health)
	EventBus.boss_phase_changed.connect(_on_boss_phase)
	EventBus.boss_spawned.connect(func(_s: int) -> void: boss_panel.visible = true)
	EventBus.boss_defeated.connect(func(_s: int) -> void: boss_panel.visible = false)
	EventBus.tower_selected.connect(_show_tower_info)
	EventBus.tower_deselected.connect(func() -> void: info_panel.visible = false)
	EventBus.relationship_activated.connect(func(_a: String, _b: String, _r: Dictionary) -> void: _refresh_relationships())
	EventBus.tower_placed.connect(func(_t) -> void: _refresh_relationships())
	EventBus.tower_sold.connect(func(_t) -> void: _refresh_relationships())
	EventBus.game_speed_changed.connect(func(_s: float) -> void: _update_speed_button())
	if game.hero != null:
		game.hero.level_changed.connect(func(_l: int) -> void: _refresh_hero_panel())
		game.hero.ability_state_changed.connect(_refresh_hero_panel)
	_on_emeralds(GameState.emeralds)
	_on_lives(GameState.lives, GameState.max_lives)
	_refresh_hero_panel()

func _on_emeralds(amount: int) -> void:
	emerald_label.text = "⬧ %d" % amount
	_refresh_shop()

func _on_lives(lives: int, max_lives: int) -> void:
	lives_label.text = "♥ %d / %d" % [lives, max_lives]
	lives_bar.max_value = maxi(1, max_lives)
	lives_bar.value = lives
	var frac := float(lives) / float(maxi(1, max_lives))
	lives_label.add_theme_color_override("font_color", UITheme.HEALTH if frac > 0.3 else UITheme.DANGER)

func _update_wave_label() -> void:
	if game == null or game.waves == null:
		return
	var w: WaveManager = game.waves
	var index := maxi(0, w.wave_index + 1)
	var name: String = w.current_wave_name() if w.running else w.next_wave_name()
	wave_label.text = "WAVE %d / %d — %s" % [index, w.total_waves(), name]
	start_button.disabled = w.running or w.wave_index + 1 >= w.total_waves()
	start_button.text = "IN PROGRESS" if w.running else "START WAVE  [Space]"

func _update_speed_button() -> void:
	speed_button.text = "%d×  [F]" % int(GameState.game_speed)

func _refresh_shop() -> void:
	for id in _shop_buttons.keys():
		var entry: Dictionary = _shop_buttons[id]
		var affordable: bool = GameState.emeralds >= int(entry["cost"])
		(entry["button"] as Button).disabled = not affordable
		(entry["cost_label"] as Label).add_theme_color_override("font_color", UITheme.TEXT_DIM if affordable else UITheme.DANGER)

func _on_announce(text: String, subtitle: String, duration: float) -> void:
	announce_label.text = text
	announce_sub.text = subtitle
	announce_label.modulate.a = 1.0
	announce_sub.modulate.a = 1.0
	_announce_timer = duration

func _on_dialogue(speaker: String, text: String, duration: float) -> void:
	dialogue_name.text = DataDB.character_display_name(speaker).to_upper()
	dialogue_text.text = text
	dialogue_panel.visible = true
	_dialogue_timer = duration

func _on_boss_health(current: float, maximum: float) -> void:
	boss_panel.visible = true
	boss_bar.max_value = maxf(1.0, maximum)
	boss_bar.value = current

func _on_boss_phase(index: int, name: String, _desc: String) -> void:
	boss_panel.visible = true
	boss_phase.text = "PHASE %d — %s" % [index + 1, name]

func _process(delta: float) -> void:
	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer < 0.6:
			var a: float = clampf(_announce_timer / 0.6, 0.0, 1.0)
			announce_label.modulate.a = a
			announce_sub.modulate.a = a
	if _dialogue_timer > 0.0:
		_dialogue_timer -= delta
		if _dialogue_timer <= 0.0:
			dialogue_panel.visible = false
	_update_wave_label()
	_update_hero_cooldowns()

# ================================================================================================
# Tower info / upgrades
# ================================================================================================

func _show_tower_info(t) -> void:
	info_panel.visible = true
	_rebuild_tower_info(t)

func _rebuild_tower_info(t) -> void:
	for c in info_box.get_children():
		c.queue_free()
	if not is_instance_valid(t):
		info_panel.visible = false
		return
	info_box.add_child(UITheme.label(t.display_name, 20))
	info_box.add_child(UITheme.label("%s  ·  %s" % [String(t.def.get("category", "")), t.tier_label()], 12, UITheme.TEXT_DIM))
	info_box.add_child(UITheme.label("DPS %.0f  ·  Damage %.0f  ·  Range %.1f" % [t.dps(), t.damage, t.range_r], 13, UITheme.GOLD))
	var tags: Array = []
	if t.detect_invisible:
		tags.append("sees invisible")
	if t.hit_air:
		tags.append("hits air")
	if t.splash > 0.0:
		tags.append("splash %.1f" % t.splash)
	if t.armor_pen > 0.0:
		tags.append("%d%% armor pierce" % int(t.armor_pen * 100.0))
	if t.crit_chance > 0.0:
		tags.append("%d%% crit" % int(t.crit_chance * 100.0))
	if not tags.is_empty():
		info_box.add_child(UITheme.label(", ".join(tags), 11, UITheme.TEXT_DIM))
	for r in t.relationship_names():
		info_box.add_child(UITheme.label("♦ %s" % String(r), 12, UITheme.GOLD))
	info_box.add_child(UITheme.separator())

	# targeting
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	trow.add_child(UITheme.label("Target:", 12, UITheme.TEXT_DIM))
	var tb := UITheme.button(t.targeting.to_upper(), 12)
	tb.pressed.connect(func() -> void:
		t.cycle_targeting(1)
		_rebuild_tower_info(t))
	trow.add_child(tb)
	info_box.add_child(trow)

	# upgrade paths
	for p in 3:
		var paths: Array = t.def.get("paths", [])
		if p >= paths.size():
			continue
		var path_def: Dictionary = paths[p]
		info_box.add_child(UITheme.label("%s  [%d/%d]" % [String(path_def.get("name", "")), t.tiers[p], (path_def.get("tiers", []) as Array).size()], 13, UITheme.EMBER))
		var info: Dictionary = t.upgrade_info(p)
		if info.is_empty():
			info_box.add_child(UITheme.label("  Fully upgraded.", 11, UITheme.TEXT_DIM))
			continue
		var can: bool = t.can_upgrade(p)
		var cost: int = t.upgrade_cost(p)
		var b := UITheme.button("%s — ⬧ %d" % [String(info.get("name", "")), cost], 12)
		b.disabled = not can or not GameState.can_afford(cost)
		b.tooltip_text = String(info.get("desc", ""))
		var path_index := p
		b.pressed.connect(func() -> void:
			if t.apply_upgrade(path_index):
				_rebuild_tower_info(t))
		info_box.add_child(b)
		info_box.add_child(UITheme.label("  %s" % String(info.get("desc", "")), 11, UITheme.TEXT_DIM))
		if not can:
			info_box.add_child(UITheme.label("  Locked by the Gear Rule.", 11, UITheme.DANGER))

	info_box.add_child(UITheme.separator())
	var sell := UITheme.button("SELL — ⬧ %d  [Backspace]" % t.sell_value(), 13, UITheme.DANGER)
	sell.pressed.connect(func() -> void: game.towers.sell(t))
	info_box.add_child(sell)

# ================================================================================================
# Hero panel
# ================================================================================================

func _refresh_hero_panel() -> void:
	for c in hero_box.get_children():
		c.queue_free()
	ability_buttons.clear()
	var hero = game.hero
	if hero == null or not is_instance_valid(hero):
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	hero_box.add_child(top)
	top.add_child(UITheme.label(String(hero.def.get("name", hero.hero_id)), 18))
	top.add_child(UITheme.label("Lv %d" % hero.level, 16, UITheme.GOLD))
	var xp_bar := UITheme.progress(UITheme.ROYAL)
	xp_bar.custom_minimum_size = Vector2(180, 8)
	xp_bar.max_value = maxi(1, hero.xp_to_next)
	xp_bar.value = hero.xp
	top.add_child(xp_bar)
	EventBus.hero_xp_changed.connect(func(x: int, n: int) -> void:
		if is_instance_valid(xp_bar):
			xp_bar.max_value = maxi(1, n)
			xp_bar.value = x)
	top.add_child(UITheme.label("Kills %d" % hero.kills, 12, UITheme.TEXT_DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	hero_box.add_child(row)
	for slot in 4:
		var a: Dictionary = hero.ability_def(slot)
		if a.is_empty():
			continue
		var b := UITheme.button("", 12, UITheme.EMBER if slot < 3 else UITheme.GOLD)
		b.custom_minimum_size = Vector2(180, 58)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 0)
		var key_text := "[%d]" % (slot + 1) if slot < 3 else "[4/R] ULTIMATE"
		var kl := UITheme.label("%s %s" % [key_text, String(a.get("name", ""))], 12)
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(kl)
		var cd := UITheme.label("", 11, UITheme.TEXT_DIM)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(cd)
		b.add_child(vb)
		b.tooltip_text = String(a.get("desc", ""))
		var s := slot
		b.pressed.connect(func() -> void: hero.use_ability(s))
		row.add_child(b)
		ability_buttons.append({"slot": slot, "button": b, "cd_label": cd, "unlock": int(a.get("unlock", 1))})

func _update_hero_cooldowns() -> void:
	var hero = game.hero if game != null else null
	if hero == null or not is_instance_valid(hero):
		return
	for entry in ability_buttons:
		var slot: int = entry["slot"]
		var b: Button = entry["button"]
		var cd: Label = entry["cd_label"]
		if not hero.unlocked[slot]:
			b.disabled = true
			cd.text = "Unlocks at level %d" % int(entry["unlock"])
			cd.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		elif hero.cooldowns[slot] > 0.0:
			b.disabled = true
			cd.text = "%.1fs" % hero.cooldowns[slot]
			cd.add_theme_color_override("font_color", UITheme.DANGER)
		else:
			b.disabled = false
			cd.text = "READY"
			cd.add_theme_color_override("font_color", UITheme.EMERALD)

func show_hero_panel() -> void:
	_refresh_hero_panel()

func _refresh_relationships() -> void:
	for c in relationship_box.get_children():
		c.queue_free()
	if game == null or game.towers == null:
		return
	if game.towers.active_relationships.is_empty():
		return
	var l := UITheme.label("ACTIVE BONDS", 12, UITheme.EMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	relationship_box.add_child(l)
	for r in game.towers.active_relationships:
		var rl := UITheme.label("♦ %s" % String(r["name"]), 12, UITheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		relationship_box.add_child(rl)

# ================================================================================================
# Pause and results
# ================================================================================================

func toggle_pause_menu() -> void:
	if is_instance_valid(results_panel) and results_panel.visible:
		return
	if is_instance_valid(pause_menu):
		var showing := not pause_menu.visible
		pause_menu.visible = showing
		GameState.set_paused(showing)
		return
	pause_menu = UITheme.make_panel()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_menu.offset_left = -180
	pause_menu.offset_right = 180
	pause_menu.offset_top = -170
	pause_menu.offset_bottom = 170
	add_child(pause_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pause_menu.add_child(v)
	v.add_child(UITheme.label("PAUSED", 30, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UITheme.separator())
	var resume := UITheme.button("RESUME", 18, UITheme.EMBER)
	resume.pressed.connect(func() -> void:
		pause_menu.visible = false
		GameState.set_paused(false))
	v.add_child(resume)
	var restart := UITheme.button("RESTART MAP", 16)
	restart.pressed.connect(func() -> void:
		GameState.set_paused(false)
		game.restart())
	v.add_child(restart)
	var quit := UITheme.button("QUIT TO MENU", 16, UITheme.DANGER)
	quit.pressed.connect(func() -> void:
		GameState.set_paused(false)
		game.quit_to_menu())
	v.add_child(quit)
	v.add_child(UITheme.spacer(6))
	v.add_child(UITheme.label("Esc closes this menu.", 11, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	GameState.set_paused(true)

func show_results(stats: Dictionary, outro: Dictionary) -> void:
	if is_instance_valid(pause_menu):
		pause_menu.visible = false
	results_panel = UITheme.make_panel(Color(0.08, 0.06, 0.07, 0.97))
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results_panel.offset_left = -330
	results_panel.offset_right = 330
	results_panel.offset_top = -260
	results_panel.offset_bottom = 260
	add_child(results_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	results_panel.add_child(v)
	var won := bool(stats.get("won", false))
	v.add_child(UITheme.label(String(outro.get("title", "VICTORY" if won else "DEFEAT")), 34,
		UITheme.EMERALD if won else UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER))
	for line in outro.get("lines", []):
		var l: Dictionary = line
		v.add_child(UITheme.label("%s: \"%s\"" % [DataDB.character_display_name(String(l.get("speaker", ""))), String(l.get("text", ""))],
			13, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UITheme.separator())
	var rows := [
		["Waves survived", "%d / %d" % [int(stats.get("waves", 0)), int(stats.get("total_waves", 0))]],
		["Enemies defeated", str(int(stats.get("kills", 0)))],
		["Leaks", str(int(stats.get("leaks", 0)))],
		["Damage dealt", "%.0f" % float(stats.get("damage_dealt", 0.0))],
		["Towers built", str(int(stats.get("towers_built", 0)))],
		["Upgrades bought", str(int(stats.get("upgrades", 0)))],
		["Abilities used", str(int(stats.get("abilities_used", 0)))],
		["Emeralds earned", str(int(stats.get("emeralds_earned", 0)))],
		["Boss defeated", "yes" if bool(stats.get("boss_defeated", false)) else "no"],
		["Hero", "%s (level %d)" % [DataDB.character_display_name(String(stats.get("hero", ""))), int(stats.get("hero_level", 1))]],
		["Hero XP earned", str(int(stats.get("xp_earned", 0)))],
		["XP Bottles earned", str(int(stats.get("bottles", 0)))],
	]
	for r in rows:
		var h := HBoxContainer.new()
		var l1 := UITheme.label(String(r[0]), 13, UITheme.TEXT_DIM)
		l1.custom_minimum_size = Vector2(280, 0)
		h.add_child(l1)
		h.add_child(UITheme.label(String(r[1]), 13, UITheme.TEXT))
		v.add_child(h)
	v.add_child(UITheme.separator())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var again := UITheme.button("PLAY AGAIN", 16, UITheme.EMBER)
	again.pressed.connect(func() -> void: game.restart())
	row.add_child(again)
	var menu := UITheme.button("MAIN MENU", 16)
	menu.pressed.connect(func() -> void: game.quit_to_menu())
	row.add_child(menu)
