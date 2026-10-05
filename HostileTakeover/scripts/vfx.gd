class_name Vfx
extends RefCounted

# Cosmetic combat effects. Damage and hit detection stay hitscan on the authority;
# these only change how shots, abilities and impacts are drawn.

enum Style { LINE, SKYRUNNER, ARC, REPAIR, ENFORCER, MIRAGE, BOUNCE, CHARGED, SWOOSH, CAPSULE }

const BOLT_SPEED := 140.0
# Lifetime multiplier; tests raise it to hold effects still for screenshots.
static var time_scale := 1.0
static var _materials: Dictionary = {}

static func glow_material(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "%s:%s" % [color.to_html(), energy]
	if not _materials.has(key):
		var mat := Visuals.glow(color, energy)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = mat
	return _materials[key]

static func orient(dir: Vector3) -> Basis:
	if absf(dir.y) > 0.999:
		return Basis.IDENTITY if dir.y > 0 else Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, dir))

static func _fade(root: Node3D, node: Node3D, life: float, shrink: Vector3) -> void:
	var tween := root.create_tween()
	tween.tween_property(node, "scale", shrink, life * time_scale)
	tween.tween_callback(node.queue_free)

static func segment(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, life: float, energy: float = 2.0) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = glow_material(color, energy)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.global_transform = Transform3D(orient((b - a) / length) * Basis.from_scale(Vector3(1, length, 1)), (a + b) * 0.5)
	_fade(root, node, life, Vector3(0.0, length, 0.0).max(Vector3(0.001, length, 0.001)))

# Jittering electric arc between two points.
static func arc(root: Node3D, a: Vector3, b: Vector3, jitter: float, radius: float, color: Color, life: float) -> void:
	var count := clampi(int(a.distance_to(b) / 2.0) + 4, 4, 12)
	var previous := a
	for i in range(1, count + 1):
		var point := a.lerp(b, float(i) / count)
		if i < count:
			point += Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter))
		segment(root, previous, point, radius, color, life, 3.0)
		previous = point

# A short bright slug travelling from muzzle to target so the direction of fire is visible.
static func bolt(root: Node3D, a: Vector3, b: Vector3, length: float, radius: float, color: Color) -> void:
	var distance := a.distance_to(b)
	if distance < length * 1.5:
		return
	var dir := (b - a) / distance
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	node.mesh = mesh
	node.material_override = glow_material(color.lightened(0.5), 3.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	var basis := orient(dir)
	node.global_transform = Transform3D(basis, a + dir * length * 0.5)
	var tween := root.create_tween()
	tween.tween_property(node, "global_position", b - dir * length * 0.5, distance / BOLT_SPEED)
	tween.tween_callback(node.queue_free)

static func flash(root: Node3D, pos: Vector3, radius: float, color: Color, life: float = 0.06) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = glow_material(color.lightened(0.6), 3.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.global_position = pos
	_fade(root, node, life, Vector3.ONE * 0.05)

static func impact(root: Node3D, pos: Vector3, color: Color) -> void:
	flash(root, pos, 0.14, color, 0.08)
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 10
	sparks.lifetime = 0.3
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 120.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -12, 0)
	var bit := BoxMesh.new()
	bit.size = Vector3(0.04, 0.04, 0.04)
	sparks.mesh = bit
	sparks.material_override = glow_material(color.lightened(0.4), 3.0)
	root.add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true
	root.get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)

# Expanding ground ring for area abilities (radius is the final size).
static func ring(root: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.05, radius - 0.12)
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = glow_material(color, 2.5)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.global_position = pos + Vector3.UP * 0.12
	node.scale = Vector3(0.2, 0.6, 0.2)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", Vector3(1.0, 0.05, 1.0), 0.4 * time_scale)
	tween.chain().tween_callback(node.queue_free)

# Wide flat swipe for melee and cone abilities.
static func swoosh(root: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.05, length)
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	var mid := (a + b) * 0.5
	node.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), mid)
	_fade(root, node, 0.18, Vector3(1.2, 0.2, 1.0))

static func tracer(root: Node3D, from: Vector3, to: Vector3, style: int, color: Color, with_impact: bool) -> void:
	if from.distance_to(to) < 0.01:
		return
	match style:
		Style.SKYRUNNER:
			segment(root, from, to, 0.012, color, 0.12)
			bolt(root, from, to, 1.4, 0.03, color)
			flash(root, from, 0.08, color)
		Style.ARC:
			arc(root, from, to, 0.14, 0.018, color.lightened(0.4), 0.1)
		Style.REPAIR:
			arc(root, from, to, 0.05, 0.03, Color("7dff9a"), 0.16)
		Style.ENFORCER:
			segment(root, from, to, 0.03, color, 0.1)
			bolt(root, from, to, 2.4, 0.05, color)
			flash(root, from, 0.14, Color("ffd9a0"))
		Style.MIRAGE:
			segment(root, from, to, 0.01, Color("c7a8f1"), 0.2)
			bolt(root, from, to, 1.6, 0.025, Color("c7a8f1"))
			flash(root, from, 0.07, Color("c7a8f1"))
		Style.BOUNCE:
			segment(root, from, to, 0.014, Color("f0dcff"), 0.32)
		Style.CHARGED:
			segment(root, from, to, 0.06, color, 0.22, 3.0)
			segment(root, from, to, 0.02, Color.WHITE, 0.14, 3.0)
			ring(root, to, 0.8, color)
			flash(root, from, 0.18, color)
		Style.SWOOSH:
			swoosh(root, from, to, 2.4, color)
		Style.CAPSULE:
			segment(root, from, to, 0.07, Color("ffde8d"), 0.3, 3.0)
		_:
			segment(root, from, to, 0.018, color, 0.08, 1.0)
	if with_impact:
		impact(root, to, color)
