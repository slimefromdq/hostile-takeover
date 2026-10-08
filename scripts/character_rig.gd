class_name CharacterRig
extends RefCounted

# Procedural character rig: a cute low-poly person (sculpted face, pointed hair locks, tapered limbs and chunky shoes)
# dressed from an Appearance code (scripts/appearance.gd), holding the loadout's primary and sidearm (only the gun in
# hand shows) and its melee weapon in the free hand. Team identity is trim in the team colour: the top's collar or
# stripe, a band on each upper arm and a stripe on each shoe.
#
# Parts are authored as faceted profiles, boxes and prisms, then baked into one vertex-coloured mesh per bone (two surfaces:
# outlined body parts and un-outlined face/trim details), so a fighter costs about a dozen draw calls. Bones and the
# node names animate() and the tests rely on: ClassEquipment/Legs/{LegL,LegR}, Body/{Head, ArmL/Melee,
# Weapon/{Primary,Sidearm}}.
#
# A Blender export at assets/models/characters/operative.glb replaces the procedural parts (see assets/README.md);
# animation then degrades gracefully because every part lookup tolerates a missing node.

const SLUG := "operative"
const DARK := Color("28323f")
const CREAM := Color("e7e9df")
const HIP_Y := 0.88  # longer legs, with the same overall height and gameplay capsule
const OUTLINE_WIDTH := 0.012

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

# Inverted hull pushed along each corner's averaged direction (CUSTOM0), so box edges stay closed with no cracks.
# The hull is also pushed back along the view ray (same screen position, farther depth): it shows around the
# silhouette but hides behind parts it merely touches, so hair, sleeves and shirt don't get lines between them.
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 outline_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float width = 0.022;
uniform float depth_push = 0.14;
void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX + CUSTOM0.xyz * width, 1.0);
	view.xyz += normalize(view.xyz) * depth_push;
	POSITION = PROJECTION_MATRIX * view;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

const LIT := 0     # body parts: outlined, cast the bone's shadow
const DETAIL := 1  # face features and trim: never outlined
const BOX := 0
const PRISM := 1
const FACET := 2
const PATCH := 3
const OVAL := [Vector2(-0.35, -0.5), Vector2(0.35, -0.5), Vector2(0.5, -0.28), Vector2(0.5, 0.28), Vector2(0.35, 0.5), Vector2(-0.35, 0.5), Vector2(-0.5, 0.28), Vector2(-0.5, -0.28)]
const EYE_SHAPE := [Vector2(-0.5, -0.22), Vector2(-0.28, -0.47), Vector2(0.25, -0.5), Vector2(0.48, -0.23), Vector2(0.5, 0.22), Vector2(0.25, 0.5), Vector2(-0.25, 0.5), Vector2(-0.5, 0.24)]
# Each ring is (height fraction, width fraction, depth fraction); corners are chamfered in XZ.
const SOFT_PROFILE := [Vector3(-0.5, 0.82, 0.82), Vector3(-0.35, 1, 1), Vector3(0.35, 1, 1), Vector3(0.5, 0.82, 0.82)]
const TAPER_PROFILE := [Vector3(-0.5, 0.72, 0.8), Vector3(-0.35, 0.85, 0.9), Vector3(0.35, 1, 1), Vector3(0.5, 0.85, 0.85)]
const LOCK_PROFILE := [Vector3(-0.5, 0.08, 0.18), Vector3(-0.12, 0.8, 0.85), Vector3(0.32, 1, 1), Vector3(0.5, 0.72, 0.72)]
const FACE_PROFILE := [Vector3(-0.5, 0.48, 0.65), Vector3(-0.3, 0.84, 0.92), Vector3(0.08, 1, 1), Vector3(0.34, 0.96, 0.98), Vector3(0.5, 0.72, 0.8)]

static var _nameplate_shader: Shader
static var _outline_shader: Shader

class Ctx:
	var root: Node3D
	var outlines: Array
	var materials: Array = []
	var ghost: bool
	var team_color: Color
	var look: Dictionary
	var parts := {}  # bone Node3D -> Array of part dictionaries, baked in bake()
	var lit_mat: StandardMaterial3D
	var detail_mat: StandardMaterial3D

	func add(bone: Node3D, pos: Vector3, size: Vector3, color: Color, layer: int = LIT, rot: Vector3 = Vector3.ZERO, shape: int = FACET) -> void:
		if not parts.has(bone):
			parts[bone] = []
		parts[bone].append({"xf": Transform3D(Basis.from_euler(rot), pos), "size": size, "color": color, "layer": layer, "shape": shape})

	func detail(bone: Node3D, pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
		add(bone, pos, size, color, DETAIL, rot, BOX)

	func form(bone: Node3D, pos: Vector3, size: Vector3, color: Color, profile: Array, rot: Vector3 = Vector3.ZERO, layer: int = LIT) -> void:
		add(bone, pos, size, color, layer, rot, FACET)
		parts[bone][-1]["profile"] = profile

	func patch(bone: Node3D, pos: Vector3, size: Vector2, color: Color, polygon: Array = OVAL) -> void:
		add(bone, pos, Vector3(size.x, size.y, 0), color, DETAIL, Vector3.ZERO, PATCH)
		parts[bone][-1]["polygon"] = polygon

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

# Builds the rig under `parent` and returns the "ClassEquipment" root. `look_code` is an Appearance code (-1: default).
static func build(parent: Node3D, team_color: Color, outlines: Array = [], ghost: bool = false, primary_id: int = 0, sidearm_id: int = 0, melee_id: int = 0, look_code: int = -1) -> Node3D:
	var root := Node3D.new()
	root.name = "ClassEquipment"
	parent.add_child(root)
	var ctx := Ctx.new()
	ctx.root = root
	ctx.outlines = outlines
	ctx.ghost = ghost
	ctx.team_color = team_color
	ctx.look = Appearance.decode(Appearance.default_code() if look_code < 0 else look_code)
	var authored := AssetLibrary.model("characters", SLUG)
	if authored != null:
		root.add_child(authored)
		_tint_team(authored, team_color)
		root.set_meta("authored", true)
		return root
	# Hips are the lean origin: Body holds everything above the legs.
	var legs := pivot(root, "Legs", Vector3(0, HIP_Y, 0))
	var body := pivot(root, "Body", Vector3(0, HIP_Y, 0))
	_person(ctx, legs, body, primary_id, sidearm_id, melee_id)
	_bake(ctx)
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

static func _tint_team(node: Node, color: Color) -> void:
	if node.name == "TeamTint":
		for child in node.find_children("*", "MeshInstance3D", true, false):
			child.material_override = Visuals.solid(color)
	for child in node.get_children():
		_tint_team(child, color)

# ---- the person ---------------------------------------------------------------------------------------------

static func _person(ctx: Ctx, legs: Node3D, body: Node3D, primary_id: int, sidearm_id: int, melee_id: int) -> void:
	var look := ctx.look
	var build: Dictionary = Appearance.BODIES[look.body]
	var w: float = build.width
	var t: float = build.limb
	var skin: Color = Appearance.SKIN_TONES[look.skin]
	var top_color: Color = Appearance.CLOTH_COLORS[look.top_color]
	var bottom_color: Color = Appearance.CLOTH_COLORS[look.bottom_color]
	var shoe_color: Color = Appearance.CLOTH_COLORS[look.shoe_color]
	for side in [-1, 1]:
		var leg := pivot(legs, "Leg%s" % ("L" if side < 0 else "R"), Vector3(side * 0.115 * w, 0, 0))
		_leg(ctx, leg, side, t, skin, bottom_color, look.bottom)
		_shoe(ctx, leg, side, shoe_color, look.shoes)
	_bottoms_body(ctx, body, w, bottom_color, look.bottom)
	var sleeve := _top(ctx, body, w, skin, top_color, look.top)
	# Neck, then the head on a neck pivot so a nod tips the whole head.
	ctx.add(body, Vector3(0, 0.56, 0.01), Vector3(0.13, 0.1, 0.13), skin)
	var head := pivot(body, "Head", Vector3(0, 0.56, 0))
	_head(ctx, head, skin)
	var covered: bool = look.headgear in [1, 2, 4]  # cap, goggle helmet, beanie sit over the crown
	_hair(ctx, head, look.hair, Appearance.HAIR_COLORS[look.hair_color], covered)
	_headgear(ctx, head, look.headgear, top_color)
	# Arms: the free left arm hangs from its shoulder; the right arm holds the gun forward along -Z.
	var shoulder_x := 0.195 * w + 0.06 * t
	var arm := pivot(body, "ArmL", Vector3(-shoulder_x, 0.45, 0))
	_free_arm(ctx, arm, t, skin, sleeve)
	_melee_model(ctx, arm, melee_id)
	var weapon := pivot(body, "Weapon", Vector3(shoulder_x, 0.45, 0))
	_gun_arm(ctx, weapon, t, skin, sleeve)
	_primary_model(ctx, weapon, primary_id)
	_sidearm_model(ctx, weapon, sidearm_id)

static func _head(ctx: Ctx, head: Node3D, skin: Color) -> void:
	var eye_color: Color = Appearance.EYE_COLORS[ctx.look.eyes]
	# A single watertight face: full cheeks taper to a small chin under a rounded crown.
	ctx.form(head, Vector3(0, 0.265, 0), Vector3(0.51, 0.49, 0.45), skin, FACE_PROFILE)
	for side in [-1, 1]:
		ctx.add(head, Vector3(side * 0.255, 0.25, 0.015), Vector3(0.06, 0.1, 0.085), skin)
		ctx.detail(head, Vector3(side * 0.277, 0.25, -0.027), Vector3(0.022, 0.05, 0.014), skin.darkened(0.12))
	# Thin polygon layers keep the eyes crisp without a texture or extra draw calls.
	var z := -0.226
	var white := Color("fbfbf6")
	var lash := Color("332637")
	for side in [-1, 1]:
		var x: float = side * 0.103
		ctx.patch(head, Vector3(x, 0.26, z - 0.003), Vector2(0.137, 0.147), lash, EYE_SHAPE)
		ctx.patch(head, Vector3(x, 0.254, z - 0.005), Vector2(0.125, 0.13), white, EYE_SHAPE)
		ctx.patch(head, Vector3(x - side * 0.009, 0.253, z - 0.007), Vector2(0.075, 0.119), eye_color.darkened(0.28))
		ctx.patch(head, Vector3(x - side * 0.009, 0.235, z - 0.009), Vector2(0.065, 0.077), eye_color)
		ctx.patch(head, Vector3(x - side * 0.009, 0.217, z - 0.011), Vector2(0.046, 0.034), eye_color.lightened(0.30))
		ctx.patch(head, Vector3(x - side * 0.009, 0.26, z - 0.013), Vector2(0.029, 0.078), lash)
		ctx.patch(head, Vector3(x - 0.015, 0.286, z - 0.015), Vector2(0.027, 0.03), white)
		ctx.patch(head, Vector3(x + 0.018, 0.222, z - 0.015), Vector2(0.013, 0.013), white)
		ctx.detail(head, Vector3(x + side * 0.06, 0.328, z - 0.011), Vector3(0.035, 0.012, 0.008), lash, Vector3(0, 0, side * 0.35))
		ctx.detail(head, Vector3(x, 0.368, z + 0.008), Vector3(0.084, 0.013, 0.01), Appearance.HAIR_COLORS[ctx.look.hair_color].darkened(0.25), Vector3(0, 0, -side * 0.08))
		ctx.patch(head, Vector3(side * 0.155, 0.16, -0.217), Vector2(0.053, 0.022), skin.lerp(Color("ed849a"), 0.22))
	ctx.form(head, Vector3(0, 0.177, -0.222), Vector3(0.022, 0.029, 0.018), skin, TAPER_PROFILE, Vector3.ZERO, DETAIL)
	# Two upturned strokes and a soft lower lip read as a small smile.
	for side in [-1, 1]:
		ctx.detail(head, Vector3(side * 0.018, 0.113, -0.207), Vector3(0.038, 0.009, 0.008), skin.lerp(Color("693346"), 0.7), Vector3(0, 0, side * 0.18))
	ctx.detail(head, Vector3(0, 0.103, -0.209), Vector3(0.032, 0.008, 0.008), skin.lerp(Color("dc8290"), 0.45))

# Crown, back and pointed locks form a faceted silhouette; hats suppress the crown volume.
static func _hair(ctx: Ctx, head: Node3D, style: int, color: Color, covered: bool) -> void:
	var dark := color.darkened(0.12)
	if style == 3:  # Buzz: a thin cap and a hairline
		if not covered:
			ctx.form(head, Vector3(0, 0.465, 0.01), Vector3(0.52, 0.13, 0.46), color, [Vector3(-0.5, 1, 1), Vector3(0.1, 0.92, 0.95), Vector3(0.5, 0.65, 0.72)])
		ctx.add(head, Vector3(0, 0.36, 0.216), Vector3(0.47, 0.25, 0.055), color)
		for side in [-1, 1]:
			ctx.add(head, Vector3(side * 0.242, 0.397, 0.015), Vector3(0.04, 0.13, 0.33), color)
		return
	if not covered:
		ctx.form(head, Vector3(0, 0.485, 0.01), Vector3(0.59, 0.22, 0.53), color, [Vector3(-0.5, 0.96, 0.95), Vector3(-0.05, 1, 1), Vector3(0.28, 0.85, 0.86), Vector3(0.5, 0.5, 0.55)])
	var back_drop := 0.32
	var side_drop := 0.25
	match style:
		0:  # Bob
			back_drop = 0.47
			side_drop = 0.45
		4:  # Long
			back_drop = 0.86
			side_drop = 0.60
	ctx.form(head, Vector3(0, 0.51 - back_drop / 2.0, 0.22), Vector3(0.56, back_drop, 0.17), dark, TAPER_PROFILE)
	for side in [-1, 1]:
		ctx.form(head, Vector3(side * 0.26, 0.51 - side_drop / 2.0, 0.04), Vector3(0.13, side_drop, 0.4), color, LOCK_PROFILE, Vector3(0, 0, -side * 0.06))
	# Asymmetric bangs have a tapered tip, leaving both eyes visible.
	if style == 2:  # Ponytail: swept to one side
		ctx.form(head, Vector3(-0.07, 0.445, -0.237), Vector3(0.34, 0.20, 0.1), color, LOCK_PROFILE, Vector3(0, 0, -0.32))
		ctx.form(head, Vector3(0.19, 0.46, -0.22), Vector3(0.14, 0.16, 0.09), dark, LOCK_PROFILE)
	else:
		ctx.form(head, Vector3(-0.155, 0.447, -0.229), Vector3(0.19, 0.19, 0.11), color, LOCK_PROFILE, Vector3(0, 0, -0.18))
		ctx.form(head, Vector3(0.006, 0.442, -0.245), Vector3(0.18, 0.245, 0.095), color, LOCK_PROFILE, Vector3(0, 0, 0.16))
		ctx.form(head, Vector3(0.167, 0.46, -0.225), Vector3(0.19, 0.175, 0.105), color.lightened(0.06), LOCK_PROFILE, Vector3(0, 0, 0.23))
		if style in [0, 4]:  # face-framing locks
			for side in [-1, 1]:
				ctx.form(head, Vector3(side * 0.245, 0.245, -0.16), Vector3(0.09, 0.36, 0.14), color, LOCK_PROFILE, Vector3(0, 0, -side * 0.12))
	match style:
		1:  # Twin Tails: tied high on each side, falling to the shoulders
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.31, 0.45, 0.1), Vector3(0.08, 0.07, 0.09), ctx.team_color, DETAIL)
				ctx.form(head, Vector3(side * 0.40, 0.27, 0.12), Vector3(0.19, 0.39, 0.20), color, TAPER_PROFILE, Vector3(0, 0, side * 0.22))
				ctx.form(head, Vector3(side * 0.46, -0.01, 0.15), Vector3(0.15, 0.30, 0.17), dark, LOCK_PROFILE, Vector3(0, 0, -side * 0.12))
		2:  # Ponytail
			ctx.detail(head, Vector3(0, 0.48, 0.34), Vector3(0.1, 0.08, 0.06), ctx.team_color)
			ctx.form(head, Vector3(0, 0.22, 0.38), Vector3(0.19, 0.50, 0.19), color, LOCK_PROFILE, Vector3(0.35, 0, 0))
		5:  # Spiky
			if not covered:
				for spike in [[Vector3(-0.17, 0.54, -0.07), Vector3(-0.45, 0, 0.55)], [Vector3(0, 0.58, -0.09), Vector3(-0.55, 0, 0)],
						[Vector3(0.17, 0.54, -0.07), Vector3(-0.45, 0, -0.55)], [Vector3(-0.12, 0.53, 0.14), Vector3(0.45, 0, 0.35)],
						[Vector3(0.12, 0.53, 0.14), Vector3(0.45, 0, -0.35)]]:
					ctx.form(head, spike[0], Vector3(0.14, 0.25, 0.14), color, LOCK_PROFILE, spike[1] + Vector3(0, 0, PI))

static func _headgear(ctx: Ctx, head: Node3D, kind: int, cloth: Color) -> void:
	var team := ctx.team_color
	match kind:
		1:  # Cap
			ctx.form(head, Vector3(0, 0.52, 0.02), Vector3(0.60, 0.18, 0.54), cloth, [Vector3(-0.5, 1, 1), Vector3(0.1, 0.96, 0.94), Vector3(0.5, 0.58, 0.64)])
			ctx.add(head, Vector3(0, 0.452, -0.30), Vector3(0.45, 0.025, 0.23), cloth.darkened(0.15))
			ctx.detail(head, Vector3(0, 0.52, -0.245), Vector3(0.09, 0.05, 0.014), team)
			ctx.add(head, Vector3(0, 0.615, 0.02), Vector3(0.045, 0.022, 0.045), team, DETAIL)
		2:  # Goggle Helmet: grey shell, ear guards, tinted goggles pushed up on the brow
			var shell := Color("6a6f7a")
			ctx.form(head, Vector3(0, 0.51, 0.02), Vector3(0.61, 0.23, 0.56), shell, [Vector3(-0.5, 1, 1), Vector3(0, 0.96, 0.95), Vector3(0.5, 0.55, 0.62)])
			ctx.add(head, Vector3(0, 0.445, -0.28), Vector3(0.50, 0.035, 0.08), shell.darkened(0.25))
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.11, 0.555, -0.254), Vector3(0.19, 0.1, 0.07), DARK)
				box(head, Vector3(side * 0.11, 0.558, -0.291), Vector3(0.14, 0.055, 0.015), ctx.glow(Color("8ab6df"), 0.5))
				ctx.add(head, Vector3(side * 0.292, 0.28, 0.02), Vector3(0.07, 0.15, 0.16), shell)
				ctx.detail(head, Vector3(side * 0.331, 0.28, 0.02), Vector3(0.01, 0.05, 0.10), team)
		3:  # Headset: band over the hair, ear cups, mic boom on the left
			ctx.add(head, Vector3(0, 0.585, 0.02), Vector3(0.53, 0.035, 0.065), DARK)
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.285, 0.47, 0.02), Vector3(0.035, 0.21, 0.06), DARK)
				ctx.add(head, Vector3(side * 0.30, 0.28, 0.02), Vector3(0.075, 0.15, 0.15), Color("c9ccd2"))
				ctx.detail(head, Vector3(side * 0.34, 0.28, 0.02), Vector3(0.01, 0.09, 0.095), team)
			ctx.add(head, Vector3(-0.29, 0.2, -0.16), Vector3(0.03, 0.03, 0.26), DARK, LIT, Vector3(0, 0.35, 0))
			box(head, Vector3(-0.22, 0.18, -0.29), Vector3(0.05, 0.04, 0.04), ctx.glow(team, 1.6))
		4:  # Beanie with a pompom in the team colour
			ctx.form(head, Vector3(0, 0.53, 0.02), Vector3(0.59, 0.25, 0.54), cloth, [Vector3(-0.5, 1, 1), Vector3(0, 0.95, 0.95), Vector3(0.5, 0.4, 0.45)])
			ctx.add(head, Vector3(0, 0.446, 0.02), Vector3(0.60, 0.06, 0.55), cloth.darkened(0.16))
			ctx.add(head, Vector3(0, 0.679, 0.02), Vector3(0.105, 0.095, 0.105), team)
		5:  # Sunglasses pushed up on the head
			var frame := Color("f2c12e")
			ctx.add(head, Vector3(0, 0.54, -0.22), Vector3(0.46, 0.025, 0.04), frame, LIT, Vector3(-0.35, 0, 0))
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.12, 0.526, -0.25), Vector3(0.195, 0.115, 0.035), frame, LIT, Vector3(-0.35, 0, 0))
				ctx.add(head, Vector3(side * 0.12, 0.524, -0.272), Vector3(0.155, 0.08, 0.012), Color("5fe0f0"), DETAIL, Vector3(-0.35, 0, 0))
				ctx.detail(head, Vector3(side * 0.12 - 0.04, 0.54, -0.276), Vector3(0.035, 0.02, 0.012), Color("e9fdff"), Vector3(-0.35, 0, 0))

# Torso (Body pivot at the hips; torso y 0.04..0.54). Returns the sleeve colour (Color(0, 0, 0, 0): short sleeves).
static func _top(ctx: Ctx, body: Node3D, w: float, skin: Color, cloth: Color, kind: int) -> Color:
	var team := ctx.team_color
	var tw := 0.39 * w
	var trim_z := -0.141
	var fitted := [Vector3(-0.5, 0.82, 0.85), Vector3(-0.2, 0.86, 0.9), Vector3(0.28, 1, 1), Vector3(0.5, 0.90, 0.92)]
	box(body, Vector3(-0.09 * w, 0.41, -0.145), Vector3(0.053, 0.027, 0.014), ctx.glow(team, 1.3))
	match kind:
		0:  # Tee
			ctx.form(body, Vector3(0, 0.29, 0), Vector3(tw, 0.5, 0.27), cloth, fitted)
			ctx.detail(body, Vector3(0, 0.52, trim_z + 0.01), Vector3(0.2, 0.04, 0.02), team)
			ctx.add(body, Vector3(0, 0.075, 0), Vector3(tw * 0.85, 0.035, 0.24), cloth.darkened(0.12), DETAIL)
			for side in [-1, 1]:
				ctx.detail(body, Vector3(side * 0.055, 0.49, -0.131), Vector3(0.11, 0.022, 0.012), team, Vector3(0, 0, side * 0.35))
			return Color(0, 0, 0, 0)
		1:  # Hoodie: bulkier, pocket, hood behind the neck, team drawstrings
			ctx.form(body, Vector3(0, 0.29, 0), Vector3(tw + 0.04, 0.52, 0.3), cloth, fitted)
			ctx.add(body, Vector3(0, 0.53, 0.13), Vector3(0.36, 0.14, 0.14), cloth.darkened(0.12))
			ctx.add(body, Vector3(0, 0.16, -0.139), Vector3(0.24, 0.105, 0.02), cloth.darkened(0.10), DETAIL)
			for side in [-1, 1]:
				ctx.detail(body, Vector3(side * 0.05, 0.43, -0.158), Vector3(0.022, 0.13, 0.02), team)
			ctx.add(body, Vector3(0, 0.06, 0), Vector3((tw + 0.04) * 0.86, 0.04, 0.27), cloth.darkened(0.15), DETAIL)
			return cloth
		2:  # Short jacket, open front, angled lapels over a cream tee.
			ctx.form(body, Vector3(0, 0.1, 0), Vector3(tw * 0.78, 0.13, 0.22), skin, TAPER_PROFILE)
			ctx.form(body, Vector3(0, 0.355, 0), Vector3(tw + 0.02, 0.37, 0.29), cloth, fitted)
			ctx.add(body, Vector3(0, 0.33, -0.145), Vector3(0.14, 0.31, 0.015), CREAM, DETAIL)
			for side in [-1, 1]:
				ctx.detail(body, Vector3(side * 0.078, 0.34, -0.159), Vector3(0.014, 0.31, 0.012), team)
				ctx.form(body, Vector3(side * 0.085, 0.474, -0.161), Vector3(0.072, 0.13, 0.023), cloth.lightened(0.18), LOCK_PROFILE, Vector3(0, 0, -side * 0.4), DETAIL)
				ctx.detail(body, Vector3(side * 0.105, 0.255, -0.153), Vector3(0.05, 0.012, 0.012), cloth.darkened(0.2), Vector3(0, 0, side * 0.12))
			return cloth
		3:  # Tactical Vest over a darker shirt, front pouches
			var shirt := cloth.darkened(0.4)
			ctx.form(body, Vector3(0, 0.29, 0), Vector3(tw - 0.02, 0.5, 0.25), shirt, fitted)
			ctx.form(body, Vector3(0, 0.31, 0), Vector3(tw + 0.03, 0.36, 0.31), cloth, fitted)
			for i in range(3):
				ctx.add(body, Vector3((i - 1) * 0.10 * w, 0.2, -0.155), Vector3(0.085, 0.10, 0.045), cloth.darkened(0.15))
			for side in [-1, 1]:
				ctx.add(body, Vector3(side * 0.13 * w, 0.52, 0), Vector3(0.08, 0.04, 0.31), cloth.darkened(0.2))
			ctx.detail(body, Vector3(0.1 * w, 0.42, -0.158), Vector3(0.1, 0.06, 0.02), team)
			return shirt
		_:  # Jersey: team stripe across the chest and a number patch
			ctx.form(body, Vector3(0, 0.29, 0), Vector3(tw, 0.5, 0.27), cloth, fitted)
			ctx.add(body, Vector3(0, 0.37, 0), Vector3(tw + 0.006, 0.055, 0.275), team, DETAIL)
			ctx.detail(body, Vector3(0, 0.51, trim_z), Vector3(0.16, 0.06, 0.02), Color("f4f1e8"), Vector3(0, 0, 0))
			ctx.detail(body, Vector3(0.1 * w, 0.2, trim_z), Vector3(0.1, 0.11, 0.02), Color("f4f1e8"))
			ctx.detail(body, Vector3(0.1 * w, 0.2, trim_z - 0.008), Vector3(0.03, 0.08, 0.02), cloth.darkened(0.3))
			return Color(0, 0, 0, 0)

# The pelvis rides with the Body; skirts hang from it.
static func _bottoms_body(ctx: Ctx, body: Node3D, w: float, cloth: Color, kind: int) -> void:
	if kind == 2:  # Skirt: flared, with pleat lines
		ctx.form(body, Vector3(0, -0.055, 0), Vector3(0.57 * w, 0.32, 0.39), cloth,
			[Vector3(-0.5, 1, 1), Vector3(-0.4, 1, 1), Vector3(0.5, 0.58, 0.64)])
		for side in [-1, 1]:
			ctx.detail(body, Vector3(side * 0.082 * w, -0.062, -0.173), Vector3(0.014, 0.25, 0.014), cloth.darkened(0.13), Vector3(-0.21, 0, -side * 0.16))
		ctx.add(body, Vector3(0, 0.092, 0), Vector3(0.34 * w, 0.045, 0.25), cloth.darkened(0.18), DETAIL)
		return
	ctx.form(body, Vector3(0, 0.035, 0), Vector3(0.39 * w, 0.17, 0.27), cloth, TAPER_PROFILE)
	ctx.add(body, Vector3(0, 0.108, 0), Vector3(0.35 * w, 0.035, 0.25), cloth.darkened(0.2), DETAIL)
	ctx.detail(body, Vector3(0, 0.108, -0.134), Vector3(0.055, 0.028, 0.015), CREAM)

# Leg pivot at the hip: tapered thigh, narrow knee and calf, with shoes filling the last 0.16 m.
static func _leg(ctx: Ctx, leg: Node3D, side: int, t: float, skin: Color, cloth: Color, kind: int) -> void:
	var sock := Color("f4f1e8")
	match kind:
		1:  # Cargo Pants
			ctx.form(leg, Vector3(0, -0.205, 0), Vector3(0.18 * t, 0.43, 0.20 * t), cloth, TAPER_PROFILE)
			ctx.form(leg, Vector3(0, -0.57, 0), Vector3(0.15 * t, 0.34, 0.17 * t), cloth, TAPER_PROFILE)
			ctx.add(leg, Vector3(side * 0.092 * t, -0.245, 0), Vector3(0.04, 0.12, 0.12), cloth.darkened(0.12))
		2:  # Skirt: bare legs, knee socks
			ctx.form(leg, Vector3(0, -0.21, 0), Vector3(0.155 * t, 0.44, 0.17 * t), skin, TAPER_PROFILE)
			ctx.form(leg, Vector3(0, -0.48, 0), Vector3(0.125 * t, 0.17, 0.14 * t), skin, TAPER_PROFILE)
			ctx.form(leg, Vector3(0, -0.645, 0), Vector3(0.135 * t, 0.21, 0.15 * t), sock, TAPER_PROFILE)
		3:  # Cutoffs: short frayed denim
			ctx.form(leg, Vector3(0, -0.08, 0), Vector3(0.18 * t, 0.19, 0.2 * t), cloth, TAPER_PROFILE)
			ctx.add(leg, Vector3(0, -0.166, 0), Vector3(0.15 * t, 0.03, 0.18 * t), cloth.lightened(0.25), DETAIL)
			ctx.form(leg, Vector3(0, -0.31, 0), Vector3(0.148 * t, 0.30, 0.164 * t), skin, TAPER_PROFILE)
			ctx.form(leg, Vector3(0, -0.59, 0), Vector3(0.126 * t, 0.30, 0.14 * t), skin, TAPER_PROFILE)
			ctx.add(leg, Vector3(0, -0.72, 0), Vector3(0.13 * t, 0.085, 0.15 * t), sock)
		_:  # Shorts
			ctx.form(leg, Vector3(0, -0.11, 0), Vector3(0.19 * t, 0.25, 0.21 * t), cloth, TAPER_PROFILE)
			ctx.add(leg, Vector3(0, -0.223, 0), Vector3(0.16 * t, 0.032, 0.18 * t), cloth.lightened(0.12), DETAIL)
			ctx.form(leg, Vector3(0, -0.345, 0), Vector3(0.148 * t, 0.26, 0.164 * t), skin, TAPER_PROFILE)
			ctx.form(leg, Vector3(0, -0.60, 0), Vector3(0.126 * t, 0.29, 0.14 * t), skin, TAPER_PROFILE)
			ctx.add(leg, Vector3(0, -0.72, 0), Vector3(0.13 * t, 0.085, 0.15 * t), sock)

static func _shoe(ctx: Ctx, leg: Node3D, side: int, cloth: Color, kind: int) -> void:
	var team := ctx.team_color
	var w: float = Appearance.BODIES[ctx.look.body].width
	var sole := Color("f1efe8") if cloth.get_luminance() < 0.8 else Color("b9bcc2")
	var y := -HIP_Y
	match kind:
		1:  # Boots: tall shaft, dark lug sole, team laces
			ctx.form(leg, Vector3(0, y + 0.22, 0), Vector3(0.18 * w, 0.22, 0.20), cloth, TAPER_PROFILE)
			ctx.add(leg, Vector3(0, y + 0.10, -0.04), Vector3(0.20 * w, 0.14, 0.31), cloth)
			ctx.add(leg, Vector3(0, y + 0.025, -0.04), Vector3(0.22 * w, 0.05, 0.33), Color("2a2622"))
			ctx.add(leg, Vector3(0, y + 0.31, 0), Vector3(0.19 * w, 0.045, 0.21), CREAM, DETAIL)
			for i in range(3):
				ctx.detail(leg, Vector3(0, y + 0.16 + i * 0.036, -0.105), Vector3(0.055, 0.012, 0.012), team, Vector3(0, 0, 0.15 if i % 2 == 0 else -0.15))
		2:  # High-tops: chunky, thick white sole and toe cap, team ankle band
			ctx.add(leg, Vector3(0, y + 0.14, -0.03), Vector3(0.205 * w, 0.2, 0.32), cloth)
			ctx.add(leg, Vector3(0, y + 0.035, -0.035), Vector3(0.22 * w, 0.07, 0.35), sole)
			ctx.add(leg, Vector3(0, y + 0.09, -0.16), Vector3(0.20 * w, 0.08, 0.08), sole)
			ctx.add(leg, Vector3(0, y + 0.22, -0.01), Vector3(0.19 * w, 0.035, 0.20), team, DETAIL)
		_:  # Sneakers
			ctx.add(leg, Vector3(0, y + 0.1, -0.04), Vector3(0.20 * w, 0.13, 0.31), cloth)
			ctx.add(leg, Vector3(0, y + 0.025, -0.045), Vector3(0.22 * w, 0.05, 0.33), sole)
			ctx.detail(leg, Vector3(side * 0.1 * w, y + 0.09, -0.03), Vector3(0.012, 0.028, 0.15), team)
			ctx.detail(leg, Vector3(0, y + 0.15, -0.13), Vector3(0.1, 0.02, 0.1), sole)

# Free arm: shoulder pivot, hanging down. Sleeve colour alpha 0 means short sleeves (bare forearm).
static func _free_arm(ctx: Ctx, arm: Node3D, t: float, skin: Color, sleeve: Color) -> void:
	var top_color: Color = Appearance.CLOTH_COLORS[ctx.look.top_color] if sleeve.a == 0.0 else sleeve
	ctx.form(arm, Vector3(0, -0.095, 0), Vector3(0.145 * t, 0.23, 0.15 * t), top_color, TAPER_PROFILE)
	ctx.add(arm, Vector3(0, -0.06, 0), Vector3(0.147 * t, 0.035, 0.152 * t), ctx.team_color, DETAIL)
	ctx.form(arm, Vector3(0, -0.295, 0), Vector3(0.105 * t, 0.21, 0.115 * t), skin if sleeve.a == 0.0 else sleeve, TAPER_PROFILE)
	ctx.add(arm, Vector3(0, -0.44, -0.01), Vector3(0.108, 0.12, 0.12), skin)
	ctx.add(arm, Vector3(0, -0.395, 0), Vector3(0.116 * t, 0.035, 0.125 * t), DARK, DETAIL)

# Gun arm: shoulder pivot pointing forward (-Z), hand under the gun's grip.
static func _gun_arm(ctx: Ctx, weapon: Node3D, t: float, skin: Color, sleeve: Color) -> void:
	var top_color: Color = Appearance.CLOTH_COLORS[ctx.look.top_color] if sleeve.a == 0.0 else sleeve
	ctx.form(weapon, Vector3(0, 0, -0.08), Vector3(0.145 * t, 0.24, 0.15 * t), top_color, TAPER_PROFILE, Vector3(PI / 2, 0, 0))
	ctx.add(weapon, Vector3(0, 0, -0.03), Vector3(0.147 * t, 0.152 * t, 0.035), ctx.team_color, DETAIL)
	ctx.form(weapon, Vector3(0, -0.01, -0.27), Vector3(0.105 * t, 0.20, 0.115 * t), skin if sleeve.a == 0.0 else sleeve, TAPER_PROFILE, Vector3(PI / 2, 0, 0))
	ctx.add(weapon, Vector3(0, -0.03, -0.39), Vector3(0.108, 0.12, 0.12), skin)
	ctx.add(weapon, Vector3(0, -0.014, -0.355), Vector3(0.116 * t, 0.125 * t, 0.035), DARK, DETAIL)

# ---- weapons --------------------------------------------------------------------------------------------------

static func _primary_model(ctx: Ctx, weapon: Node3D, primary_id: int) -> void:
	var gun := pivot(weapon, "Primary", Vector3(0, 0.07, 0))
	var metal := Color("8a949c")
	match primary_id:
		0:  # Shotgun: short, fat pump shotgun
			ctx.add(gun, Vector3(0, -0.03, -0.5), Vector3(0.11, 0.11, 0.56), DARK)
			ctx.add(gun, Vector3(0, -0.1, -0.54), Vector3(0.09, 0.09, 0.32), metal, LIT, Vector3(PI / 2, 0, 0), PRISM)
			ctx.add(gun, Vector3(0, -0.1, -0.3), Vector3(0.06, 0.12, 0.08), Color("6a4a32"))
			box(gun, Vector3(0, 0.03, -0.78), Vector3(0.04, 0.04, 0.08), ctx.glow(Color("ff9a4a"), 2.0))
		1:  # Rifle: long barrel and scope
			ctx.add(gun, Vector3(0, -0.03, -0.6), Vector3(0.07, 0.1, 0.95), DARK)
			ctx.add(gun, Vector3(0, 0.065, -0.55), Vector3(0.08, 0.08, 0.32), Color("3a4552"))
			ctx.add(gun, Vector3(0, -0.12, -0.36), Vector3(0.06, 0.12, 0.07), Color("3a4552"))
			box(gun, Vector3(0, 0.065, -0.72), Vector3(0.05, 0.05, 0.03), ctx.glow(Color("7ee8ff"), 2.4))
		_:  # SMG: compact with a stick magazine
			ctx.add(gun, Vector3(0, -0.03, -0.44), Vector3(0.1, 0.14, 0.38), DARK)
			ctx.add(gun, Vector3(0, -0.16, -0.4), Vector3(0.06, 0.18, 0.08), Color("3a4552"))
			box(gun, Vector3(0, -0.02, -0.66), Vector3(0.03, 0.03, 0.08), ctx.glow(Color("ffe08a"), 2.0))

static func _sidearm_model(ctx: Ctx, weapon: Node3D, sidearm_id: int) -> void:
	var gun := pivot(weapon, "Sidearm", Vector3(0, 0.05, 0))
	gun.visible = false
	var metal := Color("8a949c")
	match sidearm_id:
		0:  # Pistol: plain slide and grip
			ctx.add(gun, Vector3(0, -0.02, -0.42), Vector3(0.07, 0.09, 0.22), DARK)
			ctx.add(gun, Vector3(0, -0.1, -0.37), Vector3(0.06, 0.12, 0.07), Color("3a4552"))
		1:  # Burst Pistol: longer slide with a lit vent
			ctx.add(gun, Vector3(0, -0.02, -0.46), Vector3(0.08, 0.1, 0.3), DARK)
			box(gun, Vector3(0, 0.04, -0.56), Vector3(0.03, 0.03, 0.1), ctx.glow(Color("7ee8ff"), 2.0))
		_:  # Revolver: cylinder and long barrel
			ctx.add(gun, Vector3(0, -0.02, -0.42), Vector3(0.07, 0.11, 0.22), metal)
			ctx.add(gun, Vector3(0, -0.01, -0.56), Vector3(0.06, 0.06, 0.16), metal, LIT, Vector3(PI / 2, 0, 0), PRISM)

static func _melee_model(ctx: Ctx, arm: Node3D, melee_id: int) -> void:
	var hand := pivot(arm, "Melee", Vector3(0, -0.45, -0.02))
	match melee_id:
		0:  # Knife
			ctx.add(hand, Vector3(0, 0, -0.04), Vector3(0.04, 0.04, 0.08), DARK)
			ctx.add(hand, Vector3(0, 0, -0.17), Vector3(0.025, 0.05, 0.2), Color("c8d0d4"))
		1:  # Sledgehammer: long haft and a heavy head
			ctx.add(hand, Vector3(0, 0.12, 0), Vector3(0.05, 0.72, 0.05), Color("6a4a32"), LIT, Vector3.ZERO, PRISM)
			ctx.add(hand, Vector3(0, 0.46, 0), Vector3(0.15, 0.15, 0.32), DARK)
		_:  # Sword
			ctx.add(hand, Vector3(0, 0.0, 0), Vector3(0.11, 0.06, 0.06), DARK)
			ctx.add(hand, Vector3(0, 0.45, 0), Vector3(0.05, 0.8, 0.02), Color("c8d0d4"))

# ---- baking -----------------------------------------------------------------------------------------------------

static func _bake(ctx: Ctx) -> void:
	ctx.lit_mat = _vertex_material()
	ctx.detail_mat = _vertex_material()
	ctx.materials.append(ctx.lit_mat)
	ctx.materials.append(ctx.detail_mat)
	if not ctx.ghost:
		if _outline_shader == null:
			_outline_shader = Shader.new()
			_outline_shader.code = OUTLINE_SHADER
		var outline := ShaderMaterial.new()
		outline.shader = _outline_shader
		outline.set_shader_parameter("outline_color", Visuals.ENEMY_OUTLINE)
		outline.set_shader_parameter("width", OUTLINE_WIDTH)
		ctx.lit_mat.next_pass = outline
		ctx.outlines.append(outline)
	for bone in ctx.parts:
		var mesh := ArrayMesh.new()
		for layer in [LIT, DETAIL]:
			var arrays := _surface(ctx.parts[bone], layer)
			if arrays.is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			mesh.surface_set_material(mesh.get_surface_count() - 1, ctx.lit_mat if layer == LIT else ctx.detail_mat)
		var node := MeshInstance3D.new()
		node.name = "Mesh"
		node.mesh = mesh
		# Only the big masses cast shadows; arms, guns and the melee weapon would just add shadow draw calls.
		var big: bool = bone.name in ["LegL", "LegR", "Body", "Head"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bone.add_child(node)
	ctx.parts.clear()

static func _vertex_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	return mat

static func _surface(parts: Array, layer: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	for p in parts:
		if p.layer != layer:
			continue
		if p.shape == PRISM:
			_emit_prism(p, verts, normals, colors, custom)
		elif p.shape == FACET:
			_emit_facet(p, verts, normals, colors, custom)
		elif p.shape == PATCH:
			_emit_patch(p, verts, normals, colors, custom)
		else:
			_emit_box(p, verts, normals, colors, custom)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	return arrays

# One flat-shaded quad. `dirs` are the corners' outline directions (part-local). Wound clockwise seen from outside,
# which is Godot's front face.
static func _quad(xf: Transform3D, corners: Array, dirs: Array, normal: Vector3, color: Color,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	if corners[0] == corners[3]:
		order.resize(3)  # triangle fans need no degenerate second triangle
	var n: Vector3 = (xf.basis * normal).normalized()
	for i in order:
		verts.append(xf * corners[i])
		normals.append(n)
		colors.append(color)
		var d: Vector3 = xf.basis * dirs[i]
		custom.append_array([d.x, d.y, d.z, 0.0])

static func _emit_box(p: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array) -> void:
	var h: Vector3 = p.size * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for a in range(3):
		var u: int = (a + 1) % 3
		var v: int = (a + 2) % 3
		for s in [-1.0, 1.0]:
			var corners := []
			var dirs := []
			for c in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var sign_vec: Vector3 = axes[a] * s + axes[u] * c[0] + axes[v] * c[1]
				corners.append(sign_vec * h)
				dirs.append(sign_vec)
			_quad(p.xf, corners, dirs, axes[a] * s, p.color, verts, normals, colors, custom)

# Convex face patches stay flat, so eyes and blush do not cast little box shadows.
static func _emit_patch(p: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array) -> void:
	var polygon: Array = p.polygon
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		_quad(p.xf, [Vector3.ZERO, Vector3(a.x * p.size.x, a.y * p.size.y, 0), Vector3(b.x * p.size.x, b.y * p.size.y, 0), Vector3.ZERO],
			[Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO], Vector3.FORWARD, p.color, verts, normals, colors, custom)

# Chamfered rectangular rings preserve a broad front plane for facial features and garment details.
static func _facet_ring(size: Vector3, ring: Vector3) -> Array:
	var x := size.x * ring.y * 0.5
	var z := size.z * ring.z * 0.5
	var y := size.y * ring.x
	var bx := x * 0.28
	var bz := z * 0.28
	return [Vector3(-x + bx, y, -z), Vector3(x - bx, y, -z), Vector3(x, y, -z + bz),
		Vector3(x, y, z - bz), Vector3(x - bx, y, z), Vector3(-x + bx, y, z),
		Vector3(-x, y, z - bz), Vector3(-x, y, -z + bz)]

static func _emit_facet(p: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array) -> void:
	var profile: Array = p.get("profile", SOFT_PROFILE)
	var rings := []
	for ring in profile:
		rings.append(_facet_ring(p.size, ring))
	for band in range(rings.size() - 1):
		for i in range(8):
			var j := (i + 1) % 8
			var corners := [rings[band][i], rings[band][j], rings[band + 1][j], rings[band + 1][i]]
			var normal: Vector3 = (corners[3] - corners[0]).cross(corners[1] - corners[0]).normalized()
			var dirs := []
			for v in corners:
				dirs.append(Vector3(v.x / (p.size.x * 0.5), v.y / (p.size.y * 0.5), v.z / (p.size.z * 0.5)))
			_quad(p.xf, corners, dirs, normal, p.color, verts, normals, colors, custom)
	for cap in [0, rings.size() - 1]:
		var normal := Vector3.DOWN if cap == 0 else Vector3.UP
		var center := Vector3(0, rings[cap][0].y, 0)
		for i in range(8):
			var a: Vector3 = rings[cap][i]
			var b: Vector3 = rings[cap][(i + 1) % 8]
			var da := Vector3(a.x / (p.size.x * 0.5), normal.y, a.z / (p.size.z * 0.5))
			var db := Vector3(b.x / (p.size.x * 0.5), normal.y, b.z / (p.size.z * 0.5))
			_quad(p.xf, [center, a, b, center], [normal, da, db, normal], normal, p.color, verts, normals, colors, custom)

# Eight-sided prism along local Y (size.x is the diameter, size.y the length).
static func _emit_prism(p: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, custom: PackedFloat32Array) -> void:
	var sides := 8
	var r: float = p.size.x * 0.5
	var hy: float = p.size.y * 0.5
	var stretch := 1.0 / cos(PI / sides)
	for i in range(sides):
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var r0 := Vector3(cos(a0), 0, sin(a0))
		var r1 := Vector3(cos(a1), 0, sin(a1))
		var mid := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var down := Vector3.DOWN * hy
		var up := Vector3.UP * hy
		_quad(p.xf, [r0 * r + down, r1 * r + down, r1 * r + up, r0 * r + up],
			[r0 * stretch + Vector3.DOWN, r1 * stretch + Vector3.DOWN, r1 * stretch + Vector3.UP, r0 * stretch + Vector3.UP],
			mid, p.color, verts, normals, colors, custom)
		for cap in [-1.0, 1.0]:
			var c: Vector3 = Vector3.UP * hy * cap
			var cd: Vector3 = Vector3.UP * cap
			_quad(p.xf, [c, r0 * r + c, r1 * r + c, c], [cd, r0 * stretch + cd, r1 * stretch + cd, cd], Vector3.UP * cap, p.color, verts, normals, colors, custom)

# ---- animation ------------------------------------------------------------------------------------------------

# Per-frame procedural pose from synced state only (velocity, pitch, melee recovery).
static func animate(root: Node3D, dt: float, planar_speed: float, grounded: bool, pitch: float, sliding: bool, melee_time: float = 0.0) -> void:
	if root == null or not is_instance_valid(root) or root.has_meta("authored"):
		return
	var phase: float = root.get_meta("phase", 0.0)
	phase += dt * (planar_speed * 1.9 + 1.0)
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
	var hip_y := HIP_Y
	var bob := absf(sin(phase)) * 0.045 * run  # a chunky little hop in the run
	if sliding:
		# Seated slide: hips drop, front leg extends, rear leg tucks, torso leans back, free arm braces.
		# Positive x rotation swings limbs toward the front (-Z) and tips the torso backward.
		left_x = 1.3
		right_x = -0.6
		arm_x = 0.9
		lean = 1.0
		hip_y = HIP_Y * 0.5
		bob = 0.0
	# Legs ease in and out of the slide pose; otherwise they follow the run cycle directly.
	var easing: bool = sliding or absf(legs.position.y - HIP_Y) > 0.02
	if left != null:
		left.rotation.x = lerpf(left.rotation.x, left_x, blend) if easing else left_x
	if right != null:
		right.rotation.x = lerpf(right.rotation.x, right_x, blend) if easing else right_x
	legs.position.y = lerpf(legs.position.y, hip_y, blend)
	body.position.y = lerpf(body.position.y, hip_y, blend) + bob
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
