class_name CivicDividend
extends RefCounted

# Facade over MapLayout/MapBuilder so existing callers (game.gd, minimap, tests) keep one entry point.

const BOUNDS := MapLayout.BOUNDS
static var footprints: Array[Rect2] = []
static var sunken: Array[Rect2] = []
static var builder: MapBuilder

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
	var blockout := BlockoutImporter.read(BlockoutImporter.ACTIVE_PATH)
	if blockout.get("mode", "add") != "replace":
		MapLayout.build(builder)
	for message in BlockoutImporter.build(builder, blockout):
		push_warning("Blockout: " + message)
	builder.finalize(root)
	footprints = builder.footprints()
	sunken = builder.sunken
	_signage(root)
	var points := MapLayout.points()
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
