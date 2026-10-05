class_name CivicDividend
extends RefCounted

static func box(root: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = true, role: String = "") -> Node3D:
	var node := StaticBody3D.new() if solid else Node3D.new()
	root.add_child(node)
	node.position = pos
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	if role == "":
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		mesh.material_override = mat
	else:
		mesh.material_override = Visuals.surface(role, color)
	node.add_child(mesh)
	if solid:
		node.collision_layer = 1
		node.collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
		node.add_child(shape)
	return node

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
	box(root, Vector3(0, -0.6, 0), Vector3(180, 1, 52), Color("626d77"), true, "walk")
	box(root, Vector3(0, 0, -25), Vector3(180, 1, 2), Color("a2afb9"), true, "walk")
	box(root, Vector3(0, 0, 25), Vector3(180, 1, 2), Color("a2afb9"), true, "walk")
	# Low service corridors provide flanks; connected rooftops provide parkour routes.
	for x in [-64, -32, 0, 32, 64]:
		for z in [-13, 13]:
			var color := Color("32465d") if x < 0 else Color("65484b")
			box(root, Vector3(x + 9, 2.5, z), Vector3(8, 5, 8), color.darkened(0.25), true, "tower")
			box(root, Vector3(x - 9, 1.8, z), Vector3(6, 3.6, 6), color, true, "tower")
			box(root, Vector3(x - 5, 0.5, z - signf(z) * 3), Vector3(2, 1, 2), Color("a4ada7"), true, "cover")
			box(root, Vector3(x + 2, 3.9, z), Vector3(8, 0.3, 2), Color("7d8993"), true, "walk")
			# Sloped approach to rooftop, also useful for downhill slides.
			var ramp := box(root, Vector3(x + 9, 1.7, z + signf(z) * 6), Vector3(4, 0.4, 10), Color("8494a2"), true, "walk")
			ramp.rotation.x = deg_to_rad(-22.0 * signf(z))
		for z in [-5.0, 5.0]:
			box(root, Vector3(x + (3 if z < 0 else -3), 0.6, z), Vector3(3, 1.2, 2), Color("b3a27c"), true, "cover")
		box(root, Vector3(x, 0.02, 0), Vector3(12, 0.08, 10), Color("8698a0"), false, "accent")
	# Perimeter walls and skyline: no full-map sniper sightline.
	for x in [-48, -16, 16, 48]:
		box(root, Vector3(x, 2.2, 0), Vector3(2, 4.4, 6), Color("758c95"), true, "wall")
		sign_text(root, Vector3(x, 5.3, 0), "TRANSIT\nTEMPORARILY PRIVATIZED", Color("efe7c9"), 0.25)
	box(root, Vector3(-90, 4, 0), Vector3(1, 8, 52), Color("344052"), true, "wall")
	box(root, Vector3(90, 4, 0), Vector3(1, 8, 52), Color("493840"), true, "wall")
	for z in [-27, 27]:
		box(root, Vector3(0, 4, z), Vector3(180, 8, 1), Color("445467"), true, "wall")
		for x in range(-84, 85, 12):
			box(root, Vector3(x, 12, z + signf(z) * 7), Vector3(9, 24 + abs(x) % 15, 8), Color("3e4a5b"), false, "tower")
	for side in [0, 1]:
		var sx := -82.0 if side == 0 else 82.0
		var col := Color("53c8f4") if side == 0 else Color("ff956f")
		box(root, Vector3(sx, 2, 0), Vector3(2, 4, 12), col.darkened(0.5), true, "wall")
		box(root, Vector3(sx, 2, -12), Vector3(2, 4, 8), col.darkened(0.5), true, "wall")
		box(root, Vector3(sx, 2, 12), Vector3(2, 4, 8), col.darkened(0.5), true, "wall")
		sign_text(root, Vector3(sx, 6, 0), "HELIX LOGISTICS" if side == 0 else "MONARCH HOLDINGS", col, 0.65)
	sign_text(root, Vector3(0, 10, -18), "CIVIC DIVIDEND\nPUBLIC SPACE. PRIVATE PROBLEM.", Color("efe7c9"), 0.65)
	var points: Array[Vector3] = []
	for i in range(5):
		var pos := Vector3((i - 2) * 32, 0, 0)
		points.append(pos)
		sign_text(root, pos + Vector3(0, 5, 0), String.chr(65 + i), Color.WHITE)
	return points
