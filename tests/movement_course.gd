extends SceneTree

# Walks real Fighters through every station of the Movement Course (maps/movement.blockout.json).
#   godot --headless --path . --script res://tests/movement_course.gd
# The course is rebuilt 300 m south of its real position so it never touches the playable map; station
# coordinates below are course coordinates (see docs/MOVEMENT_COURSE.md) shifted by OFF on z.

const OFF := 300.0

var checks := 0
var failures := 0
var game: Node3D

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func at(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z + OFF)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_game("offline")
	game.set_physics_process(false)
	var data := BlockoutImporter.read("res://maps/movement.blockout.json")
	check(not data.is_empty(), "movement course parses")
	for o in data["objects"]:
		o["min"][2] += OFF
		o["max"][2] += OFF
	var b := MapBuilder.new()
	var errors := BlockoutImporter.build(b, data)
	check(errors.is_empty(), "movement course builds without errors: %s" % [errors])
	b.finalize(game)
	for p in game.fighters.values():
		p.global_position = at(60, 0, 20)
	await physics_frame
	await physics_frame
	await test_slide_hill()
	await test_gaps()
	await test_hurdles()
	await test_ledges()
	await test_wall_corridor()
	print("MOVEMENT COURSE: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

# primary_id -1: the reference body, holding a sidearm (move speed multiplier 1.0); 0..2 hold that primary.
func fighter(primary_id: int = -1) -> Fighter:
	var p: Fighter = game.local_player()
	p.apply_loadout(Loadout.encode(maxi(primary_id, 0), 0, 0, 0))
	if primary_id < 0:
		p.swap_weapon()
		p.swap_timer = 0.0
	p.velocity = Vector3.ZERO
	p.movement = Vector2.ZERO
	p.held = 0
	p.hp = Fighter.MAX_HEALTH
	p.idle_weapon = 2.0
	p.wall_normal = Vector3.ZERO
	p.wall_repeats = 0
	return p

func tick(p: Fighter, edges: int = 0) -> void:
	p.simulate_movement(1.0 / 60, edges)
	await physics_frame

# Slide down the 14 degree hill: slope speed makes the slide longer than the 4-5 m it covers on the flat.
func test_slide_hill() -> void:
	var p := fighter()
	p.global_position = at(-32.0, 3.05, -13.0)
	p.yaw = PI / 2 # facing -x, down the ramp
	for i in range(8):
		await tick(p)
	p.velocity = Vector3(-8, 0, 0)
	p.slide_cd = 0.0
	p.held = 8
	var start_x := p.global_position.x
	var frames := 0
	await tick(p)
	var started := p.sliding
	while p.sliding and frames < 180:
		await tick(p)
		frames += 1
	var distance := start_x - p.global_position.x
	check(started, "hill: slide starts on the platform")
	check(distance > 5.5, "hill: sliding downhill goes farther than the flat 4-5 m (%.1f m)" % distance)
	p.held = 0

# Run-jump from a platform edge and report whether the fighter ever stands on a platform whose top is past `target_x`.
# slide: hold slide on the way to the edge and jump out of it (a slide-jump).
func gap_attempt(start_x: float, edge_x: float, target_x: float, slide: bool) -> bool:
	var p := fighter()
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	p.global_position = at(start_x, 1.05, -24.0)
	p.velocity = Vector3(8, 0, 0)
	p.slide_cd = 0.0
	var phase := 0
	var landed := false
	for i in range(200):
		var edges := 0
		if phase == 0 and p.global_position.x >= edge_x - (0.6 if not slide else 0.4):
			if slide:
				p.held = 8
				phase = 1
			else:
				edges = 1
				phase = 2
		elif phase == 1:
			edges = 1
			phase = 2
		await tick(p, edges)
		if phase == 2 and not p.is_on_floor():
			phase = 3
		if phase == 3 and p.is_on_floor() and p.global_position.y > 0.9 and p.global_position.x > target_x:
			landed = true
			break
	p.held = 0
	return landed

# Gaps between the 1 m platforms (5, 7, 9 m): a run-jump clears 5 m, only a slide-jump clears 7 m.
func test_gaps() -> void:
	var plain5 := await gap_attempt(-44.0, -36.0, -31.0, false)
	check(plain5, "gap 5 m: a run-jump lands on the next platform")
	var plain7 := await gap_attempt(-30.5, -25.0, -18.0, false)
	check(not plain7, "gap 7 m: a plain run-jump falls short")
	var slide7 := await gap_attempt(-30.5, -25.0, -18.0, true)
	check(slide7, "gap 7 m: a slide-jump reaches the far platform")

# Run at the 1.1 m hurdles along x = 10..43: each should be vaulted at speed, not stopped by.
func test_hurdles() -> void:
	for primary_id in [0, 2]:
		var p := fighter(primary_id)
		var title: String = p.weapon.title
		p.yaw = -PI / 2
		p.movement = Vector2(0, -1)
		p.global_position = at(3.0, 0.05, -14.0)
		p.velocity = Vector3(6, 0, 0)
		var vaults := 0
		var was := false
		for i in range(480):
			await tick(p)
			var now := p.vault_time > 0.0
			if now and not was:
				vaults += 1
			was = now
		check(vaults >= 4 and p.global_position.x > 44.0, "%s: runs the hurdle lane, vaulting %d of 5 (x %.1f)" % [title, vaults, p.global_position.x])

# Ledge ladder at z 8..12: 0.6 m to 2.4 m are mantled from a run, 3.0 m is out of reach; high ledges grab in the air.
func test_ledges() -> void:
	var heights := [0.6, 1.2, 1.8, 2.4, 3.0]
	for i in range(heights.size()):
		var h: float = heights[i]
		var x := 8.0 + 6.0 * i
		var p := fighter()
		p.yaw = 0.0 # facing -z toward the ledge face at z = 12
		p.movement = Vector2(0, -1)
		p.global_position = at(x, 0.05, 17.0)
		p.velocity = Vector3(0, 0, -7)
		var reached := false
		for t in range(180):
			await tick(p)
			if p.is_on_floor() and p.global_position.y > h - 0.2 and p.global_position.z > OFF + 8.0 and p.global_position.z < OFF + 12.0:
				reached = true
				break
		if h <= 2.4:
			check(reached, "ledge %.1f m: mantled from a run" % h)
		else:
			check(not reached, "ledge %.1f m: beyond mantle reach" % h)
	var q := fighter()
	q.yaw = 0.0
	q.global_position = at(26.0, 0.9, 12.5)
	await tick(q)
	q.movement = Vector2(0, -1)
	q.velocity = Vector3(0, 0, -2)
	await tick(q)
	await tick(q)
	check(q.hang_time > 0.0, "ledge 2.4 m: reached in the air it is grabbed")

# Two parallel 8 m walls 7 m apart (z 19 and z 26): wall run one, kick across, wall run the other.
func test_wall_corridor() -> void:
	var p := fighter()
	p.yaw = -PI / 2 # facing +x along the corridor
	p.movement = Vector2(0, -1)
	p.global_position = at(6.0, 4.0, 19.6)
	p.velocity = Vector3(9, 0, 0)
	for i in range(3):
		await tick(p)
	check(p.wall_running and p.wall_run_normal.z > 0.5, "corridor: attaches to the first wall (normal %s)" % p.wall_run_normal)
	for i in range(8):
		await tick(p)
	await tick(p, 1)
	check(not p.wall_running and p.velocity.z > 5.0, "corridor: jump kicks across the corridor (vz %.1f)" % p.velocity.z)
	var reattached := false
	for i in range(120):
		await tick(p)
		if p.wall_running and p.wall_run_normal.z < -0.5:
			reattached = true
			break
	check(reattached, "corridor: wall runs the opposite wall after the kick")
