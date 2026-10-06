extends SceneTree

# Drives every climb lane, bounce pad and cable of the loaded map with the fastest (Skyrunner) and the heaviest
# (Enforcer) hero, and sanity-checks every mover. Needs a map with features (maps/blockout.json).
#   godot --headless --path . --script res://tests/verbs_map.gd

const HEROES := [0, 2]

# Movers use sync_to_physics, which only takes a pose inside a physics callback; this drives them like the game does.
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
	var data := BlockoutImporter.read(BlockoutImporter.ACTIVE_PATH)
	if data.is_empty() or BlockoutImporter.features(data).is_empty():
		print("verbs_map: no blockout with features loaded; nothing to test")
		quit()
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_game("offline")
	game.set_physics_process(false)
	for p in game.fighters.values():
		if p != game.local_player():
			p.global_position = Vector3(0, -50, 0)
	driver = Driver.new()
	driver.game = game
	root.add_child(driver)
	await physics_frame
	await physics_frame
	var features := BlockoutImporter.features(data)
	var counts := {"climb": 0, "bounce": 0, "zip": 0, "grind": 0, "mover": 0}
	for f in features:
		match f.get("type", ""):
			"climb":
				counts.climb += 1
				for hero in HEROES:
					await test_climb(f, hero)
			"bounce":
				counts.bounce += 1
				for hero in HEROES:
					await test_bounce(f, hero)
			"cable":
				counts[f.get("mode", "zip")] += 1
				for hero in HEROES:
					await test_cable(f, hero, false)
					await test_cable(f, hero, true)
			"mover":
				counts.mover += 1
				test_mover(f)
				if _carries_riders(f):
					for hero in HEROES:
						await test_ride(f, hero)
	print("verbs_map: %s" % [counts])
	print("VERBS MAP: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

func fighter(hero: int) -> Fighter:
	var p: Fighter = game.local_player()
	p.change_class(hero)
	p.velocity = Vector3.ZERO
	p.zip_id = -1
	p.zip_cd = 0.0
	p.climbing = false
	p.climb_cd = 0.0
	p.bounce_cd = 0.0
	p.movement = Vector2.ZERO
	p.held = 0
	p.hp = p.spec.health
	return p

func yaw_for(face: String) -> float:
	match face:
		"+x":
			return -PI / 2
		"-x":
			return PI / 2
		"+z":
			return PI
	return 0.0

func label(f: Dictionary, hero: int) -> String:
	return "%s %s (%s)" % [f.get("tag", f.type), f.min if f.has("min") else f.get("from", ""), Fighter.SPECS[hero].title]

# A lane must carry the hero up and top out onto solid ground at its top.
func test_climb(f: Dictionary, hero: int) -> void:
	var lo := MapVerbs.vec(f.min)
	var hi := MapVerbs.vec(f.max)
	var p := fighter(hero)
	p.global_position = Vector3((lo.x + hi.x) / 2.0, lo.y + 0.3, (lo.z + hi.z) / 2.0)
	p.yaw = yaw_for(str(f.get("face", "-z")))
	p.movement = Vector2(0, -1)
	await physics_frame
	var top := p.global_position.y
	for i in range(60 * 14):
		p.simulate_movement(1.0 / 60, 0)
		top = maxf(top, p.global_position.y)
		await physics_frame
		if p.is_on_floor() and p.global_position.y > hi.y - 1.2:
			break
	p.movement = Vector2.ZERO
	for i in range(30):
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
	var surface := hi.y - 0.6
	check(top >= surface - 0.2, "climb reaches the top: %s (peak %.1f of %.1f)" % [label(f, hero), top, surface])
	check(p.is_on_floor() and absf(p.global_position.y - surface) < 0.5, "climb tops out onto solid ground: %s (ended at y %.2f, expected %.1f)" % [label(f, hero), p.global_position.y, surface])

# A pad must launch to the height its power promises (and carry the kick).
func test_bounce(f: Dictionary, hero: int) -> void:
	var lo := MapVerbs.vec(f.min)
	var hi := MapVerbs.vec(f.max)
	var power := float(f.get("power", 15.0))
	var kick := MapVerbs.vec(f.get("kick", [0, 0, 0]))
	var p := fighter(hero)
	var start := Vector3((lo.x + hi.x) / 2.0, hi.y + 2.5, (lo.z + hi.z) / 2.0)
	p.global_position = start
	await physics_frame
	var peak := 0.0
	var fired := false
	for i in range(150):
		p.simulate_movement(1.0 / 60, 0)
		peak = maxf(peak, p.global_position.y)
		fired = fired or p.bounce_cd > 0.0
		await physics_frame
		if fired and p.velocity.y < -4.0:
			break
	var expected := lo.y + power * power / 52.0
	check(fired, "bounce triggers: %s" % label(f, hero))
	check(peak >= expected - 1.0, "bounce reaches its apex: %s (peak %.1f, expected %.1f)" % [label(f, hero), peak, expected])
	if kick.length() > 0.1:
		var moved := Vector3(p.global_position.x - start.x, 0, p.global_position.z - start.z)
		check(moved.dot(kick.normalized()) > 1.5, "bounce kick carries the hero sideways: %s (moved %.1f)" % [label(f, hero), moved.dot(kick.normalized())])

# A cable must catch a hero at either end, carry them along it and drop them on solid ground near the far end.
func test_cable(f: Dictionary, hero: int, reverse: bool) -> void:
	var a := MapVerbs.vec(f["from"])
	var b := MapVerbs.vec(f["to"])
	if reverse:
		var swap := a
		a = b
		b = swap
	var grind: bool = f.get("mode", "zip") == "grind"
	var along := (b - a).normalized()
	var p := fighter(hero)
	var drop := 1.0 if grind else MapVerbs.ZIP_HANG - 0.15
	p.global_position = a.lerp(b, 0.04) + Vector3(0, 1.0 if grind else -drop, 0)
	p.yaw = atan2(-along.x, -along.z)
	# A hero reaches a zip by jumping into it (it needs them airborne), so the first tick is a jump.
	await physics_frame
	var attached := false
	var max_speed := 0.0
	var farthest := 0.0
	for i in range(60 * 12):
		p.simulate_movement(1.0 / 60, 1 if (i == 0 and not grind) else 0)
		attached = attached or p.zip_id >= 0
		max_speed = maxf(max_speed, Vector2(p.velocity.x, p.velocity.z).length())
		farthest = maxf(farthest, (p.global_position - a).dot(along))
		await physics_frame
		if attached and p.zip_id < 0:
			break
	var tag := "%s %s (%s)" % [f.get("tag", "cable"), "reverse" if reverse else "forward", Fighter.SPECS[hero].title]
	check(attached, "cable catches the hero: %s" % tag)
	if grind:
		# A rail runs along a stack or ledge; riding off its end is fine, so only the ride itself is checked.
		check(farthest >= a.distance_to(b) * 0.9, "grind carries the hero along the rail: %s (%.1f of %.1f m)" % [tag, farthest, a.distance_to(b)])
		return
	for i in range(120):
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
		if p.is_on_floor():
			break
	var end_height := b.y - (0.0 if grind else MapVerbs.ZIP_HANG)
	var past := Vector2(p.global_position.x - b.x, p.global_position.z - b.z).dot(Vector2(along.x, along.z))
	check(p.is_on_floor() and p.global_position.y > end_height - 2.5, "cable lands on solid ground near the far end: %s (y %.1f, expected about %.1f)" % [tag, p.global_position.y, end_height])
	check(past < 10.0, "cable does not overshoot its landing by more than 10 m: %s (%.1f m past the end)" % [tag, past])

# Movers: the timeline must be continuous (no teleports) and loops must close.
func test_mover(f: Dictionary) -> void:
	var keys: Array = f.get("keys", [])
	check(keys.size() >= 2, "mover %s has a timeline" % f.get("tag", ""))
	var period := float(f.get("period", 0.0))
	if period > 0.0 and keys.size() >= 2:
		check(MapVerbs.vec(keys[0][1]).distance_to(MapVerbs.vec(keys[-1][1])) < 0.01, "looping mover %s ends where it starts" % f.get("tag", ""))
	var worst := 0.0
	for i in range(1, keys.size()):
		var dt := float(keys[i][0]) - float(keys[i - 1][0])
		if dt > 0.0:
			worst = maxf(worst, MapVerbs.vec(keys[i][1]).distance_to(MapVerbs.vec(keys[i - 1][1])) / dt)
	var tag: String = f.get("tag", "")
	var limit := 30.0 if tag.begins_with("skylight") else 12.0
	check(worst <= limit, "mover %s never exceeds %.0f m/s (worst %.1f)" % [tag, limit, worst])

# A platform without rotation should carry whoever stands on it: stand on its top, let the clock run, stay on it.
func _carries_riders(f: Dictionary) -> bool:
	if str(f.get("tag", "")).begins_with("skylight"):
		return false
	for k in f.get("keys", []):
		if k.size() > 2 and MapVerbs.vec(k[2]).length() > 0.01:
			return false
	return true

func test_ride(f: Dictionary, hero: int) -> void:
	var m: Dictionary = MapVerbs.movers[0]
	for candidate in MapVerbs.movers:
		if candidate.tag == f.get("tag", ""):
			m = candidate
	var size := MapVerbs.vec(f.size)
	# Ride from the moment the platform starts moving (the first key that differs from the start pose).
	var begin := 0.0
	for k in f.keys:
		if MapVerbs.vec(k[1]).distance_to(MapVerbs.vec(f.keys[0][1])) > 0.01:
			begin = maxf(0.0, float(k[0]) - 1.5)
			break
	driver.t = begin
	await physics_frame
	await physics_frame
	var start_pose: Vector3 = MapVerbs.pose_at(m, begin)[0]
	var p := fighter(hero)
	p.global_position = start_pose + Vector3(0, size.y / 2.0 + 0.05, 0)
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
	var worst := 0.0
	var seconds := 6.0
	for i in range(int(seconds * 60)):
		driver.t += 1.0 / 60
		p.simulate_movement(1.0 / 60, 0)
		await physics_frame
		var pose: Vector3 = MapVerbs.pose_at(m, driver.t)[0]
		var off := Vector2(p.global_position.x - pose.x, p.global_position.z - pose.z).length()
		worst = maxf(worst, off)
	var final_pose: Vector3 = MapVerbs.pose_at(m, driver.t)[0]
	var tag := "%s (%s)" % [f.get("tag", "mover"), Fighter.SPECS[hero].title]
	var travelled := final_pose.distance_to(start_pose)
	check(absf(p.global_position.y - (final_pose.y + size.y / 2.0)) < 0.6, "rider stays on top of %s (rider y %.2f, platform top %.2f)" % [tag, p.global_position.y, final_pose.y + size.y / 2.0])
	check(worst < maxf(size.x, size.z) / 2.0 + 1.0, "rider is carried along by %s (worst offset %.1f m over %.1f m travelled)" % [tag, worst, travelled])
	driver.t = 0.0
	await physics_frame
	await physics_frame
