class_name ClassIdentity
extends RefCounted

static func build(parent: Node3D, archetype: int, team_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ClassEquipment"
	parent.add_child(root)
	var dark := Color("28323f")
	var cream := Color("e7e9df")
	match archetype:
		0:
			for side in [-1, 1]:
				CivicDividend.box(root, Vector3(side * 0.32, 1.15, 0.25), Vector3(0.14, 0.7, 0.3), Color("ffe2a3"), false)
				CivicDividend.box(root, Vector3(side * 0.22, 0.15, -0.12), Vector3(0.25, 0.2, 0.5), dark, false)
		1:
			CivicDividend.box(root, Vector3(0, 1, 0.36), Vector3(0.65, 0.6, 0.4), Color("d9b95b"), false)
			CivicDividend.box(root, Vector3(0.29, 1.6, 0.42), Vector3(0.06, 0.7, 0.06), dark, false)
			CivicDividend.box(root, Vector3(-0.45, 0.85, 0), Vector3(0.2, 0.55, 0.22), cream, false)
		2:
			for side in [-1, 1]:
				CivicDividend.box(root, Vector3(side * 0.52, 1.3, 0), Vector3(0.4, 0.45, 0.6), team_color.darkened(0.35), false)
				CivicDividend.box(root, Vector3(side * 0.28, 0.15, -0.1), Vector3(0.4, 0.3, 0.55), dark, false)
			CivicDividend.box(root, Vector3(0, 1.1, -0.4), Vector3(0.65, 0.7, 0.12), cream, false)
		3:
			for side in [-1, 1]:
				CivicDividend.box(root, Vector3(side * 0.22, 0.5, 0.23), Vector3(0.28, 0.6, 0.15), dark, false)
			CivicDividend.box(root, Vector3(0, 1.25, -0.37), Vector3(0.12, 0.42, 0.04), Color("c7a8f1"), false)
			CivicDividend.box(root, Vector3(0, 1.7, -0.28), Vector3(0.45, 0.09, 0.04), dark, false)
	return root
