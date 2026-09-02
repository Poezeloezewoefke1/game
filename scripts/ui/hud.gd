extends Control
## In-mission HUD. Strictly a view: it reads GameManager / the local player and
## renders. It never decides anything and never sends a request.

@onready var _objective: Label = %ObjectiveLabel
@onready var _prompt: Label = %PromptLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_text: Label = %HealthText
@onready var _heat_bar: ProgressBar = %HeatBar
@onready var _heat_text: Label = %HeatText
@onready var _crystal_label: Label = %CrystalLabel
@onready var _starmap_label: Label = %StarMapLabel
@onready var _team_list: VBoxContainer = %TeamList
@onready var _downed_panel: PanelContainer = %DownedPanel
@onready var _downed_label: Label = %DownedLabel
@onready var _crosshair: Control = %Crosshair
@onready var _net_label: Label = %NetLabel

var _health_fill: StyleBoxFlat
var _heat_fill: StyleBoxFlat

var _team_rows: Dictionary = {}


const HEALTH_GOOD := Color(0.35, 0.86, 0.55)
const HEALTH_HURT := Color(1.00, 0.72, 0.25)
const HEALTH_CRIT := Color(1.00, 0.33, 0.29)
const HEAT_COOL := Color(0.30, 0.75, 1.00)
const HEAT_HOT := Color(1.00, 0.45, 0.20)


## A ProgressBar's fill is a shared theme resource, so tinting one bar would
## tint every bar in the game. Each gets its own StyleBoxFlat here.
func _own_fill(bar: ProgressBar, colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", box)
	return box


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_fill = _own_fill(_health_bar, HEALTH_GOOD)
	_heat_fill = _own_fill(_heat_bar, HEAT_COOL)
	_build_crosshair()
	GameManager.objective_changed.connect(_on_objective_changed)
	GameManager.snapshot_changed.connect(_on_snapshot_changed)
	_on_objective_changed(GameManager.objective_text())
	_downed_panel.visible = false
	_net_label.text = ""


func _process(_delta: float) -> void:
	var me := NetworkManager.local_peer_id()
	var player: Node = SpawnManager.local_player()

	if player == null:
		_prompt.text = ""
		_crosshair.visible = false
		_downed_panel.visible = false
		return

	_crosshair.visible = true

	var health := int(player.get("health"))
	var downed := bool(player.get("is_downed"))
	_health_bar.max_value = GameConfig.MAX_HEALTH
	_health_bar.value = health
	_health_text.text = "%d / %d" % [health, GameConfig.MAX_HEALTH]
	_tint_health(float(health) / float(GameConfig.MAX_HEALTH))

	var heat := float(player.get("heat"))
	var overheated := bool(player.get("overheated"))
	_heat_bar.max_value = GameConfig.BLASTER_HEAT_MAX
	_heat_bar.value = heat
	_tint_heat(heat / GameConfig.BLASTER_HEAT_MAX, overheated)
	_heat_text.text = "OVERHEATED" if overheated else "HEAT %d%%" % int(heat / GameConfig.BLASTER_HEAT_MAX * 100.0)
	_heat_text.add_theme_color_override("font_color",
		Color(1.0, 0.42, 0.32) if overheated else Color(0.85, 0.9, 1.0))

	_downed_panel.visible = downed
	if downed:
		var progress := float(player.get("revive_progress"))
		if bool(player.get("revive_active")):
			_downed_label.text = "BEING REVIVED  %d%%" % int(progress * 100.0)
		else:
			_downed_label.text = "DOWNED - hold on, a teammate can revive you"

	if downed:
		_prompt.text = ""
	elif player.has_method("hovered_prompt"):
		_prompt.text = String(player.hovered_prompt())

	var carried := GameManager.carried_crystal_of(me)
	_crystal_label.text = "Crystal: %s" % (_pretty_crystal(carried) if not carried.is_empty() else "none")

	var map_state := GameManager.star_map_state()
	var carrier := GameManager.star_map_carrier()
	match map_state:
		MissionRules.MAP_CARRIED:
			_starmap_label.text = "Star Map: %s" % (
				"YOU" if carrier == me else LobbyManager.display_name_of(carrier))
		MissionRules.MAP_DROPPED:
			_starmap_label.text = "Star Map: DROPPED - recover it"
		MissionRules.MAP_AVAILABLE:
			_starmap_label.text = "Star Map: on the altar"
		MissionRules.MAP_EXTRACTED:
			_starmap_label.text = "Star Map: secured"
		_:
			_starmap_label.text = "Star Map: shielded (%d/%d pedestals)" % [
				GameManager.placed_pedestal_count(), GameConfig.REQUIRED_PEDESTAL_COUNT]

	_refresh_team(me)


func _refresh_team(me: int) -> void:
	var ids := LobbyManager.sorted_peer_ids()
	if _team_rows.size() != ids.size():
		for child in _team_list.get_children():
			child.queue_free()
		_team_rows.clear()
		for peer_id in ids:
			var label := Label.new()
			_team_list.add_child(label)
			_team_rows[peer_id] = label

	for peer_id in ids:
		var label: Variant = _team_rows.get(peer_id)
		if label == null or not is_instance_valid(label):
			continue
		var node: Node = SpawnManager.player_node(int(peer_id))
		var suffix := ""
		var colour := Color(0.85, 0.9, 1.0)
		if node == null:
			suffix = " (loading)"
			colour = Color(0.6, 0.62, 0.7)
		elif bool(node.get("is_downed")):
			suffix = " - DOWNED"
			colour = Color(1.0, 0.45, 0.4)
		else:
			suffix = " - %d hp" % int(node.get("health"))
		if GameManager.star_map_carrier() == int(peer_id) \
				and GameManager.star_map_state() == MissionRules.MAP_CARRIED:
			suffix += "  [MAP]"
			colour = Color(1.0, 0.87, 0.42)
		var text := LobbyManager.display_name_of(int(peer_id))
		if int(peer_id) == me:
			text += " (you)"
		(label as Label).text = text + suffix
		(label as Label).add_theme_color_override("font_color", colour)


func _on_objective_changed(text: String) -> void:
	_objective.text = text


func _on_snapshot_changed(_snap: Dictionary) -> void:
	_objective.text = GameManager.objective_text()


static func _pretty_crystal(id: String) -> String:
	match id:
		GameConfig.CRYSTAL_RUINS: return "Ruins Crystal"
		GameConfig.CRYSTAL_CAVE: return "Cave Crystal"
		GameConfig.CRYSTAL_GROVE: return "Grove Crystal"
		_: return id


## A bar you have to read the number off is a bar that failed. Green through
## amber to red, with the crossover points where a player's decision actually
## changes: below 60% you start thinking about cover, below 30% one more hit
## puts you down.
func _tint_health(ratio: float) -> void:
	if _health_fill == null:
		return
	var colour := HEALTH_CRIT
	if ratio > 0.6:
		colour = HEALTH_GOOD
	elif ratio > 0.3:
		colour = HEALTH_HURT.lerp(HEALTH_GOOD, (ratio - 0.3) / 0.3)
	else:
		colour = HEALTH_CRIT.lerp(HEALTH_HURT, ratio / 0.3)
	_health_fill.bg_color = colour


func _tint_heat(ratio: float, overheated: bool) -> void:
	if _heat_fill == null:
		return
	_heat_fill.bg_color = Color(1.0, 0.25, 0.15) if overheated \
		else HEAT_COOL.lerp(HEAT_HOT, clampf(ratio, 0.0, 1.0))


## Four ticks around a gap, rather than one dot. A single pixel disappears over
## a bright dune and gives no sense of where the weapon is pointing; ticks stay
## visible against anything and leave the centre of the screen clear.
func _build_crosshair() -> void:
	for child in _crosshair.get_children():
		child.queue_free()
	# Each tick is ANCHORED to the parent's centre rather than positioned from
	# its origin. The control is a 16 px box whose top-left sits eight pixels up
	# and left of screen centre, so origin-relative placement puts the whole
	# crosshair off-centre - which is exactly what the first version did.
	for spec in [
		[-11.0, -1.0, -4.0, 1.0],   # left
		[4.0, -1.0, 11.0, 1.0],     # right
		[-1.0, -11.0, 1.0, -4.0],   # top
		[-1.0, 4.0, 1.0, 11.0],     # bottom
		[-1.0, -1.0, 1.0, 1.0],     # centre dot
	]:
		var tick := ColorRect.new()
		tick.color = Color(0.88, 0.95, 1.0, 0.55 if spec == [-1.0, -1.0, 1.0, 1.0] else 0.9)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.set_anchors_preset(Control.PRESET_CENTER)
		tick.anchor_left = 0.5
		tick.anchor_top = 0.5
		tick.anchor_right = 0.5
		tick.anchor_bottom = 0.5
		tick.offset_left = float(spec[0])
		tick.offset_top = float(spec[1])
		tick.offset_right = float(spec[2])
		tick.offset_bottom = float(spec[3])
		_crosshair.add_child(tick)


## Fills every widget with representative mid-mission state and stops the
## per-frame refresh, so `tools/render_ui.sh` can photograph the HUD without a
## live session behind it.
##
## This exists because a HUD screenshot taken with no player shows an empty
## frame, and one taken at full health with nothing carried and no objective
## shows the one state that tells you nothing about whether the HUD works. It
## touches no game state and is never called during play.
func preview_state() -> void:
	set_process(false)

	_objective.text = "Find 3 Power Crystals to power the altar."
	_prompt.text = "Press E to Take Power Crystal"
	_crosshair.visible = true

	_health_bar.max_value = GameConfig.MAX_HEALTH
	_health_bar.value = 67
	_health_text.text = "67 / %d" % GameConfig.MAX_HEALTH

	_heat_bar.max_value = GameConfig.BLASTER_HEAT_MAX
	_heat_bar.value = GameConfig.BLASTER_HEAT_MAX * 0.74
	_heat_text.text = "HEAT 74%"
	_tint_health(0.67)
	_tint_heat(0.74, false)

	_crystal_label.text = "CARRYING: Cave Crystal"
	_starmap_label.text = "STAR MAP: LOCKED"
	_net_label.text = "42 ms"

	for child in _team_list.get_children():
		child.queue_free()
	for entry in [["Vega (you)", "100", false], ["Kess", "84", false],
			["Rook", "0", true], ["Juno", "58", false]]:
		var line := Label.new()
		line.text = "%s   %s%s" % [entry[0], entry[1], "  DOWNED" if entry[2] else ""]
		line.add_theme_color_override("font_color",
			Color(1.0, 0.42, 0.36) if entry[2] else Color(0.86, 0.92, 1.0))
		_team_list.add_child(line)

	_downed_panel.visible = true
	_downed_label.text = "DOWNED - a teammate can revive you"
