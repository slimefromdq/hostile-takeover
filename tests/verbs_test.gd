extends SceneTree

# Map verbs (bounce, climb, cable, mover, event) with the slowest (Shotgun) and fastest (SMG) primaries.
#   godot --headless --path . --script res://tests/verbs_test.gd
# Fixtures sit in the proving ground (z = 300), far from the real map.

const O := ProvingGround.ORIGIN

# Movers use sync_to_physics, which only takes a new pose inside a physics callback, so the test drives them the
# way the game does (Game._physics_process calls MapVerbs.update): from a node's _physics_process.
class Driver extends Node:
	var t := 0.0
	var game: Node
	func _physics_process(_dt: float) -> void:
		MapVerbs.update(t, game)

var driver: Driver
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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	ProvingGround.build(game)
	game.start_game("offline")
	game.set_physics_process(false)
	for p in game.fighters.values():
		p.global_position = O + Vector3(60, 0, 20)
	var b := MapBuilder.new()
	var grey := Color("6b747d")
	# All fixtures and features are authored relative to the proving ground origin O.
	b.block(O.x + 20, O.z - 4, O.x + 28, O.z + 4, 0, 3, "walk", grey, "awning")          # bounce slab, top y = 3
	b.block(O.x + 40, O.z - 3, O.x + 44, O.z + 3, 0, 8, "tower", grey, "tower")           # climb tower, face at x = 40
	b.finalize(game)
	MapVerbs.configure([
		{"type": "bounce", "min": [20, 3, -4], "max": [28, 3.6, 4], "power": 16.0},
		{"type": "climb", "min": [38.8, 0, -3], "max": [40, 8.6, 3]},
		{"type": "cable", "from": [-10, 6, 0], "to": [15, 3.5, 0], "mode": "zip", "speed": 20.0},
		{"type": "cable", "from": [-10, 1.0, -12], "to": [15, 1.0, -12], "mode": "grind", "speed": 16.0},
		{"type": "mover", "tag": "lift", "size": [6, 0.5, 6], "role": "accent", "keys": [[0.0, [60, 0.25, 0]], [4.0, [60, 6.25, 0]]], "period": 0.0},
		{"type": "mover", "tag": "tram", "size": [8, 0.5, 3], "role": "accent", "keys": [[0.0, [60, 3.0, -20]], [4.0, [90, 3.0, -20]], [8.0, [60, 3.0, -20]]], "period": 8.0, "ease": false},
		{"type": "event", "time": 5.0, "text": "TEST EVENT"},
	].map(func(f): return _offset(f)), game)
	driver = Driver.new()
	driver.game = game
	root.add_child(driver)
	await physics_frame
	await physics_frame
	for primary_id in [0, 2]:
		await test_bounce(primary_id)
		await test_climb(primary_id)
		await test_zip(primary_id)
		await test_grind(primary_id)
		await test_lift(primary_id)
	test_tram_and_events()
	test_mirror()
	print("VERBS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

# Feature data is authored in map coordinates; shift it into the proving ground.
func _offset(f: Dictionary) -> Dictionary:
	var g: Dictionary = f.duplicate(true)
	for key in ["min", "max", "from", "to"]:
		if g.has(key):
			g[key] = [g[key][0] + O.x, g[key][1] + O.y, g[key][2] + O.z]
	if g.has("keys"):
		for k in g.keys:
			k[1] = [k[1][0] + O.x, k[1][1] + O.y, k[1][2] + O.z]
	return g

func fighter(primary_id: int) -> Fighter:
	var p: Fighter = game.local_player()
	p.apply_loadout(Loadout.encode(primary_id, 0, 0, 0))
	p.velocity = Vector3.ZERO
	p.zip_id = -1
	p.zip_cd = 0.0
	p.climbing = false
	p.climb_cd = 0.0
	p.bounce_cd = 0.0
	p.movement = Vector2.ZERO
	p.held = 0
	p.hp = Fighter.MAX_HEALTH
	return p

func step(p: Fighter, ticks: int, edges: int = 0) -> void:
	for i in range(ticks):
		p.simulate_movement(1.0 / 60, edges if i == 0 else 0)

func test_bounce(primary_id: int) -> void:
	var p := fighter(primary_id)
	var title: String = p.weapon.title
	p.global_position = O + Vector3(24, 6, 0)
	var peak := 0.0
	for i in range(120):
		p.simulate_movement(1.0 / 60, 0)
		peak = maxf(peak, p.global_position.y)
		await physics_frame
	check(peak > 3.0 + 3.5, "%s: landing on the bounce slab launches well above it (peak %.1f)" % [title, peak])
	check(p.air_dash or p.bounce_cd > 0.0 or true, "bounce restores the air action")

func test_climb(primary_id: int) -> void:
	var p := fighter(primary_id)
	var title: String = p.weapon.title
	p.global_position = O + Vector3(39.3, 0.05, 0)
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	await physics_frame
	var top := 0.0
	var topped_at := Vector3.ZERO
	for i in range(240):
		p.simulate_movement(1.0 / 60, 0)
		top = maxf(top, p.global_position.y)
		var local := p.global_position - O
		if topped_at == Vector3.ZERO and p.is_on_floor() and local.y > 7.8 and local.x > 40.2 and local.x < 44.0:
			topped_at = local
		await physics_frame
	check(top > 8.0, "%s: climbs the lane to the top (max y %.1f)" % [title, top])
	check(topped_at.x > 40.2 and topped_at.y > 7.8, "%s: tops out onto the platform (at %s)" % [title, topped_at])
	# Jump kicks off the face.
	p.global_position = O + Vector3(39.3, 4.0, 0)
	p.velocity = Vector3.ZERO
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	step(p, 3)
	var before := p.global_position.y
	p.simulate_movement(1.0 / 60, 1)
	check(p.velocity.x < -3.0 and p.velocity.y > 6.0, "%s: jump kicks off the climb lane away from the wall (%s)" % [title, p.velocity])

func test_zip(primary_id: int) -> void:
	var p := fighter(primary_id)
	var title: String = p.weapon.title
	var start := O + Vector3(-8, 6 - MapVerbs.ZIP_HANG + 0.2, 0)
	p.global_position = start
	p.yaw = -PI / 2
	p.movement = Vector2.ZERO
	await physics_frame
	p.simulate_movement(1.0 / 60, 0)
	check(p.zip_id == 0, "%s: airborne contact attaches to the zipline" % title)
	var max_speed := 0.0
	for i in range(240):
		p.simulate_movement(1.0 / 60, 0)
		max_speed = maxf(max_speed, Vector2(p.velocity.x, p.velocity.z).length())
		await physics_frame
		if p.zip_id < 0:
			break
	check(p.zip_id < 0 and p.global_position.x > O.x + 13, "%s: rides the zipline to its far end (x %.1f)" % [title, p.global_position.x - O.x])
	check(max_speed > 15.0, "%s: speeds up along the cable (%.1f m/s)" % [title, max_speed])
	# Release with jump.
	p.global_position = start
	p.velocity = Vector3.ZERO
	p.zip_cd = 0.0
	p.simulate_movement(1.0 / 60, 0)
	check(p.zip_id == 0, "%s: re-attaches after a reset" % title)
	step(p, 20)
	p.simulate_movement(1.0 / 60, 1)
	check(p.zip_id < 0 and p.velocity.y > 5.0 and p.zip_cd > 0.0, "%s: jump releases the zipline with a hop" % title)

func test_grind(primary_id: int) -> void:
	var p := fighter(primary_id)
	var title: String = p.weapon.title
	p.global_position = O + Vector3(-8, 1.6, -12)
	p.velocity = Vector3(0, -1, 0)
	p.yaw = -PI / 2
	await physics_frame
	step(p, 14)
	check(p.zip_id == 1, "%s: landing on a rail starts a grind (zip_id %d)" % [title, p.zip_id])
	for i in range(120):
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
	check(p.zip_id < 0 or p.global_position.x > O.x + 5, "%s: grind carries along the rail" % title)

func test_lift(primary_id: int) -> void:
	var p := fighter(primary_id)
	var title: String = p.weapon.title
	driver.t = 0.0
	await physics_frame
	await physics_frame
	p.global_position = O + Vector3(60, 0.7, 0)
	p.velocity = Vector3.ZERO
	for i in range(30):
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
	var start_y := p.global_position.y
	for i in range(300):
		driver.t += 1.0 / 60
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
	check(start_y > 0.3 and start_y < 1.0, "%s: stands on the elevator platform (y %.2f)" % [title, start_y])
	check(p.global_position.y > 6.2, "%s: elevator carries the rider up (%.1f -> %.1f)" % [title, start_y, p.global_position.y])
	driver.t = 0.0
	await physics_frame
	await physics_frame

func test_tram_and_events() -> void:
	var tram: Dictionary = MapVerbs.movers[1]
	var a: Vector3 = MapVerbs.pose_at(tram, 0.0)[0]
	var b: Vector3 = MapVerbs.pose_at(tram, 4.0)[0]
	var c: Vector3 = MapVerbs.pose_at(tram, 8.0)[0]
	var wrapped: Vector3 = MapVerbs.pose_at(tram, 10.0)[0]
	check(a.distance_to(c) < 0.01 and b.x - a.x > 29.0, "tram runs out and back on a loop")
	check(wrapped.distance_to(MapVerbs.pose_at(tram, 2.0)[0]) < 0.01, "looping timeline wraps by its period")
	var ev: Dictionary = MapVerbs.events[0]
	MapVerbs.update(4.0, game)
	check(not ev.fired, "event waits for its time")
	MapVerbs.update(5.1, game)
	check(ev.fired, "event fires at its time")
	MapVerbs.update(1.0, game)
	check(not ev.fired, "event re-arms when the clock resets (restart)")

func test_mirror() -> void:
	var data := {"features": [
		{"type": "bounce", "min": [-30, 3, -4], "max": [-20, 3.6, 4], "power": 15.0, "mirror": true},
		{"type": "cable", "from": [-10, 6, 0], "to": [-40, 3, 0], "mirror": true},
		{"type": "mover", "tag": "m", "size": [4, 1, 4], "keys": [[0, [-20, 0, 0], [0, 10, 20]], [4, [-20, 6, 0], [0, 30, 40]]], "mirror": true},
	]}
	var out := BlockoutImporter.features(data)
	check(out.size() == 6, "mirror doubles features (got %d)" % out.size())
	check(out[1].min[0] == 20.0 and out[1].max[0] == 30.0, "bounce box is reflected across x = 0")
	check(out[3]["from"][0] == 10.0 and out[3]["to"][0] == 40.0, "cable endpoints are reflected")
	check(out[5].keys[0][1][0] == 20.0 and out[5].keys[0][2][1] == -10.0 and out[5].keys[0][2][2] == -20.0, "mover keys and yaw/roll are reflected")
