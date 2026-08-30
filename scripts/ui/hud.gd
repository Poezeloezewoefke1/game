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

var _team_rows: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var heat := float(player.get("heat"))
	var overheated := bool(player.get("overheated"))
	_heat_bar.max_value = GameConfig.BLASTER_HEAT_MAX
	_heat_bar.value = heat
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
