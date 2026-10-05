class_name Fighter
extends CharacterBody3D

const SPECS = [preload("res://resources/skyrunner.tres"), preload("res://resources/engineer.tres"), preload("res://resources/enforcer.tres"), preload("res://resources/mirage.tres")]
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
var aim_target: int = -1
var body: MeshInstance3D
var head: MeshInstance3D
var gun: MeshInstance3D
var marker: Label3D
var pivot: Node3D
var camera: Camera3D
var shoulder: float = 1.0
var remote_target: Vector3 = Vector3.ZERO
var remote_velocity: Vector3 = Vector3.ZERO
var has_remote_target := false
var step_timer := 0.0
var equipment: Node3D
var outlines: Array[ShaderMaterial] = []
var outline_side: int = -1

func _process(dt: float) -> void:
	if game != null and not game.authoritative and fighter_id != game.local_id and has_remote_target:
		global_position = global_position.lerp(remote_target, minf(1.0, dt * 20))

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
	body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = 1.5
	body.mesh = mesh
	body.position.y = 0.85
	body.material_override = outlined_material(game.team_color(team), 0.045)
	add_child(body)
	head = MeshInstance3D.new()
	var helmet := BoxMesh.new()
	helmet.size = Vector3(0.5, 0.32, 0.5)
	head.mesh = helmet
	head.position.y = 1.7
	head.material_override = outlined_material(Color("e7e9df"), 0.03)
	add_child(head)
	gun = MeshInstance3D.new()
	var barrel := BoxMesh.new()
	barrel.size = Vector3(0.15 if class_id != 2 else 0.3, 0.18, 0.6)
	gun.mesh = barrel
	gun.material_override = outlined_material(Color("28323f"), 0.025)
	gun.position = Vector3(0.36, 1.3, -0.3)
	add_child(gun)
	equipment = preload("res://scripts/class_identity.gd").build(self, class_id, game.team_color(team))
	marker = Label3D.new()
	marker.position.y = 2.3
	marker.font_size = 30
	marker.pixel_size = 0.008
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = game.team_color(team)
	add_child(marker)
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
	arm.add_child(camera)
	update_visual()

func make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func outlined_material(color: Color, width: float) -> StandardMaterial3D:
	var mat := make_material(color)
	outlines.append(Visuals.add_outline(mat, Visuals.ENEMY_OUTLINE, width))
	return mat

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
	var desired := Basis(Vector3.UP, yaw) * Vector3(movement.x, 0, movement.y)
	var speed := 8.0 if idle_weapon >= 1.25 else 6.0
	if class_id == 2 and held & 1:
		speed *= 0.55
	var sliding: bool = held & 8 != 0 and grounded and Vector2(velocity.x, velocity.z).length() > 5.0
	var acceleration := 28.0 if grounded else (16.0 if hot_lap > 0 else 9.0)
	if sliding:
		var downhill := Vector3.DOWN.slide(get_floor_normal())
		velocity += downhill * 16.0 * dt
		velocity.x = move_toward(velocity.x, desired.x * speed, 2 * dt)
		velocity.z = move_toward(velocity.z, desired.z * speed, 2 * dt)
	else:
		velocity.x = move_toward(velocity.x, desired.x * speed, acceleration * dt)
		velocity.z = move_toward(velocity.z, desired.z * speed, acceleration * dt)
	if not grounded:
		velocity.y -= 22.0 * dt
	else:
		velocity.y = -0.1
	if movement_edges & 1:
		if grounded:
			velocity.y = 8.0
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
				velocity += wall.normal * (8.5 if class_id == 0 else 7.0)
				velocity.y = 8.0 / (1.0 + wall_repeats * 0.6)
				if class_id == 0:
					hot_lap = 2.0
	if movement_edges & 2 and not grounded and air_dash:
		air_dash = false
		var dash_dir := desired.normalized() if desired.length() > 0.1 else horizontal_direction()
		velocity = dash_dir * 16.0 + Vector3.UP * maxf(velocity.y, 1.0)
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
	if held & 16 and not grounded and velocity.y <= 3.0:
		var low: Dictionary = game.ray(global_position + Vector3.UP * 0.7, global_position + Vector3.UP * 0.7 + horizontal_direction() * 0.8, [get_rid()], 1 | 4)
		var high: Dictionary = game.ray(global_position + Vector3.UP * 1.9, global_position + Vector3.UP * 1.9 + horizontal_direction() * 0.8, [get_rid()], 1 | 4)
		if not low.is_empty() and high.is_empty():
			velocity.y = 6.0
	move_and_slide()
	step_timer -= dt
	if game.authoritative and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 2 and step_timer <= 0:
		step_timer = 0.36
		game.play_cue_at(global_position, 75)
	if global_position.y < -12.0 and game.authoritative:
		game.damage_fighter(self, 10000, -1)
	update_visual()

func change_class(value: int) -> void:
	class_id = clampi(value, 0, 3)
	spec = SPECS[class_id]
	hp = spec.health
	ammo = spec.magazine
	cooldowns.assign([0.0, 0.0, 0.0])
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
	if is_instance_valid(body):
		body.mesh.radius = 0.52 if class_id == 2 else 0.38
		get_child(0).shape.radius = 0.52 if class_id == 2 else 0.38
		gun.mesh.size.x = 0.3 if class_id == 2 else 0.15
		if is_instance_valid(equipment):
			equipment.queue_free()
		equipment = preload("res://scripts/class_identity.gd").build(self, class_id, game.team_color(team))
	update_visual()

func update_visual() -> void:
	if not is_instance_valid(body):
		return
	body.rotation.y = yaw
	head.rotation.y = yaw
	gun.rotation.y = yaw
	equipment.rotation.y = yaw
	gun.position = Basis(Vector3.UP, yaw) * Vector3(0.36, 1.3, -0.3)
	pivot.rotation = Vector3(pitch, yaw, 0)
	pivot.get_child(0).position.x = 0.65 * shoulder
	var hidden := hp <= 0
	body.visible = not hidden
	head.visible = not hidden
	gun.visible = not hidden
	equipment.visible = not hidden
	marker.visible = not hidden and fighter_id != game.local_id
	refresh_outline()
	var obscured: bool = conceal > 0 and reveal <= 0 and game.local_team() != team and fighter_id != game.local_id
	if obscured and game.local_player() != null:
		obscured = game.local_player().global_position.distance_to(global_position) > 5.0
	if obscured:
		body.visible = false
		head.visible = false
		gun.visible = false
		equipment.visible = false
		marker.visible = false
	marker.text = "%s%s" % ["BOT · " if bot else "", spec.title]
	if team == game.local_team():
		marker.text += "\n%d / %d" % [int(hp), int(spec.health)]
	collision_layer = 0 if hidden else 2

func pack() -> Dictionary:
	return {"id": fighter_id, "team": team, "class": class_id, "bot": bot, "pos": global_position, "vel": velocity, "yaw": yaw, "pitch": pitch, "hp": hp, "ammo": ammo, "cd": cooldowns, "reload": reload_timer, "conceal": conceal, "reveal": reveal, "dead": dead_time, "double": double_id, "idle": idle_weapon, "dash": air_dash, "hot": hot_lap, "grapple": grapple, "grapple_time": grapple_time, "brake": brake_time, "rush": rush_time, "spin": spin, "gun_buff": gun_buff, "melee_buff": melee_buff}

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
	update_visual()
