extends Node
## Registers input actions programmatically so the project does not depend on hand-edited InputMap entries.

const KEY_ACTIONS := {
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_forward": [KEY_W, KEY_UP],
	"cam_back": [KEY_S, KEY_DOWN],
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"ability_1": [KEY_1],
	"ability_2": [KEY_2],
	"ability_3": [KEY_3],
	"ultimate": [KEY_4, KEY_R],
	"start_wave": [KEY_SPACE],
	"toggle_speed": [KEY_F],
	"pause": [KEY_ESCAPE],
	"sell": [KEY_BACKSPACE, KEY_DELETE],
	"cancel": [KEY_ESCAPE],
	"toggle_range": [KEY_TAB],
	"screenshot": [KEY_F12],
}

func _ready() -> void:
	for action in KEY_ACTIONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	_add_mouse("select", MOUSE_BUTTON_LEFT)
	_add_mouse("context", MOUSE_BUTTON_RIGHT)
	_add_mouse("cam_drag", MOUSE_BUTTON_MIDDLE)
	_add_mouse("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
