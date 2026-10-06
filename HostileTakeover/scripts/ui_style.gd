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
