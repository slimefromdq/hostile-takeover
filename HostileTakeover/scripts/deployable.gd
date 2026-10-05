class_name Deployable
extends StaticBody3D

var game: Node3D
var entity_id: int
var owner_id: int
var team: int
var kind: String
var hp: float
var max_hp: float
var lifetime: float
var age: float = 0
var last_damage: float = 0
var used: bool = false
var timer: float = 0
var display: Label3D
var mesh: MeshInstance3D

func configure(g: Node3D, data: Dictionary) -> void:
	game = g
	entity_id = data.id
	owner_id = data.owner
	team = data.team
	kind = data.kind
	max_hp = data.get("max_hp", data.hp)
	hp = data.hp
	lifetime = data.life
	name = "Entity_%d" % entity_id
	collision_layer = 8 if kind == "double" else (4 if kind in ["cover", "turret", "pad"] else 0)
	collision_mask = 0
	mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 1.7, 0.55) if kind == "double" else Vector3(0.8, 0.9, 0.8)
	if kind == "cover":
		box.size = Vector3(3.5, 1.8, 0.3)
	elif kind == "pad":
		box.size = Vector3(2.0, 0.15, 2.0)
	elif kind == "smoke":
		box.size = Vector3(3.0, 2.5, 3.0)
	mesh.mesh = box
	mesh.position.y = box.size.y / 2
	if kind == "double":
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.38
		capsule.height = 1.5
		mesh.mesh = capsule
		mesh.position.y = 0.85
		var head := MeshInstance3D.new()
		var head_mesh := BoxMesh.new()
		head_mesh.size = Vector3(0.5, 0.32, 0.5)
		head.mesh = head_mesh
		head.position.y = 1.7
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = Color("e7e9df")
		head.material_override = head_mat
		add_child(head)
		var gun := MeshInstance3D.new()
		var gun_mesh := BoxMesh.new()
		gun_mesh.size = Vector3(0.15, 0.18, 0.6)
		gun.mesh = gun_mesh
		gun.position = Vector3(0.36, 1.3, -0.3)
		var gun_mat := StandardMaterial3D.new()
		gun_mat.albedo_color = Color("28323f")
		gun.material_override = gun_mat
		add_child(gun)
		preload("res://scripts/class_identity.gd").build(self, 3, game.team_color(team))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = g.team_color(team)
	if kind == "smoke":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.65 if kind == "double" else 0.25
		mat.emission_enabled = true
		mat.emission = g.team_color(team) * 0.3
	mesh.material_override = mat
	add_child(mesh)
	if collision_layer != 0:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		shape.position = mesh.position
		add_child(shape)
	display = Label3D.new()
	display.position.y = box.size.y + 0.5
	display.font_size = 26
	display.pixel_size = 0.008
	display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	display.no_depth_test = false
	add_child(display)

func update_visual() -> void:
	display.visible = true
	display.modulate = game.team_color(team)
	display.text = kind.to_upper()
	if owner_id == game.local_id:
		display.text += " · %d/%d" % [int(hp), int(max_hp)]
		display.no_depth_test = kind in ["turret", "pad"]
	if kind == "double":
		display.text = "ALLY DOUBLE" if team == game.local_team() else "Mirage Agent"

func pack() -> Dictionary:
	return {"id": entity_id, "owner": owner_id, "team": team, "kind": kind, "hp": hp, "max_hp": max_hp, "life": lifetime, "pos": global_position, "yaw": rotation.y, "used": used}
