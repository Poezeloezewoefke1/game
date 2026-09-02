extends Interactable
## The chart table. Cycles the destination through the missions the crew has
## unlocked, and doubles as the "plot the course" pre-flight task - plotting a
## course IS choosing where to go, and having two separate interactions for one
## idea would be busywork.

@onready var _table: MeshInstance3D = $Table
@onready var _hologram: MeshInstance3D = $Hologram
@onready var _lamp: OmniLight3D = $Lamp


func _ready() -> void:
	super()
	PropBuilder.build_nav_console(self, _table, _hologram)


func current_id() -> String:
	return String(GameManager.snapshot.get("mission_id", MissionCatalog.first_id()))


## The next unlocked destination after the current one, wrapping. Returns the
## current id when only one is unlocked, which makes the prompt read honestly
## instead of pretending there is a choice.
func next_id() -> String:
	var unlocked := MissionCatalog.unlocked_ids(GameManager.snapshot.get("completed_missions", []))
	if unlocked.is_empty():
		return MissionCatalog.first_id()
	var here := unlocked.find(current_id())
	return String(unlocked[(here + 1) % unlocked.size()])


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	if not MissionRules.is_ship_state(GameManager.mission_state()):
		return ""
	var mine := current_id()
	var next := next_id()
	if next == mine:
		return "Course: %s (no other destination unlocked)" % MissionCatalog.display_name(mine)
	return "Course: %s - press E to plot %s" % [
		MissionCatalog.display_name(mine), MissionCatalog.display_name(next)]


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) \
		and MissionRules.is_ship_state(GameManager.mission_state())


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var target := next_id()
	var verdict := MissionRules.can_set_destination(GameManager.snapshot, target, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_destination(peer_id, target)
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	# The hologram takes the destination's threat colour, so the table reads at
	# a glance as "we are going somewhere calm" or "somewhere that will kill us".
	var threat := MissionCatalog.threat(current_id())
	var colour := Color(0.35, 0.85, 1.0)
	if threat == 2:
		colour = Color(1.0, 0.72, 0.30)
	elif threat >= 3:
		colour = Color(1.0, 0.42, 0.36)
	_apply_effect_shader(_hologram, "res://shaders/hologram.gdshader", colour, 1.6)
	if _lamp != null:
		_lamp.light_color = colour
		_lamp.light_energy = 1.2
