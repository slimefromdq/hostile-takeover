class_name Minimap
extends Control

# North-up top-down map drawn from the map's footprint list; no extra camera or viewport.

const WIDTH := 220.0
var game: Node3D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bounds := CivicDividend.bounds
	custom_minimum_size = Vector2(WIDTH, WIDTH * bounds.size.y / bounds.size.x)
	size = custom_minimum_size

# World (x, z) to minimap pixels.
func to_map(x: float, z: float) -> Vector2:
	var bounds := CivicDividend.bounds
	return Vector2((x - bounds.position.x) / bounds.size.x * size.x, (z - bounds.position.y) / bounds.size.y * size.y)

func _draw() -> void:
	UiStyle.draw_panel(self, Rect2(Vector2.ZERO, size), Color(UiStyle.PANEL, 0.75), Color(0, 0, 0, 0))
	for rect in CivicDividend.sunken:
		var sa := to_map(rect.position.x, rect.position.y)
		var sb := to_map(rect.end.x, rect.end.y)
		draw_rect(Rect2(sa, sb - sa), Color(0.2, 0.35, 0.55, 0.35))
	for rect in CivicDividend.footprints:
		var a := to_map(rect.position.x, rect.position.y)
		var b := to_map(rect.end.x, rect.end.y)
		draw_rect(Rect2(a, b - a), Color(0.55, 0.6, 0.68, 0.45))
	UiStyle.draw_panel(self, Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), Color(UiStyle.ACCENT, 0.85))
	if game == null:
		return
	var font := ThemeDB.fallback_font
	var points: Array[Vector3] = game.points
	for i in range(points.size()):
		var owner: int = game.match_state.owners[i]
		var color := Visuals.team_color(owner) if owner >= 0 else Color("c4c2af")
		if not game.match_state.unlocked[i]:
			color = color.darkened(0.45)
		var c := to_map(points[i].x, points[i].z)
		draw_circle(c, 9.0, Color(color, 0.35))
		draw_arc(c, 9.0, 0, TAU, 20, color, 2.0)
		draw_string(font, c + Vector2(-4, 5), String.chr(65 + i), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var me: Fighter = game.local_player()
	_draw_health_packs(me)
	if me == null:
		return
	for p in game.fighters.values():
		if p.hp <= 0 or p == me:
			continue
		var c := to_map(p.global_position.x, p.global_position.z)
		if p.team == me.team:
			draw_circle(c, 3.5, Visuals.team_color(p.team))
		elif p.reveal > 0 or p.global_position.distance_to(me.global_position) < 12.0:
			# Enemies are diamonds so team is never conveyed by colour alone.
			var d := 5.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Visuals.ENEMY_OUTLINE)
	var m := to_map(me.global_position.x, me.global_position.z)
	var forward := Vector2(-sin(me.yaw), -cos(me.yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([m + forward * 8.0, m - forward * 4.0 + side * 4.5, m - forward * 4.0 - side * 4.5]), Color.WHITE)

# Health packs: a plus per pack, always shown so you can plan a route. Taken packs go grey. Many sit on
# top of each other in x/z across tiers, so packs more than a floor above or below you are dimmer and
# carry an arrow pointing which way to go.
func _draw_health_packs(me: Fighter) -> void:
	for e in game.entities.values():
		if e.kind != "healpack" and not Items.KINDS.has(e.kind):
			continue
		var c := to_map(e.global_position.x, e.global_position.z)
		var dy: float = 0.0 if me == null else e.global_position.y - me.global_position.y
		var base_color: Color = Color("3dff7a") if e.kind == "healpack" else Items.KINDS[e.kind].color
		if e.kind == "power" and Items.POWER_COLORS.has(int(e.hp)):
			base_color = Items.POWER_COLORS[int(e.hp)]
		var color := base_color if not e.used else Color(0.55, 0.6, 0.6)
		if absf(dy) > 3.0:
			color.a = 0.55
		if e.kind == "power" and Items.power_spawning_soon(e.used, e.timer):
			# About to spawn: a pulsing ring that closes in as the timer runs down, with the seconds left.
			var warn: Color = Items.KINDS.power.color
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
			draw_arc(c, 7.0 + 5.0 * (e.timer / Items.POWER_WARNING), 0, TAU, 24, Color(warn, 0.5 + 0.5 * pulse), 2.0)
			draw_string(ThemeDB.fallback_font, c + Vector2(-8, -10), "%d" % ceili(e.timer), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color(warn, 1.0))
			color = Color(warn, 0.6 + 0.4 * pulse)
		if e.kind == "bubble":
			draw_circle(c, 2.5, color)
		elif e.kind == "power":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), color)
		elif e.kind == "armor1" or e.kind == "armor2":
			var half := 3.0 if e.kind == "armor1" else 4.5
			draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), color)
		else:
			draw_line(c + Vector2(-3.5, 0), c + Vector2(3.5, 0), color, 2.0)
			draw_line(c + Vector2(0, -3.5), c + Vector2(0, 3.5), color, 2.0)
		if dy > 3.0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(3.5, -5), c + Vector2(-3.5, -5)]), color)
		elif dy < -3.0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 9), c + Vector2(3.5, 5), c + Vector2(-3.5, 5)]), color)
