extends Interactable
## One pre-flight station: prime the reactor, pressurise the fuel line, seal the
## hatch. Completing all of them is what arms the launch lever.
##
## Any crew member can work any station, deliberately. Four players should be
## able to split the checklist between them rather than queue behind the host.

@export var task_id: String = ""

@onready var _housing: MeshInstance3D = $Housing
@onready var _panel: MeshInstance3D = $Panel
@onready var _lamp: OmniLight3D = $Lamp


func _ready() -> void:
	super()
	PropBuilder.build_ship_station(self, _housing, _panel)


func is_done() -> bool:
	var done: Dictionary = GameManager.snapshot.get("ship_tasks", {})
	return done.has(task_id)


func label() -> String:
	return String(GameConfig.SHIP_TASK_LABELS.get(task_id, task_id))


func get_interaction_prompt(player: Node) -> String:
	if player == null or bool(player.get("is_downed")):
		return ""
	if not MissionRules.is_ship_state(GameManager.mission_state()):
		return ""
	if is_done():
		return "%s - done" % label()
	return "Press E to %s" % label().to_lower()


func can_interact(player: Node) -> bool:
	return player != null and not bool(player.get("is_downed")) \
		and MissionRules.is_ship_state(GameManager.mission_state()) and not is_done()


func host_validate_and_apply_interaction(peer_id: int, player: Node) -> Dictionary:
	var actor: Dictionary = player.actor_state() if player.has_method("actor_state") else {}
	var verdict := MissionRules.can_complete_ship_task(GameManager.snapshot, peer_id, task_id, actor)
	if not bool(verdict["ok"]):
		return verdict
	GameManager.host_apply_ship_task(peer_id, task_id)
	AudioDirector.play(AudioDirector.Cue.UI_CLICK)
	return {"ok": true, "reason": ""}


func refresh_visual_state() -> void:
	var done := is_done()
	var colour := Color(0.30, 0.95, 0.55) if done else Color(1.0, 0.55, 0.20)
	_set_emission(_panel, colour, 1.5 if done else 1.0)
	if _lamp != null:
		_lamp.light_color = colour
		_lamp.light_energy = 1.1 if done else 0.7
