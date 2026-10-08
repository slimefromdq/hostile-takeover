class_name Hud
extends Control

# In-game HUD drawn with _draw() so layout is anchor-based and needs no texture assets.
# Item icons use assets/textures/icon_utility_<id>.png and icon_melee_<id>.png when present.

const NEUTRAL := Color("c4c2af")
const KILL_FEED_LIFE := 6.0
const KILL_FEED_MAX := 5

var game: Node3D
var minimap: Minimap
var font: Font
var notice_text := ""
var notice_timer := 0.0
var quip_text := ""
var quip_timer := 0.0
var feed: Array = []
var indicators: Array = []
var hit_timer := 0.0
var hit_kind := 0
var session_time := 0.0
var help_hidden := false
var help_pinned := false
var explore := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	minimap = Minimap.new()
	add_child(minimap)

# ---- API used by game.gd -------------------------------------------------

func announce(text: String) -> void:
	notice_text = text
	notice_timer = 3.0

func quip(text: String) -> void:
	if quip_timer > 0.0:
		return
	quip_text = '“%s”' % text
	quip_timer = 4.0

func add_kill(killer_title: String, killer_team: int, victim_title: String, victim_team: int) -> void:
	feed.push_front({"killer": killer_title, "kt": killer_team, "victim": victim_title, "vt": victim_team, "age": 0.0})
	while feed.size() > KILL_FEED_MAX:
		feed.pop_back()

# kind: 0 hit, 1 headshot, 2 kill
func hit(kind: int) -> void:
	hit_kind = kind
	hit_timer = 0.45 if kind == 2 else 0.25

func damaged(from_pos: Vector3) -> void:
	indicators.append({"pos": from_pos, "age": 0.0})
	while indicators.size() > 6:
		indicators.pop_front()

func help_shown() -> bool:
	return not help_hidden and (help_pinned or session_time < 15.0)

func toggle_help() -> void:
	if help_shown():
		help_hidden = true
		help_pinned = false
	else:
		help_hidden = false
		help_pinned = true

func refresh(g: Node3D, dt: float) -> void:
	game = g
	minimap.game = g
	minimap.position = Vector2(size.x - minimap.size.x - 16.0, 16.0)
	notice_timer = maxf(0.0, notice_timer - dt)
	quip_timer = maxf(0.0, quip_timer - dt)
	hit_timer = maxf(0.0, hit_timer - dt)
	session_time += dt
	for entry in feed:
		entry.age += dt
	feed = feed.filter(func(e): return e.age < KILL_FEED_LIFE)
	for entry in indicators:
		entry.age += dt
	indicators = indicators.filter(func(e): return e.age < 1.5)
	if visible:
		minimap.queue_redraw()
		queue_redraw()

# ---- drawing helpers -------------------------------------------------------

func text(pos: Vector2, value: String, font_size: int, color: Color = Color("eef0e5"), align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), value, align, width, font_size, Color(0, 0, 0, 0.85))
	draw_string(font, pos, value, align, width, font_size, color)

func centered(center_x: float, y: float, value: String, font_size: int, color: Color = Color("eef0e5")) -> void:
	text(Vector2(center_x - 300.0, y), value, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, 600.0)

func pie(center: Vector2, radius: float, fraction: float, color: Color) -> void:
	if fraction <= 0.0:
		return
	var steps := int(32 * minf(fraction, 1.0)) + 2
	var pts := PackedVector2Array([center])
	for i in range(steps + 1):
		var a := -PI / 2.0 + TAU * minf(fraction, 1.0) * i / steps
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)

func diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)

func owner_color(owner: int) -> Color:
	return Visuals.team_color(owner) if owner >= 0 else NEUTRAL

# ---- main draw -------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	var p: Fighter = game.local_player()
	if explore:
		_draw_explore_tag()
	else:
		_draw_objective_bar()
	if p != null:
		_draw_vignette(p)
		_draw_indicators(p)
		if not explore:
			_draw_waypoint(p)
		_draw_crosshair(p)
		_draw_player_panel(p)
		_draw_health_bar(p)
		_draw_item_bar(p)
	_draw_notice()
	_draw_feed()
	_draw_help()
	if game.match_state.winner != -2:
		_draw_winner()
	if Input.is_action_pressed("scoreboard") and not game.menu.visible and not explore:
		_draw_scoreboard(p)

func _draw_explore_tag() -> void:
	var rect := Rect2(size.x / 2.0 - 150.0, 16.0, 300.0, 44.0)
	UiStyle.draw_panel(self, rect, Color(UiStyle.PANEL, 0.9), Color(UiStyle.ACCENT, 0.85))
	text(Vector2(rect.position.x, rect.position.y + 29.0), "EXPLORATION  ·  FREE ROAM", 18, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _draw_objective_bar() -> void:
	var state: Acquisition = game.match_state
	var cx := size.x / 2.0
	var y := 40.0
	var step := 74.0
	UiStyle.draw_panel(self, Rect2(cx - 2.0 * step - 40.0, y - 34.0, 4.0 * step + 80.0, 98.0), UiStyle.PANEL, Color(UiStyle.ACCENT, 0.7))
	for i in range(4):
		draw_line(Vector2(cx + (i - 2) * step + 24, y), Vector2(cx + (i - 1) * step - 24, y), Color(1, 1, 1, 0.25), 3.0)
	for i in range(5):
		var c := Vector2(cx + (i - 2) * step, y)
		var color := owner_color(state.owners[i])
		var unlocked: bool = state.unlocked[i]
		draw_circle(c, 23.0, UiStyle.SLOT)
		draw_circle(c, 18.0, Color(color, 0.85 if unlocked else 0.25))
		if unlocked:
			draw_arc(c, 22.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 2.0)
		var progress: float = state.progress[i]
		if progress > 0.0:
			var attacker_color := owner_color(1 - state.owners[i]) if state.owners[i] >= 0 else Color.WHITE
			draw_arc(c, 27.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, attacker_color, 4.0)
		text(c + Vector2(-20, 7), String.chr(65 + i), 22, Color.WHITE if unlocked else Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		if not unlocked:
			draw_rect(Rect2(c + Vector2(-5, 9), Vector2(10, 8)), Color(1, 1, 1, 0.8))
			draw_arc(c + Vector2(0, 9), 4.0, PI, TAU, 8, Color(1, 1, 1, 0.8), 1.5)
	var seconds := int(state.remaining)
	if state.overtime:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
		centered(cx, 100.0, "OVERTIME", 22, Color(1.0, 0.35, 0.3, pulse))
	else:
		centered(cx, 100.0, "%02d:%02d" % [seconds / 60, seconds % 60], 22)
	var held_by := [state.owners.count(0), state.owners.count(1)]
	var side_y := y - 34.0
	UiStyle.draw_tag(self, Rect2(cx - 2.0 * step - 190.0, side_y + 22.0, 140.0, 28.0), Color(Visuals.team_color(0), 0.25))
	UiStyle.draw_tag(self, Rect2(cx + 2.0 * step + 50.0, side_y + 22.0, 140.0, 28.0), Color(Visuals.team_color(1), 0.25))
	text(Vector2(cx - 2.0 * step - 184.0, side_y + 43.0), "HELIX  %d" % held_by[0], 18, Visuals.team_color(0), HORIZONTAL_ALIGNMENT_RIGHT, 124.0)
	text(Vector2(cx + 2.0 * step + 62.0, side_y + 43.0), "%d  MONARCH" % held_by[1], 18, Visuals.team_color(1))

func _draw_waypoint(p: Fighter) -> void:
	if p.hp <= 0 or game.match_state.winner != -2:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var best := -1
	var best_distance := INF
	for i in range(5):
		if game.match_state.unlocked[i] and game.match_state.owners[i] != p.team:
			var d: float = p.global_position.distance_to(game.points[i])
			if d < best_distance:
				best_distance = d
				best = i
	if best < 0:
		return
	var world: Vector3 = game.points[best] + Vector3.UP * 4.0
	var behind := camera.is_position_behind(world)
	# A point exactly on the camera plane has no projection; treat it as off to the side.
	var depth := (world - camera.global_position).dot(-camera.global_transform.basis.z)
	var screen := camera.unproject_position(world) if absf(depth) > 0.001 else size / 2.0 + Vector2.RIGHT
	var margin := 56.0
	var inside := not behind and screen.x > margin and screen.x < size.x - margin and screen.y > margin + 60.0 and screen.y < size.y - margin
	if not inside:
		var center := size / 2.0
		var dir := screen - center
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2.UP
		var scale := minf((size.x / 2.0 - margin) / maxf(absf(dir.x), 1.0), (size.y / 2.0 - margin) / maxf(absf(dir.y), 1.0))
		screen = center + dir * scale
	var zone := reticle_zone().grow(34.0)
	if zone.has_point(screen):
		screen.y = zone.position.y - 4.0
	var color := owner_color(game.match_state.owners[best])
	diamond(screen, 15.0, Color(0, 0, 0, 0.6))
	diamond(screen, 12.0, Color(color, 0.9))
	text(screen + Vector2(-12, 6), String.chr(65 + best), 16, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, 24.0)
	text(screen + Vector2(-30, 30), "%dm" % int(best_distance), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 60.0)

func _draw_crosshair(p: Fighter) -> void:
	if p.hp <= 0:
		return
	var c := size / 2.0
	var gap := 6.0
	var arm := 9.0
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * gap + Vector2(1, 1), c + dir * (gap + arm) + Vector2(1, 1), Color(0, 0, 0, 0.7), 3.0)
		draw_line(c + dir * gap, c + dir * (gap + arm), Color.WHITE, 2.0)
	draw_circle(c, 1.8, Color.WHITE)
	if p.swap_timer > 0.0:
		draw_arc(c, 20.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - clampf(p.swap_timer / Fighter.SWAP_TIME, 0.0, 1.0)), 24, Color("ffe2a3"), 3.0)
	if p.reload_timer > 0.0:
		var total: float = p.weapon.reload_time
		draw_arc(c, 28.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - clampf(p.reload_timer / total, 0.0, 1.0)), 32, Color(1, 1, 1, 0.9), 3.0)
	_draw_dash_icon(p, c + Vector2(48.0, 0.0))
	_draw_ammo(p, c + Vector2(0.0, 52.0))
	if hit_timer > 0.0:
		var color := Color.WHITE
		var inner := 10.0
		var outer := 18.0
		if hit_kind == 1:
			color = Color("ffd24a")
		elif hit_kind == 2:
			color = Color("ff4a3a")
			inner = 12.0
			outer = 24.0
		for dir in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir.normalized() * inner, c + dir.normalized() * outer, color, 3.0)

# Screen area reserved for the reticle cluster (dash icon, hit marker, ammo); world-anchored
# markers and the HP bar are nudged out of it so nothing overlaps.
func reticle_zone() -> Rect2:
	var c := size / 2.0
	return Rect2(c.x - 90.0, c.y - 44.0, 180.0, 100.0)

# Double chevron: white while the dash is ready (3 s cooldown), red once spent.
func _draw_dash_icon(p: Fighter, c: Vector2) -> void:
	var color := Color.WHITE if p.air_dash else UiStyle.DANGER
	for k in range(2):
		var o := Vector2(k * 7.0 - 7.0, 0.0)
		var pts := PackedVector2Array([c + o + Vector2(-3, -7), c + o + Vector2(4, 0), c + o + Vector2(-3, 7)])
		draw_polyline(PackedVector2Array([pts[0] + Vector2(1, 1), pts[1] + Vector2(1, 1), pts[2] + Vector2(1, 1)]), Color(0, 0, 0, 0.7), 4.0, true)
		draw_polyline(pts, color, 2.5, true)

# Gun in hand (ammo, or RELOADING) with the holstered gun's magazine under it, and the swap key.
func _draw_ammo(p: Fighter, c: Vector2) -> void:
	var stowed := p.stowed_weapon()
	text(c + Vector2(-80, 20), "2 · %s %d / %d" % [stowed.title, p.stowed_ammo, stowed.magazine], 13, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	if p.reload_timer > 0.0:
		text(c + Vector2(-80, 0), "RELOADING", 18, UiStyle.HIGHLIGHT, HORIZONTAL_ALIGNMENT_CENTER, 160.0)
		return
	text(c + Vector2(-80, 0), "%d / %d" % [p.ammo, p.weapon.magazine], 22, Color(UiStyle.DANGER) if p.ammo <= maxi(1, p.weapon.magazine / 5) else UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 160.0)

func _draw_player_panel(p: Fighter) -> void:
	var team_color := Visuals.team_color(p.team)
	var mode := "SPRINT" if p.idle_weapon >= 1.25 else "COMBAT"
	var base_y := size.y - 24.0
	UiStyle.draw_panel(self, Rect2(12, base_y - 56.0, 300.0, 56.0), UiStyle.PANEL, Color(team_color, 0.85))
	draw_rect(Rect2(12, base_y - 44.0, 4, 32.0), team_color)
	text(Vector2(24, base_y - 22), "%s   ·   %s" % [p.weapon.title.to_upper(), mode], 20)
	if p.hp <= 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		centered(size.x / 2.0, size.y / 2.0 - 30.0, "ELIMINATED", 40, Color("ff6a5a"))
		centered(size.x / 2.0, size.y / 2.0 + 10.0, "Respawn in %.1fs  ·  Esc to change loadout" % maxf(0.0, p.dead_time), 20)

# Vertical HP bar anchored beside the player's on-screen model (segments of 20 HP, bottom up).
func _draw_health_bar(p: Fighter) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or p.hp <= 0:
		return
	var feet: Vector3 = p.global_position
	var head: Vector3 = feet + Vector3.UP * 1.9
	var side: Vector3 = -camera.global_transform.basis.x * 0.65
	if camera.is_position_behind(head + side):
		return
	var bottom := camera.unproject_position(feet + side)
	var top := camera.unproject_position(head + side)
	var h := clampf(bottom.y - top.y, 80.0, 360.0)
	var mid := (bottom + top) * 0.5
	var rect := Rect2(mid.x - 7.0, mid.y - h / 2.0, 14.0, h)
	rect.position.x = clampf(rect.position.x, 40.0, size.x - 300.0)
	rect.position.y = clampf(rect.position.y, 150.0, size.y - 160.0 - h)
	var zone := reticle_zone().grow(8.0)
	if rect.grow(4.0).intersects(zone):
		rect.position.x = zone.position.x - rect.size.x - 12.0
	var team_color := Visuals.team_color(p.team)
	var fraction: float = clampf(p.hp / Fighter.MAX_HEALTH, 0.0, 1.0)
	var fill := team_color.lightened(0.15) if fraction > 0.35 else Color(1.0, 0.3 + 0.2 * sin(Time.get_ticks_msec() / 120.0), 0.25)
	UiStyle.draw_panel(self, rect.grow(4.0), UiStyle.PANEL, Color(team_color, 0.85), 5.0, 1.5)
	var segments := int(ceil(Fighter.MAX_HEALTH / 20.0))
	var seg_h := (rect.size.y - (segments - 1) * 2.0) / segments
	for i in range(segments):
		var y := rect.end.y - (i + 1) * seg_h - i * 2.0
		draw_rect(Rect2(rect.position.x, y, rect.size.x, seg_h), Color(1, 1, 1, 0.08))
		var f := clampf((p.hp - i * 20.0) / 20.0, 0.0, 1.0)
		if f > 0.0:
			draw_rect(Rect2(rect.position.x, y + seg_h * (1.0 - f), rect.size.x, seg_h * f), fill)
	text(Vector2(rect.position.x - 20.0, rect.position.y - 12.0), "%d" % int(ceil(p.hp)), 18, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 54.0)
	if p.armor > 0.0:
		var armor_h := rect.size.y * clampf(p.armor / Fighter.MAX_HEALTH, 0.0, 1.0)
		draw_rect(Rect2(rect.end.x + 3.0, rect.end.y - armor_h, 5.0, armor_h), Color("5ab8ff"))
		text(Vector2(rect.end.x - 20.0, rect.end.y + 18.0), "+%d" % int(ceil(p.armor)), 14, Color("5ab8ff"), HORIZONTAL_ALIGNMENT_CENTER, 54.0)

# Two slots: the utility on Q (cooldown pie) and the melee on F (recovery pie).
func _draw_item_bar(p: Fighter) -> void:
	var cx := size.x / 2.0
	var cy := size.y - 78.0
	var team_color := Visuals.team_color(p.team)
	var utility: Dictionary = Loadout.UTILITIES[p.utility()]
	var melee: Dictionary = Loadout.MELEES[p.melee()]
	var slots := [
		{"key": "Q", "name": utility.name, "cooldown": p.utility_cd, "total": utility.cooldown, "icon": "icon_utility_%d" % p.utility(), "state": "RELEASE" if p.grapple_time > 0.0 else ""},
		{"key": "F", "name": melee.name, "cooldown": p.melee_cd, "total": melee.recovery, "icon": "icon_melee_%d" % p.melee(), "state": ""},
	]
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var c := Vector2(cx + (i - (slots.size() - 1) / 2.0) * 96.0, cy)
		var cooldown: float = 0.0 if slot.state != "" else slot.cooldown
		draw_circle(c, 34.0, UiStyle.SLOT)
		var icon := AssetLibrary.texture(slot.icon)
		if icon != null:
			draw_texture_rect(icon, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false, Color(1, 1, 1, 0.35 if cooldown > 0.0 else 1.0))
		elif cooldown <= 0.0:
			text(c + Vector2(-20, 13), slot.name.substr(0, 1), 38, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		if cooldown > 0.0:
			pie(c, 33.0, cooldown / slot.total, Color(0, 0, 0, 0.62))
			text(c + Vector2(-24, 8), "%.0f" % cooldown if cooldown >= 1.0 else "%.1f" % cooldown, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 48.0)
			draw_arc(c, 34.0, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0)
		else:
			draw_arc(c, 34.0, 0, TAU, 40, Color("ffe2a3") if slot.state != "" else team_color, 3.0)
		if slot.state != "":
			text(c + Vector2(-34, -38), slot.state, 14, Color("ffe2a3"), HORIZONTAL_ALIGNMENT_CENTER, 68.0)
		UiStyle.draw_tag(self, Rect2(c + Vector2(-14, 26), Vector2(28, 20)), UiStyle.ACCENT)
		text(c + Vector2(-14, 42), slot.key, 15, UiStyle.SLOT, HORIZONTAL_ALIGNMENT_CENTER, 28.0)
		text(c + Vector2(-48, 62), slot.name, 12, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 96.0)
	if p.power != 0:
		centered(cx, cy - 92.0, "%s  %.1f" % [Items.POWER_NAMES[p.power], p.power_time], 24, Items.POWER_COLORS[p.power])
	if quip_timer > 0.0:
		centered(cx, cy - 56.0, quip_text, 18, Color(1, 1, 1, minf(1.0, quip_timer)))

func _draw_notice() -> void:
	if notice_timer > 0.0:
		centered(size.x / 2.0, 140.0, notice_text, 22, Color(1, 1, 1, minf(1.0, notice_timer * 2.0)))

func _draw_vignette(p: Fighter) -> void:
	var fraction: float = p.hp / Fighter.MAX_HEALTH
	if p.hp <= 0 or fraction >= 0.35:
		return
	var a := 0.25 + 0.1 * sin(Time.get_ticks_msec() / 160.0)
	for k in range(6):
		draw_rect(Rect2(k * 8.0, k * 8.0, size.x - k * 16.0, size.y - k * 16.0), Color(0.8, 0.05, 0.05, a * (1.0 - k / 6.0)), false, 8.0)

func _draw_indicators(p: Fighter) -> void:
	var c := size / 2.0
	for entry in indicators:
		var diff: Vector3 = entry.pos - p.global_position
		var rel := wrapf(atan2(-diff.x, -diff.z) - p.yaw, -PI, PI)
		var angle := -PI / 2.0 + rel
		var alpha := clampf(1.0 - entry.age / 1.5, 0.0, 1.0)
		draw_arc(c, 130.0, angle - 0.22, angle + 0.22, 12, Color(1.0, 0.2, 0.15, alpha), 8.0)

func _draw_feed() -> void:
	var y := minimap.position.y + minimap.size.y + 14.0
	var right := size.x - 16.0
	for entry in feed:
		var fade := clampf((KILL_FEED_LIFE - entry.age) / 1.5, 0.0, 1.0)
		var victim_w := font.get_string_size(entry.victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var killer_w := font.get_string_size(entry.killer, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var arrow_w := 26.0
		var total := killer_w + arrow_w + victim_w + 12.0
		UiStyle.draw_tag(self, Rect2(right - total, y, total, 22), Color(UiStyle.PANEL, 0.8 * fade), 6.0)
		var x := right - total + 6.0
		text(Vector2(x, y + 17), entry.killer, 15, Color(Visuals.team_color(entry.kt), fade))
		text(Vector2(x + killer_w, y + 17), " » ", 15, Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_CENTER, arrow_w)
		text(Vector2(x + killer_w + arrow_w, y + 17), entry.victim, 15, Color(Visuals.team_color(entry.vt), fade))
		y += 26.0

func _draw_help() -> void:
	if not help_shown():
		return
	var lines := ["WASD move · SPACE jump, double jump, wall kick", "SHIFT slide · SPACE out of a slide to slide-jump", "Run along a wall to wall run · ledges mantle", "1 air dash · strafe to steer in the air", "Q utility · F melee · 2 swap gun · R reload · V shoulder · TAB scores", "ESC menu · F1 hints · F2 colour-blind palette · F3 mute"]
	for i in range(lines.size()):
		text(Vector2(size.x - 420.0, size.y - 138.0 + i * 20.0), lines[i], 14, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 404.0)

func _draw_winner() -> void:
	var winner: int = game.match_state.winner
	draw_rect(Rect2(0, size.y * 0.25 - 40, size.x, 150), Color(UiStyle.PANEL, 0.8))
	draw_rect(Rect2(0, size.y * 0.25 - 40, size.x, 3), Color(UiStyle.ACCENT, 0.8))
	draw_rect(Rect2(0, size.y * 0.25 + 107, size.x, 3), Color(UiStyle.ACCENT, 0.8))
	if winner == -1:
		centered(size.x / 2.0, size.y * 0.25 + 20.0, "DRAW · Contract disputed", 40)
	else:
		centered(size.x / 2.0, size.y * 0.25 + 20.0, "%s WINS · Acquisition complete" % ("HELIX" if winner == 0 else "MONARCH"), 40, Visuals.team_color(winner))
	centered(size.x / 2.0, size.y * 0.25 + 62.0, "Esc → Restart round", 18)

# ---- scoreboard -------------------------------------------------------------

# Rows per team, sorted by kills. Static so tests can verify it without drawing.
static func scoreboard_rows(g: Node3D) -> Array:
	var teams: Array = [[], []]
	for p in g.fighters.values():
		var shown_name: String = "You" if p.fighter_id == g.local_id else p.callsign()
		teams[p.team].append({"name": shown_name, "loadout": p.primary.title, "k": p.kills, "d": p.deaths, "pp": p.power_pickups, "alive": p.hp > 0, "you": p.fighter_id == g.local_id})
	for team in teams:
		team.sort_custom(func(a, b): return a.k > b.k)
	return teams

func _draw_scoreboard(p: Fighter) -> void:
	var teams := scoreboard_rows(game)
	var panel := Rect2(size.x / 2.0 - 400.0, 130.0, 800.0, 360.0)
	UiStyle.draw_panel(self, panel, Color(UiStyle.PANEL, 0.94), Color(UiStyle.ACCENT, 0.8), 16.0)
	for t in range(2):
		var x := panel.position.x + 20.0 + t * 390.0
		var held: int = game.match_state.owners.count(t)
		text(Vector2(x, panel.position.y + 30), "%s  ·  %d points" % [["HELIX", "MONARCH"][t], held], 20, Visuals.team_color(t))
		text(Vector2(x + 160, panel.position.y + 56), "PRIMARY", 12, Color(1, 1, 1, 0.6))
		text(Vector2(x + 250, panel.position.y + 56), "K", 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
		text(Vector2(x + 288, panel.position.y + 56), "D", 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
		text(Vector2(x + 326, panel.position.y + 56), "PWR", 12, Color(Items.POWER_COLORS[Items.POWER_QUAD], 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 36.0)
		var row_y := panel.position.y + 80.0
		for row in teams[t]:
			var alpha := 1.0 if row.alive else 0.45
			if row.you:
				draw_rect(Rect2(x - 6, row_y - 17, 372, 24), Color(1, 1, 1, 0.12))
			# Shape + colour: allies get a circle, enemies a diamond.
			if t == p.team:
				draw_circle(Vector2(x + 6, row_y - 5), 5.0, Color(Visuals.team_color(t), alpha))
			else:
				diamond(Vector2(x + 6, row_y - 5), 6.0, Color(Visuals.team_color(t), alpha))
			text(Vector2(x + 20, row_y), row.name, 16, Color(1, 1, 1, alpha))
			text(Vector2(x + 160, row_y), row.loadout, 14, Color(1, 1, 1, alpha))
			text(Vector2(x + 250, row_y), "%d" % row.k, 16, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
			text(Vector2(x + 288, row_y), "%d" % row.d, 16, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
			text(Vector2(x + 326, row_y), "%d" % row.pp, 16, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_RIGHT, 36.0)
			row_y += 24.0
	if p != null:
		text(Vector2(panel.position.x + 20, panel.end.y - 16), "YOUR LOADOUT  ·  " + Loadout.describe(p.loadout), 14, Color(1, 1, 1, 0.8))
