class_name UiStyle
extends RefCounted

# Shared UI tokens and shape helpers. Mirrors the "Hostile Takeover UI Kit" Figma file
# (colour variables, Panel / Objective banner / Ability slot / Health plate components).

const PANEL := Color(0.039, 0.067, 0.098, 0.9)       # surface/panel  #0a1119
const PANEL_RAISED := Color("1a2a3d")                # surface/panel-raised
const SLOT := Color(0.031, 0.051, 0.078, 0.9)        # surface/slot
const ACCENT := Color("3fd0ff")                      # accent/cyan
const TEXT := Color("eef0e5")                        # text/primary
const TEXT_MUTED := Color(1, 1, 1, 0.7)
const HIGHLIGHT := Color("ffe2a3")                   # state/highlight
const DANGER := Color("ff4a3a")                      # state/danger
const CUT := 10.0                                    # panel corner cut

# Panel with one cut top-right and one cut bottom-left corner, as in the Figma Panel component.
static func panel_points(rect: Rect2, cut: float = CUT) -> PackedVector2Array:
	var r := rect
	return PackedVector2Array([
		r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut),
		r.end, Vector2(r.position.x + cut, r.end.y), Vector2(r.position.x, r.end.y - cut)])

static func draw_panel(ci: CanvasItem, rect: Rect2, fill: Color = PANEL, edge: Color = Color(ACCENT, 0.85), cut: float = CUT, width: float = 2.0) -> void:
	var pts := panel_points(rect, cut)
	ci.draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	if edge.a > 0.0:
		ci.draw_polyline(outline, edge, width, true)

# Parallelogram "tag", used for key hints and feed rows.
static func draw_tag(ci: CanvasItem, rect: Rect2, fill: Color, slant: float = 5.0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + slant, rect.position.y), Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - slant, rect.end.y), Vector2(rect.position.x, rect.end.y)]), fill)

# ---- Control styling (menus) -------------------------------------------------

static func box(fill: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, margin: float = 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.6
	style.content_margin_bottom = margin * 0.6
	return style

# Flat button: raised navy, cyan hairline, cyan fill when `primary` or pressed.
static func style_button(button: Button, primary: bool = false) -> void:
	var normal := box(ACCENT if primary else Color(PANEL_RAISED, 0.9), Color(ACCENT, 0.9 if primary else 0.45), 1)
	var hover := box(ACCENT.lightened(0.2) if primary else PANEL_RAISED.lightened(0.12), ACCENT, 2)
	var pressed := box(ACCENT.darkened(0.15) if primary else Color(ACCENT, 0.25), ACCENT, 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), HIGHLIGHT, 2))
	var ink := SLOT if primary else TEXT
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
