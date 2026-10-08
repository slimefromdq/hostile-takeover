class_name CharacterRig
extends RefCounted

# Procedural character rig: one shared operative body for every fighter, holding the loadout's primary and sidearm
# (only the gun in hand shows) and its melee weapon in the free hand. A Blender export at
# assets/models/characters/operative.glb replaces the procedural parts (see assets/README.md); animation then degrades
# gracefully because every part lookup tolerates a missing node.

const SLUG := "operative"
const DARK := Color("28323f")
const CREAM := Color("e7e9df")

const NAMEPLATE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float fill = 1.0;
uniform vec4 bar_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float edge = step(UV.x, 0.03) + step(0.97, UV.x) + step(UV.y, 0.14) + step(0.86, UV.y);
	vec3 col = UV.x < fill ? bar_color.rgb : vec3(0.08, 0.09, 0.11);
	ALBEDO = edge > 0.5 ? vec3(0.0) : col;
}
"""

static var _nameplate_shader: Shader

class Ctx:
	var root: Node3D
	var outlines: Array
	var materials: Array = []
	var ghost: bool
	var team_color: Color

	func lit(color: Color, outline_width: float = 0.0) -> StandardMaterial3D:
		var mat := Visuals.solid(color)
		materials.append(mat)
		if outline_width > 0.0 and not ghost:
			outlines.append(Visuals.add_outline(mat, Visuals.ENEMY_OUTLINE, outline_width))
		return mat

	func glow(color: Color, energy: float = 1.5) -> StandardMaterial3D:
		var mat := Visuals.glow(color, energy)
		materials.append(mat)
		return mat

static func mesh_part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation = rot
	parent.add_child(node)
	return node

static func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_part(parent, m, pos, mat, rot)

static func capsule(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 3
	return mesh_part(parent, m, pos, mat, rot)

static func sphere(parent: Node3D, pos: Vector3, radius: float, mat: Material, squash: float = 1.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = 14
	m.rings = 7
	return mesh_part(parent, m, pos, mat)

static func cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, height: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 12
	m.rings = 1
	return mesh_part(parent, m, pos, mat, rot)

static func pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node

# Builds the rig under `parent` and returns the "ClassEquipment" root.
static func build(parent: Node3D, team_color: Color, outlines: Array = [], ghost: bool = false, primary_id: int = 0, sidearm_id: int = 0, melee_id: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "ClassEquipment"
	parent.add_child(root)
	var ctx := Ctx.new()
	ctx.root = root
	ctx.outlines = outlines
	ctx.ghost = ghost
	ctx.team_color = team_color
	var authored := AssetLibrary.model("characters", SLUG)
	if authored != null:
		root.add_child(authored)
		_tint_team(authored, team_color)
		root.set_meta("authored", true)
		return root
	# Hips are the lean origin: Body holds everything above the legs.
	var legs := pivot(root, "Legs", Vector3(0, 0.9, 0))
	var body := pivot(root, "Body", Vector3(0, 0.9, 0))
	_operative(ctx, legs, body, primary_id, sidearm_id, melee_id)
	# Only the body capsules and spheres cast shadows; small details would just double draw calls.
	for part in root.find_children("*", "MeshInstance3D", true, false):
		if not (part.mesh is CapsuleMesh or part.mesh is SphereMesh):
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("materials", ctx.materials)
	if ghost:
		set_alpha(root, 0.55)
	return root

# Shows the gun in hand: slot 0 the primary, slot 1 the sidearm.
static func set_active_slot(root: Node3D, slot: int) -> void:
	if root == null or not is_instance_valid(root):
		return
	var weapon := root.get_node_or_null("Body/Weapon")
	if weapon == null:
		return
	var primary := weapon.get_node_or_null("Primary")
	var sidearm := weapon.get_node_or_null("Sidearm")
	if primary != null:
		primary.visible = slot == 0
	if sidearm != null:
		sidearm.visible = slot == 1

static func _primary_model(ctx: Ctx, weapon: Node3D, primary_id: int) -> void:
	var gun := pivot(weapon, "Primary", Vector3.ZERO)
	match primary_id:
		0:  # Shotgun: short, fat pump shotgun
			box(gun, Vector3(0, -0.03, -0.5), Vector3(0.1, 0.1, 0.56), ctx.lit(DARK))
			cylinder(gun, Vector3(0, -0.09, -0.52), 0.045, 0.045, 0.34, ctx.lit(Color("8a949c")), Vector3(PI / 2, 0, 0))
			box(gun, Vector3(0, 0.03, -0.78), Vector3(0.04, 0.04, 0.08), ctx.glow(Color("ff9a4a"), 2.0))
		1:  # Rifle: long barrel and scope
			box(gun, Vector3(0, -0.03, -0.62), Vector3(0.06, 0.09, 0.95), ctx.lit(DARK))
			box(gun, Vector3(0, 0.06, -0.55), Vector3(0.07, 0.07, 0.32), ctx.lit(Color("3a4552")))
			box(gun, Vector3(0, 0.06, -0.72), Vector3(0.05, 0.05, 0.03), ctx.glow(Color("7ee8ff"), 2.4))
		_:  # SMG: compact with a stick magazine
			box(gun, Vector3(0, -0.03, -0.42), Vector3(0.09, 0.13, 0.38), ctx.lit(DARK))
			box(gun, Vector3(0, -0.15, -0.38), Vector3(0.06, 0.18, 0.08), ctx.lit(Color("3a4552")))
			box(gun, Vector3(0, -0.02, -0.64), Vector3(0.03, 0.03, 0.08), ctx.glow(Color("ffe08a"), 2.0))

static func _sidearm_model(ctx: Ctx, weapon: Node3D, sidearm_id: int) -> void:
	var gun := pivot(weapon, "Sidearm", Vector3.ZERO)
	gun.visible = false
	match sidearm_id:
		0:  # Pistol: plain slide and grip
			box(gun, Vector3(0, -0.02, -0.38), Vector3(0.06, 0.08, 0.2), ctx.lit(DARK))
			box(gun, Vector3(0, -0.1, -0.32), Vector3(0.05, 0.12, 0.06), ctx.lit(Color("3a4552")))
		1:  # Burst Pistol: longer slide with a lit vent
			box(gun, Vector3(0, -0.02, -0.42), Vector3(0.07, 0.1, 0.3), ctx.lit(DARK))
			box(gun, Vector3(0, 0.04, -0.52), Vector3(0.03, 0.03, 0.1), ctx.glow(Color("7ee8ff"), 2.0))
		_:  # Revolver: cylinder and long barrel
			box(gun, Vector3(0, -0.02, -0.38), Vector3(0.06, 0.1, 0.22), ctx.lit(Color("8a949c")))
			cylinder(gun, Vector3(0, -0.01, -0.5), 0.03, 0.03, 0.14, ctx.lit(Color("8a949c")), Vector3(PI / 2, 0, 0))

static func _melee_model(ctx: Ctx, arm: Node3D, melee_id: int) -> void:
	var hand := pivot(arm, "Melee", Vector3(0, -0.56, -0.02))
	match melee_id:
		0:  # Knife
			box(hand, Vector3(0, 0, -0.12), Vector3(0.03, 0.03, 0.22), ctx.lit(Color("c8d0d4")))
		1:  # Sledgehammer: long haft and a heavy head
			cylinder(hand, Vector3(0, 0.1, 0), 0.025, 0.025, 0.7, ctx.lit(Color("6a4a32")))
			box(hand, Vector3(0, 0.45, 0), Vector3(0.14, 0.14, 0.3), ctx.lit(DARK))
		_:  # Sword
			box(hand, Vector3(0, 0.0, 0), Vector3(0.1, 0.06, 0.06), ctx.lit(DARK))
			box(hand, Vector3(0, 0.45, 0), Vector3(0.05, 0.8, 0.02), ctx.lit(Color("c8d0d4"), 0.01))

static func _tint_team(node: Node, color: Color) -> void:
	if node.name == "TeamTint":
		for child in node.find_children("*", "MeshInstance3D", true, false):
			child.material_override = Visuals.solid(color)
	for child in node.get_children():
		_tint_team(child, color)

static func _legs(ctx: Ctx, legs: Node3D, spread: float, radius: float, color: Color) -> void:
	for side in [-1, 1]:
		var leg := pivot(legs, "Leg%s" % ("L" if side < 0 else "R"), Vector3(side * spread, 0, 0))
		capsule(leg, Vector3(0, -0.42, 0), radius, 0.86, ctx.lit(color, 0.02))

static func _head(ctx: Ctx, body: Node3D, radius: float, y: float, visor: Color) -> Node3D:
	var head := pivot(body, "Head", Vector3(0, y, 0))
	sphere(head, Vector3.ZERO, radius, ctx.lit(CREAM, 0.025))
	box(head, Vector3(0, 0.02, -radius * 0.8), Vector3(radius * 1.3, radius * 0.4, radius * 0.5), ctx.glow(visor, 1.2))
	return head

static func _weapon_arm(ctx: Ctx, body: Node3D, shoulder: Vector3, arm_radius: float, color: Color) -> Node3D:
	var weapon := pivot(body, "Weapon", shoulder)
	capsule(weapon, Vector3(0, 0, -0.18), arm_radius, 0.42, ctx.lit(color, 0.02), Vector3(PI / 2, 0, 0))
	return weapon

static func _free_arm(ctx: Ctx, body: Node3D, shoulder: Vector3, radius: float, color: Color) -> void:
	var arm := pivot(body, "ArmL", shoulder)
	capsule(arm, Vector3(0, -0.28, 0), radius, 0.6, ctx.lit(color, 0.02))

static func _operative(ctx: Ctx, legs: Node3D, body: Node3D, primary_id: int, sidearm_id: int, melee_id: int) -> void:
	var suit := Color("34404f")
	_legs(ctx, legs, 0.14, 0.1, DARK)
	capsule(body, Vector3(0, 0.4, 0), 0.24, 0.72, ctx.lit(suit, 0.03))
	box(body, Vector3(0, 0.46, -0.22), Vector3(0.36, 0.34, 0.06), ctx.lit(DARK))
	box(body, Vector3(0, 0.5, -0.255), Vector3(0.22, 0.06, 0.02), ctx.glow(ctx.team_color, 1.2))
	box(body, Vector3(0, 0.48, 0.24), Vector3(0.34, 0.42, 0.14), ctx.lit(DARK))
	for side in [-1, 1]:
		sphere(body, Vector3(side * 0.3, 0.74, 0), 0.13, ctx.lit(ctx.team_color.darkened(0.35), 0.03), 0.8)
	_head(ctx, body, 0.16, 0.9, Color("7ee8ff"))
	_free_arm(ctx, body, Vector3(-0.3, 0.65, 0), 0.075, suit)
	_melee_model(ctx, body.get_node("ArmL"), melee_id)
	var weapon := _weapon_arm(ctx, body, Vector3(0.3, 0.65, 0), 0.075, suit)
	_primary_model(ctx, weapon, primary_id)
	_sidearm_model(ctx, weapon, sidearm_id)

# Per-frame procedural pose from synced state only (velocity, pitch, melee recovery).
static func animate(root: Node3D, dt: float, planar_speed: float, grounded: bool, pitch: float, sliding: bool, melee_time: float = 0.0) -> void:
	if root == null or not is_instance_valid(root) or root.has_meta("authored"):
		return
	var phase: float = root.get_meta("phase", 0.0)
	phase += dt * (planar_speed * 1.6 + 1.0)
	root.set_meta("phase", phase)
	var run := clampf(planar_speed / 8.0, 0.0, 1.0) if grounded else 0.0
	var swing := sin(phase) * 0.9 * run
	var legs: Node3D = root.get_node_or_null("Legs")
	var body: Node3D = root.get_node_or_null("Body")
	if legs == null or body == null:
		return
	var left: Node3D = legs.get_node_or_null("LegL")
	var right: Node3D = legs.get_node_or_null("LegR")
	var air_tuck := 0.0 if grounded else 0.5
	var blend := minf(1.0, dt * 10.0)
	var left_x := swing - air_tuck
	var right_x := -swing + air_tuck * 0.4
	var arm_x := -swing * 0.8
	var lean := -0.06 - 0.22 * run
	var hip_y := 0.9
	if sliding:
		# Seated slide: hips drop, front leg extends, rear leg tucks, torso leans back, free arm braces.
		# Positive x rotation swings limbs toward the front (-Z) and tips the torso backward.
		left_x = 1.3
		right_x = -0.6
		arm_x = 0.9
		lean = 1.1
		hip_y = 0.5
	# Legs ease in and out of the slide pose; otherwise they follow the run cycle directly.
	var easing: bool = sliding or absf(legs.position.y - 0.9) > 0.02
	if left != null:
		left.rotation.x = lerpf(left.rotation.x, left_x, blend) if easing else left_x
	if right != null:
		right.rotation.x = lerpf(right.rotation.x, right_x, blend) if easing else right_x
	legs.position.y = lerpf(legs.position.y, hip_y, blend)
	body.position.y = lerpf(body.position.y, hip_y, blend)
	body.rotation.x = lerpf(body.rotation.x, lean, blend)
	var arm: Node3D = body.get_node_or_null("ArmL")
	if arm != null:
		# A melee swing throws the free arm up and across while recovery runs.
		arm.rotation.x = 2.2 if melee_time > 0.0 else arm_x
	var weapon: Node3D = body.get_node_or_null("Weapon")
	if weapon != null:
		# Counter the body lean so the weapon follows the aim exactly.
		weapon.rotation.x = pitch - body.rotation.x
	var head: Node3D = body.get_node_or_null("Head")
	if head != null:
		head.rotation.x = (pitch - body.rotation.x) * 0.4

# Fades the whole rig (concealment shimmer, hologram doubles).
static func set_alpha(root: Node3D, alpha: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root.has_meta("authored"):
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			mesh.transparency = 1.0 - alpha
		return
	if is_equal_approx(root.get_meta("alpha", 1.0), alpha):
		return
	root.set_meta("alpha", alpha)
	for mat in root.get_meta("materials", []):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = alpha

# Billboard health bar (single quad, fill driven by a shader parameter).
static func make_nameplate() -> MeshInstance3D:
	if _nameplate_shader == null:
		_nameplate_shader = Shader.new()
		_nameplate_shader.code = NAMEPLATE_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.11)
	var node := MeshInstance3D.new()
	node.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _nameplate_shader
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func update_nameplate(node: MeshInstance3D, fraction: float, color: Color) -> void:
	var mat: ShaderMaterial = node.material_override
	mat.set_shader_parameter("fill", clampf(fraction, 0.0, 1.0))
	mat.set_shader_parameter("bar_color", color)
