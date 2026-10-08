class_name CivicDividend
extends RefCounted

# Facade over MapLayout/MapBuilder so existing callers (game.gd, minimap, tests) keep one entry point.

# Fighters per team. Depot spawn slots are laid out in rows of SPAWN_ROW slots (see spawn_slot_position).
const TEAM_SIZE := 5
const SPAWN_ROW := 5
const SPAWN_ROW_GAP := 2.5

static var footprints: Array[Rect2] = []
static var sunken: Array[Rect2] = []
static var builder: MapBuilder
static var pickups: Array = []  # blockout "pickup" features (health packs), mirrors already expanded

# Active map settings. They default to MapLayout and are overridden when a blockout in "replace" mode is loaded.
static var bounds: Rect2 = MapLayout.BOUNDS
static var capture_points: Array[Vector3] = MapLayout.points()
static var goal_names: Array[String] = ["A", "B", "C", "e_B", "e_A"]
static var spawn_nodes: Array[String] = ["S", "e_S"]
static var spawn_x: float = MapLayout.SPAWN_X
static var spawn_z: float = -7.0
static var spawn_step: float = 2.8
static var depot_limit: float = MapLayout.DEPOT_LIMIT
# Height above which fighters are killed (grapples and launch pads can never carry anyone out of the arena).
static var ceiling: float = 40.0
static var kill_floor: float = -INF
static var team_spawns: Array = []
static var spawn_zones: Array[AABB] = []
static var test_lane: Vector3 = MapLayout.TEST_LANE
static var graph_data: Dictionary = {}
# Optional audit profile from the blockout (sightline lanes, route families, spawn sight); {} means the built-in map's.
static var audit_profile: Dictionary = {}
static var replaced := false

# Depot position for a team slot (0..TEAM_SIZE-1): rows of SPAWN_ROW across z, centered where the old single row of six
# was, later rows stepping back from the gate so a full team fits the depot (the audit checks every slot is clear).
static func spawn_slot_position(side: int, slot: int) -> Vector3:
	if not team_spawns.is_empty():
		return team_spawns[side][slot % TEAM_SIZE]
	var row := slot / SPAWN_ROW
	var column := slot % SPAWN_ROW
	var x := spawn_x + row * SPAWN_ROW_GAP
	var z := spawn_z + spawn_step * 0.5 + column * spawn_step
	return Vector3(-x if side == 0 else x, 0.2, z)

static func spawn_protected(pos: Vector3) -> bool:
	if spawn_zones.is_empty():
		return absf(pos.x) > depot_limit
	for zone in spawn_zones:
		if zone.has_point(pos):
			return true
	return false

static func at_spawn(pos: Vector3) -> bool:
	return absf(pos.x) >= 80.0 if spawn_zones.is_empty() else spawn_protected(pos)

static func reset_settings() -> void:
	bounds = MapLayout.BOUNDS
	capture_points = MapLayout.points()
	goal_names = ["A", "B", "C", "e_B", "e_A"]
	spawn_nodes = ["S", "e_S"]
	spawn_x = MapLayout.SPAWN_X
	spawn_z = -7.0
	spawn_step = 2.8
	depot_limit = MapLayout.DEPOT_LIMIT
	ceiling = 40.0
	kill_floor = -INF
	team_spawns.clear()
	spawn_zones.clear()
	test_lane = MapLayout.TEST_LANE
	graph_data = MapLayout.graph()
	audit_profile = {}
	replaced = false

static func apply_settings(r: Dictionary) -> void:
	bounds = r.bounds
	capture_points = r.points
	goal_names = r.goal_names
	spawn_nodes = r.spawn_nodes
	spawn_x = r.spawn_x
	spawn_z = r.spawn_z
	spawn_step = r.spawn_step
	depot_limit = r.depot_limit
	ceiling = r.ceiling
	kill_floor = r.kill_floor
	team_spawns = r.team_spawns.duplicate(true)
	spawn_zones.assign(r.spawn_zones)
	test_lane = r.test_lane
	graph_data = r.graph
	audit_profile = r.audit
	replaced = true

# Wall-mounted sign: flush on a face (`normal_z` = +1 faces south, -1 faces north), never billboarded,
# so it cannot clip through geometry when viewed from the side.
static func wall_sign(root: Node3D, pos: Vector3, normal_z: float, value: String, color: Color, scale_value: float = 1.0) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = 64
	label.pixel_size = 0.012 * scale_value
	label.modulate = color
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.position = pos + Vector3(0, 0, 0.06 * normal_z)
	if normal_z < 0.0:
		label.rotation.y = PI
	root.add_child(label)

static func sign_text(root: Node3D, pos: Vector3, value: String, color: Color, scale_value: float = 1) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = pos
	label.font_size = 64
	label.pixel_size = 0.015 * scale_value
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

static func build(root: Node3D) -> Array[Vector3]:
	Visuals.build_environment(root)
	builder = MapBuilder.new()
	reset_settings()
	var blockout := BlockoutImporter.read(BlockoutImporter.active_path())
	if blockout.get("mode", "add") == "replace":
		var resolved := BlockoutImporter.resolve(blockout)
		if resolved.errors.is_empty():
			apply_settings(resolved)
		else:
			# A half-valid replacement would leave the game unplayable, so ignore the whole file.
			for message in resolved.errors:
				push_error("Blockout replace mode refused, using the built-in map: " + message)
			blockout = {}
	if not replaced:
		MapLayout.build(builder)
	for message in BlockoutImporter.build(builder, blockout):
		push_warning("Blockout: " + message)
	builder.finalize(root)
	if is_finite(kill_floor):
		Visuals.build_ocean(root, bounds, kill_floor)
	MapVerbs.clear()
	pickups.clear()
	if not blockout.is_empty():
		var features := BlockoutImporter.features(blockout)
		MapVerbs.configure(features, root)
		for f in features:
			if f.get("type", "") == "pickup":
				pickups.append(f)
	footprints = builder.footprints()
	sunken = builder.sunken
	if not replaced:
		_signage(root)
	var points := capture_points.duplicate()
	for i in range(points.size()):
		var label_y: float = points[i].y + 9.0
		for solid in builder.solids:
			var box: AABB = solid.aabb
			if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).has_point(Vector2(points[i].x, points[i].z)):
				label_y = maxf(label_y, box.end.y + 2.0)
		sign_text(root, Vector3(points[i].x, label_y, points[i].z), String.chr(65 + i), Color.WHITE, 1.0)
	return points

static func _signage(root: Node3D) -> void:
	# Corporate-satire signage on facades, facing the street and away from the HUD sightline.
	wall_sign(root, Vector3(-76, 4.0, -12), 1.0, "HELIX LOGISTICS", Visuals.HELIX, 1.4)
	wall_sign(root, Vector3(76, 4.0, -12), 1.0, "MONARCH HOLDINGS", Visuals.MONARCH, 1.4)
	wall_sign(root, Vector3(-16, -1.0, 29), -1.0, "CIVIC DIVIDEND\nPUBLIC SPACE. PRIVATE PROBLEM.", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(16, -1.0, 29), -1.0, "CIVIC DIVIDEND\nPUBLIC SPACE. PRIVATE PROBLEM.", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(-48, -1.5, 29), -1.0, "TRANSIT\nTEMPORARILY PRIVATIZED", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(48, -1.5, 29), -1.0, "TRANSIT\nTEMPORARILY PRIVATIZED", Color("efe7c9"), 0.9)
