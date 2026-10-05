class_name Minimap
extends Control

# North-up top-down map drawn from the map's footprint list; no extra camera or viewport.

const WIDTH := 220.0
var game: Node3D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bounds := CivicDividend.BOUNDS
	custom_minimum_size = Vector2(WIDTH, WIDTH * bounds.size.y / bounds.size.x)
	size = custom_minimum_size

# World (x, z) to minimap pixels.
func to_map(x: float, z: float) -> Vector2:
	var bounds := CivicDividend.BOUNDS
	return Vector2((x - bounds.position.x) / bounds.size.x * size.x, (z - bounds.position.y) / bounds.size.y * size.y)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.62))
	for rect in CivicDividend.sunken:
		var sa := to_map(rect.position.x, rect.position.y)
		var sb := to_map(rect.end.x, rect.end.y)
		draw_rect(Rect2(sa, sb - sa), Color(0.2, 0.35, 0.55, 0.35))
	for rect in CivicDividend.footprints:
		var a := to_map(rect.position.x, rect.position.y)
		var b := to_map(rect.end.x, rect.end.y)
		draw_rect(Rect2(a, b - a), Color(0.55, 0.6, 0.68, 0.45))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.5)
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
