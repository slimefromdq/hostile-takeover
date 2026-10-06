class_name CharacterRig
extends RefCounted

# Procedural per-class character rig. A Blender export at assets/models/characters/<slug>.glb
# replaces the procedural parts (see assets/README.md); animation then degrades gracefully
# because every part lookup tolerates a missing node.

const SLUGS := ["skyrunner", "field_engineer", "enforcer", "mirage_agent"]
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

static func slug(class_id: int) -> String:
	return SLUGS[clampi(class_id, 0, SLUGS.size() - 1)]

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
static func build(parent: Node3D, class_id: int, team_color: Color, outlines: Array = [], ghost: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "ClassEquipment"
	parent.add_child(root)
	var ctx := Ctx.new()
	ctx.root = root
	ctx.outlines = outlines
	ctx.ghost = ghost
	ctx.team_color = team_color
	var authored := AssetLibrary.model("characters", slug(class_id))
	if authored != null:
		root.add_child(authored)
		_tint_team(authored, team_color)
		root.set_meta("authored", true)
		return root
	# Hips are the lean origin: Body holds everything above the legs.
	var legs := pivot(root, "Legs", Vector3(0, 0.9, 0))
	var body := pivot(root, "Body", Vector3(0, 0.9, 0))
	match class_id:
		0: _skyrunner(ctx, legs, body)
		1: _engineer(ctx, legs, body)
		2: _enforcer(ctx, legs, body)
		_: _mirage(ctx, legs, body)
	# Only the body capsules and spheres cast shadows; small details would just double draw calls.
	for part in root.find_children("*", "MeshInstance3D", true, false):
		if not (part.mesh is CapsuleMesh or part.mesh is SphereMesh):
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("materials", ctx.materials)
	if ghost:
		set_alpha(root, 0.55)
	return root

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

static func _skyrunner(ctx: Ctx, legs: Node3D, body: Node3D) -> void:
	var suit := Color("2f4f7a")
	_legs(ctx, legs, 0.12, 0.085, DARK)
	capsule(body, Vector3(0, 0.38, 0), 0.19, 0.66, ctx.lit(suit, 0.03))
	_head(ctx, body, 0.16, 0.86, Color("7ee8ff"))
	box(body, Vector3(0, 0.45, -0.19), Vector3(0.24, 0.16, 0.03), ctx.glow(ctx.team_color, 1.0))
	box(body, Vector3(0, 0.45, 0.19), Vector3(0.1, 0.4, 0.03), ctx.glow(ctx.team_color, 1.0))
	# Boost vanes read as the class's winged silhouette from behind and the side.
	var vanes := pivot(body, "Vanes", Vector3(0, 0.55, 0.2))
	for side in [-1, 1]:
		box(vanes, Vector3(side * 0.2, 0, 0.1), Vector3(0.05, 0.5, 0.26), ctx.glow(Color("ffe2a3"), 1.6), Vector3(0.35, 0, side * 0.4))
	_free_arm(ctx, body, Vector3(-0.27, 0.62, 0), 0.065, suit)
	var launcher := pivot(body.get_node("ArmL"), "Launcher", Vector3(0, -0.45, -0.04))
	cylinder(launcher, Vector3.ZERO, 0.05, 0.05, 0.2, ctx.lit(DARK), Vector3(PI / 2, 0, 0))
	var weapon := _weapon_arm(ctx, body, Vector3(0.27, 0.62, 0), 0.065, suit)
	box(weapon, Vector3(0, -0.03, -0.42), Vector3(0.07, 0.12, 0.34), ctx.lit(DARK))
	box(weapon, Vector3(0, 0.04, -0.58), Vector3(0.03, 0.03, 0.1), ctx.glow(Color("7ee8ff"), 2.0))

static func _engineer(ctx: Ctx, legs: Node3D, body: Node3D) -> void:
	var overalls := Color("5a6b4a")
	var vest := Color("d9b95b")
	_legs(ctx, legs, 0.15, 0.11, DARK)
	capsule(body, Vector3(0, 0.4, 0), 0.26, 0.74, ctx.lit(overalls, 0.03))
	box(body, Vector3(0, 0.45, -0.22), Vector3(0.44, 0.38, 0.06), ctx.lit(vest))
	box(body, Vector3(0, 0.45, -0.255), Vector3(0.12, 0.12, 0.02), ctx.glow(ctx.team_color, 1.0))
	var head := _head(ctx, body, 0.17, 0.9, Color("ffe9a0"))
	sphere(head, Vector3(0, 0.1, 0), 0.2, ctx.lit(Color("ffd23f"), 0.02), 0.7)
	# Tool-rig backpack with fuel tanks and a hose coil.
	box(body, Vector3(0, 0.5, 0.3), Vector3(0.5, 0.55, 0.26), ctx.lit(vest, 0.02))
	for side in [-1, 1]:
		cylinder(body, Vector3(side * 0.14, 0.82, 0.3), 0.07, 0.07, 0.3, ctx.lit(Color("c8d0d4")))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.07
	coil.outer_radius = 0.2
	coil.rings = 14
	coil.ring_segments = 6
	mesh_part(body, coil, Vector3(-0.3, 0.2, 0.0), ctx.lit(DARK), Vector3(0, 0, PI / 2))
	_free_arm(ctx, body, Vector3(-0.34, 0.65, 0), 0.09, overalls)
	var weapon := _weapon_arm(ctx, body, Vector3(0.34, 0.65, 0), 0.09, overalls)
	box(weapon, Vector3(0, -0.03, -0.4), Vector3(0.14, 0.16, 0.36), ctx.lit(DARK))
	cylinder(weapon, Vector3(0, -0.03, -0.62), 0.05, 0.08, 0.12, ctx.glow(Color("7ef7ff"), 1.8), Vector3(PI / 2, 0, 0))

static func _enforcer(ctx: Ctx, legs: Node3D, body: Node3D) -> void:
	var armor := Color("3c4756")
	_legs(ctx, legs, 0.22, 0.14, DARK)
	capsule(body, Vector3(0, 0.45, 0), 0.38, 0.95, ctx.lit(armor, 0.035))
	box(body, Vector3(0, 0.5, -0.36), Vector3(0.5, 0.45, 0.08), ctx.lit(CREAM))
	box(body, Vector3(0, 0.5, -0.41), Vector3(0.3, 0.1, 0.02), ctx.glow(ctx.team_color, 1.0))
	_head(ctx, body, 0.17, 1.0, Color("ff6a4a"))
	for side in [-1, 1]:
		sphere(body, Vector3(side * 0.5, 0.8, 0), 0.24, ctx.lit(ctx.team_color.darkened(0.35), 0.03), 0.8)
	box(body, Vector3(0, 0.5, 0.36), Vector3(0.5, 0.6, 0.12), ctx.lit(DARK))
	_free_arm(ctx, body, Vector3(-0.52, 0.72, 0), 0.12, armor)
	var weapon := _weapon_arm(ctx, body, Vector3(0.5, 0.72, 0), 0.12, armor)
	box(weapon, Vector3(0, -0.05, -0.35), Vector3(0.24, 0.24, 0.4), ctx.lit(DARK))
	var spinner := pivot(weapon, "Spinner", Vector3(0, -0.05, -0.7))
	var heat_mat := ctx.glow(Color("ff5a2a"), 0.0)
	for i in range(6):
		var a := TAU * i / 6.0
		cylinder(spinner, Vector3(cos(a) * 0.08, sin(a) * 0.08, 0), 0.025, 0.025, 0.5, ctx.lit(Color("8a949c")), Vector3(PI / 2, 0, 0))
		sphere(spinner, Vector3(cos(a) * 0.08, sin(a) * 0.08, -0.26), 0.03, heat_mat)
	spinner.set_meta("heat", heat_mat)

static func _mirage(ctx: Ctx, legs: Node3D, body: Node3D) -> void:
	var suit := Color("30283f")
	_legs(ctx, legs, 0.12, 0.09, DARK)
	capsule(body, Vector3(0, 0.38, 0), 0.2, 0.68, ctx.lit(suit, 0.03))
	# Long coat skirt plus a cloak that trails when moving.
	cylinder(body, Vector3(0, -0.05, 0), 0.22, 0.34, 0.75, ctx.lit(DARK, 0.02))
	box(body, Vector3(0, 0.45, -0.2), Vector3(0.1, 0.4, 0.03), ctx.glow(Color("c7a8f1"), 1.2))
	var head := _head(ctx, body, 0.15, 0.86, Color("c7a8f1"))
	cylinder(head, Vector3(0, 0.13, 0), 0.31, 0.31, 0.025, ctx.lit(DARK, 0.015))
	cylinder(head, Vector3(0, 0.2, 0), 0.15, 0.17, 0.16, ctx.lit(DARK, 0.015))
	var cloak := pivot(body, "Cloak", Vector3(0, 0.72, 0.18))
	box(cloak, Vector3(0, -0.4, 0.03), Vector3(0.42, 0.95, 0.03), ctx.lit(suit.lightened(0.1), 0.0))
	_free_arm(ctx, body, Vector3(-0.27, 0.62, 0), 0.065, suit)
	var weapon := _weapon_arm(ctx, body, Vector3(0.27, 0.62, 0), 0.065, suit)
	box(weapon, Vector3(0, -0.02, -0.38), Vector3(0.06, 0.1, 0.22), ctx.lit(Color("8a949c")))
	cylinder(weapon, Vector3(0, -0.01, -0.5), 0.03, 0.03, 0.14, ctx.lit(Color("8a949c")), Vector3(PI / 2, 0, 0))

# Per-frame procedural pose from synced state only (velocity, pitch, spin).
static func animate(root: Node3D, dt: float, class_id: int, planar_speed: float, grounded: bool, pitch: float, spin: float, sliding: bool) -> void:
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
	var base_lean := -0.12 if class_id == 0 else (-0.06 if class_id == 3 else 0.0)
	var lean := base_lean - 0.22 * run
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
		arm.rotation.x = arm_x
	var weapon: Node3D = body.get_node_or_null("Weapon")
	if weapon != null:
		# Counter the body lean so the weapon follows the aim exactly.
		weapon.rotation.x = pitch - body.rotation.x
	var head: Node3D = body.get_node_or_null("Head")
	if head != null:
		head.rotation.x = (pitch - body.rotation.x) * 0.4
	var cloak: Node3D = body.get_node_or_null("Cloak")
	if cloak != null:
		cloak.rotation.x = 0.15 + run * 0.7 + (0.0 if grounded else 0.4)
	var vanes: Node3D = body.get_node_or_null("Vanes")
	if vanes != null:
		vanes.rotation.x = 0.1 + run * 0.35 + (0.0 if grounded else 0.3)
	if weapon != null:
		var spinner: Node3D = weapon.get_node_or_null("Spinner")
		if spinner != null:
			var turn: float = spinner.get_meta("turn", 0.0) + dt * spin * 30.0
			spinner.set_meta("turn", turn)
			spinner.rotation.z = turn
			var heat: StandardMaterial3D = spinner.get_meta("heat")
			heat.emission_energy_multiplier = spin * 3.0

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
