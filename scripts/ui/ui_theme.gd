class_name UITheme
extends RefCounted
## Shared visual language: an ember-on-charcoal palette with blocky, hard-edged panels.

const BG := Color(0.055, 0.045, 0.055)
const BG_DEEP := Color(0.03, 0.025, 0.032)
const PANEL := Color(0.11, 0.095, 0.105, 0.96)
const PANEL_LIGHT := Color(0.16, 0.14, 0.15, 0.96)
const BORDER := Color(0.32, 0.26, 0.26)
const EMBER := Color(1.0, 0.42, 0.15)
const EMBER_DIM := Color(0.62, 0.24, 0.09)
const ROYAL := Color(0.34, 0.55, 0.95)
const GOLD := Color(0.98, 0.80, 0.28)
const EMERALD := Color(0.34, 0.92, 0.48)
const TEXT := Color(0.93, 0.91, 0.88)
const TEXT_DIM := Color(0.62, 0.59, 0.57)
const DANGER := Color(0.94, 0.30, 0.28)
const HEALTH := Color(0.88, 0.26, 0.32)

static func panel_style(bg: Color = PANEL, border: Color = BORDER, width: int = 2, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func make_panel(bg: Color = PANEL, border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	return p

static func label(text: String, size: int = 16, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(2, size / 8))
	l.horizontal_alignment = align
	return l

static func rich(text: String, size: int = 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	return r

static func button(text: String, size: int = 18, accent: Color = EMBER) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	var normal := panel_style(PANEL, BORDER, 2)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := panel_style(PANEL_LIGHT, accent, 2)
	hover.content_margin_top = 10
	hover.content_margin_bottom = 10
	hover.content_margin_left = 18
	hover.content_margin_right = 18
	var pressed := panel_style(accent.darkened(0.65), accent, 2)
	pressed.content_margin_top = 10
	pressed.content_margin_bottom = 10
	pressed.content_margin_left = 18
	pressed.content_margin_right = 18
	var disabled := panel_style(Color(0.09, 0.08, 0.09, 0.8), Color(0.2, 0.18, 0.18), 2)
	disabled.content_margin_top = 10
	disabled.content_margin_bottom = 10
	disabled.content_margin_left = 18
	disabled.content_margin_right = 18
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
	return b

static func progress(color: Color, bg: Color = Color(0.08, 0.07, 0.08, 0.9)) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = bg
	bgs.border_color = BORDER
	bgs.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	p.add_theme_stylebox_override("background", bgs)
	p.add_theme_stylebox_override("fill", fill)
	return p

static func separator(color: Color = BORDER) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 2)
	var s := StyleBoxFlat.new()
	s.bg_color = color
	p.add_theme_stylebox_override("panel", s)
	return p

static func spacer(height: float = 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

## Full-screen dark background with an ember vignette, used by every menu screen.
static func background(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var grad := TextureRect.new()
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.16, 0.06, 0.03, 0.85))
	gr.set_color(1, Color(0.03, 0.025, 0.035, 0.0))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.85)
	g.fill_to = Vector2(1.2, 0.1)
	grad.texture = g
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grad)

## The game's wordmark, used on the menu and the results screen.
static func title_block(small: bool = false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var t := label("UNSTABLE: LAST STAND", 64 if not small else 34, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_color_override("font_outline_color", Color(0.5, 0.15, 0.03))
	t.add_theme_constant_override("outline_size", 10 if not small else 6)
	v.add_child(t)
	var s := label("A TOWER DEFENSE STORY", 20 if not small else 13, EMBER, HORIZONTAL_ALIGNMENT_CENTER)
	s.add_theme_constant_override("outline_size", 4)
	v.add_child(s)
	return v

static func confidence_color(confidence: String) -> Color:
	if confidence.begins_with("canon"):
		return EMERALD
	if confidence.begins_with("supported"):
		return GOLD
	if confidence.begins_with("uncertain"):
		return EMBER
	return TEXT_DIM

static func confidence_label(confidence: String) -> String:
	if confidence.begins_with("canon"):
		return "CONFIRMED CANON"
	if confidence.begins_with("supported"):
		return "SUPPORTED"
	if confidence.begins_with("uncertain"):
		return "UNCERTAIN"
	if confidence.begins_with("fan"):
		return "FAN THEORY"
	return confidence.to_upper()
