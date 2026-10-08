class_name Fighter
extends CharacterBody3D

# Every fighter shares one body: the same health, size and movement. What differs is the loadout (scripts/loadout.gd).
const MAX_HEALTH := 200.0
const BODY_RADIUS := 0.42
const SWAP_TIME := 0.25  # primary <-> sidearm; well under any primary reload, so swapping beats reloading mid-fight
# Movement tuning (Source-style: momentum on the ground, strafe-steered air control).
const GRAVITY := 26.0
const JUMP_SPEED := 10.0
const DOUBLE_JUMP_SPEED := 13.5
const WALL_KICK_UP := 10.5
const WALL_KICK_PUSH := 7.5
const DASH_SPEED := 19.0
const DASH_TIME := 0.24
const DASH_COOLDOWN := 2.5
const ARMOR_MAX := 100.0  # armor (kill drops and map items) absorbs damage 1:1 before health; lost on death
const DASH_MIN_VERTICAL := -3.0  # a falling dash still hovers: downward speed is capped when the dash begins
const GROUND_ACCEL := 20.0
const GROUND_FRICTION := 14.0
const AIR_CAP := 1.2
const AIR_CAP_HOT_LAP := 2.0
const AIR_ACCEL := 60.0
const AIR_ACCEL_HOT_LAP := 100.0
const AIR_SPEED_SOFT_CAP := 15.0
const WEAPON_SPEED_CAP := 24.0
const WEAPON_LAUNCH_GRACE := 0.12
const WEAPON_BOOST_TIME := 0.8
# Slide: a short, boosted burst that bleeds speed at a fixed rate and steers by rotating the velocity.
const SLIDE_MIN_SPEED := 5.0
const SLIDE_EXIT_SPEED := 4.5
const SLIDE_ENTRY_SPEED := 9.5
const SLIDE_ENTRY_BOOST_MAX := 1.5
const SLIDE_FRICTION := 8.0
const SLIDE_TURN_RATE := 2.5
const SLIDE_COOLDOWN := 0.6
const SLIDE_DOWNHILL := 16.0
# Slide-jump: jumping out of a slide (or just after one) adds speed up to a cap, so chains cannot run away.
const SLIDE_JUMP_GRACE := 0.15
const SLIDE_JUMP_BOOST := 1.5
const SLIDE_JUMP_SPEED_CAP := 12.0
const SLIDE_JUMP_BOOST_HOT_LAP := 3.0
const SLIDE_JUMP_SPEED_CAP_HOT_LAP := 14.0
# Input forgiveness windows (seconds) and wall-kick probe length (m, was 0.85).
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const WALL_KICK_REACH := 1.1
# Wall run: auto-attaches to a wall you are moving along, holds height with a slow sag, and exits with a wall kick.
const WALL_RUN_MIN_SPEED := 5.0
const WALL_RUN_TIME := 0.9
const WALL_RUN_TIME_HOT_LAP := 1.4
const WALL_RUN_GRAVITY := 0.15
const WALL_RUN_SAG_TIME := 0.3
const WALL_RUN_STICK := 2.0
const WALL_RUN_REACH := 0.85
const WALL_RUN_COOLDOWN := 0.35
const WALL_RUN_SPEED_CAP := 12.0
const WALL_RUN_SPEED_CAP_HOT_LAP := 14.0
const WALL_RUN_MAX_RISE := 1.0
const WALL_RUN_ENTRY_FALL := 3.0
const WALL_RUN_PROBE_ANGLES := [PI / 2.0, -PI / 2.0, PI / 4.0, -PI / 4.0]
# Vault (low ledge: keep running) and ledge grab (high ledge in the air: brief hang, then pull-up).
const VAULT_MAX_HEIGHT := 1.3
const VAULT_MIN_SPEED := 4.5
const VAULT_SPEED_CAP := 12.0
const VAULT_CLEARANCE := 0.4
const VAULT_TIME := 0.4
const LEDGE_TOP_REACH := 0.8
const LEDGE_HANG_TIME := 0.2
const LEDGE_HANG_COOLDOWN := 0.8
const LEDGE_DROP_COOLDOWN := 0.5
const MANTLE_SPEED := 8.5
const MANTLE_HEAD_CLEARANCE := 2.6
const MANTLE_REACH := 1.2
const MANTLE_PROBE_HEIGHTS := [0.45, 1.0, 1.5]
const MANTLE_PROBE_ANGLES := [0.0, 0.5, -0.5]
var game: Node3D
var fighter_id: int = 0
var team: int = 0
var bot: bool = false
var loadout: int = 0  # Loadout.encode(primary, sidearm, utility, melee)
var look: int = 0  # Appearance code: cosmetic only, drawn by CharacterRig
var primary: WeaponSpec
var sidearm: WeaponSpec
var slot: int = 0  # 0 = primary out, 1 = sidearm out
var weapon: WeaponSpec  # the gun in hand (primary or sidearm); ammo and reload_timer belong to it
var pending_weapon_impulse := Vector3.ZERO
var weapon_impulse_sequence := 0
var weapon_launch_time := 0.0
var weapon_boost_time := 0.0
var stowed_ammo: int = 0  # the other gun's magazine, kept while it is holstered
var swap_timer: float = 0.0  # cannot fire until the swap finishes
var utility_cd: float = 0.0
var melee_cd: float = 0.0  # melee recovery; also blocks firing while it runs
var hp: float = MAX_HEALTH
var heal_left: float = 0.0  # health-pack regen still owed (server only); enemy damage cancels it
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
var dead_time: float = 0.0
var hot_lap: float = 0.0
var conceal: float = 0.0
var reveal: float = 0.0
var grapple: Vector3 = Vector3.ZERO
var grapple_time: float = 0.0
var air_dash: bool = true # dash ready; recharges on a timer, not on landing
var air_jump: bool = true # double jump ready; restored only on landing
var dash_cd: float = 0.0
var sliding: bool = false
var slide_cd: float = 0.0
var slide_grace: float = 0.0
var wall_running: bool = false
var wall_run_time: float = 0.0
var wall_run_normal: Vector3 = Vector3.ZERO
var wall_run_cd: float = 0.0
var vault_time: float = 0.0
var vault_velocity: Vector3 = Vector3.ZERO
var hang_time: float = 0.0
var hang_cd: float = 0.0
var ledge_cd: float = 0.0
var coyote_time: float = 0.0
var jump_buffer: float = 0.0
# Map verbs (scripts/map_verbs.gd): cable riding, climbing and cooldowns.
var zip_id: int = -1
var zip_t: float = 0.0
var zip_dir: int = 1
var zip_speed: float = 0.0
var zip_cd: float = 0.0
var climbing: bool = false
var climb_cd: float = 0.0
var bounce_cd: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO
var wall_repeats: int = 0
var armor: float = 0.0  # light armor (dropped by kills): absorbs damage before health, lost on death
var power: int = 0  # active power-up (Items.POWER_*), 0 = none; lost on death
var power_time: float = 0.0
var power_kills: int = 0  # kills scored during the current power-up (server only, drives the streak announcement)
var damagers: Dictionary = {}  # attacker id -> seconds since last hit (server only, for assists)
var knockback_attacker: int = -1  # server-only environmental elimination credit
var knockback_age: float = 0.0
enum BotRole { ATTACK, ROAM, DEFEND }
var spawn_slot: int = 0
var bot_role: int = BotRole.ATTACK
var bot_role_until: float = 0.0
var bot_pause_until: float = 0.0
var bot_roam_node: int = -1
var bot_goal_node: int = -1
var bot_item: int = -1  # entity id of the armor/bubble this bot is detouring for, or -1
var bot_item_until: float = 0.0
var bot_offset: Vector3 = Vector3.ZERO
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
var marker: Label3D
var pivot: Node3D
var camera: Camera3D
var shoulder: float = 1.0
var remote_target: Vector3 = Vector3.ZERO
var has_remote_target := false
var step_timer := 0.0
var dash_time := 0.0
var dash_velocity := Vector3.ZERO
var dash_vertical := 0.0  # vertical speed held for the whole dash (no gravity)
var kills: int = 0
var deaths: int = 0
var power_pickups: int = 0  # power-ups taken this match (scoreboard column)
var equipment: Node3D
var outlines: Array[ShaderMaterial] = []
var outline_side: int = -1

# Right mouse held = aim down sights: the shoulder camera pulls in and zooms hard, so your own
# body is pushed toward the left screen edge, and a near depth-of-field blur softens it. Guns with alternate attacks
# keep the hip camera, both here and in the authority's aim reconstruction.
# The server reconstructs the same camera from the held button (aim_point), so the crosshair stays true.
const ADS_FOV := 42.0
const ADS_ARM_LENGTH := 2.2
const HIP_SIDE := 1.8  # Frame the body at the left third of a 16:9 view, clear of the crosshair.
const ADS_SIDE := 1.1
const ADS_BLUR_DISTANCE := 3.4
const ADS_BLUR_TRANSITION := 1.6
const ADS_BLUR_AMOUNT := 0.2
const ADS_BLEND_RATE := 10.0
const HIP_FOV := 80.0
const HIP_ARM_LENGTH := 3.6
var ads_blend: float = 0.0
var _ads_blur: CameraAttributesPractical

func _update_ads(dt: float) -> void:
	var want := 1.0 if held & 2 and weapon.uses_ads() and hp > 0 and not game.menu.visible else 0.0
	if is_equal_approx(ads_blend, want):
		return
	ads_blend = move_toward(ads_blend, want, dt * ADS_BLEND_RATE)
	camera.fov = lerpf(HIP_FOV, ADS_FOV, ads_blend)
	(pivot.get_child(0) as SpringArm3D).spring_length = lerpf(HIP_ARM_LENGTH, ADS_ARM_LENGTH, ads_blend)
	if ads_blend > 0.0:
		if _ads_blur == null:
			_ads_blur = CameraAttributesPractical.new()
			_ads_blur.dof_blur_near_enabled = true
			_ads_blur.dof_blur_near_distance = ADS_BLUR_DISTANCE
			_ads_blur.dof_blur_near_transition = ADS_BLUR_TRANSITION
		_ads_blur.dof_blur_amount = ADS_BLUR_AMOUNT * ads_blend
		camera.attributes = _ads_blur
	else:
		camera.attributes = null
	update_visual()

func _process(dt: float) -> void:
	if game != null and fighter_id == game.local_id:
		_update_ads(dt)
	if game != null and not game.authoritative and fighter_id != game.local_id and has_remote_target:
		global_position = global_position.lerp(remote_target, minf(1.0, dt * 20))
	if is_instance_valid(equipment) and hp > 0:
		var planar := Vector2(velocity.x, velocity.z).length()
		var slide: bool = held & 8 != 0 and is_on_floor() and planar > 5.0
		CharacterRig.animate(equipment, dt, planar, is_on_floor(), pitch, slide, melee_cd)

func configure(owner_game: Node3D, id: int, side: int, loadout_code: int, is_bot: bool, look_code: int = -1) -> void:
	game = owner_game
	fighter_id = id
	team = side
	bot = is_bot
	look = Appearance.default_code() if look_code < 0 else Appearance.sanitize(look_code)
	equip(loadout_code)
	hp = MAX_HEALTH
	name = "Fighter_%s" % id
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
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
	arm.spring_length = HIP_ARM_LENGTH
	arm.collision_mask = 1 | 4
	arm.margin = 0.18
	arm.position.x = HIP_SIDE
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = HIP_FOV
	camera.near = 0.1
	camera.far = 500.0
	arm.add_child(camera)
	update_visual()

func build_rig() -> void:
	outlines.clear()
	outline_side = -1
	var ids := Loadout.decode(loadout)
	equipment = CharacterRig.build(self, game.team_color(team), outlines, false, ids[0], ids[1], ids[3], look)
	CharacterRig.set_active_slot(equipment, slot)
	if is_instance_valid(trail):
		trail.queue_free()
	# Speed trail: shown while moving fast or in the Grapple's Hot Lap window.
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

# Kill feed and scoreboard name.
func callsign() -> String:
	return ("Bot %d" if bot else "Player %d") % fighter_id

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
	var ads := 1.0 if held & 2 != 0 and weapon.uses_ads() else 0.0
	var back := basis * Vector3(lerpf(HIP_SIDE, ADS_SIDE, ads) * shoulder, 0, lerpf(HIP_ARM_LENGTH, ADS_ARM_LENGTH, ads))
	var wall: Dictionary = game.ray(origin, origin + back, [get_rid()], 1 | 4)
	var cam: Vector3 = origin + back if wall.is_empty() else wall.position + wall.normal * 0.2
	var aim_reach := weapon.reach
	var hit: Dictionary = game.ray(cam, cam + direction() * aim_reach, [get_rid()], 1 | 2 | 4 | 8)
	return cam + direction() * aim_reach if hit.is_empty() else hit.position

func simulate_movement(dt: float, movement_edges: int) -> void:
	if hp <= 0:
		zip_id = -1
		climbing = false
		sliding = false
		wall_running = false
		vault_time = 0.0
		hang_time = 0.0
		return
	idle_weapon += dt
	if held & 3:
		idle_weapon = 0.0
	hot_lap = maxf(0, hot_lap - dt)
	var was_grappling := grapple_time > 0
	grapple_time = maxf(0, grapple_time - dt)
	if was_grappling and grapple_time <= 0:
		hot_lap = 2.0
	dash_cd = maxf(0.0, dash_cd - dt)
	slide_cd = maxf(0.0, slide_cd - dt)
	if dash_cd <= 0.0:
		air_dash = true
	weapon_launch_time = maxf(0.0, weapon_launch_time - dt)
	weapon_boost_time = maxf(0.0, weapon_boost_time - dt)
	var grounded := is_on_floor() and weapon_launch_time <= 0.0
	if grounded:
		weapon_boost_time = 0.0
		air_jump = true
		wall_repeats = 0
		wall_normal = Vector3.ZERO
	movement_edges = MapVerbs.pre_move(self, dt, movement_edges, grounded)
	if zip_id >= 0:
		sliding = false
		wall_running = false
		vault_time = 0.0
		hang_time = 0.0
		MapVerbs.zip_move(self, dt, movement_edges)
		move_and_slide()
		MapVerbs.zip_after_slide(self)
		update_visual()
		return
	var desired := Basis(Vector3.UP, yaw) * Vector3(movement.x, 0, movement.y)
	var speed := (8.0 if idle_weapon >= 1.25 else 6.0) * weapon.move_speed_mult
	_update_slide_state(grounded, dt)
	dash_time = maxf(0.0, dash_time - dt)
	if pending_weapon_impulse == Vector3.ZERO and weapon_launch_time <= 0.0:
		_update_wall_run(grounded, desired, dt)
	if sliding:
		_slide_step(desired, dt)
	elif grounded:
		var rate := GROUND_ACCEL if desired.length() > 0.05 else GROUND_FRICTION
		velocity.x = move_toward(velocity.x, desired.x * speed, rate * dt)
		velocity.z = move_toward(velocity.z, desired.z * speed, rate * dt)
	elif wall_running:
		_wall_run_step(dt)
	elif dash_time > 0.0:
		velocity.x = dash_velocity.x
		velocity.z = dash_velocity.z
		velocity.y = dash_vertical
	else:
		_air_steer(desired, dt)
	if not grounded:
		var gravity_scale := 1.0
		if dash_time > 0.0:
			gravity_scale = 0.0
		elif wall_running:
			gravity_scale = lerpf(1.0, WALL_RUN_GRAVITY, clampf(wall_run_time / WALL_RUN_SAG_TIME, 0.0, 1.0))
		velocity.y -= GRAVITY * gravity_scale * dt
	else:
		velocity.y = -0.1
	# Input forgiveness: a press shortly before a landing or wall still counts, and a jump just after
	# walking off an edge is still a ground jump.
	coyote_time = COYOTE_TIME if grounded else maxf(0.0, coyote_time - dt)
	jump_buffer = maxf(0.0, jump_buffer - dt)
	var fresh_press: bool = movement_edges & 1 != 0
	if fresh_press or jump_buffer > 0.0:
		if _try_jump(desired, grounded, fresh_press):
			jump_buffer = 0.0
			vault_time = 0.0
			hang_time = 0.0
		elif fresh_press:
			jump_buffer = JUMP_BUFFER
	if movement_edges & 2 and not grounded and air_dash:
		air_dash = false
		dash_cd = DASH_COOLDOWN
		_end_wall_run()
		vault_time = 0.0
		hang_time = 0.0
		var dash_dir := desired.normalized() if desired.length() > 0.1 else horizontal_direction()
		dash_time = DASH_TIME
		dash_velocity = dash_dir * DASH_SPEED
		if game.authoritative:
			game.play_sfx(global_position, Sfx.Kind.DASH)
		dash_vertical = maxf(velocity.y, DASH_MIN_VERTICAL)
		velocity = dash_velocity + Vector3.UP * dash_vertical
	if grapple_time > 0:
		velocity += (grapple - global_position).normalized() * 32.0 * dt
		velocity = velocity.limit_length(23.0)
		if global_position.distance_to(grapple) < 1.5:
			grapple_time = 0.0
			hot_lap = 2.0
	MapVerbs.post_move(self, dt)
	_consume_weapon_impulse()
	if weapon_launch_time <= 0.0:
		_ledge_step(desired, grounded, dt)
	move_and_slide()
	step_timer -= dt
	if game.authoritative and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 2 and step_timer <= 0:
		step_timer = 0.36
		game.play_sfx(global_position, Sfx.Kind.STEP)
	if global_position.y < -12.0 and game.authoritative:
		game.damage_fighter(self, 10000, -1)
	update_visual()

# Slide starts on the ground above SLIDE_MIN_SPEED with a small entry boost, and ends on release,
# leaving the ground, or dropping below SLIDE_EXIT_SPEED (hysteresis stops it flickering).
func _update_slide_state(grounded: bool, dt: float) -> void:
	slide_grace = SLIDE_JUMP_GRACE if sliding else maxf(0.0, slide_grace - dt)
	var planar := Vector2(velocity.x, velocity.z)
	var wants: bool = held & 8 != 0 and grounded
	if sliding:
		if not wants or planar.length() < SLIDE_EXIT_SPEED:
			sliding = false
			slide_cd = SLIDE_COOLDOWN
	elif wants and slide_cd <= 0.0 and planar.length() >= SLIDE_MIN_SPEED:
		sliding = true
		var boost := clampf(SLIDE_ENTRY_SPEED - planar.length(), 0.0, SLIDE_ENTRY_BOOST_MAX)
		var boosted := planar + planar.normalized() * boost
		velocity.x = boosted.x
		velocity.z = boosted.y

# Input turns the velocity toward the wish direction without losing speed; friction then sets the
# slide's length. Pushing straight back neither steers nor brakes extra, and slopes add speed.
func _slide_step(desired: Vector3, dt: float) -> void:
	var planar := Vector2(velocity.x, velocity.z)
	var wish := Vector2(desired.x, desired.z)
	var wish_len := wish.length()
	if wish_len > 0.05 and planar.length() > 0.01:
		var angle := planar.angle_to(wish / wish_len)
		if absf(angle) > PI / 2.0:
			angle = signf(angle) * (PI - absf(angle))
		var max_turn := SLIDE_TURN_RATE * wish_len * dt
		planar = planar.rotated(clampf(angle, -max_turn, max_turn))
	planar = planar.move_toward(Vector2.ZERO, SLIDE_FRICTION * dt)
	velocity.x = planar.x
	velocity.z = planar.y
	velocity += Vector3.DOWN.slide(get_floor_normal()) * SLIDE_DOWNHILL * dt

# Jumping out of a slide keeps the slide's speed and adds a little, up to a cap. Consumes the slide.
func _slide_jump_boost() -> void:
	var hot := hot_lap > 0.0
	var planar := Vector2(velocity.x, velocity.z)
	var boost := clampf((SLIDE_JUMP_SPEED_CAP_HOT_LAP if hot else SLIDE_JUMP_SPEED_CAP) - planar.length(), 0.0, SLIDE_JUMP_BOOST_HOT_LAP if hot else SLIDE_JUMP_BOOST)
	if planar.length() > 0.1:
		planar += planar.normalized() * boost
		velocity.x = planar.x
		velocity.z = planar.y
	slide_grace = 0.0
	if sliding:
		sliding = false
		slide_cd = SLIDE_COOLDOWN

func _end_wall_run() -> void:
	if wall_running:
		wall_running = false
		wall_run_cd = WALL_RUN_COOLDOWN

func _wall_ray(dir: Vector3) -> Dictionary:
	var origin := global_position + Vector3.UP
	var hit: Dictionary = game.ray(origin, origin + dir * WALL_RUN_REACH, [get_rid()], 1 | 4)
	if not hit.is_empty() and absf(hit.normal.y) >= 0.3:
		return {}
	return hit

# Attach while airborne, holding forward, at speed along a wall (at most about 45 degrees into it, so
# a head-on hit stays a plain wall kick); stay on while the wall, speed and input hold out.
func _update_wall_run(grounded: bool, desired: Vector3, dt: float) -> void:
	wall_run_cd = maxf(0.0, wall_run_cd - dt)
	if grounded or climbing or grapple_time > 0.0 or dash_time > 0.0:
		_end_wall_run()
		return
	var forward: bool = movement.y < -0.1
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if wall_running:
		wall_run_time -= dt
		var wall := _wall_ray(-wall_run_normal)
		var normal := Vector3(wall.normal.x, 0, wall.normal.z).normalized() if not wall.is_empty() else Vector3.ZERO
		if wall_run_time <= 0.0 or not forward or horizontal.length() < WALL_RUN_MIN_SPEED or normal.dot(wall_run_normal) < 0.7:
			_end_wall_run()
		else:
			wall_run_normal = normal
		return
	if wall_run_cd > 0.0 or not forward or horizontal.length() < WALL_RUN_MIN_SPEED:
		return
	var heading := horizontal.normalized()
	for angle in WALL_RUN_PROBE_ANGLES:
		var wall := _wall_ray(heading.rotated(Vector3.UP, angle))
		if wall.is_empty():
			continue
		var normal := Vector3(wall.normal.x, 0, wall.normal.z).normalized()
		var tangent := horizontal - normal * horizontal.dot(normal)
		var along := tangent.length()
		if along < WALL_RUN_MIN_SPEED or -horizontal.dot(normal) > along or desired.dot(tangent / along) < 0.3:
			continue
		wall_running = true
		wall_run_normal = normal
		wall_run_time = WALL_RUN_TIME_HOT_LAP if hot_lap > 0.0 else WALL_RUN_TIME
		velocity.y = clampf(velocity.y, -WALL_RUN_ENTRY_FALL, WALL_RUN_MAX_RISE)
		return

# Keep speed along the wall (a gentle push into it holds contact); height only sags.
func _wall_run_step(dt: float) -> void:
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var tangent := horizontal - wall_run_normal * horizontal.dot(wall_run_normal)
	if tangent.length() < 0.01:
		_end_wall_run()
		return
	var cap := WALL_RUN_SPEED_CAP_HOT_LAP if hot_lap > 0.0 else WALL_RUN_SPEED_CAP
	var speed := move_toward(tangent.length(), cap, 18.0 * dt) if tangent.length() > cap else tangent.length()
	var run := tangent.normalized() * speed - wall_run_normal * WALL_RUN_STICK
	velocity.x = run.x
	velocity.z = run.z
	velocity.y = minf(velocity.y, WALL_RUN_MAX_RISE)

# One jump press: ground jump (including coyote time), else wall kick, else the double jump.
# Returns false when nothing was available so the caller can buffer the press. Buffered presses
# never spend the double jump, which only a fresh press may use.
func _try_jump(desired: Vector3, grounded: bool, allow_double: bool) -> bool:
	if grounded or (coyote_time > 0.0 and velocity.y <= 0.0):
		velocity.y = JUMP_SPEED
		coyote_time = 0.0
		if slide_grace > 0.0:
			_slide_jump_boost()
		if game.authoritative:
			game.play_sfx(global_position, Sfx.Kind.JUMP)
		return true
	var origin := global_position + Vector3.UP
	var wall: Dictionary = {"normal": wall_run_normal} if wall_running else game.ray(origin, origin + horizontal_direction() * WALL_KICK_REACH, [get_rid()], 1 | 4)
	if wall.is_empty():
		for offset in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]:
			wall = game.ray(origin, origin + Basis(Vector3.UP, yaw) * offset * WALL_KICK_REACH, [get_rid()], 1 | 4)
			if not wall.is_empty():
				break
	if not wall.is_empty() and absf(wall.normal.y) < 0.3:
		if wall_normal.dot(wall.normal) > 0.9:
			wall_repeats += 1
		else:
			wall_repeats = 0
		wall_normal = wall.normal
		if wall_running:
			velocity += wall.normal * WALL_RUN_STICK # cancel the contact push so the kick is full strength
		_end_wall_run()
		hang_time = 0.0
		hang_cd = LEDGE_HANG_COOLDOWN
		velocity += wall.normal * WALL_KICK_PUSH
		velocity.y = WALL_KICK_UP / (1.0 + wall_repeats * 0.5)
		dash_time = 0.0
		if game.authoritative:
			game.play_sfx(global_position, Sfx.Kind.JUMP)
		return true
	if allow_double and air_jump:
		# One double jump per landing, independent of the dash cooldown.
		air_jump = false
		velocity.y = DOUBLE_JUMP_SPEED
		if game.authoritative:
			game.play_sfx(global_position, Sfx.Kind.JUMP)
		velocity.x += desired.x * 1.5
		velocity.z += desired.z * 1.5
		return true
	return false

# Ledges: low ones are vaulted at speed, high ones reached in the air are grabbed for a moment, and
# anything else in reach is popped over as before. Skipped while wall running or climbing.
func _ledge_step(desired: Vector3, grounded: bool, dt: float) -> void:
	ledge_cd = maxf(0.0, ledge_cd - dt)
	hang_cd = maxf(0.0, hang_cd - dt)
	if grounded:
		hang_time = 0.0
	if vault_time > 0.0:
		vault_time -= dt
		if vault_time > 0.0 and not wall_running and not climbing and not (grounded and vault_time < VAULT_TIME - 0.1):
			velocity.x = vault_velocity.x
			velocity.z = vault_velocity.z
			return
		vault_time = 0.0
	var heading := desired.normalized() if desired.length() > 0.1 else horizontal_direction()
	if hang_time > 0.0:
		if climbing or wall_running or movement.y > 0.5 or held & 8 != 0:
			hang_time = 0.0
			ledge_cd = LEDGE_DROP_COOLDOWN
			return
		hang_time -= dt
		if hang_time > 0.0:
			velocity = Vector3.ZERO
			return
		hang_cd = LEDGE_HANG_COOLDOWN
		velocity.y = MANTLE_SPEED
		return
	if ledge_cd > 0.0 or climbing or wall_running or velocity.y > 4.0 or not (movement.length() > 0.1 or held & 16 != 0):
		return
	var height := _ledge_height(heading)
	if height < 0.0:
		return
	if height <= VAULT_MAX_HEIGHT:
		var speed := clampf(maxf(velocity.dot(heading), VAULT_MIN_SPEED), VAULT_MIN_SPEED, VAULT_SPEED_CAP)
		vault_velocity = heading * speed
		vault_time = VAULT_TIME
		# Just enough lift to clear the ledge by VAULT_CLEARANCE: a fixed MANTLE_SPEED floor threw low steps
		# (0.6 m) 1.4 m into the air, carrying a running fighter clean over a 4 m deep block.
		velocity.y = sqrt(2.0 * GRAVITY * (height + VAULT_CLEARANCE))
	elif not grounded and hang_cd <= 0.0:
		hang_time = LEDGE_HANG_TIME
		velocity = Vector3.ZERO
	else:
		velocity.y = MANTLE_SPEED

# Ledge top height above the feet in the probed direction, or -1.0 when there is nothing to mantle.
func _ledge_height(heading: Vector3) -> float:
	if not _can_mantle(heading):
		return -1.0
	for angle in MANTLE_PROBE_ANGLES:
		var dir := heading.rotated(Vector3.UP, angle)
		var top_origin := global_position + Vector3.UP * MANTLE_HEAD_CLEARANCE + dir * LEDGE_TOP_REACH
		var hit: Dictionary = game.ray(top_origin, top_origin + Vector3.DOWN * (MANTLE_HEAD_CLEARANCE + 0.2), [get_rid()], 1 | 4)
		if not hit.is_empty() and hit.normal.y > 0.7:
			return hit.position.y - global_position.y
	return MANTLE_HEAD_CLEARANCE

# Forgiving ledge probe: several heights and slightly fanned angles, so grazing a ledge still counts.
func _can_mantle(heading: Vector3) -> bool:
	var origin := global_position
	var blocked := false
	for angle in MANTLE_PROBE_ANGLES:
		var dir := heading.rotated(Vector3.UP, angle)
		var high: Dictionary = game.ray(origin + Vector3.UP * MANTLE_HEAD_CLEARANCE, origin + Vector3.UP * MANTLE_HEAD_CLEARANCE + dir * MANTLE_REACH, [get_rid()], 1 | 4)
		if not high.is_empty():
			continue
		for h in MANTLE_PROBE_HEIGHTS:
			var low: Dictionary = game.ray(origin + Vector3.UP * h, origin + Vector3.UP * h + dir * MANTLE_REACH, [get_rid()], 1 | 4)
			if not low.is_empty() and absf(low.normal.y) < 0.3:
				blocked = true
				break
		if blocked:
			return true
	return false

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
	if grapple_time <= 0.0:
		var horizontal := Vector2(velocity.x, velocity.z)
		var cap := WEAPON_SPEED_CAP if weapon_boost_time > 0.0 else AIR_SPEED_SOFT_CAP
		if horizontal.length() > cap:
			var limited := horizontal.move_toward(horizontal.normalized() * cap, 18.0 * dt)
			velocity.x = limited.x
			velocity.z = limited.y

func apply_weapon_impulse(impulse: Vector3) -> void:
	if hp <= 0 or not impulse.is_finite():
		return
	pending_weapon_impulse += impulse
	dash_time = 0.0
	_end_wall_run()
	grapple_time = 0.0
	zip_id = -1
	climbing = false
	vault_time = 0.0
	hang_time = 0.0
	sliding = false

func _consume_weapon_impulse() -> void:
	if pending_weapon_impulse == Vector3.ZERO:
		return
	velocity += pending_weapon_impulse
	var flat := Vector2(velocity.x, velocity.z).limit_length(WEAPON_SPEED_CAP)
	velocity.x = flat.x
	velocity.z = flat.y
	velocity.y = minf(velocity.y, WEAPON_SPEED_CAP)
	pending_weapon_impulse = Vector3.ZERO
	weapon_launch_time = WEAPON_LAUNCH_GRACE
	weapon_boost_time = WEAPON_BOOST_TIME
	weapon_impulse_sequence += 1

# Takes a loadout's guns in hand: the primary out, both magazines full.
func equip(loadout_code: int) -> void:
	var ids := Loadout.decode(loadout_code)
	loadout = Loadout.encode(ids[0], ids[1], ids[2], ids[3])
	primary = Loadout.PRIMARIES[ids[0]]
	sidearm = Loadout.SIDEARMS[ids[1]]
	slot = 0
	weapon = primary
	ammo = primary.magazine
	stowed_ammo = sidearm.magazine

func utility() -> int:
	return Loadout.utility(loadout)

func melee() -> int:
	return Loadout.melee(loadout)

func stowed_weapon() -> WeaponSpec:
	return sidearm if slot == 0 else primary

# Primary <-> sidearm. Each gun keeps its own magazine; a reload in progress is dropped and has to start again.
func swap_weapon() -> void:
	slot = 1 - slot
	weapon = sidearm if slot == 1 else primary
	var held_ammo := ammo
	ammo = stowed_ammo
	stowed_ammo = held_ammo
	reload_timer = 0.0
	burst_left = 0
	swap_timer = SWAP_TIME
	shot_timer = 0.0
	if is_instance_valid(equipment):
		CharacterRig.set_active_slot(equipment, slot)

# A new look rebuilds the rig in place; unlike a loadout it changes nothing about play, so it applies anywhere.
func set_look(look_code: int) -> void:
	var code := Appearance.sanitize(look_code)
	if code == look:
		return
	look = code
	if is_instance_valid(equipment):
		equipment.queue_free()
		build_rig()
		update_visual()

# Respawn or a new loadout: full health, full magazines, fresh cooldowns.
func apply_loadout(loadout_code: int) -> void:
	var before := Loadout.decode(loadout)
	var after := Loadout.decode(loadout_code)
	var rebuild: bool = before[0] != after[0] or before[1] != after[1] or before[3] != after[3]
	equip(loadout_code)
	hp = MAX_HEALTH
	armor = 0.0
	power = 0
	power_time = 0.0
	heal_left = 0.0
	utility_cd = 0.0
	melee_cd = 0.0
	swap_timer = 0.0
	dash_time = 0.0
	dash_cd = 0.0
	sliding = false
	slide_cd = 0.0
	slide_grace = 0.0
	coyote_time = 0.0
	jump_buffer = 0.0
	wall_running = false
	wall_run_cd = 0.0
	vault_time = 0.0
	hang_time = 0.0
	hang_cd = 0.0
	ledge_cd = 0.0
	air_dash = true
	air_jump = true
	reload_timer = 0
	shot_timer = 0
	burst_left = 0
	conceal = 0
	grapple_time = 0
	hot_lap = 0
	damagers.clear()
	knockback_attacker = -1
	knockback_age = 0.0
	pending_weapon_impulse = Vector3.ZERO
	weapon_launch_time = 0.0
	weapon_boost_time = 0.0
	if is_instance_valid(equipment):
		if rebuild:
			equipment.queue_free()
			build_rig()
		else:
			CharacterRig.set_active_slot(equipment, slot)
	update_visual()

func update_visual() -> void:
	if not is_instance_valid(equipment):
		return
	equipment.rotation.y = yaw
	pivot.rotation = Vector3(pitch, yaw, 0)
	pivot.get_child(0).position.x = lerpf(HIP_SIDE, ADS_SIDE, ads_blend) * shoulder
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
		CharacterRig.update_nameplate(nameplate, hp / MAX_HEALTH, Visuals.team_color(team) if is_ally else Visuals.ENEMY_OUTLINE)
	refresh_outline()
	marker.text = "%s%s" % ["BOT · " if bot else "", weapon.title]
	if grapple_time > 0 and not hidden and is_inside_tree():
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
	var state := {"id": fighter_id, "team": team, "lo": loadout, "ap": look, "bot": bot, "pos": global_position, "vel": velocity, "yaw": yaw, "pitch": pitch, "hp": hp, "ammo": ammo, "reload": reload_timer, "conceal": conceal, "reveal": reveal, "dead": dead_time, "idle": idle_weapon, "dash": air_dash, "aj": air_jump, "dcd": dash_cd, "hot": hot_lap, "grapple": grapple, "grapple_time": grapple_time, "k": kills, "d": deaths, "pp": power_pickups, "sl": sliding, "wr": wall_running, "wrt": wall_run_time, "wrn": wall_run_normal, "vt": vault_time, "vv": vault_velocity, "ht": hang_time, "zip": zip_id, "zt": zip_t, "zd": zip_dir, "zs": zip_speed, "climb": climbing}
	if weapon_impulse_sequence > 0:
		state["wi"] = weapon_impulse_sequence
	if weapon_launch_time > 0.0:
		state["wl"] = weapon_launch_time
	if weapon_boost_time > 0.0:
		state["wb"] = weapon_boost_time
	# Optional state is only sent while it matters (snapshots are already past the MTU); unpack supplies defaults.
	if slot != 0:
		state["slot"] = slot
	if stowed_ammo != stowed_weapon().magazine:
		state["ammo2"] = stowed_ammo
	if swap_timer > 0.0:
		state["swap"] = swap_timer
	if utility_cd > 0.0:
		state["ucd"] = utility_cd
	if melee_cd > 0.0:
		state["mcd"] = melee_cd
	if armor >= 1.0:
		state["ar"] = int(ceil(armor))
	if power != 0:
		state["pw"] = power
		state["pwt"] = power_time
	return state

func unpack(data: Dictionary, local: bool) -> void:
	var want_look: int = Appearance.sanitize(data.get("ap", look))
	if loadout != data["lo"] or look != want_look:
		equip(data["lo"])
		look = want_look
		if is_instance_valid(equipment):
			equipment.queue_free()
			build_rig()
	var want_slot: int = data.get("slot", 0)
	if slot != want_slot:
		slot = want_slot
		weapon = sidearm if slot == 1 else primary
		if is_instance_valid(equipment):
			CharacterRig.set_active_slot(equipment, slot)
	var error := global_position.distance_to(data.pos)
	if not local:
		remote_target = data.pos
		if not has_remote_target or error > 8.0 or hp <= 0:
			global_position = data.pos
		has_remote_target = true
	else:
		global_position = data.pos if error > 2.0 or hp <= 0 else global_position.lerp(data.pos, 0.25)
	var impulse_sequence: int = data.get("wi", 0)
	var new_impulse := impulse_sequence != weapon_impulse_sequence
	if new_impulse:
		dash_time = 0.0  # A predicted dash must not overwrite the authority's launch velocity.
		pending_weapon_impulse = Vector3.ZERO
	velocity = data.vel if not local or error > 2.0 or new_impulse else velocity.lerp(data.vel, 0.25)
	weapon_impulse_sequence = impulse_sequence
	weapon_launch_time = data.get("wl", 0.0)
	weapon_boost_time = data.get("wb", 0.0)
	if not local:
		yaw = data.yaw
		pitch = data.pitch
	hp = data.hp
	ammo = data.ammo
	stowed_ammo = data.get("ammo2", stowed_weapon().magazine)
	swap_timer = data.get("swap", 0.0)
	utility_cd = data.get("ucd", 0.0)
	melee_cd = data.get("mcd", 0.0)
	reload_timer = data.reload
	conceal = data.conceal
	reveal = data.reveal
	dead_time = data.dead
	idle_weapon = data.idle
	air_dash = data.dash
	air_jump = data.aj
	dash_cd = data.dcd
	hot_lap = data.hot
	grapple = data.grapple
	grapple_time = data.grapple_time
	sliding = data.get("sl", false)
	wall_running = data.get("wr", false)
	wall_run_time = data.get("wrt", 0.0)
	wall_run_normal = data.get("wrn", Vector3.ZERO)
	vault_time = data.get("vt", 0.0)
	vault_velocity = data.get("vv", Vector3.ZERO)
	hang_time = data.get("ht", 0.0)
	zip_id = data.get("zip", -1)
	zip_t = data.get("zt", 0.0)
	zip_dir = data.get("zd", 1)
	zip_speed = data.get("zs", 0.0)
	climbing = data.get("climb", false)
	armor = float(data.get("ar", 0))
	power = data.get("pw", 0)
	power_time = data.get("pwt", 0.0)
	kills = data.get("k", 0)
	deaths = data.get("d", 0)
	power_pickups = data.get("pp", 0)
	update_visual()
