class_name CharacterRig
extends RefCounted

# Procedural character rig: a squat, chunky low-poly person (big blocky head and eyes, short limbs, oversized shoes)
# dressed from an Appearance code (scripts/appearance.gd), holding the loadout's primary and sidearm (only the gun in
# hand shows) and its melee weapon in the free hand. Team identity is trim in the team colour: the top's collar or
# stripe, a band on each upper arm and a stripe on each shoe.
#
# Parts are authored as boxes and prisms per bone, then baked into one vertex-coloured mesh per bone (two surfaces:
# outlined body parts and un-outlined face/trim details), so a fighter costs about a dozen draw calls. Bones and the
# node names animate() and the tests rely on: ClassEquipment/Legs/{LegL,LegR}, Body/{Head, ArmL/Melee,
# Weapon/{Primary,Sidearm}}.
#
# A Blender export at assets/models/characters/operative.glb replaces the procedural parts (see assets/README.md);
# animation then degrades gracefully because every part lookup tolerates a missing node.

const SLUG := "operative"
const DARK := Color("28323f")
const CREAM := Color("e7e9df")
const HIP_Y := 0.72  # hip height; legs plus shoes fill it exactly
const OUTLINE_WIDTH := 0.022

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

	func add(bone: Node3D, pos: Vector3, size: Vector3, color: Color, layer: int = LIT, rot: Vector3 = Vector3.ZERO, shape: int = BOX) -> void:
		if not parts.has(bone):
			parts[bone] = []
		parts[bone].append({"xf": Transform3D(Basis.from_euler(rot), pos), "size": size, "color": color, "layer": layer, "shape": shape})

	func detail(bone: Node3D, pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
		add(bone, pos, size, color, DETAIL, rot)

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
		var leg := pivot(legs, "Leg%s" % ("L" if side < 0 else "R"), Vector3(side * 0.11 * w, 0, 0))
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
	var shoulder_x := 0.22 * w + 0.07 * t
	var arm := pivot(body, "ArmL", Vector3(-shoulder_x, 0.45, 0))
	_free_arm(ctx, arm, t, skin, sleeve)
	_melee_model(ctx, arm, melee_id)
	var weapon := pivot(body, "Weapon", Vector3(shoulder_x, 0.45, 0))
	_gun_arm(ctx, weapon, t, skin, sleeve)
	_primary_model(ctx, weapon, primary_id)
	_sidearm_model(ctx, weapon, sidearm_id)

static func _head(ctx: Ctx, head: Node3D, skin: Color) -> void:
	var eye_color: Color = Appearance.EYE_COLORS[ctx.look.eyes]
	# A chunky block with bevelled vertical edges (two overlapping boxes read as a chamfer under flat shading).
	ctx.add(head, Vector3(0, 0.3, 0), Vector3(0.56, 0.5, 0.46), skin)
	ctx.add(head, Vector3(0, 0.3, 0), Vector3(0.5, 0.48, 0.5), skin)
	ctx.add(head, Vector3(0, 0.07, 0.02), Vector3(0.44, 0.06, 0.4), skin)  # rounder jaw
	for side in [-1, 1]:
		ctx.add(head, Vector3(side * 0.29, 0.27, 0.03), Vector3(0.05, 0.1, 0.08), skin.darkened(0.04))  # ears
	# Face on the -Z side: big eyes low on the face, brows, nose, mouth, blush.
	var z := -0.25
	var white := Color("fbfbf6")
	var lash := Color("1f1a22")
	for side in [-1, 1]:
		var x: float = side * 0.11
		ctx.detail(head, Vector3(x, 0.25, z - 0.005), Vector3(0.12, 0.15, 0.02), white)
		ctx.detail(head, Vector3(x - side * 0.008, 0.24, z - 0.012), Vector3(0.085, 0.12, 0.02), eye_color)
		ctx.detail(head, Vector3(x - side * 0.008, 0.235, z - 0.018), Vector3(0.042, 0.065, 0.02), eye_color.darkened(0.65))
		ctx.detail(head, Vector3(x + side * 0.012, 0.275, z - 0.024), Vector3(0.03, 0.03, 0.02), white)
		ctx.detail(head, Vector3(x - side * 0.022, 0.215, z - 0.024), Vector3(0.016, 0.016, 0.02), white.darkened(0.08))
		ctx.detail(head, Vector3(x, 0.327, z - 0.016), Vector3(0.13, 0.02, 0.02), lash)  # upper lash line
		ctx.detail(head, Vector3(x + side * 0.068, 0.318, z - 0.016), Vector3(0.022, 0.03, 0.02), lash)  # outer lash tick
		ctx.detail(head, Vector3(x + side * 0.01, 0.398, z - 0.01), Vector3(0.085, 0.018, 0.02), Appearance.HAIR_COLORS[ctx.look.hair_color].darkened(0.35))
		ctx.detail(head, Vector3(side * 0.185, 0.155, z - 0.004), Vector3(0.075, 0.032, 0.02), skin.lerp(Color("ff6f8a"), 0.42))
	ctx.detail(head, Vector3(0, 0.165, z - 0.012), Vector3(0.03, 0.03, 0.03), skin.darkened(0.12))
	ctx.detail(head, Vector3(0, 0.105, z - 0.006), Vector3(0.075, 0.024, 0.02), Color("8e3446"))
	ctx.detail(head, Vector3(0, 0.094, z - 0.008), Vector3(0.04, 0.012, 0.02), Color("d86a7c"))

# Hair is built around the head block (x +-0.28, y 0.05..0.55, z +-0.25). `covered` drops what a hat would hide.
static func _hair(ctx: Ctx, head: Node3D, style: int, color: Color, covered: bool) -> void:
	var dark := color.darkened(0.18)
	if style == 3:  # Buzz: a thin cap and a hairline
		if not covered:
			ctx.add(head, Vector3(0, 0.565, 0.0), Vector3(0.54, 0.05, 0.52), color)
		ctx.add(head, Vector3(0, 0.4, 0.258), Vector3(0.52, 0.32, 0.03), color)
		for side in [-1, 1]:
			ctx.add(head, Vector3(side * 0.288, 0.44, 0.02), Vector3(0.03, 0.22, 0.44), color)
		ctx.detail(head, Vector3(0, 0.53, -0.258), Vector3(0.46, 0.05, 0.02), color)
		return
	if not covered:
		ctx.add(head, Vector3(0, 0.56, 0.02), Vector3(0.62, 0.12, 0.56), color)
	var back_drop := 0.38  # how far the back hangs below the crown
	var side_drop := 0.26
	match style:
		0:  # Bob
			back_drop = 0.5
			side_drop = 0.48
		4:  # Long
			back_drop = 0.95
			side_drop = 0.62
	ctx.add(head, Vector3(0, 0.6 - back_drop / 2.0, 0.28), Vector3(0.62, back_drop, 0.09), color)
	for side in [-1, 1]:
		ctx.add(head, Vector3(side * 0.305, 0.58 - side_drop / 2.0, 0.03), Vector3(0.07, side_drop, 0.5), color)
	# Jagged bangs across the forehead (brows show under the side chunks).
	if style == 2:  # Ponytail: swept to one side
		ctx.add(head, Vector3(-0.1, 0.47, -0.27), Vector3(0.36, 0.16, 0.06), color, LIT, Vector3(0, 0, -0.12))
		ctx.add(head, Vector3(0.18, 0.5, -0.27), Vector3(0.2, 0.1, 0.06), dark)
	else:
		ctx.add(head, Vector3(-0.17, 0.48, -0.27), Vector3(0.2, 0.14, 0.06), color)
		ctx.add(head, Vector3(0.0, 0.45, -0.275), Vector3(0.17, 0.2, 0.06), color)
		ctx.add(head, Vector3(0.17, 0.485, -0.27), Vector3(0.2, 0.13, 0.06), dark)
		if style in [0, 4]:  # face-framing locks
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.255, 0.33, -0.235), Vector3(0.07, 0.34, 0.07), color)
	match style:
		1:  # Twin Tails: tied high on each side, falling to the shoulders
			for side in [-1, 1]:
				ctx.detail(head, Vector3(side * 0.34, 0.5, 0.1), Vector3(0.08, 0.08, 0.08), ctx.team_color)
				ctx.add(head, Vector3(side * 0.42, 0.32, 0.12), Vector3(0.15, 0.36, 0.15), color, LIT, Vector3(0, 0, side * 0.22))
				ctx.add(head, Vector3(side * 0.47, 0.04, 0.15), Vector3(0.12, 0.3, 0.12), dark, LIT, Vector3(0, 0, side * 0.08))
		2:  # Ponytail
			ctx.detail(head, Vector3(0, 0.48, 0.34), Vector3(0.1, 0.08, 0.06), ctx.team_color)
			ctx.add(head, Vector3(0, 0.27, 0.4), Vector3(0.15, 0.44, 0.13), color, LIT, Vector3(0.35, 0, 0))
		5:  # Spiky
			if not covered:
				for spike in [[Vector3(-0.17, 0.66, -0.08), Vector3(-0.45, 0, 0.55)], [Vector3(0, 0.7, -0.1), Vector3(-0.55, 0, 0)],
						[Vector3(0.17, 0.66, -0.08), Vector3(-0.45, 0, -0.55)], [Vector3(-0.12, 0.65, 0.14), Vector3(0.45, 0, 0.35)],
						[Vector3(0.12, 0.65, 0.14), Vector3(0.45, 0, -0.35)]]:
					ctx.add(head, spike[0], Vector3(0.13, 0.22, 0.13), color, LIT, spike[1])

static func _headgear(ctx: Ctx, head: Node3D, kind: int, cloth: Color) -> void:
	var team := ctx.team_color
	match kind:
		1:  # Cap
			ctx.add(head, Vector3(0, 0.6, 0.02), Vector3(0.64, 0.15, 0.58), cloth)
			ctx.add(head, Vector3(0, 0.535, -0.37), Vector3(0.5, 0.035, 0.22), cloth.darkened(0.2))
			ctx.detail(head, Vector3(0, 0.6, -0.272), Vector3(0.16, 0.08, 0.02), team)
			ctx.detail(head, Vector3(0, 0.685, 0.02), Vector3(0.06, 0.03, 0.06), team)
		2:  # Goggle Helmet: grey shell, ear guards, tinted goggles pushed up on the brow
			var shell := Color("6a6f7a")
			ctx.add(head, Vector3(0, 0.6, 0.02), Vector3(0.66, 0.18, 0.62), shell)
			ctx.add(head, Vector3(0, 0.52, -0.33), Vector3(0.62, 0.05, 0.1), shell.darkened(0.25))
			ctx.add(head, Vector3(0, 0.66, -0.3), Vector3(0.52, 0.14, 0.09), Color("3a3d46"))
			box(head, Vector3(0, 0.665, -0.35), Vector3(0.44, 0.09, 0.02), ctx.glow(Color("e05cff"), 1.4))
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.335, 0.32, 0.02), Vector3(0.07, 0.18, 0.18), shell)
				ctx.detail(head, Vector3(side * 0.372, 0.32, 0.02), Vector3(0.01, 0.06, 0.12), team)
		3:  # Headset: band over the hair, ear cups, mic boom on the left
			ctx.add(head, Vector3(0, 0.63, 0.02), Vector3(0.66, 0.05, 0.08), DARK)
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.335, 0.6, 0.02), Vector3(0.05, 0.1, 0.07), DARK)
				ctx.add(head, Vector3(side * 0.34, 0.3, 0.02), Vector3(0.08, 0.18, 0.18), Color("c9ccd2"))
				ctx.detail(head, Vector3(side * 0.382, 0.3, 0.02), Vector3(0.01, 0.12, 0.12), team)
			ctx.add(head, Vector3(-0.29, 0.2, -0.16), Vector3(0.03, 0.03, 0.26), DARK, LIT, Vector3(0, 0.35, 0))
			box(head, Vector3(-0.22, 0.18, -0.29), Vector3(0.05, 0.04, 0.04), ctx.glow(team, 1.6))
		4:  # Beanie with a pompom in the team colour
			ctx.add(head, Vector3(0, 0.6, 0.02), Vector3(0.64, 0.22, 0.58), cloth)
			ctx.add(head, Vector3(0, 0.5, 0.02), Vector3(0.66, 0.08, 0.6), cloth.darkened(0.2))
			ctx.add(head, Vector3(0, 0.75, 0.02), Vector3(0.13, 0.1, 0.13), team)
		5:  # Sunglasses pushed up on the head
			var frame := Color("f2c12e")
			ctx.add(head, Vector3(0, 0.615, -0.22), Vector3(0.52, 0.03, 0.04), frame, LIT, Vector3(-0.35, 0, 0))
			for side in [-1, 1]:
				ctx.add(head, Vector3(side * 0.13, 0.6, -0.25), Vector3(0.22, 0.14, 0.04), frame, LIT, Vector3(-0.35, 0, 0))
				ctx.detail(head, Vector3(side * 0.13, 0.598, -0.272), Vector3(0.17, 0.095, 0.02), Color("5fe0f0"), Vector3(-0.35, 0, 0))
				ctx.detail(head, Vector3(side * 0.13 - 0.04, 0.615, -0.276), Vector3(0.04, 0.025, 0.02), Color("e9fdff"), Vector3(-0.35, 0, 0))

# Torso (Body pivot at the hips; torso y 0.04..0.54). Returns the sleeve colour (Color(0, 0, 0, 0): short sleeves).
static func _top(ctx: Ctx, body: Node3D, w: float, skin: Color, cloth: Color, kind: int) -> Color:
	var team := ctx.team_color
	var tw := 0.44 * w
	var trim_z := -0.15
	box(body, Vector3(-0.1 * w, 0.42, -0.152), Vector3(0.07, 0.04, 0.02), ctx.glow(team, 1.3))  # chest badge
	match kind:
		0:  # Tee
			ctx.add(body, Vector3(0, 0.29, 0), Vector3(tw, 0.5, 0.27), cloth)
			ctx.detail(body, Vector3(0, 0.52, trim_z + 0.01), Vector3(0.2, 0.04, 0.02), team)
			ctx.detail(body, Vector3(0, 0.08, trim_z), Vector3(tw + 0.005, 0.03, 0.02), cloth.darkened(0.15))
			return Color(0, 0, 0, 0)
		1:  # Hoodie: bulkier, pocket, hood behind the neck, team drawstrings
			ctx.add(body, Vector3(0, 0.29, 0), Vector3(tw + 0.04, 0.52, 0.3), cloth)
			ctx.add(body, Vector3(0, 0.53, 0.13), Vector3(0.36, 0.14, 0.14), cloth.darkened(0.12))
			ctx.detail(body, Vector3(0, 0.14, -0.155), Vector3(0.28, 0.12, 0.02), cloth.darkened(0.12))
			for side in [-1, 1]:
				ctx.detail(body, Vector3(side * 0.05, 0.43, -0.158), Vector3(0.022, 0.13, 0.02), team)
			ctx.detail(body, Vector3(0, 0.06, -0.152), Vector3(tw + 0.045, 0.04, 0.02), cloth.darkened(0.2))
			return cloth
		2:  # Crop Jacket over a white tee, midriff showing, team zip lines
			ctx.add(body, Vector3(0, 0.1, 0), Vector3(tw - 0.04, 0.12, 0.24), skin)
			ctx.add(body, Vector3(0, 0.355, 0), Vector3(tw + 0.02, 0.37, 0.29), cloth)
			ctx.add(body, Vector3(0, 0.53, 0.0), Vector3(tw + 0.03, 0.06, 0.31), cloth.darkened(0.18))
			ctx.detail(body, Vector3(0, 0.33, -0.148), Vector3(0.13, 0.32, 0.02), Color("f4f1e8"))
			for side in [-1, 1]:
				ctx.detail(body, Vector3(side * 0.08, 0.34, -0.152), Vector3(0.025, 0.34, 0.02), team)
			ctx.detail(body, Vector3(0, 0.03, -0.12), Vector3(0.12, 0.04, 0.02), Color("3a3a3a"))  # belt buckle peeks under
			return cloth
		3:  # Tactical Vest over a darker shirt, front pouches
			var shirt := cloth.darkened(0.4)
			ctx.add(body, Vector3(0, 0.29, 0), Vector3(tw - 0.02, 0.5, 0.25), shirt)
			ctx.add(body, Vector3(0, 0.31, 0), Vector3(tw + 0.03, 0.36, 0.31), cloth)
			for i in range(3):
				ctx.add(body, Vector3((i - 1) * 0.12 * w, 0.2, -0.17), Vector3(0.1, 0.11, 0.05), cloth.darkened(0.2))
			for side in [-1, 1]:
				ctx.add(body, Vector3(side * 0.13 * w, 0.52, 0), Vector3(0.08, 0.04, 0.31), cloth.darkened(0.2))
			ctx.detail(body, Vector3(0.1 * w, 0.42, -0.158), Vector3(0.1, 0.06, 0.02), team)
			return shirt
		_:  # Jersey: team stripe across the chest and a number patch
			ctx.add(body, Vector3(0, 0.29, 0), Vector3(tw, 0.5, 0.27), cloth)
			ctx.detail(body, Vector3(0, 0.33, 0), Vector3(tw + 0.008, 0.06, 0.278), team)
			ctx.detail(body, Vector3(0, 0.51, trim_z), Vector3(0.16, 0.06, 0.02), Color("f4f1e8"), Vector3(0, 0, 0))
			ctx.detail(body, Vector3(0.1 * w, 0.2, trim_z), Vector3(0.1, 0.11, 0.02), Color("f4f1e8"))
			ctx.detail(body, Vector3(0.1 * w, 0.2, trim_z - 0.008), Vector3(0.03, 0.08, 0.02), cloth.darkened(0.3))
			return Color(0, 0, 0, 0)

# The pelvis rides with the Body; skirts hang from it.
static func _bottoms_body(ctx: Ctx, body: Node3D, w: float, cloth: Color, kind: int) -> void:
	if kind == 2:  # Skirt: flared, with pleat lines
		ctx.add(body, Vector3(0, 0.0, 0), Vector3(0.5 * w, 0.24, 0.34), cloth)
		for i in range(4):
			ctx.detail(body, Vector3((i - 1.5) * 0.11 * w, -0.02, -0.172), Vector3(0.018, 0.2, 0.02), cloth.darkened(0.2))
		return
	ctx.add(body, Vector3(0, 0.05, 0), Vector3(0.42 * w, 0.16, 0.26), cloth)
	ctx.detail(body, Vector3(0, 0.115, 0), Vector3(0.425 * w, 0.03, 0.265), cloth.darkened(0.3))  # waistband

# Leg pivot at the hip, y down: thigh 0..-0.3, shin -0.3..-0.58, shoes below.
static func _leg(ctx: Ctx, leg: Node3D, side: int, t: float, skin: Color, cloth: Color, kind: int) -> void:
	var sock := Color("f4f1e8")
	match kind:
		1:  # Cargo Pants
			ctx.add(leg, Vector3(0, -0.16, 0), Vector3(0.19 * t, 0.34, 0.21 * t), cloth)
			ctx.add(leg, Vector3(0, -0.45, 0), Vector3(0.18 * t, 0.26, 0.2 * t), cloth)
			ctx.add(leg, Vector3(side * 0.1 * t, -0.22, 0), Vector3(0.04, 0.12, 0.12), cloth.darkened(0.18))
		2:  # Skirt: bare legs, knee socks
			ctx.add(leg, Vector3(0, -0.16, 0), Vector3(0.16 * t, 0.32, 0.18 * t), skin)
			ctx.add(leg, Vector3(0, -0.4, 0), Vector3(0.15 * t, 0.16, 0.17 * t), skin)
			ctx.add(leg, Vector3(0, -0.52, 0), Vector3(0.16 * t, 0.16, 0.18 * t), sock)
		3:  # Cutoffs: short frayed denim
			ctx.add(leg, Vector3(0, -0.07, 0), Vector3(0.19 * t, 0.16, 0.21 * t), cloth)
			ctx.detail(leg, Vector3(0, -0.16, 0), Vector3(0.195 * t, 0.03, 0.215 * t), cloth.lightened(0.35))
			ctx.add(leg, Vector3(0, -0.33, 0), Vector3(0.16 * t, 0.36, 0.18 * t), skin)
			ctx.add(leg, Vector3(0, -0.53, 0), Vector3(0.165 * t, 0.1, 0.185 * t), sock)
		_:  # Shorts
			ctx.add(leg, Vector3(0, -0.1, 0), Vector3(0.2 * t, 0.22, 0.22 * t), cloth)
			ctx.add(leg, Vector3(0, -0.36, 0), Vector3(0.16 * t, 0.32, 0.18 * t), skin)
			ctx.add(leg, Vector3(0, -0.53, 0), Vector3(0.165 * t, 0.1, 0.185 * t), sock)

static func _shoe(ctx: Ctx, leg: Node3D, side: int, cloth: Color, kind: int) -> void:
	var team := ctx.team_color
	var sole := Color("f1efe8") if cloth.get_luminance() < 0.8 else Color("b9bcc2")
	var y := -HIP_Y
	match kind:
		1:  # Boots: tall shaft, dark lug sole, team laces
			ctx.add(leg, Vector3(0, y + 0.22, 0), Vector3(0.2, 0.2, 0.21), cloth)
			ctx.add(leg, Vector3(0, y + 0.09, -0.04), Vector3(0.21, 0.12, 0.33), cloth)
			ctx.add(leg, Vector3(0, y + 0.025, -0.04), Vector3(0.23, 0.05, 0.35), Color("2a2622"))
			ctx.detail(leg, Vector3(0, y + 0.2, -0.108), Vector3(0.06, 0.2, 0.02), team)
		2:  # High-tops: chunky, thick white sole and toe cap, team ankle band
			ctx.add(leg, Vector3(0, y + 0.14, -0.03), Vector3(0.23, 0.2, 0.34), cloth)
			ctx.add(leg, Vector3(0, y + 0.035, -0.035), Vector3(0.245, 0.07, 0.37), sole)
			ctx.add(leg, Vector3(0, y + 0.09, -0.175), Vector3(0.225, 0.08, 0.08), sole)
			ctx.detail(leg, Vector3(0, y + 0.22, -0.01), Vector3(0.235, 0.045, 0.22), team)
		_:  # Sneakers
			ctx.add(leg, Vector3(0, y + 0.1, -0.04), Vector3(0.21, 0.13, 0.33), cloth)
			ctx.add(leg, Vector3(0, y + 0.025, -0.045), Vector3(0.23, 0.05, 0.35), sole)
			ctx.detail(leg, Vector3(side * 0.106, y + 0.09, -0.03), Vector3(0.02, 0.035, 0.18), team)
			ctx.detail(leg, Vector3(0, y + 0.15, -0.13), Vector3(0.1, 0.02, 0.1), sole)

# Free arm: shoulder pivot, hanging down. Sleeve colour alpha 0 means short sleeves (bare forearm).
static func _free_arm(ctx: Ctx, arm: Node3D, t: float, skin: Color, sleeve: Color) -> void:
	var top_color: Color = Appearance.CLOTH_COLORS[ctx.look.top_color] if sleeve.a == 0.0 else sleeve
	ctx.add(arm, Vector3(0, -0.1, 0), Vector3(0.14 * t, 0.24, 0.14 * t), top_color)
	ctx.detail(arm, Vector3(0, -0.06, 0), Vector3(0.145 * t, 0.04, 0.145 * t), ctx.team_color)
	ctx.add(arm, Vector3(0, -0.3, 0), Vector3(0.12 * t, 0.18, 0.12 * t), skin if sleeve.a == 0.0 else sleeve)
	ctx.add(arm, Vector3(0, -0.44, -0.01), Vector3(0.13, 0.12, 0.13), skin)

# Gun arm: shoulder pivot pointing forward (-Z), hand under the gun's grip.
static func _gun_arm(ctx: Ctx, weapon: Node3D, t: float, skin: Color, sleeve: Color) -> void:
	var top_color: Color = Appearance.CLOTH_COLORS[ctx.look.top_color] if sleeve.a == 0.0 else sleeve
	ctx.add(weapon, Vector3(0, 0, -0.08), Vector3(0.14 * t, 0.14 * t, 0.24), top_color)
	ctx.detail(weapon, Vector3(0, 0, -0.03), Vector3(0.145 * t, 0.145 * t, 0.04), ctx.team_color)
	ctx.add(weapon, Vector3(0, -0.01, -0.27), Vector3(0.12 * t, 0.12 * t, 0.17), skin if sleeve.a == 0.0 else sleeve)
	ctx.add(weapon, Vector3(0, -0.03, -0.39), Vector3(0.13, 0.13, 0.12), skin)

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
