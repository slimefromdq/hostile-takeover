class_name Vfx
extends RefCounted

# Cosmetic combat effects. Damage and hit detection stay on the authority;
# these only change how shots, abilities and impacts are drawn.

enum Style { LINE, PISTOL, REVOLVER, BOUNCE, SWOOSH, GRENADE, PELLET, RIFLE, SMG, ROCKET, PLASMA, LIGHTNING, RAIL, NAIL, DISC }

const BOLT_SPEED := 140.0
# Lifetime multiplier; tests raise it to hold effects still for screenshots.
static var time_scale := 1.0
static var _materials: Dictionary = {}
static var _segment_mesh: CylinderMesh
# Hard cap on live effect nodes under one root: a 20-fighter firefight cannot spike the node count.
const MAX_EFFECT_NODES := 220

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

# Segments are pooled: a unit-radius cylinder scaled per use, returned to the pool when it fades.
static func segment(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, life: float, energy: float = 2.0) -> void:
	var length := a.distance_to(b)
	if length < 0.01 or _live(root) > MAX_EFFECT_NODES:
		return
	var node := _take_segment(root)
	node.material_override = glow_material(color, energy)
	node.visible = true
	node.global_transform = Transform3D(orient((b - a) / length) * Basis.from_scale(Vector3(radius, length, radius)), (a + b) * 0.5)
	var tween := root.create_tween()
	tween.tween_property(node, "scale", Vector3(0.001, length, 0.001), life * time_scale)
	tween.tween_callback(_release_segment.bind(root, node))

# The pool lives on the root node, so it is freed with the root and never shared between roots.
static func _pool(root: Node3D) -> Array:
	if not root.has_meta("fx_pool"):
		root.set_meta("fx_pool", [])
	return root.get_meta("fx_pool")

static func _live(root: Node3D) -> int:
	return root.get_child_count() - _pool(root).size()

static func _take_segment(root: Node3D) -> MeshInstance3D:
	var pool := _pool(root)
	while not pool.is_empty():
		var pooled = pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	if _segment_mesh == null:
		_segment_mesh = CylinderMesh.new()
		_segment_mesh.top_radius = 1.0
		_segment_mesh.bottom_radius = 1.0
		_segment_mesh.height = 1.0
		_segment_mesh.radial_segments = 6
		_segment_mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = _segment_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node

static func _release_segment(root: Node3D, node: MeshInstance3D) -> void:
	if is_instance_valid(node) and is_instance_valid(root):
		node.visible = false
		_pool(root).append(node)

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
	mesh.radial_segments = 8
	mesh.rings = 2
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
	Sfx.play_at(root, pos, Sfx.Kind.IMPACT)
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
	if from.distance_to(to) < 0.01 or _live(root) > MAX_EFFECT_NODES:
		return
	match style:
		Style.LIGHTNING:
			arc(root, from, to, 0.12, 0.025, Color("86dfff"), 0.06)
		Style.RAIL:
			segment(root, from, to, 0.05, Color("d5a0ff"), 0.45, 3.0)
			flash(root, from, 0.18, Color("d5a0ff"))
		Style.ROCKET:
			segment(root, from, to, 0.08, Color("ffb457"), 0.15)
		Style.PLASMA:
			segment(root, from, to, 0.045, Color("76ffe0"), 0.09)
		Style.NAIL:
			segment(root, from, to, 0.02, Color("ffed9b"), 0.1)
		Style.DISC:
			segment(root, from, to, 0.065, Color("a8b8ff"), 0.15)
		Style.PISTOL:
			segment(root, from, to, 0.012, color, 0.12)
			bolt(root, from, to, 1.4, 0.03, color)
			flash(root, from, 0.08, color)
		Style.REVOLVER:
			segment(root, from, to, 0.01, Color("c7a8f1"), 0.2)
			bolt(root, from, to, 1.6, 0.025, Color("c7a8f1"))
			flash(root, from, 0.07, Color("c7a8f1"))
		Style.BOUNCE:
			segment(root, from, to, 0.014, Color("f0dcff"), 0.32)
		Style.PELLET:
			segment(root, from, to, 0.012, Color("ffd9a0"), 0.09, 1.5)
			if from.distance_to(to) > 0.5 and _live(root) < MAX_EFFECT_NODES / 2:
				flash(root, from, 0.16, Color("ffd9a0"))
		Style.RIFLE:
			segment(root, from, to, 0.02, color.lightened(0.3), 0.2, 2.5)
			bolt(root, from, to, 3.0, 0.03, Color.WHITE)
			flash(root, from, 0.1, color)
		Style.SMG:
			segment(root, from, to, 0.008, Color("fff2b8"), 0.06, 1.5)
		Style.SWOOSH:
			swoosh(root, from, to, 2.4, color)
		Style.GRENADE:
			segment(root, from, to, 0.07, Color("ffde8d"), 0.3, 3.0)
		_:
			segment(root, from, to, 0.018, color, 0.08, 1.0)
	if with_impact:
		impact(root, to, color)
