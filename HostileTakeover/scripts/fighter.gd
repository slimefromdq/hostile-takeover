class_name Fighter
extends CharacterBody3D

const SPECS = [preload("res://resources/skyrunner.tres"), preload("res://resources/engineer.tres"), preload("res://resources/enforcer.tres"), preload("res://resources/mirage.tres")]
# Movement tuning (Source-style: momentum on the ground, strafe-steered air control).
const GRAVITY := 26.0
const JUMP_SPEED := 10.0
const DOUBLE_JUMP_SPEED := 9.0
const WALL_KICK_UP := 10.5
const WALL_KICK_PUSH := 7.5
const WALL_KICK_PUSH_SKYRUNNER := 9.0
const DASH_SPEED := 22.0
const DASH_TIME := 0.28
const GROUND_ACCEL := 20.0
const GROUND_FRICTION := 14.0
const AIR_CAP := 1.2
const AIR_CAP_HOT_LAP := 2.0
const AIR_ACCEL := 60.0
const AIR_ACCEL_HOT_LAP := 100.0
const AIR_SPEED_SOFT_CAP := 15.0
const MANTLE_SPEED := 8.5
const MANTLE_HEAD_CLEARANCE := 2.6
var game: Node3D
var fighter_id: int = 0
var team: int = 0
@export var class_id: int = 0
var bot: bool = false
var spec: ClassSpec
var hp: float = 200.0
var ammo: int = 0
var yaw: float = 0.0
var pitch: float = 0.0
var movement: Vector2 = Vector2.ZERO
var held: int = 0
var edges: int = 0
var idle_weapon: float = 2.0
var shot_timer: float = 0.0
var burst_left: int = 0
var burst_timer: float = 0.0
var reload_timer: float = 0.0
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var dead_time: float = 0.0
var hot_lap: float = 0.0
var melee_buff: float = 0.0
var gun_buff: float = 0.0
var consecutive_hits: int = 0
var spin: float = 0.0
var charge: float = 0.0
var conceal: float = 0.0
var reveal: float = 0.0
var grapple: Vector3 = Vector3.ZERO
var grapple_time: float = 0.0
var brake_time: float = 0.0
var rush_time: float = 0.0
var rush_hit: Array[int] = []
var air_dash: bool = true
var wall_normal: Vector3 = Vector3.ZERO
var wall_repeats: int = 0
var double_id: int = -1
var alt_timer: float = 0.0
var bot_think: float = 0.0
var bot_target: Vector3 = Vector3.ZERO
var bot_path: Array[Vector3] = []
var bot_path_i: int = 0
var bot_goal: int = -1
var bot_bias: Dictionary = {}
var bot_progress_pos: Vector3 = Vector3.ZERO
var bot_progress_time: float = 0.0
var aim_target: int = -1
var nameplate: MeshInstance3D
var rope: MeshInstance3D
var trail: CPUParticles3D
var sliding_visual := false
var marker: Label3D
var pivot: Node3D
var camera: Camera3D
var shoulder: float = 1.0
var remote_target: Vector3 = Vector3.ZERO
var remote_velocity: Vector3 = Vector3.ZERO
var has_remote_target := false
var step_timer := 0.0
var dash_time := 0.0
var dash_velocity := Vector3.ZERO
var kills: int = 0
var deaths: int = 0
var equipment: Node3D
var outlines: Array[ShaderMaterial] = []
var outline_side: int = -1

func _process(dt: float) -> void:
	if game != null and not game.authoritative and fighter_id != game.local_id and has_remote_target:
		global_position = global_position.lerp(remote_target, minf(1.0, dt * 20))
	if is_instance_valid(equipment) and hp > 0:
		var planar := Vector2(velocity.x, velocity.z).length()
		var slide: bool = held & 8 != 0 and is_on_floor() and planar > 5.0
		CharacterRig.animate(equipment, dt, class_id, planar, is_on_floor(), pitch, spin, slide)

func configure(owner_game: Node3D, id: int, side: int, archetype: int, is_bot: bool) -> void:
	game = owner_game
	fighter_id = id
	team = side
	bot = is_bot
	class_id = archetype
	spec = SPECS[class_id]
	hp = spec.health
	ammo = spec.magazine
	name = "Fighter_%s" % id
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38 if class_id != 2 else 0.52
	capsule.height = 1.9
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)
	build_rig()
	marker = Label3D.new()
	marker.position.y = 2.3
	marker.font_size = 26
	marker.pixel_size = 0.0075
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = game.team_color(team)
	add_child(marker)
	nameplate = CharacterRig.make_nameplate()
	nameplate.position.y = 2.2
	add_child(nameplate)
	rope = MeshInstance3D.new()
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = 0.02
	rope_mesh.bottom_radius = 0.02
	rope_mesh.height = 1.0
	rope_mesh.radial_segments = 6
	rope.mesh = rope_mesh
	rope.material_override = Visuals.glow(Color("ffe2a3"), 1.5)
	rope.top_level = true
	rope.visible = false
	add_child(rope)
	pivot = Node3D.new()
	pivot.position.y = 1.55
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 3.6
	arm.collision_mask = 1 | 4
	arm.margin = 0.18
	arm.position.x = 0.65
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.1
	camera.far = 500.0
	arm.add_child(camera)
	update_visual()

func make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func build_rig() -> void:
	outlines.clear()
	outline_side = -1
	equipment = CharacterRig.build(self, class_id, game.team_color(team), outlines)
	if is_instance_valid(trail):
		trail.queue_free()
	trail = null
	if class_id == 0:
		trail = CPUParticles3D.new()
		trail.amount = 20
		trail.lifetime = 0.45
		trail.local_coords = false
		trail.emitting = false
		trail.direction = Vector3.ZERO
		trail.spread = 180.0
		trail.initial_velocity_min = 0.2
		trail.initial_velocity_max = 0.6
		trail.gravity = Vector3.ZERO
		var bit := BoxMesh.new()
		bit.size = Vector3(0.07, 0.07, 0.07)
		trail.mesh = bit
		trail.material_override = Visuals.glow(game.team_color(team).lightened(0.3), 2.0)
		trail.position = Vector3(0, 1.0, 0.3)
		equipment.add_child(trail)

# Allies read cool, enemies read red, whatever the team palette is.
func refresh_outline() -> void:
	var local_side: int = game.local_team()
	if local_side == outline_side:
		return
	outline_side = local_side
	var color := Visuals.outline_color_for(team, local_side)
	for outline in outlines:
		outline.set_shader_parameter("outline_color", color)

func direction() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD

func horizontal_direction() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD

func muzzle() -> Vector3:
	return global_position + Vector3.UP * 1.35 + Basis(Vector3.UP, yaw) * Vector3(0.32, 0, -0.45)

func aim_point() -> Vector3:
	var origin := global_position + Vector3.UP * 1.55
	# Reconstruct the shoulder camera on the authority; clients cannot submit hits.
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	var back := basis * Vector3(0.65 * shoulder, 0, 3.6)
	var wall: Dictionary = game.ray(origin, origin + back, [get_rid()], 1 | 4)
	var cam: Vector3 = origin + back if wall.is_empty() else wall.position + wall.normal * 0.2
	var hit: Dictionary = game.ray(cam, cam + direction() * spec.reach, [get_rid()], 1 | 2 | 4 | 8)
	return cam + direction() * spec.reach if hit.is_empty() else hit.position

func simulate_movement(dt: float, movement_edges: int) -> void:
	if hp <= 0:
		return
	idle_weapon += dt
	if held & 3:
		idle_weapon = 0.0
	hot_lap = maxf(0, hot_lap - dt)
	var was_grappling := grapple_time > 0
	grapple_time = maxf(0, grapple_time - dt)
	if was_grappling and grapple_time <= 0:
		hot_lap = 2.0
	brake_time = maxf(0, brake_time - dt)
	rush_time = maxf(0, rush_time - dt)
	var grounded := is_on_floor()
	if grounded:
		air_dash = true
		wall_repeats = 0
		wall_normal = Vector3.ZERO
	var desired := Basis(Vector3.UP, yaw) * Vector3(movement.x, 0, movement.y)
	var speed := 8.0 if idle_weapon >= 1.25 else 6.0
	if class_id == 2 and held & 1:
		speed *= 0.55
	var sliding: bool = held & 8 != 0 and grounded and Vector2(velocity.x, velocity.z).length() > 5.0
	dash_time = maxf(0.0, dash_time - dt)
	if sliding:
		var downhill := Vector3.DOWN.slide(get_floor_normal())
		velocity += downhill * 16.0 * dt
		velocity.x = move_toward(velocity.x, desired.x * speed, 2 * dt)
		velocity.z = move_toward(velocity.z, desired.z * speed, 2 * dt)
	elif grounded:
		var rate := GROUND_ACCEL if desired.length() > 0.05 else GROUND_FRICTION
		velocity.x = move_toward(velocity.x, desired.x * speed, rate * dt)
		velocity.z = move_toward(velocity.z, desired.z * speed, rate * dt)
	elif dash_time > 0.0:
		velocity.x = dash_velocity.x
		velocity.z = dash_velocity.z
	else:
		_air_steer(desired, dt)
	if not grounded:
		velocity.y -= GRAVITY * (0.35 if dash_time > 0.0 else 1.0) * dt
	else:
		velocity.y = -0.1
	if movement_edges & 1:
		if grounded:
			velocity.y = JUMP_SPEED
		else:
			var wall: Dictionary = game.ray(global_position + Vector3.UP, global_position + Vector3.UP + horizontal_direction() * 0.85, [get_rid()], 1 | 4)
			if wall.is_empty():
				for offset in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]:
					wall = game.ray(global_position + Vector3.UP, global_position + Vector3.UP + Basis(Vector3.UP, yaw) * offset * 0.85, [get_rid()], 1 | 4)
					if not wall.is_empty():
						break
			if not wall.is_empty() and absf(wall.normal.y) < 0.3:
				if wall_normal.dot(wall.normal) > 0.9:
					wall_repeats += 1
				else:
					wall_repeats = 0
				wall_normal = wall.normal
				velocity += wall.normal * (WALL_KICK_PUSH_SKYRUNNER if class_id == 0 else WALL_KICK_PUSH)
				velocity.y = WALL_KICK_UP / (1.0 + wall_repeats * 0.5)
				dash_time = 0.0
				air_dash = true
				if class_id == 0:
					hot_lap = 2.0
			elif air_dash:
				# Double jump shares its charge with the air dash (one air action per landing or wall kick).
				air_dash = false
				velocity.y = DOUBLE_JUMP_SPEED
				velocity.x += desired.x * 1.5
				velocity.z += desired.z * 1.5
	if movement_edges & 2 and not grounded and air_dash:
		air_dash = false
		var dash_dir := desired.normalized() if desired.length() > 0.1 else horizontal_direction()
		dash_time = DASH_TIME
		dash_velocity = dash_dir * DASH_SPEED
		velocity = dash_velocity + Vector3.UP * maxf(velocity.y, 1.5)
	if grapple_time > 0:
		velocity += (grapple - global_position).normalized() * 32.0 * dt
		velocity = velocity.limit_length(23.0)
		if global_position.distance_to(grapple) < 1.5:
			grapple_time = 0.0
			hot_lap = 2.0
	if brake_time > 0 and held & 4 and not grounded:
		velocity.x = move_toward(velocity.x, 0.0, 35 * dt)
		velocity.z = move_toward(velocity.z, 0.0, 35 * dt)
		velocity.y = maxf(velocity.y, -1.2)
	if rush_time > 0:
		var rush := horizontal_direction() * 17.0
		velocity.x = rush.x
		velocity.z = rush.z
	# Held jump requests a mantle only against a low wall with clear headroom.
	if held & 16 and not grounded and velocity.y <= 4.0:
		var low: Dictionary = game.ray(global_position + Vector3.UP * 0.7, global_position + Vector3.UP * 0.7 + horizontal_direction() * 0.8, [get_rid()], 1 | 4)
		var high: Dictionary = game.ray(global_position + Vector3.UP * MANTLE_HEAD_CLEARANCE, global_position + Vector3.UP * MANTLE_HEAD_CLEARANCE + horizontal_direction() * 0.8, [get_rid()], 1 | 4)
		if not low.is_empty() and high.is_empty():
			velocity.y = MANTLE_SPEED
	move_and_slide()
	step_timer -= dt
	if game.authoritative and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 2 and step_timer <= 0:
		step_timer = 0.36
		game.play_cue_at(global_position, 75)
	if global_position.y < -12.0 and game.authoritative:
		game.damage_fighter(self, 10000, -1)
	update_visual()

# Source-style air control: input only adds speed along the wish direction up to a small cap, so
# holding forward does nothing at speed and steering comes from strafing while turning the view.
func _air_steer(desired: Vector3, dt: float) -> void:
	var wish_len := desired.length()
	if wish_len > 0.01:
		var wish_dir := desired / wish_len
		var cap := (AIR_CAP_HOT_LAP if hot_lap > 0 else AIR_CAP) * wish_len
		var current := velocity.x * wish_dir.x + velocity.z * wish_dir.z
		var add := cap - current
		if add > 0.0:
			var gain := minf((AIR_ACCEL_HOT_LAP if hot_lap > 0 else AIR_ACCEL) * dt, add)
			velocity.x += wish_dir.x * gain
			velocity.z += wish_dir.z * gain
	# Soft ceiling so strafing and dashes cannot build unbounded speed.
	if grapple_time <= 0.0 and rush_time <= 0.0:
		var horizontal := Vector2(velocity.x, velocity.z)
		if horizontal.length() > AIR_SPEED_SOFT_CAP:
			var limited := horizontal.move_toward(horizontal.normalized() * AIR_SPEED_SOFT_CAP, 18.0 * dt)
			velocity.x = limited.x
			velocity.z = limited.y

func change_class(value: int) -> void:
	class_id = clampi(value, 0, 3)
	spec = SPECS[class_id]
	hp = spec.health
	ammo = spec.magazine
	cooldowns.assign([0.0, 0.0, 0.0])
	dash_time = 0.0
	reload_timer = 0
	shot_timer = 0
	burst_left = 0
	spin = 0
	charge = 0
	conceal = 0
	grapple_time = 0
	rush_time = 0
	brake_time = 0
	hot_lap = 0
	melee_buff = 0
	gun_buff = 0
	consecutive_hits = 0
	if is_instance_valid(equipment):
		get_child(0).shape.radius = 0.52 if class_id == 2 else 0.38
		equipment.queue_free()
		build_rig()
	update_visual()

func update_visual() -> void:
	if not is_instance_valid(equipment):
		return
	equipment.rotation.y = yaw
	pivot.rotation = Vector3(pitch, yaw, 0)
	pivot.get_child(0).position.x = 0.65 * shoulder
	var hidden := hp <= 0
	var local_side: int = game.local_team()
	var is_ally: bool = team == local_side or fighter_id == game.local_id
	var player = game.local_player()
	var distance: float = 0.0
	if player != null and is_inside_tree() and player.is_inside_tree():
		distance = player.global_position.distance_to(global_position)
	var shown := not hidden
	var alpha := 1.0
	if conceal > 0 and reveal <= 0 and not hidden:
		if is_ally:
			alpha = 0.3
		elif distance > 5.0:
			shown = false
	equipment.visible = shown
	CharacterRig.set_alpha(equipment, alpha)
	var plate: bool = shown and fighter_id != game.local_id and (is_ally or distance < 25.0 or reveal > 0)
	marker.visible = plate
	nameplate.visible = plate
	if plate:
		CharacterRig.update_nameplate(nameplate, hp / spec.health, Visuals.team_color(team) if is_ally else Visuals.ENEMY_OUTLINE)
	refresh_outline()
	marker.text = "%s%s" % ["BOT · " if bot else "", spec.title]
	if class_id == 0 and grapple_time > 0 and not hidden and is_inside_tree():
		var hand := muzzle()
		var span := grapple - hand
		var length := span.length()
		if length > 0.1:
			var dir := span / length
			var tilt := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.y) < 0.999 else (Basis.IDENTITY if dir.y > 0 else Basis(Vector3.RIGHT, PI))
			rope.global_transform = Transform3D(tilt * Basis.from_scale(Vector3(1, length, 1)), hand + span * 0.5)
			rope.visible = true
		else:
			rope.visible = false
	else:
		rope.visible = false
	if is_instance_valid(trail):
		trail.emitting = shown and (hot_lap > 0 or Vector2(velocity.x, velocity.z).length() > 9.0)
	collision_layer = 0 if hidden else 2

func pack() -> Dictionary:
	return {"id": fighter_id, "team": team, "class": class_id, "bot": bot, "pos": global_position, "vel": velocity, "yaw": yaw, "pitch": pitch, "hp": hp, "ammo": ammo, "cd": cooldowns, "reload": reload_timer, "conceal": conceal, "reveal": reveal, "dead": dead_time, "double": double_id, "idle": idle_weapon, "dash": air_dash, "hot": hot_lap, "grapple": grapple, "grapple_time": grapple_time, "brake": brake_time, "rush": rush_time, "spin": spin, "gun_buff": gun_buff, "melee_buff": melee_buff, "k": kills, "d": deaths}

func unpack(data: Dictionary, local: bool) -> void:
	if class_id != data["class"]:
		change_class(data["class"])
	var error := global_position.distance_to(data.pos)
	if not local:
		remote_target = data.pos
		if not has_remote_target or error > 8.0 or hp <= 0:
			global_position = data.pos
		has_remote_target = true
	else:
		global_position = data.pos if error > 2.0 or hp <= 0 else global_position.lerp(data.pos, 0.25)
	velocity = data.vel if not local or error > 2.0 else velocity.lerp(data.vel, 0.25)
	if not local:
		yaw = data.yaw
		pitch = data.pitch
	hp = data.hp
	ammo = data.ammo
	cooldowns.assign(data.cd)
	reload_timer = data.reload
	conceal = data.conceal
	reveal = data.reveal
	dead_time = data.dead
	double_id = data.double
	idle_weapon = data.idle
	air_dash = data.dash
	hot_lap = data.hot
	grapple = data.grapple
	grapple_time = data.grapple_time
	brake_time = data.brake
	rush_time = data.rush
	spin = data.spin
	gun_buff = data.gun_buff
	melee_buff = data.melee_buff
	kills = data.get("k", 0)
	deaths = data.get("d", 0)
	update_visual()
