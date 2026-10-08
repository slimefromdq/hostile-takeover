class_name MapVerbs
extends RefCounted

# Traversal verbs that live in the map, driven by the "features" list of a blockout (docs/JUNGLE_GYM.md):
#   bounce  awnings and shelters: a trigger box that launches anyone landing in it
#   climb   fire escapes and scaffolding: a volume you climb with forward / back / jump, kick off with jump
#   cable   power lines: "zip" hangs you from the wire, "grind" rides it standing; jump to release
#   mover   a platform on a keyframed timeline (elevators, trams, cranes, drawbridges, collapsing floors, the blimp)
#   event   a timed announcement
# Everything dynamic is a pure function of the match clock (game.map_clock), so a client needs nothing but the clock.
# Fighter.simulate_movement calls pre_move, zip_move and post_move, so server and client prediction agree.

const CLIMB_SPEED := 6.5
const CLIMB_DOWN := 5.0
const CLIMB_STRAFE := 3.0
const CLIMB_KICK := 6.0
const CLIMB_COOLDOWN := 0.3
const ZIP_ACCEL := 22.0
const ZIP_START := 9.0
const ZIP_HANG := 1.75
const ZIP_GRAB := 0.9
const GRIND_GRAB := 0.5
const ZIP_COOLDOWN := 0.4
const BOUNCE_COOLDOWN := 0.25

static var climbs: Array = []     # {box: AABB}
static var bounces: Array = []    # {box: AABB, power: float, kick: Vector3}
static var cables: Array = []     # {a, b, length, mode, speed}
static var movers: Array = []     # {body, keys, period, phase, ease, tag}
static var events: Array = []     # {time, text, fired}

static func clear() -> void:
	climbs.clear()
	bounces.clear()
	cables.clear()
	movers.clear()
	events.clear()

static func is_empty() -> bool:
	return climbs.is_empty() and bounces.is_empty() and cables.is_empty() and movers.is_empty() and events.is_empty()

static func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func box_of(f: Dictionary) -> AABB:
	var lo := vec(f.min)
	return AABB(lo, vec(f.max) - lo)

# Builds runtime state (and the cable and mover nodes under root) from an already mirror-expanded feature list.
static func configure(features: Array, root: Node3D) -> void:
	clear()
	for f in features:
		match f.get("type", ""):
			"climb":
				climbs.append({"box": box_of(f)})
				_add_climb_visual(f, root)
			"bounce":
				bounces.append({"box": box_of(f), "power": float(f.get("power", 15.0)), "kick": vec(f.get("kick", [0, 0, 0]))})
			"cable":
				_add_cable(f, root)
			"mover":
				_add_mover(f, root)
			"event":
				events.append({"time": float(f.get("time", 0.0)), "text": str(f.get("text", "")), "fired": false})

# Every climb lane draws its own ladder (two rails and rungs on the wall side), so the verb reads the same everywhere.
static func _add_climb_visual(f: Dictionary, root: Node3D) -> void:
	var face := str(f.get("face", ""))
	if face == "":
		return
	var box := box_of(f)
	var along_x := face == "+z" or face == "-z"          # the ladder's width runs along x when you face along z
	var lo := box.position
	var hi := box.end
	var plane := 0.0
	match face:
		"-z":
			plane = lo.z + 0.06
		"+z":
			plane = hi.z - 0.06
		"-x":
			plane = lo.x + 0.06
		"+x":
			plane = hi.x - 0.06
	var w0 := (lo.x if along_x else lo.z) + 0.15
	var w1 := (hi.x if along_x else hi.z) - 0.15
	var y0 := lo.y + 0.3
	var y1 := hi.y - 0.7
	if y1 <= y0 or w1 <= w0:
		return
	var transforms: Array[Transform3D] = []
	var rail_h := y1 - y0
	for w in [w0, w1]:
		var centre := Vector3(w, (y0 + y1) * 0.5, plane) if along_x else Vector3(plane, (y0 + y1) * 0.5, w)
		transforms.append(Transform3D(Basis.from_scale(Vector3(0.1, rail_h, 0.1)), centre))
	var y := y0
	while y <= y1:
		var centre := Vector3((w0 + w1) * 0.5, y, plane) if along_x else Vector3(plane, y, (w0 + w1) * 0.5)
		var size := Vector3(w1 - w0, 0.07, 0.07) if along_x else Vector3(0.07, 0.07, w1 - w0)
		transforms.append(Transform3D(Basis.from_scale(size), centre))
		y += 0.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = Visuals.glow(Color(f.get("color", "#3fd96b")), 1.3)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

static func _add_cable(f: Dictionary, root: Node3D) -> void:
	var a := vec(f["from"])
	var b := vec(f["to"])
	var mode: String = f.get("mode", "zip")
	cables.append({"a": a, "b": b, "length": a.distance_to(b), "mode": mode, "speed": float(f.get("speed", 20.0 if mode == "zip" else 16.0))})
	var wire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	wire.mesh = mesh
	wire.material_override = Visuals.glow(Color(f.get("color", "#38d6ff")), 1.6)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wire)
	wire.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.0001:
		wire.global_transform.basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))

static func _add_mover(f: Dictionary, root: Node3D) -> void:
	var size := vec(f.size)
	var body := AnimatableBody3D.new()
	body.name = "Mover_%s" % f.get("tag", "m")
	body.sync_to_physics = true
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	var color := Color(f.get("color", "#a38bff"))
	mesh_node.material_override = Visuals.surface(str(f.get("role", "accent")), color)
	body.add_child(mesh_node)
	root.add_child(body)
	var keys: Array = []
	for k in f.get("keys", []):
		keys.append({"t": float(k[0]), "p": vec(k[1]), "r": vec(k[2]) if k.size() > 2 else Vector3.ZERO})
	movers.append({"body": body, "keys": keys, "period": float(f.get("period", 0.0)), "phase": float(f.get("phase", 0.0)), "ease": bool(f.get("ease", true)), "tag": f.get("tag", "")})
	if not keys.is_empty():
		_pose(movers[-1], 0.0)

# Pose of a mover at match time t: [position, rotation in degrees].
static func pose_at(m: Dictionary, t: float) -> Array:
	var keys: Array = m.keys
	if keys.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	var tt := t - float(m.phase)
	if float(m.period) > 0.0:
		tt = fposmod(tt, float(m.period))
	if tt <= keys[0].t:
		return [keys[0].p, keys[0].r]
	for i in range(keys.size() - 1):
		var k0: Dictionary = keys[i]
		var k1: Dictionary = keys[i + 1]
		if tt <= k1.t:
			var u: float = (tt - k0.t) / maxf(0.0001, k1.t - k0.t)
			if m.ease:
				u = u * u * (3.0 - 2.0 * u)
			return [k0.p.lerp(k1.p, u), k0.r.lerp(k1.r, u)]
	return [keys[-1].p, keys[-1].r]

static func _pose(m: Dictionary, t: float) -> void:
	var pose := pose_at(m, t)
	var body: AnimatableBody3D = m.body
	var rot: Vector3 = pose[1]
	# One combined transform: a sync_to_physics body applies position lazily, so setting rotation separately would undo it.
	body.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))), pose[0])

# Called once per physics tick before fighters move.
static func update(t: float, game: Node) -> void:
	for m in movers:
		if is_instance_valid(m.body):
			_pose(m, t)
	for ev in events:
		if t >= ev.time and not ev.fired:
			ev.fired = true
			if game.authoritative:
				game.announce(ev.text)
				if game.multiplayer.has_multiplayer_peer() and game.multiplayer.get_peers().size() > 0:
					game.remote_notice.rpc(ev.text)
		elif t < ev.time:
			ev.fired = false

# ---- fighter hooks ---------------------------------------------------------------------------------

# Runs before normal movement. Returns the jump/dash edges the normal code should still see.
static func pre_move(f: Fighter, dt: float, edges: int, grounded: bool) -> int:
	f.zip_cd = maxf(0.0, f.zip_cd - dt)
	f.bounce_cd = maxf(0.0, f.bounce_cd - dt)
	f.climb_cd = maxf(0.0, f.climb_cd - dt)
	if f.pending_weapon_impulse != Vector3.ZERO or f.weapon_launch_time > 0.0:
		f.zip_id = -1
		f.climbing = false
		return edges  # Do not immediately reattach and swallow a weapon launch.
	if f.zip_id >= 0:
		return edges
	if f.zip_cd <= 0.0 and not cables.is_empty() and not grounded:
		_try_attach(f)
		if f.zip_id >= 0:
			return edges
	var was_climbing := f.climbing
	f.climbing = false
	if f.climb_cd <= 0.0 and not climbs.is_empty():
		var center := f.global_position + Vector3.UP * 0.9
		for c in climbs:
			if c.box.has_point(center):
				if absf(f.movement.y) > 0.2 or f.held & 16 != 0 or was_climbing:
					f.climbing = true
				break
	if f.climbing and edges & 1:
		f.velocity = -f.horizontal_direction() * CLIMB_KICK + Vector3.UP * 8.0
		f.climbing = false
		f.climb_cd = CLIMB_COOLDOWN
		edges &= ~1
	return edges

# Runs after normal velocity is computed, before move_and_slide.
static func post_move(f: Fighter, _dt: float) -> void:
	if f.climbing:
		var up := 0.0
		if f.movement.y < -0.2 or f.held & 16 != 0:
			up = CLIMB_SPEED
		elif f.movement.y > 0.2:
			up = -CLIMB_DOWN
		var side := Basis(Vector3.UP, f.yaw) * Vector3(f.movement.x, 0, 0) * CLIMB_STRAFE
		f.velocity = Vector3(side.x, up, side.z)
		# Topping out: near the top of the lane, step forward onto the platform.
		var center := f.global_position + Vector3.UP * 0.9
		for c in climbs:
			if c.box.has_point(center) and center.y > c.box.end.y - 1.2 and up > 0.0:
				var fwd := f.horizontal_direction() * 4.0
				f.velocity = Vector3(fwd.x, CLIMB_SPEED + 1.0, fwd.z)
		return
	if f.bounce_cd <= 0.0 and f.velocity.y <= 3.0 and not bounces.is_empty():
		var feet := f.global_position + Vector3.UP * 0.1
		for b in bounces:
			if b.box.has_point(feet):
				f.velocity.y = b.power
				f.velocity += b.kick
				f.bounce_cd = BOUNCE_COOLDOWN
				if f.game.authoritative:
					f.game.play_sfx(f.global_position, Sfx.Kind.PAD)
				break

static func closest_t(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)

static func _try_attach(f: Fighter) -> void:
	var hands := f.global_position + Vector3.UP * (ZIP_HANG - 0.1)
	var feet := f.global_position + Vector3.UP * 0.1
	for i in range(cables.size()):
		var c: Dictionary = cables[i]
		var probe := hands if c.mode == "zip" else feet
		var t := closest_t(c.a, c.b, probe)
		var point: Vector3 = c.a.lerp(c.b, t)
		var reach := ZIP_GRAB if c.mode == "zip" else GRIND_GRAB
		if point.distance_to(probe) > reach:
			continue
		if c.mode == "grind" and f.velocity.y > 1.0:
			continue
		var along: Vector3 = (c.b - c.a).normalized()
		var flat := Vector3(f.velocity.x, 0, f.velocity.z)
		var heading := flat if flat.length() > 1.0 else f.horizontal_direction()
		var forward := heading.dot(Vector3(along.x, 0, along.z))
		f.zip_id = i
		f.zip_t = t
		f.zip_dir = 1 if forward >= 0.0 else -1
		f.zip_speed = maxf(ZIP_START, absf(forward) if flat.length() > 1.0 else ZIP_START)
		f.climbing = false
		return

static func detach(f: Fighter, hop: bool) -> void:
	if f.zip_id < 0:
		return
	var c: Dictionary = cables[f.zip_id]
	var along: Vector3 = (c.b - c.a).normalized() * f.zip_dir
	f.velocity = along * f.zip_speed + (Vector3.UP * 8.5 if hop else Vector3.UP * 2.0)
	f.zip_id = -1
	f.zip_cd = ZIP_COOLDOWN

# One tick of riding a cable (caller then runs move_and_slide).
static func zip_move(f: Fighter, dt: float, edges: int) -> void:
	if f.zip_id < 0 or f.zip_id >= cables.size():
		f.zip_id = -1
		return
	if edges & 1:
		detach(f, true)
		return
	var c: Dictionary = cables[f.zip_id]
	f.zip_speed = minf(float(c.speed), f.zip_speed + ZIP_ACCEL * dt)
	f.zip_t += f.zip_dir * f.zip_speed * dt / maxf(0.01, float(c.length))
	if f.zip_t <= 0.0 or f.zip_t >= 1.0:
		f.zip_t = clampf(f.zip_t, 0.0, 1.0)
		detach(f, false)
		return
	var along: Vector3 = (c.b - c.a).normalized()
	var hang := Vector3.DOWN * (ZIP_HANG if c.mode == "zip" else 0.0)
	var target: Vector3 = c.a.lerp(c.b, f.zip_t) + hang
	f.velocity = along * f.zip_dir * f.zip_speed + (target - f.global_position) * 12.0

# After move_and_slide: running into geometry drops you off the wire.
static func zip_after_slide(f: Fighter) -> void:
	if f.zip_id >= 0 and f.get_real_velocity().length() < f.zip_speed * 0.3:
		detach(f, false)
