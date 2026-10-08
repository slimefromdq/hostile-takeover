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
	elif kind == "healpack":
		box.size = Vector3(0.7, 0.4, 0.7)
	elif kind == "armor":
		box.size = Vector3(0.5, 0.2, 0.5)
	elif kind == "bubble":
		box.size = Vector3(0.4, 0.4, 0.4)
	elif kind == "armor1":
		box.size = Vector3(0.7, 0.2, 0.7)
	elif kind == "armor2":
		box.size = Vector3(0.9, 0.3, 0.9)
	elif kind == "power":
		box.size = Vector3(0.9, 0.9, 0.9)
	mesh.mesh = box
	mesh.position.y = box.size.y / 2
	if kind == "double":
		# The double is a ghosted Mirage Agent rig; the box mesh only sizes the collider.
		mesh.visible = false
		preload("res://scripts/class_identity.gd").build(self, 3, game.team_color(team), true)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = g.team_color(team)
	if kind == "smoke":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.65 if kind == "double" else 0.25
		mat.emission_enabled = true
		mat.emission = g.team_color(team) * 0.3
	if kind != "smoke":
		Visuals.add_outline(mat, Visuals.team_color(team).lightened(0.4), 0.03)
	mesh.material_override = mat
	add_child(mesh)
	build_model()
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

var chevrons: Array[StandardMaterial3D] = []

func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(chevrons.size()):
		chevrons[i].emission_energy_multiplier = 0.6 + 2.4 * maxf(0.0, sin(t * 6.0 - i * 1.2))

# Compound stand-ins for the old single boxes. The box mesh stays only to size the collider.
# An authored model at assets/models/deployables/<kind>.glb replaces these.
func build_model() -> void:
	if kind == "double":
		return
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	mesh.visible = false
	var authored := AssetLibrary.model("deployables", kind)
	if authored != null:
		model.add_child(authored)
		return
	var team_col: Color = game.team_color(team)
	var dark := Color("28323f")
	match kind:
		"turret":
			var base := CharacterRig.cylinder(model, Vector3(0, 0.12, 0), 0.4, 0.46, 0.24, Visuals.solid(dark))
			Visuals.add_outline(base.material_override, team_col.lightened(0.4), 0.025)
			var head := CharacterRig.pivot(model, "Head", Vector3(0, 0.6, 0))
			var shell := CharacterRig.box(head, Vector3.ZERO, Vector3(0.5, 0.36, 0.5), Visuals.solid(team_col.darkened(0.3)))
			Visuals.add_outline(shell.material_override, team_col.lightened(0.4), 0.025)
			CharacterRig.cylinder(head, Vector3(0, 0, -0.45), 0.06, 0.06, 0.55, Visuals.solid(Color("8a949c")), Vector3(PI / 2, 0, 0))
			CharacterRig.sphere(head, Vector3(0, 0.05, -0.74), 0.06, Visuals.glow(team_col, 2.5))
		"pad":
			var plate := CharacterRig.box(model, Vector3(0, 0.07, 0), Vector3(2.0, 0.14, 2.0), Visuals.solid(dark))
			Visuals.add_outline(plate.material_override, team_col.lightened(0.4), 0.02)
			for i in range(3):
				var mat := Visuals.glow(team_col.lightened(0.2), 1.0)
				chevrons.append(mat)
				var arrow := CharacterRig.box(model, Vector3(0, 0.15, 0.55 - i * 0.55), Vector3(0.9, 0.03, 0.14), mat)
				arrow.rotation.y = 0.0
				CharacterRig.box(arrow, Vector3(-0.3, 0, 0.1), Vector3(0.4, 0.03, 0.12), mat, Vector3(0, 0.6, 0))
				CharacterRig.box(arrow, Vector3(0.3, 0, 0.1), Vector3(0.4, 0.03, 0.12), mat, Vector3(0, -0.6, 0))
		"healpack":
			var green := Color("3dff7a")
			var case := CharacterRig.box(model, Vector3(0, 0.25, 0), Vector3(0.7, 0.4, 0.7), Visuals.solid(Color("e8eef0")))
			Visuals.add_outline(case.material_override, green, 0.025)
			CharacterRig.box(model, Vector3(0, 0.46, 0), Vector3(0.44, 0.06, 0.14), Visuals.glow(green, 2.0))
			CharacterRig.box(model, Vector3(0, 0.46, 0), Vector3(0.14, 0.06, 0.44), Visuals.glow(green, 2.0))
		"armor":
			var blue := Color("5ab8ff")
			var plate := CharacterRig.box(model, Vector3(0, 0.3, 0), Vector3(0.5, 0.2, 0.5), Visuals.solid(Color("e8eef0")))
			Visuals.add_outline(plate.material_override, blue, 0.025)
			CharacterRig.box(model, Vector3(0, 0.42, 0), Vector3(0.3, 0.05, 0.3), Visuals.glow(blue, 2.0))
		"bubble", "armor1", "armor2":
			var tint: Color = Items.KINDS[kind].color
			if kind == "bubble":
				var orb := CharacterRig.sphere(model, Vector3(0, 0.45, 0), 0.2, Visuals.glow(tint, 2.0))
				Visuals.add_outline(orb.material_override, tint.lightened(0.4), 0.02)
			else:
				var wide := 0.7 if kind == "armor1" else 0.9
				var base := CharacterRig.box(model, Vector3(0, 0.12, 0), Vector3(wide, 0.16, wide), Visuals.solid(Color("2b3440")))
				Visuals.add_outline(base.material_override, tint, 0.025)
				CharacterRig.box(model, Vector3(0, 0.26, 0), Vector3(wide * 0.6, 0.1, wide * 0.6), Visuals.glow(tint, 2.2))
				if kind == "armor2":
					CharacterRig.box(model, Vector3(0, 0.4, 0), Vector3(wide * 0.3, 0.14, wide * 0.3), Visuals.glow(tint.lightened(0.3), 3.0))
		"power":
			# Both orbs exist; update_visual shows the one that is up (hp 1 = invincibility, 2 = triple damage).
			for which in [Items.POWER_INVULNERABLE, Items.POWER_QUAD]:
				var tint: Color = Items.POWER_COLORS[which]
				var holder := CharacterRig.pivot(model, "Power%d" % which, Vector3.ZERO)
				CharacterRig.box(holder, Vector3(0, 0.1, 0), Vector3(0.7, 0.14, 0.7), Visuals.solid(Color("2b3440")))
				var orb := CharacterRig.sphere(holder, Vector3(0, 0.65, 0), 0.32, Visuals.glow(tint, 3.0))
				Visuals.add_outline(orb.material_override, tint.lightened(0.4), 0.03)
		"cover":
			var slab := CharacterRig.box(model, Vector3(0, 0.9, 0), Vector3(3.5, 1.8, 0.3), Visuals.solid(dark.lightened(0.15)))
			Visuals.add_outline(slab.material_override, team_col.lightened(0.4), 0.02)
			CharacterRig.box(model, Vector3(0, 1.75, 0), Vector3(3.5, 0.1, 0.34), Visuals.glow(team_col, 1.6))
			CharacterRig.box(model, Vector3(0, 0.06, 0), Vector3(3.5, 0.1, 0.34), Visuals.glow(team_col, 1.2))
			for side in [-1, 1]:
				CharacterRig.box(model, Vector3(side * 1.6, 0.9, 0), Vector3(0.2, 1.8, 0.4), Visuals.solid(dark))
		"smoke":
			var puffs := CPUParticles3D.new()
			puffs.local_coords = true
			puffs.amount = 14
			puffs.lifetime = 2.2
			puffs.preprocess = 1.0
			puffs.direction = Vector3.UP
			puffs.spread = 70.0
			puffs.initial_velocity_min = 0.05
			puffs.initial_velocity_max = 0.3
			puffs.gravity = Vector3.ZERO
			puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			puffs.emission_sphere_radius = 0.9
			var ball := SphereMesh.new()
			ball.radius = 0.7
			ball.height = 1.4
			ball.radial_segments = 8
			ball.rings = 4
			puffs.mesh = ball
			var smoke := StandardMaterial3D.new()
			smoke.albedo_color = Color(0.78, 0.7, 0.9, 0.3)
			smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			puffs.material_override = smoke
			puffs.position.y = 1.2
			model.add_child(puffs)

func update_visual() -> void:
	if kind == "armor":
		display.visible = false
		return
	if kind == "healpack" or Items.KINDS.has(kind):
		# A taken pack hides until it respawns.
		var model := get_node_or_null("Model")
		if model != null:
			model.visible = not used
			if kind == "power":
				for which in [Items.POWER_INVULNERABLE, Items.POWER_QUAD]:
					var holder := model.get_node_or_null("Power%d" % which)
					if holder != null:
						holder.visible = int(hp) == which
		display.visible = false
		return
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
