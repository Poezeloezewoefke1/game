extends SceneTree
## Builds the game's UI theme and writes resources/ui_theme.tres.
##
##   usage: <godot> --headless --path . --script tools/generate_ui_theme.gd
##
## WHY GENERATED. A Theme with styleboxes for every control state is about forty
## sub-resources; as hand-written scene text it is unreadable and unreviewable,
## and changing one colour means editing it in nine places. Here the palette is
## six constants at the top and every stylebox is derived from them, so "make the
## accent warmer" is a one-line change with a visible diff.
##
## It is set as the project's DEFAULT theme, so every Control in the game picks
## it up - including any screen added later without anyone remembering to.

const OUT := "res://resources/ui_theme.tres"

# The station's palette: cold metal, a cyan accent, warning amber and red.
const BG        := Color(0.055, 0.070, 0.098, 0.94)
const BG_RAISED := Color(0.094, 0.114, 0.153)
const BG_SUNK   := Color(0.031, 0.043, 0.063)
const LINE      := Color(0.243, 0.294, 0.373)
const ACCENT    := Color(0.290, 0.749, 1.000)
const ACCENT_DIM:= Color(0.157, 0.412, 0.573)
const TEXT      := Color(0.855, 0.898, 0.949)
const TEXT_DIM  := Color(0.514, 0.573, 0.647)
const WARN      := Color(1.000, 0.639, 0.220)
const DANGER    := Color(1.000, 0.365, 0.318)
const GOOD      := Color(0.404, 0.902, 0.635)


func _init() -> void:
	var theme := Theme.new()
	theme.default_font_size = 16

	_buttons(theme)
	_panels(theme)
	_inputs(theme)
	_bars(theme)
	_labels(theme)
	_misc(theme)

	var err := ResourceSaver.save(theme, OUT)
	print("theme -> %s (%s)" % [OUT, "ok" if err == OK else "FAILED %d" % err])
	quit()


func _flat(bg: Color, border: Color, width: int, radius: int,
		margin_h: int = 0, margin_v: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(width)
	box.border_color = border
	box.set_corner_radius_all(radius)
	box.content_margin_left = float(margin_h)
	box.content_margin_right = float(margin_h)
	box.content_margin_top = float(margin_v)
	box.content_margin_bottom = float(margin_v)
	return box


func _buttons(theme: Theme) -> void:
	# A left-hand accent bar rather than a full outline: it marks the active
	# control without boxing in every button on the screen, and it is what makes
	# hover read instantly at a glance.
	var normal := _flat(BG_RAISED, LINE, 1, 3, 18, 11)
	normal.border_width_left = 3
	normal.border_color = LINE

	var hover := _flat(Color(0.137, 0.184, 0.243), ACCENT, 1, 3, 18, 11)
	hover.border_width_left = 3

	var pressed := _flat(ACCENT_DIM, ACCENT, 1, 3, 18, 11)
	pressed.border_width_left = 3

	var disabled := _flat(Color(0.070, 0.082, 0.106), Color(0.157, 0.180, 0.220), 1, 3, 18, 11)
	disabled.border_width_left = 3

	var focus := _flat(Color(0, 0, 0, 0), ACCENT, 2, 3, 18, 11)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	theme.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	theme.set_color("font_disabled_color", "Button", Color(0.365, 0.408, 0.475))
	theme.set_font_size("font_size", "Button", 17)

	for control in ["CheckBox", "CheckButton", "OptionButton"]:
		theme.set_stylebox("normal", control, normal)
		theme.set_stylebox("hover", control, hover)
		theme.set_stylebox("pressed", control, pressed)
		theme.set_color("font_color", control, TEXT)


func _panels(theme: Theme) -> void:
	var panel := _flat(BG, LINE, 1, 5, 22, 18)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	# A tighter variant for HUD widgets, which sit over the game and must not
	# eat the screen.
	var hud_panel := _flat(Color(0.043, 0.055, 0.078, 0.72), Color(0.216, 0.267, 0.353, 0.8),
		1, 4, 12, 9)
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", hud_panel)


func _inputs(theme: Theme) -> void:
	var normal := _flat(BG_SUNK, LINE, 1, 3, 12, 8)
	normal.border_width_bottom = 2
	var focus := _flat(Color(0.043, 0.078, 0.110), ACCENT, 1, 3, 12, 8)
	focus.border_width_bottom = 2
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.400, 0.451, 0.522))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", ACCENT_DIM)


func _bars(theme: Theme) -> void:
	# The default ProgressBar is grey on grey, which is exactly wrong for the
	# two things a player checks under pressure: how hurt they are and how close
	# the blaster is to cutting out. The HUD overrides the fill colour per bar;
	# the track is shared.
	var track := _flat(Color(0.031, 0.043, 0.063, 0.85), Color(0.196, 0.235, 0.310), 1, 2)
	track.content_margin_top = 0.0
	track.content_margin_bottom = 0.0
	var fill := _flat(ACCENT, Color(0, 0, 0, 0), 0, 2)
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", TEXT)


func _labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", 16)
	# Named variations, so a scene says what a label IS rather than repeating a
	# pile of overrides.
	for entry in [
		["TitleLabel", 42, TEXT], ["SubtitleLabel", 18, TEXT_DIM],
		["HeadingLabel", 20, ACCENT], ["HintLabel", 13, TEXT_DIM],
		["ValueLabel", 17, TEXT], ["WarningLabel", 17, WARN],
		["DangerLabel", 17, DANGER], ["GoodLabel", 17, GOOD],
	]:
		var name: String = entry[0]
		theme.set_type_variation(name, "Label")
		theme.set_font_size("font_size", name, int(entry[1]))
		theme.set_color("font_color", name, entry[2] as Color)
		# An outline on everything that sits over the game: white text on a
		# sunlit dune is invisible without one.
		theme.set_color("font_outline_color", name, Color(0, 0, 0, 0.85))
		theme.set_constant("outline_size", name, 4)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	theme.set_constant("outline_size", "Label", 3)


func _misc(theme: Theme) -> void:
	var separator := StyleBoxLine.new()
	separator.color = LINE
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_stylebox("separator", "VSeparator", separator)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HBoxContainer", 10)

	var scroll := _flat(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 3)
	theme.set_stylebox("panel", "ScrollContainer", scroll)

	var tooltip := _flat(BG_SUNK, ACCENT_DIM, 1, 3, 10, 7)
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
