class_name WeaponProjectile
extends Node3D

# Authority owns collision and damage; clients only extrapolate between world snapshots.
var game: Node3D
var projectile_id: int
var owner_id: int
var team: int
var gun_id: int
var spec: WeaponSpec
var velocity := Vector3.ZERO
var age := 0.0
var travelled := 0.0
var bounces := 0
var damage_scale := 1.0
var source_rid: RID
var shape: SphereShape3D
var visual: MeshInstance3D

func configure(g: Node3D, data: Dictionary) -> void:
	game = g
	projectile_id = data.id
	owner_id = data.o
	team = data.t
	gun_id = data.w
	spec = Loadout.SIDEARMS[gun_id - 16] if gun_id >= 16 else Loadout.PRIMARIES[gun_id]
	global_position = data.p
	velocity = data.v
	age = data.get("a", 0.0)
	bounces = data.get("b", 0)
	shape = SphereShape3D.new()
	shape.radius = spec.projectile_radius
	if game.fighters.has(owner_id):
		source_rid = game.fighters[owner_id].get_rid()
	if DisplayServer.get_name() != "headless":
		visual = MeshInstance3D.new()
		if spec.title == "Disc Launcher":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.18
			disc.bottom_radius = 0.18
			disc.height = 0.06
			disc.radial_segments = 10
			visual.mesh = disc
		else:
			var pod := CapsuleMesh.new()
			pod.radius = spec.projectile_radius
			pod.height = spec.projectile_radius * 2.0 + (0.35 if spec.splash_radius > 0.0 else 0.2)
			pod.radial_segments = 8
			pod.rings = 2
			visual.mesh = pod
		visual.material_override = Visuals.glow(game.team_color(team).lightened(0.3), 3.0)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	update_visual()

func pack() -> Dictionary:
	return {"id": projectile_id, "o": owner_id, "t": team, "w": gun_id, "p": global_position, "v": velocity, "a": age, "b": bounces}

func update_visual() -> void:
	if velocity.length_squared() > 0.01:
		basis = Basis(Vector3.UP, age * 12.0) if spec.title == "Disc Launcher" else Vfx.orient(velocity.normalized())

func sweep(motion: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = motion
	query.collision_mask = 15
	query.exclude = [source_rid] if source_rid.is_valid() else []
	var space := get_world_3d().direct_space_state
	var overlap := space.get_rest_info(query)
	if not overlap.is_empty():
		overlap["fraction"] = 0.0
		overlap["collider"] = instance_from_id(overlap.collider_id)
		return overlap
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0:
		return {}
	query.transform.origin += motion * minf(1.0, fractions[1] + 0.001)
	query.motion = Vector3.ZERO
	var hit := space.get_rest_info(query)
	if hit.is_empty():
		# Even a numerical grazing contact must not advance through the blocking surface.
		var overlaps := space.intersect_shape(query, 1)
		return {"fraction": fractions[0], "collider": null if overlaps.is_empty() else overlaps[0].collider, "normal": -motion.normalized()}
	hit["fraction"] = fractions[0]
	hit["collider"] = instance_from_id(hit.collider_id)
	return hit

func tick(dt: float) -> void:
	age += dt
	if not game.authoritative:
		velocity.y -= spec.projectile_gravity * dt
		global_position += velocity * dt
		update_visual()
		return
	if spec.projectile_fuse > 0.0 and age >= spec.projectile_fuse:
		game.explode_projectile(self)
		return
	velocity.y -= spec.projectile_gravity * dt
	var remaining := dt
	for step in range(4):
		var motion := velocity * remaining
		if spec.projectile_fuse <= 0.0:
			motion = motion.limit_length(maxf(0.0, spec.reach - travelled))
		var hit := sweep(motion)
		if hit.is_empty():
			global_position += motion
			travelled += motion.length()
			break
		var fraction: float = hit.fraction
		global_position += motion * fraction
		travelled += motion.length() * fraction
		var object: Object = hit.collider
		if object is Fighter or object is Deployable:
			if spec.splash_radius > 0.0:
				game.explode_projectile(self, object)
			else:
				game.projectile_hit(self, object, spec.damage)
				game.show_trace(global_position, global_position + Vector3.UP * 0.2, game.team_color(team), Vfx.Style.LINE, true)
				game.remove_projectile(projectile_id)
			return
		if bounces >= spec.projectile_bounces:
			if spec.splash_radius > 0.0:
				game.explode_projectile(self)
			else:
				game.remove_projectile(projectile_id)
			return
		bounces += 1
		velocity = velocity.bounce(hit.normal) * spec.bounce_retention
		global_position += hit.normal * 0.025
		remaining *= 1.0 - fraction
		if remaining < 0.00001:
			break
	if spec.projectile_fuse <= 0.0 and travelled >= spec.reach - 0.001:
		game.remove_projectile(projectile_id)
	update_visual()
