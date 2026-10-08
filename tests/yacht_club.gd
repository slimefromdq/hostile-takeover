extends SceneTree

# Real-map hazards, capture interiors and movement shortcuts.
# godot --headless --fixed-fps 60 --path . --script res://tests/yacht_club.gd -- --map=res://maps/yacht_club.blockout.json
var checks := 0
var failures := 0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func place(p: Fighter, at: Vector3) -> void:
	p.apply_loadout(Loadout.encode(0, 0, Loadout.Utility.GRAPPLE, 0))
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.movement = Vector2.ZERO
	p.held = 0
	p.edges = 0
	p.coyote_time = 0
	p.jump_buffer = 0
	p.idle_weapon = 2
	p.slide_cd = 0
	p.hp = Fighter.MAX_HEALTH
	p.wall_repeats = 0
	p.wall_normal = Vector3.ZERO
	p.utility_cd = 0

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_game("offline")
	game.set_physics_process(false)
	check(CivicDividend.goal_names == ["A", "B", "C", "D", "E"] and CivicDividend.kill_floor == -8, "Yacht Club is the active map")
	if CivicDividend.kill_floor != -8:
		quit(1)
		return
	for p in game.fighters.values():
		p.hp = 0
		p.dead_time = 1000
		p.global_position = Vector3(0, -50, 300)
	await physics_frame
	await physics_frame
	var me: Fighter = game.local_player()
	var enemy: Fighter
	for p in game.fighters.values():
		if p.team != me.team:
			enemy = p
			break
	test_capture(me)
	test_hazards(me, enemy)
	test_bot_order(me, enemy)
	await test_vertical_walks(me)
	await test_shortcuts(me)
	game.start_game("restart")
	check(game.match_state.owners == [0, 0, -1, 1, 1] and game.entities.size() == 5, "restart resets objectives and recreates map pickups")
	check(me.knockback_attacker == -1, "restart clears knockback credit")
	print("YACHT CLUB: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func test_capture(me: Fighter) -> void:
	for i in range(5):
		game.match_state.reset()
		game.match_state.unlocked.fill(false)
		game.match_state.unlocked[i] = true
		game.match_state.owners[i] = -1
		place(me, game.points[i] + Vector3.UP * 0.2)
		game.objectives_tick(1.0)
		check(game.match_state.progress[i] > 0, "ground-floor objective %s captures" % String.chr(65 + i))
	for i in [1, 2, 3]:
		for height in [-3.0, 6.0, 7.0]:
			game.match_state.reset()
			game.match_state.unlocked.fill(false)
			game.match_state.unlocked[i] = true
			game.match_state.owners[i] = -1
			place(me, game.points[i] + Vector3.UP * height)
			game.objectives_tick(1.0)
			check(game.match_state.progress[i] == 0, "upper/lower floor cannot capture %s at %.1f" % [String.chr(65 + i), height])
	game.match_state.reset()

func test_hazards(me: Fighter, enemy: Fighter) -> void:
	check(game.ray(Vector3(0, 5, 24), Vector3(0, -10, 24)).is_empty(), "ocean surface has no supporting collider")
	place(me, Vector3(0, -7.9, 30))
	check(not game.out_of_bounds(me.global_position), "recovery is allowed above the ocean threshold")
	check(game.out_of_bounds(Vector3(0, -8.01, 30)), "ocean covers open water within horizontal bounds")
	place(me, Vector3(0, -8.1, 30))
	me.power = Items.POWER_INVULNERABLE
	me.power_time = 12
	me.armor = 20000
	game.cheat_invulnerable = true
	var deaths := me.deaths
	game._physics_process(1.0 / 60)
	check(me.hp == 0 and me.deaths == deaths + 1, "ocean eliminates through armor, power-up and test invulnerability")
	check(game.hud.feed[0].killer == "Ocean", "uncredited ocean death is reported as environmental")
	game.cheat_invulnerable = false
	place(me, Vector3(0, -8.1, 30))
	var kills := enemy.kills
	game.record_knockback(me, enemy.fighter_id)
	game._physics_process(1.0 / 60)
	check(enemy.kills == kills + 1 and me.knockback_attacker == -1, "recent enemy knockback earns the ocean elimination and clears on death")
	place(me, Vector3(0, -8.1, 30))
	game.record_knockback(me, enemy.fighter_id)
	me.knockback_age = game.ASSIST_WINDOW + 0.1
	game._physics_process(1.0 / 60)
	check(enemy.kills == kills + 1, "expired knockback earns no elimination")
	place(me, Vector3(0, -8.1, 30))
	game.record_knockback(me, me.fighter_id)
	check(me.knockback_attacker == -1, "self launches earn no enemy knockback credit")
	place(me, Vector3(0, -7.9, 30))
	game.record_knockback(me, enemy.fighter_id)
	game.combat_tick(me, game.ASSIST_WINDOW + 0.01)
	check(me.knockback_attacker == -1, "server ages and expires knockback credit after six seconds")
	place(me, Vector3(0, -8.1, 24))
	game.authoritative = false
	check(not game.damage_fighter(me, 10000, -1, Vector3.INF, "Ocean", 1.0, true) and me.hp > 0, "clients cannot eliminate ocean victims")
	game.authoritative = true
	game.explore = true
	game._physics_process(1.0 / 60)
	check(me.hp == 0, "Explore retains lethal ocean")
	game.explore = false
	game.respawn(me)
	check(CivicDividend.spawn_protected(me.global_position) and not game.out_of_bounds(me.global_position), "ocean victim respawns safely on yacht")
	check(not game.damage_fighter(me, 50, enemy.fighter_id), "yacht cabin blocks enemy damage")
	game.apply_loadout(me.fighter_id, Loadout.encode(2, 0, 0, 0))
	check(me.primary.title == "SMG", "loadout changes are accepted inside the yacht")
	place(me, game.points[0] + Vector3.UP * 0.2)
	check(game.damage_fighter(me, 50, enemy.fighter_id), "boat-side final objective is not spawn protected")
	game.apply_loadout(me.fighter_id, Loadout.encode(2, 0, 0, 0))
	check(me.primary.title == "Shotgun", "loadout changes are rejected on the final objective")
	me.hp = 0
	me.dead_time = 1000

func tick(p: Fighter, edges: int = 0) -> void:
	p.simulate_movement(1.0 / 60, edges)
	await physics_frame

func test_bot_order(me: Fighter, enemy: Fighter) -> void:
	for p in [me, enemy]:
		place(p, CivicDividend.spawn_slot_position(p.team, 0))
		game.match_state.reset()
		for goal in ([2, 3, 4] if p.team == 0 else [2, 1, 0]):
			check(game.frontier_point(p) == goal, "team %d bot advances toward %s" % [p.team, CivicDividend.goal_names[goal]])
			game.plan_bot_path(p, goal)
			check(not p.bot_path.is_empty() and p.bot_path.back().distance_to(game.points[goal]) < 0.01, "bot path ends at the ordered objective")
			var occupancy := [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
			occupancy[goal][p.team] = 1
			game.match_state.tick(Acquisition.TIMES[goal] + 0.1, occupancy)
		check(game.match_state.winner == p.team, "capturing the opposing yacht landing wins")
		p.hp = 0
		p.dead_time = 1000
		p.global_position = Vector3(0, -50, 300)
	game.match_state.reset()

func test_vertical_walks(p: Fighter) -> void:
	for primary in [0, 2]:
		for prefix in ["", "e_"]:
			for names in [["diag0", "ln", "l0", "l1", "l2", "l3", "l4", "l5"], ["diag2", "r_entry", "r0", "r1", "r_turn", "r2", "r3", "r4"],
				["B", "diag0", "diag1", "diag2", "diag3", "ce", "C"]]:
				var route: Array[Vector3] = []
				for name in names:
					var node: String = "C" if name == "C" else ("D" if prefix == "e_" and name == "B" else prefix + name)
					route.append(game.bot_graph.positions[game.bot_graph.node(node)])
				place(p, route[0] + Vector3.UP * 0.1)
				p.apply_loadout(Loadout.encode(primary, 0, 0, 0))
				p.idle_weapon = 2
				var index := 1
				var frames := 0
				while index < route.size() and frames < 1800:
					var to := route[index] - p.global_position
					if Vector2(to.x, to.z).length() < 0.8 and absf(to.y) < 0.5:
						index += 1
						continue
					p.yaw = atan2(-to.x, -to.z)
					p.movement = Vector2(0, -1)
					await tick(p)
					frames += 1
				check(index == route.size(), "walkable %s%s primary %d (%s)" % [prefix, names[-1], primary, p.global_position])
				print("ROUTE vertical %s%s primary=%d time=%.2f" % [prefix, names[-1], primary, frames / 60.0])

func test_shortcuts(p: Fighter) -> void:
	for primary in [0, 2]:
		for side in [1.0, -1.0]:
			place(p, Vector3(25 * side, -2.9, 11.5 * side))
			p.apply_loadout(Loadout.encode(primary, 0, 0, 0))
			p.idle_weapon = 2
			p.yaw = -PI / 2 if side > 0 else PI / 2
			for i in range(6):
				await tick(p)
			p.velocity = Vector3(9 * side, 0, 0)
			p.held = 8
			p.movement = Vector2(0, -1)
			await tick(p)
			var launched := false
			var landed := false
			var frames := 0
			for i in range(150):
				var edges := 0
				if not launched and p.global_position.x * side >= 27:
					edges = game.EDGE_JUMP
					launched = true
				await tick(p, edges)
				frames += 1
				if p.global_position.x * side > 35.2 and p.is_on_floor():
					landed = true
					break
				if p.global_position.y < -8:
					break
			check(landed, "7 m beam hop primary %d side %.0f lands (%s)" % [primary, side, p.global_position])
			print("ROUTE beam hop primary=%d side=%.0f time=%.2f" % [primary, side, frames / 60.0])
	for side in [1.0, -1.0]:
		place(p, Vector3(37 * side, -2.9, 11.5 * side))
		for i in range(6):
			await tick(p)
		for i in range(3):
			var aim := Vector3(52.25 * side, 1.75, 14.25 * side) - p.muzzle()
			p.yaw = atan2(-aim.x, -aim.z)
			p.pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
		game.use_utility(p)
		check(p.grapple_time > 0, "10 m gap has a reachable grapple anchor")
		p.movement = Vector2(0, -1)
		p.velocity = Vector3(8 * side, 0, 0)
		await tick(p, game.EDGE_JUMP)
		var landed := false
		var frames := 0
		for i in range(180):
			if p.global_position.x * side > 50:
				p.grapple_time = 0
				var landing := Vector3(52 * side, -3, 12 * side) - p.global_position
				p.yaw = atan2(-landing.x, -landing.z)
				p.movement = Vector2(0, -1)
			await tick(p)
			frames += 1
			if p.is_on_floor() and p.global_position.x * side > 49 and p.global_position.y > -3.2:
				landed = true
				break
			if p.global_position.y < -8:
				break
		check(landed, "grapple crosses 10 m ocean gap side %.0f (%s)" % [side, p.global_position])
		print("ROUTE grapple side=%.0f time=%.2f" % [side, frames / 60.0])
	for side in [1.0, -1.0]:
		place(p, Vector3(37 * side, -2.9, 11.5 * side))
		p.apply_loadout(Loadout.encode(3, 0, 0, 0))
		for i in range(6):
			await tick(p)
		p.velocity = Vector3(8 * side, 0, 0)
		p.yaw = PI / 2 if side > 0 else -PI / 2
		p.pitch = -1.35
		var before := p.weapon_impulse_sequence
		check(game.fire_weapon(p), "10 m gap fires a real rocket")
		var target := Vector3(52 * side, -3, 12 * side)
		steer(p, target)
		await tick(p, game.EDGE_JUMP)
		var landed := false
		var double_used := false
		var frames := 0
		for i in range(240):
			game.projectiles_tick(1.0 / 60)
			steer(p, target)
			var edges := 0
			if p.velocity.y < 0 and not double_used:
				edges = game.EDGE_JUMP
				double_used = true
			await tick(p, edges)
			frames += 1
			if p.is_on_floor() and p.global_position.distance_to(target) < 2:
				landed = true
				break
			if p.global_position.y < -8:
				break
		check(landed and p.weapon_impulse_sequence > before, "rocket/double-jump crosses 10 m ocean gap side %.0f (%s)" % [side, p.global_position])
		print("ROUTE rocket gap side=%.0f time=%.2f" % [side, frames / 60.0])
		game.clear_projectiles()
	for side in [1.0, -1.0]:
		place(p, Vector3(51.4 * side, 6.1, -32 * side))
		for i in range(6):
			await tick(p)
		await tick(p, game.EDGE_JUMP)
		var target := Vector3(44 * side, 5.5, -26 * side)
		var to := target - p.global_position
		p.yaw = atan2(-to.x, -to.z)
		p.movement = Vector2(0, -1)
		await tick(p, game.EDGE_JUMP)
		check(p.wall_normal.length() > 0, "lighthouse transfer starts with a real wall kick")
		var landed := false
		var frames := 0
		for i in range(150):
			steer(p, target)
			await tick(p, game.EDGE_JUMP if i == 24 else 0)
			frames += 1
			if p.is_on_floor() and p.global_position.distance_to(target) < 2:
				landed = true
				break
			if p.global_position.y < -8:
				break
		check(landed, "lighthouse wall-kick transfer side %.0f lands (%s)" % [side, p.global_position])
		print("ROUTE lighthouse whip side=%.0f time=%.2f" % [side, frames / 60.0])
	for side in [1.0, -1.0]:
		place(p, Vector3(41 * side, 3.6, -18 * side))
		p.apply_loadout(Loadout.encode(3, 0, 0, 0))
		for i in range(6):
			await tick(p)
		p.velocity = Vector3(-8 * side, 0, 0)
		p.yaw = -PI / 2 if side > 0 else PI / 2
		p.pitch = -1.35
		var impulse_before := p.weapon_impulse_sequence
		check(game.fire_weapon(p), "boathouse launch fires a real rocket")
		var target := Vector3(24 * side, 5.5, -16 * side)
		steer(p, target)
		await tick(p, game.EDGE_JUMP)
		var landed := false
		var frames := 0
		var boosted := false
		var double_used := false
		for i in range(240):
			game.projectiles_tick(1.0 / 60)
			steer(p, target)
			var edges := 0
			if p.velocity.y < 0 and not double_used:
				edges = game.EDGE_JUMP
				double_used = true
			await tick(p, edges)
			frames += 1
			boosted = boosted or p.weapon_impulse_sequence > impulse_before
			if p.is_on_floor() and p.global_position.distance_to(target) < 2:
				landed = true
				break
			if p.global_position.y < -8:
				break
		check(boosted and landed, "boathouse rocket/double-jump side %.0f lands (%s)" % [side, p.global_position])
		print("ROUTE boathouse launch side=%.0f time=%.2f" % [side, frames / 60.0])
		game.clear_projectiles()

func steer(p: Fighter, target: Vector3) -> void:
	# Aim into the turn early: Source air steering preserves sideways momentum.
	var to := target - p.global_position - p.velocity * 0.45
	p.yaw = atan2(-to.x, -to.z)
	p.movement = Vector2(0, -1)
