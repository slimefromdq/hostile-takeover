class_name CivicDividend
extends RefCounted

# Facade over MapLayout/MapBuilder so existing callers (game.gd, minimap, tests) keep one entry point.

static var footprints: Array[Rect2] = []
static var sunken: Array[Rect2] = []
static var builder: MapBuilder

# Active map settings. They default to MapLayout and are overridden when a blockout in "replace" mode is loaded.
static var bounds: Rect2 = MapLayout.BOUNDS
static var capture_points: Array[Vector3] = MapLayout.points()
static var goal_names: Array[String] = ["A", "B", "C", "e_B", "e_A"]
static var spawn_nodes: Array[String] = ["S", "e_S"]
static var spawn_x: float = MapLayout.SPAWN_X
static var spawn_z: float = -7.0
static var spawn_step: float = 2.8
static var depot_limit: float = MapLayout.DEPOT_LIMIT
static var test_lane: Vector3 = MapLayout.TEST_LANE
static var graph_data: Dictionary = {}
# Optional audit profile from the blockout (sightline lanes, route families, spawn sight); {} means the built-in map's.
static var audit_profile: Dictionary = {}
static var replaced := false

static func reset_settings() -> void:
	bounds = MapLayout.BOUNDS
	capture_points = MapLayout.points()
	goal_names = ["A", "B", "C", "e_B", "e_A"]
	spawn_nodes = ["S", "e_S"]
	spawn_x = MapLayout.SPAWN_X
	spawn_z = -7.0
	spawn_step = 2.8
	depot_limit = MapLayout.DEPOT_LIMIT
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
	var blockout := BlockoutImporter.read(BlockoutImporter.ACTIVE_PATH)
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
	MapVerbs.clear()
	if not blockout.is_empty():
		MapVerbs.configure(BlockoutImporter.features(blockout), root)
	footprints = builder.footprints()
	sunken = builder.sunken
	if not replaced:
		_signage(root)
	var points := capture_points.duplicate()
	for i in range(points.size()):
		sign_text(root, points[i] + Vector3(0, 9, 0), String.chr(65 + i), Color.WHITE, 1.0)
	return points

static func _signage(root: Node3D) -> void:
	# Corporate-satire signage on facades, facing the street and away from the HUD sightline.
	wall_sign(root, Vector3(-76, 4.0, -12), 1.0, "HELIX LOGISTICS", Visuals.HELIX, 1.4)
	wall_sign(root, Vector3(76, 4.0, -12), 1.0, "MONARCH HOLDINGS", Visuals.MONARCH, 1.4)
	wall_sign(root, Vector3(-16, -1.0, 29), -1.0, "CIVIC DIVIDEND\nPUBLIC SPACE. PRIVATE PROBLEM.", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(16, -1.0, 29), -1.0, "CIVIC DIVIDEND\nPUBLIC SPACE. PRIVATE PROBLEM.", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(-48, -1.5, 29), -1.0, "TRANSIT\nTEMPORARILY PRIVATIZED", Color("efe7c9"), 0.9)
	wall_sign(root, Vector3(48, -1.5, 29), -1.0, "TRANSIT\nTEMPORARILY PRIVATIZED", Color("efe7c9"), 0.9)
