extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
const O := ProvingGround.ORIGIN

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func empty_occupancy() -> Array:
	return [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]

func capture(state: Acquisition, index: int, team: int) -> void:
	var occupancy := empty_occupancy()
	occupancy[index][team] = 1
	state.tick(Acquisition.TIMES[index] + 0.01, occupancy)

func run() -> void:
	test_objectives()
	test_specs()
	test_weapon_specs()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	ProvingGround.build(game)
	game.start_game("offline")
	game.set_physics_process(false)
	for p in game.fighters.values():
		p.global_position = O + Vector3(60, 0, 20)
	await physics_frame
	await process_frame
	await test_movement()
	await test_weapons()
	await test_shared_weapons()
	await test_mirage()
	await test_machinery()
	test_healpack()
	test_authority_and_respawn()
	test_roster_and_roles()
	await test_hud()
	await test_explore()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func test_objectives() -> void:
	var state := Acquisition.new()
	check(state.unlocked == [false, false, true, false, false], "only center unlocked initially")
	capture(state, 2, 0)
	check(state.owners == [0, 0, 0, 1, 1], "center acquisition")
	check(state.unlocked == [false, false, true, true, false], "center and enemy intermediate unlock")
	capture(state, 3, 0)
	check(state.unlocked == [false, false, false, true, true], "advance locks point behind")
	capture(state, 3, 1)
	check(state.unlocked == [false, false, true, true, false], "counterpush restores frontier")
	capture(state, 2, 1)
	check(state.unlocked == [false, true, true, false, false], "counterpush into blue territory")
	capture(state, 1, 1)
	capture(state, 0, 1)
	check(state.winner == 1, "enemy final point wins")
	state.reset()
	capture(state, 2, 0)
	capture(state, 3, 0)
	capture(state, 4, 0)
	check(state.winner == 0, "mirrored final victory")
	state.reset()
	var occupancy := empty_occupancy()
	occupancy[2] = [1, 1]
	state.tick(20, occupancy)
	check(state.progress[2] == 0, "contested point never advances")
	occupancy[2] = [1, 0]
	state.tick(2, occupancy)
	var partial := state.progress[2]
	state.tick(2.9, empty_occupancy())
	check(is_equal_approx(partial, state.progress[2]), "three-second decay grace")
	state.tick(1, empty_occupancy())
	check(state.progress[2] < partial, "abandoned capture decays")
	state.reset()
	state.remaining = 0.1
	state.tick(0.2, occupancy)
	check(state.overtime and state.winner == -2, "active capture triggers overtime")
	state.tick(2.9, empty_occupancy())
	check(state.winner == -2, "overtime grace preserves match")
	state.tick(0.2, empty_occupancy())
	check(state.winner == -1, "equal territory draws after overtime")
	state.reset()
	capture(state, 2, 0)
	state.remaining = 0
	state.tick(0.1, empty_occupancy())
	check(state.winner == 0, "territory leader wins at timer")
	state.reset()
	capture(state, 2, 0)
	state.progress[2] = 0.999
	state.attackers[2] = 1
	state.progress[3] = 0.999
	state.attackers[3] = 0
	occupancy = empty_occupancy()
	occupancy[2] = [0, 1]
	occupancy[3] = [1, 0]
	state.tick(0.1, occupancy)
	check(state.owners == [0, 0, 0, 1, 1], "simultaneous opposing exchange cannot create islands")
	check(state.unlocked.count(true) <= 2, "at most two frontier points unlocked")
	state.reset()
	occupancy = empty_occupancy()
	occupancy[0] = [0, 6]
	state.tick(60, occupancy)
	check(state.owners[0] == 0, "locked points ignore occupancy")
	var packed := state.pack()
	var copy := Acquisition.new()
	copy.unpack(packed)
	check(copy.owners == state.owners and copy.unlocked == state.unlocked, "match snapshot round trip")

func test_specs() -> void:
	var expected := [2.07, 2.8, 2.6, 2.2]
	for i in range(4):
		var spec: ClassSpec = Fighter.SPECS[i]
		print("MODEL TTK %s: %.3fs" % [spec.title, spec.body_ttk()])
		check(absf(spec.body_ttk() - expected[i]) < 0.02, "weapon model target: " + spec.title)
		check(spec.abilities.size() == 3, "three active abilities: " + spec.title)
	check(Fighter.SPECS[0].body_ttk() < Fighter.SPECS[3].body_ttk(), "Skyrunner fastest primary")
	check(35 + Fighter.SPECS[3].damage * 1.35 < 160, "capsule plus one headshot cannot instant kill lowest-health class")
	var limited := ClassSpec.new()
	limited.damage = 50
	limited.magazine = 2
	limited.interval = 0.5
	limited.reload_time = 1.4
	check(is_equal_approx(limited.body_ttk(), 2.4), "weapon model includes reload time")

func test_movement() -> void:
	var p: Fighter = game.local_player()
	p.global_position = O + Vector3(-10, 0.01, -21)
	p.change_class(0)
	p.movement = Vector2(0, -1)
	p.yaw = -PI / 2
	p.held = 0
	p.idle_weapon = 0
	for i in range(80):
		p.simulate_movement(1.0 / 60, 0)
	check(p.idle_weapon >= 1.25 and p.velocity.x > 7.9, "automatic sprint after idle delay")
	p.held = 1
	p.simulate_movement(1.0 / 60, 0)
	check(p.idle_weapon == 0, "primary weapon resets sprint immediately")
	p.held = 2
	p.simulate_movement(1.0 / 60, 0)
	check(p.idle_weapon == 0, "alternate weapon also resets sprint")
	p.held = 0
	p.global_position = O + Vector3(-10, 4, -21)
	p.air_dash = true
	p.simulate_movement(1.0 / 60, 0)
	p.simulate_movement(1.0 / 60, 2)
	check(not p.air_dash and p.velocity.x > 14, "air dash consumed and propels")
	p.global_position = O + Vector3(-10, 0, -21)
	p.velocity = Vector3.ZERO
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
	check(not p.air_dash and p.dash_cd > 2.0, "landing does not restore the dash; 3 s cooldown applies")
	for i in range(190):
		p.simulate_movement(1.0 / 60, 0)
	check(p.air_dash, "dash recharges after its 3 s cooldown")
	for archetype in range(4):
		p.change_class(archetype)
		p.global_position = O + Vector3(88.8, 3, 20)
		p.wall_repeats = 0
		p.wall_normal = Vector3.ZERO
		p.velocity = Vector3.ZERO
		p.yaw = -PI / 2
		p.movement = Vector2.ZERO
		p.simulate_movement(1.0 / 60, 0)
		p.simulate_movement(1.0 / 60, 1)
		check(p.velocity.x < -6 and p.velocity.y >= 10.4, "universal wall kick: " + p.spec.title)
	p.global_position = O + Vector3(-10, 0, -21)
	p.velocity = Vector3.ZERO
	p.movement = Vector2.ZERO
	p.held = 0
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
	p.yaw = 0.0
	p.slide_cd = 0.0
	p.velocity = Vector3(8, 0, 0)
	p.movement = Vector2.ZERO
	p.held = 8
	var slide_start := p.global_position.x
	p.simulate_movement(1.0 / 60, 0)
	check(p.sliding and p.velocity.x > 9.3 and p.velocity.x <= 9.5, "slide entry gives a small capped boost")
	var slide_frames := 0
	while p.sliding and slide_frames < 120:
		p.simulate_movement(1.0 / 60, 0)
		slide_frames += 1
	var slide_distance := p.global_position.x - slide_start
	check(not p.sliding and slide_distance > 3.5 and slide_distance < 5.5, "slide is short: %.2f m" % slide_distance)
	p.simulate_movement(1.0 / 60, 0)
	check(not p.sliding and p.slide_cd > 0.0, "slide cooldown stops back-to-back boosts")
	p.held = 0
	p.global_position = O + Vector3(-10, 0, -21)
	p.velocity = Vector3.ZERO
	p.slide_cd = 0.0
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
	p.velocity = Vector3(9, 0, 0)
	p.movement = Vector2(0, -1)
	p.held = 8
	for i in range(18):
		p.simulate_movement(1.0 / 60, 0)
	check(p.sliding and p.velocity.z < -3.0 and Vector2(p.velocity.x, p.velocity.z).length() > 6.5, "slide steers toward the wish direction without bleeding extra speed")
	p.held = 0
	p.velocity = Vector3.ZERO
	p.simulate_movement(1.0 / 60, 0)
	check(not p.sliding, "releasing slide ends it")
	p.global_position = O + Vector3(-5.2, 0.3, 5)
	p.velocity = Vector3.ZERO
	p.held = 0
	p.simulate_movement(1.0 / 60, 0)
	p.held = 16
	p.velocity.y = 0
	p.simulate_movement(1.0 / 60, 0)
	check(p.velocity.y >= 8.4, "held jump mantles a low ledge")
	p.held = 0
	await physics_frame
	await process_frame
	await test_air_movement()
	await test_input_forgiveness()
	await test_slide_jump()
	test_visual_pipeline()
	test_effect_pool()
	test_sfx()

func aim_at(p: Fighter, target: Vector3) -> void:
	for i in range(12):
		var basis := Basis.from_euler(Vector3(p.pitch, p.yaw, 0))
		var cam := p.global_position + Vector3.UP * 1.55 + basis * Vector3(0.65 * p.shoulder, 0, 3.6)
		var diff := (target - cam).normalized()
		p.yaw = atan2(-diff.x, -diff.z)
		p.pitch = asin(diff.y)

func test_weapons() -> void:
	var p: Fighter = game.local_player()
	var target: Fighter = game.fighters[105]
	target.team = 1 - p.team  # with 10v10 rosters bot 105 starts as a teammate
	for class_index in range(4):
		p.change_class(class_index)
		p.global_position = O + Vector3(-10, 0, -21)
		p.velocity = Vector3.ZERO
		p.held = 1
		p.spin = 1
		target.change_class(1)
		target.global_position = O + Vector3(0, 0, -21)
		target.hp = 200
		target.update_visual()
		await physics_frame
		await process_frame
		aim_at(p, target.global_position + Vector3.UP * 1.1)
		var elapsed := 0.0
		var first_hit := -1.0
		for frame in range(360):
			game.combat_tick(p, 1.0 / 60.0)
			if target.hp < 200 and first_hit < 0:
				first_hit = elapsed
			if target.hp <= 0:
				break
			elapsed += 1.0 / 60.0
		var ttk := elapsed - first_hit
		print("LIVE TTK %s: %.3fs" % [p.spec.title, ttk])
		check(target.hp <= 0, "authoritative primary hits target: " + p.spec.title)
		check(absf(ttk - p.spec.body_ttk()) <= 0.11, "live primary cadence matches model: " + p.spec.title)
	p.held = 0
	# Friendly hits cannot award damage.
	target.change_class(1)
	target.team = p.team
	game.apply_hit(p, {"collider": target, "position": target.global_position + Vector3.UP}, 100)
	check(target.hp == target.spec.health, "friendly fire disabled")
	target.team = 1

func test_mirage() -> void:
	var p: Fighter = game.local_player()
	p.change_class(3)
	p.global_position = O + Vector3(-10, 0.05, -21)
	var pos := O + Vector3(-3, 0.05, -21)
	p.double_id = game.create_entity(p, "double", pos, 45, 8)
	await physics_frame
	await process_frame
	var e: Deployable = game.entities[p.double_id]
	p.velocity = Vector3(3, 2, -4)
	p.yaw = 0.9
	p.ammo = 2
	p.idle_weapon = 0
	var old := p.global_position
	game.activate(p, 0)
	check(p.global_position.is_equal_approx(pos) and e.global_position.is_equal_approx(old), "double exchanges both positions")
	check(p.velocity.is_equal_approx(Vector3(3, 2, -4)) and p.yaw == 0.9, "swap preserves velocity and facing")
	check(e.used and p.ammo == 3 and p.idle_weapon >= 1.25, "swap consumes use and triggers Clean Getaway")
	game.activate(p, 0)
	check(p.global_position.is_equal_approx(pos), "second swap unavailable")
	game.remove_owned(p.fighter_id)
	p.double_id = game.create_entity(p, "double", O + Vector3(9, 0.05, -13), 45, 8)
	await physics_frame
	await process_frame
	var blocked: Deployable = game.entities[p.double_id]
	old = p.global_position
	game.activate(p, 0)
	check(p.global_position.is_equal_approx(old) and not blocked.used, "obstructed swap fails without consuming")
	blocked.hp = 0
	game.activate(p, 0)
	check(p.global_position.is_equal_approx(old), "destroyed double cannot swap before removal tick")
	game.entities_tick(0.01)
	check(p.double_id == -1, "destroying double removes escape")
	p.double_id = game.create_entity(p, "double", game.points[2], 45, 8)
	game.match_state.reset()
	for other in game.fighters.values():
		other.global_position = O + Vector3(60, 0, 20)
	game.objectives_tick(10)
	check(game.match_state.progress[2] == 0 and game.match_state.owners[2] == -1, "double cannot capture or contest")
	game.entities_tick(8.1)
	check(p.double_id == -1, "double expires")
	check(p.collision_mask & 8 == 0, "double collision layer cannot block fighters")
	p.cooldowns[2] = 0
	game.activate(p, 2)
	check(p.conceal == 2.5, "concealment activates")
	p.held = 1
	p.shot_timer = 0
	game.combat_tick(p, 1.0 / 60)
	check(p.conceal == 0, "firing ends concealment")
	p.conceal = 2
	game.damage_fighter(p, 10, 105)
	check(p.conceal == 2 and p.reveal > 0, "damage reveals without cancelling concealment")
	p.cooldowns[1] = 0
	p.held = 0
	game.activate(p, 1)
	check(p.conceal == 0, "Dead Drop ends concealment")
	await create_timer(0.2).timeout

func test_healpack() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	p.change_class(2)
	p.global_position = O + Vector3(30, 0, 30)
	var data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": "healpack", "hp": 1.0, "life": 1e9, "pos": p.global_position, "yaw": 0.0, "used": false}
	game.entity_next += 1
	game.create_entity_from(data)
	var pack: Deployable = game.entities[data.id]
	game.entities_tick(0.1)
	check(not pack.used and p.hp == p.spec.health, "health pack ignores a fighter at full health")
	p.hp = 100.0
	game.entities_tick(0.1)
	check(is_equal_approx(p.hp, 160.0) and pack.used, "health pack heals 60 at once and is taken")
	check(is_equal_approx(p.heal_left, game.PACK_REGEN), "health pack queues 150 HP of regen")
	p.hp = 50.0
	game.entities_tick(0.1)
	check(p.hp == 50.0, "a taken pack heals nobody until it respawns")
	p.heal_left = game.PACK_REGEN
	game.damage_fighter(p, 5.0, p.fighter_id)
	check(p.heal_left > 0, "self damage does not interrupt regen")
	game.damage_fighter(p, 5.0, foe.fighter_id if foe.team != p.team else 100)
	check(p.heal_left == 0.0, "enemy hero damage interrupts regen")
	game.entities_tick(game.PACK_RESPAWN + 1.0)
	check(not pack.used, "health pack respawns after its cooldown")
	game.remove_entity(data.id)

func test_machinery() -> void:
	var p: Fighter = game.local_player()
	p.change_class(1)
	p.global_position = O + Vector3(-10, 0, -21)
	var id: int = game.create_entity(p, "turret", p.global_position + Vector3(1, 0, 0), 100, 90)
	var e: Deployable = game.entities[id]
	e.hp = 50
	e.age = 5
	game.entities_tick(1)
	check(e.hp > 50, "engineer passive repairs idle nearby machinery")
	e.last_damage = e.age
	var hp := e.hp
	game.entities_tick(1)
	check(e.hp == hp, "recent damage stops passive repair")
	game.activate(p, 2)
	check(not game.entities.has(id), "recall removes installation")
	var pad: int = game.create_entity(p, "pad", p.global_position, 80, 90)
	game.entities_tick(0.01)
	check(p.velocity.y == 14.5, "launch pad propels fighters")
	var opponent: Fighter = game.fighters[105]
	opponent.change_class(1)
	opponent.global_position = p.global_position + Vector3(0.5, 0, 0)
	game.entities[pad].timer = 0
	game.entities_tick(0.01)
	check(opponent.velocity.y == 14.5, "enemy can use engineer launch pad")
	game.remove_entity(pad)
	await physics_frame
	await process_frame
	var turret_id: int = game.create_entity(p, "turret", p.global_position + Vector3(1, 0, 0), 100, 90)
	var turret: Deployable = game.entities[turret_id]
	turret.rotation.y = 0
	opponent.global_position = turret.global_position + Vector3(0, 0, 3)
	await physics_frame
	await process_frame
	game.entities_tick(0.1)
	check(opponent.hp == 200, "turret cannot attack outside firing arc")
	opponent.global_position = turret.global_position + Vector3(0, 0, -4)
	await physics_frame
	await process_frame
	game.entities_tick(0.1)
	check(opponent.hp < 200, "turret supplements primary with aimed pressure")
	turret.hp = 0
	game.entities_tick(0.01)
	check(not game.entities.has(turret_id), "destroyed turret is removed")
	p.change_class(2)
	p.global_position = O + Vector3(-10, 0, -21)
	p.yaw = -PI / 2
	opponent.global_position = O + Vector3(-8, 0, -21)
	opponent.hp = 200
	await physics_frame
	await process_frame
	p.held = 2
	game.combat_tick(p, 1.0 / 60)
	check(opponent.hp == 125 and p.melee_buff > 0, "Enforcer melee damages and improves spin-up")
	for i in range(5):
		game.apply_hit(p, {"collider": opponent, "position": opponent.global_position + Vector3.UP}, p.spec.damage)
	check(p.gun_buff > 0, "sustained gun hits improve melee recovery")
	p.held = 0

func test_weapon_specs() -> void:
	var breacher: WeaponSpec = Fighter.WEAPONS[1]
	var longshot: WeaponSpec = Fighter.WEAPONS[2]
	var chatterbox: WeaponSpec = Fighter.WEAPONS[3]
	check(Fighter.WEAPONS[0] == null and Fighter.WEAPONS.size() == 4, "weapon table: signature plus three shared guns")
	for i in range(4):
		var signature := WeaponSpec.from_class(Fighter.SPECS[i], i)
		check(absf(signature.body_ttk() - Fighter.SPECS[i].body_ttk()) < 0.001, "signature weapon mirrors class gun: " + Fighter.SPECS[i].title)
	check(WeaponSpec.from_class(Fighter.SPECS[1], 1).headshot_mult == 1.0, "engineer signature cannot headshot")
	# Falloff: flat inside the start range, linear to the floor, flat after.
	check(is_equal_approx(breacher.falloff_at(3.0), 1.0), "shotgun full damage up close")
	check(is_equal_approx(breacher.falloff_at(13.0), 0.6), "shotgun falloff is linear (13 m of 6..20)")
	check(is_equal_approx(breacher.falloff_at(60.0), breacher.falloff_min), "shotgun falloff floors")
	check(is_equal_approx(longshot.falloff_at(30.0), 1.0) and longshot.falloff_at(80.0) >= 0.7 - 0.001, "rifle barely falls off")
	var last := 2.0
	for d in range(0, 100, 5):
		var f := chatterbox.falloff_at(float(d))
		check(f <= last + 0.0001, "smg falloff never increases (%d m)" % d)
		last = f
	# Role ordering: the shotgun wins up close, the rifle at range, and reach grows shotgun < smg < rifle.
	check(breacher.reach < chatterbox.reach and chatterbox.reach < longshot.reach, "reach order shotgun < smg < rifle")
	check(breacher.body_ttk(200.0, 3.0) < chatterbox.body_ttk(200.0, 3.0), "shotgun kills fastest point blank")
	check(longshot.body_ttk(200.0, 40.0) < chatterbox.body_ttk(200.0, 28.0), "rifle out-trades the smg at range")
	check(breacher.body_ttk(200.0, 19.0) > 3.0 * breacher.body_ttk(200.0, 3.0), "shotgun collapses at range")
	check(chatterbox.interval < 0.1 and chatterbox.magazine >= 30, "smg is rapid fire")
	for w in [breacher, longshot, chatterbox]:
		var t: float = w.body_ttk(200.0, 10.0)
		check(t > 0.5 and t < 4.0, "weapon time-to-kill in band: %s (%.2fs)" % [w.title, t])
		print("WEAPON TTK %s: %.2fs at 3 m, %.2fs at 25 m" % [w.title, w.body_ttk(200.0, 3.0), w.body_ttk(200.0, 25.0)])

func test_shared_weapons() -> void:
	var p: Fighter = game.local_player()
	var target: Fighter = game.fighters[105]
	var cases := [[1, 3.0], [2, 20.0], [3, 10.0]]
	for class_index in [0, 2]:
		for entry in cases:
			var weapon_id: int = entry[0]
			var distance: float = entry[1]
			p.change_class(class_index, weapon_id)
			var w: WeaponSpec = p.weapon
			check(p.weapon_id == weapon_id and p.ammo == w.magazine, "equip %s on %s" % [w.title, p.spec.title])
			p.global_position = O + Vector3(-distance, 0, -21)
			p.velocity = Vector3.ZERO
			p.held = 1
			p.spin = 0  # the Enforcer's spin-up belongs to its Signature gun only
			target.change_class(1)
			target.global_position = O + Vector3(0, 0, -21)
			target.hp = 200
			target.update_visual()
			await physics_frame
			await process_frame
			aim_at(p, target.global_position + Vector3.UP * 1.1)
			var elapsed := 0.0
			var first_hit := -1.0
			for frame in range(600):
				game.combat_tick(p, 1.0 / 60.0)
				if target.hp < 200 and first_hit < 0:
					first_hit = elapsed
				if target.hp <= 0:
					break
				elapsed += 1.0 / 60.0
			var ttk := elapsed - first_hit
			var label := "%s on %s" % [w.title, p.spec.title]
			print("LIVE TTK %s: %.3fs at %.0f m" % [label, ttk, distance])
			check(target.hp <= 0, "shared weapon kills: " + label)
			check(absf(ttk - w.body_ttk(200.0, distance)) <= 0.15, "shared weapon cadence matches model: " + label)
			p.held = 0
	# One shotgun blast on one target is one hit: five pellets landing must not trip the Enforcer's five-hit buff.
	p.change_class(2, 1)
	p.consecutive_hits = 0
	p.gun_buff = 0
	p.global_position = O + Vector3(-3, 0, -21)
	target.change_class(1)
	target.global_position = O + Vector3(0, 0, -21)
	target.hp = 200
	await physics_frame
	aim_at(p, target.global_position + Vector3.UP * 1.1)
	game.fire_ray(p, p.weapon.damage, false)
	check(p.consecutive_hits == 1 and p.gun_buff <= 0, "a shotgun blast counts as one hit")
	check(target.hp < 200, "blast damaged the target")
	# Out of range: falloff and reach both bite.
	target.hp = 200
	p.global_position = O + Vector3(-40, 0, -21)
	aim_at(p, target.global_position + Vector3.UP * 1.1)
	game.fire_ray(p, p.weapon.damage, false)
	check(target.hp == 200, "shotgun cannot reach 40 m")
	# Loadout survives the snapshot, respawn and class swaps.
	p.change_class(0, 3)
	var state := p.pack()
	check(state["w"] == 3, "snapshot carries weapon id")
	p.change_class(1, 0)
	p.unpack(state, true)
	check(p.weapon_id == 3 and p.class_id == 0, "snapshot restores class and weapon")
	game.respawn(p)
	check(p.weapon_id == 3 and p.ammo == p.weapon.magazine, "respawn keeps the weapon and refills it")
	game.apply_class(p.fighter_id, 3, 2)
	check(p.class_id == 3 and p.weapon_id == 2, "class request carries a weapon")
	p.change_class(0, 99)
	check(p.weapon_id == Fighter.WEAPONS.size() - 1, "weapon id is clamped")
	p.change_class(0, 0)
	p.held = 0
	target.hp = 200

func test_authority_and_respawn() -> void:
	var p: Fighter = game.local_player()
	game.authoritative = false
	var hp := p.hp
	game.damage_fighter(p, 100, 105)
	check(p.hp == hp, "client cannot award damage")
	game.authoritative = true
	p.global_position = O + Vector3(0, 0, 20)
	game.damage_fighter(p, 10000, 105)
	check(p.hp == 0 and p.dead_time == 5, "death schedules respawn")
	game.respawn(p)
	check(p.hp == p.spec.health and p.ammo == p.spec.magazine, "respawn restores class and ammunition")
	game.apply_class(p.fighter_id, 0)
	check(p.class_id == 0, "class change permitted at spawn")
	p.global_position = Vector3.ZERO
	game.apply_class(p.fighter_id, 2)
	check(p.class_id == 0, "class change forbidden away from spawn")
	game.last_world_tick = 100
	var count: int = game.fighters.size()
	game.apply_world({"tick": 99, "players": [], "entities": [], "match": game.match_state.pack()})
	check(game.fighters.size() == count, "stale snapshot cannot erase newly joined fighters")
	game.last_world_tick = -1
	game.match_state.winner = 1
	game.start_game("restart")
	check(game.match_state.winner == -2 and game.match_state.remaining == 720, "host restart resets round")
	check(game.entities.is_empty() and p.hp == p.spec.health, "restart clears deployables and restores fighters")

func test_roster_and_roles() -> void:
	check(game.fighters.size() == CivicDividend.TEAM_SIZE * 2, "full roster of %d fighters" % (CivicDividend.TEAM_SIZE * 2))
	var slots: Array = [{}, {}]
	for p in game.fighters.values():
		slots[p.team][p.spawn_slot] = true
	check(slots[0].size() == CivicDividend.TEAM_SIZE and slots[1].size() == CivicDividend.TEAM_SIZE, "every teammate holds a distinct spawn slot")
	var spawns := {}
	for side in range(2):
		for slot in range(CivicDividend.TEAM_SIZE):
			spawns[CivicDividend.spawn_slot_position(side, slot)] = true
	check(spawns.size() == CivicDividend.TEAM_SIZE * 2, "spawn slot positions never overlap")
	game.refresh_bot_enemies()
	for p in game.fighters.values():
		if p.bot:
			p.hp = p.spec.health
			p.bot_think = 0.0
			p.bot_role_until = 0.0
			p.bot_goal = -1
			p.bot_role = Fighter.BotRole.ATTACK
	for p in game.fighters.values():
		if p.bot:
			game.bot_input(p, 0.1)
	var attackers := [0, 0]
	var roamers := 0
	var valid_roam := true
	for p in game.fighters.values():
		if not p.bot:
			continue
		if p.bot_role == Fighter.BotRole.ATTACK:
			attackers[p.team] += 1
		else:
			roamers += 1
			valid_roam = valid_roam and p.bot_roam_node >= 0 and not p.bot_path.is_empty()
	check(attackers[0] <= game.BOT_MAX_ATTACKERS + 1 and attackers[1] <= game.BOT_MAX_ATTACKERS + 1, "attackers per team stay near the capture cap (%s)" % [attackers])
	check(roamers >= 4, "surplus bots roam or defend instead of stacking on the point (%d)" % roamers)
	check(valid_roam, "every roaming bot has a graph node and a route")

func test_hud() -> void:
	game.set_physics_process(false)
	var victim: Fighter = game.fighters[100]
	var killer: Fighter = game.fighters[105]
	victim.team = 0
	killer.team = 1
	victim.global_position = O + Vector3(0, 0, 20)
	killer.global_position = O + Vector3(1, 0, 20)
	victim.hp = victim.spec.health
	var before: int = game.hud.feed.size()
	var kills_before: int = killer.kills
	var deaths_before: int = victim.deaths
	game.damage_fighter(victim, 10000, 105)
	check(killer.kills == kills_before + 1 and victim.deaths == deaths_before + 1, "kill increments killer kills and victim deaths")
	check(game.hud.feed.size() == mini(5, before + 1) and game.hud.feed[0].killer == killer.spec.title, "kill feed records the kill")
	check(killer.pack().k == killer.kills and victim.pack().d == victim.deaths, "kills and deaths are replicated in snapshots")
	var twin: Fighter = game.fighters[101]
	twin.unpack(killer.pack(), false)
	check(twin.kills == killer.kills, "snapshot restores kills")
	for i in range(8):
		game.hud.add_kill("A", 0, "B", 1)
	check(game.hud.feed.size() == 5, "kill feed keeps at most five entries")
	var rows: Array = Hud.scoreboard_rows(game)
	check(rows[0].size() == CivicDividend.TEAM_SIZE and rows[1].size() == CivicDividend.TEAM_SIZE, "scoreboard lists a full team per side")
	check(rows[1][0].k >= rows[1][-1].k, "scoreboard sorts by kills")
	var mini: Minimap = game.hud.minimap
	check(mini.to_map(CivicDividend.bounds.position.x, CivicDividend.bounds.position.y).is_zero_approx(), "minimap maps bounds origin to its corner")
	check(mini.to_map(CivicDividend.bounds.end.x, CivicDividend.bounds.end.y).is_equal_approx(mini.size), "minimap maps bounds end to its far corner")
	var pack_data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": "healpack", "hp": 1.0, "life": 1e9, "pos": O + Vector3(0, 12, 0), "yaw": 0.0, "used": false}
	game.entity_next += 1
	game.create_entity_from(pack_data)
	mini._draw_health_packs(game.local_player())
	mini._draw_health_packs(null)
	check(true, "minimap draws health packs above, below and without a local player")
	game.remove_entity(pack_data.id)
	check(not CivicDividend.footprints.is_empty(), "map records building footprints for the minimap")
	check(game.menu.cards.size() == Fighter.SPECS.size(), "menu has a card per class")
	game.hud.hit(2)
	game.hud.damaged(Vector3(5, 0, 5))
	game.hud.refresh(game, 0.016)
	check(game.hud.hit_timer > 0.0 and game.hud.indicators.size() >= 1, "hit marker and damage indicator register")
	game.respawn(victim)
	game.respawn(killer)

func test_sfx() -> void:
	var silent := 0
	var total := 0
	for kind in Sfx.Kind.values():
		var wave := Sfx.stream(kind)
		total += 1
		var peak := 0
		for i in range(0, wave.data.size() - 1, 2):
			peak = maxi(peak, absi(wave.data.decode_s16(i)))
		if wave.data.size() < 1000 or peak < 1500:
			silent += 1
	check(silent == 0 and total == Sfx.RECIPES.size(), "every sound cue synthesises audible audio (%d cues)" % total)
	check(Sfx.stream(Sfx.Kind.SHOT_ENFORCER) == Sfx.stream(Sfx.Kind.SHOT_ENFORCER), "cues are cached")

func test_effect_pool() -> void:
	var root_node: Node3D = game.tracer_root
	for i in range(600):
		Vfx.tracer(root_node, Vector3(0, 1, 0), Vector3(20, 1, 0), Vfx.Style.ARC, Color.WHITE, true)
	check(root_node.get_child_count() <= Vfx.MAX_EFFECT_NODES + 40, "effect nodes stay capped under a tracer flood (%d)" % root_node.get_child_count())

func test_visual_pipeline() -> void:
	# Writing ALPHA in the opaque map shader moves every map mesh into the transparent pipeline
	# (no depth writes), which made walls draw on top of each other.
	check(Visuals.SURFACE_SHADER.find("ALPHA") == -1, "map surface shader stays in the opaque pipeline")
	check(Visuals.surface("glass", Color.WHITE) is StandardMaterial3D, "glass uses its own transparent material")

func test_input_forgiveness() -> void:
	await physics_frame
	var p: Fighter = game.local_player()
	p.change_class(1)
	p.held = 0
	p.movement = Vector2.ZERO
	var base := O + Vector3(-30, 0, -20)
	# Coyote time: a jump just after leaving the ground is still a ground jump and keeps the double jump.
	p.global_position = base + Vector3(0, 3.0, 0)
	p.velocity = Vector3.ZERO
	p.air_jump = true
	for i in range(7):
		p.simulate_movement(1.0 / 60, 0)
	p.simulate_movement(1.0 / 60, 1)
	check(p.velocity.y > 9.5 and p.air_jump, "coyote jump counts as a ground jump and keeps the double jump")
	await physics_frame
	p.global_position = base + Vector3(0, 6.0, 0)
	p.velocity = Vector3.ZERO
	p.air_jump = true
	for i in range(14):
		p.simulate_movement(1.0 / 60, 0)
	p.simulate_movement(1.0 / 60, 1)
	check(p.velocity.y > 12.0 and not p.air_jump, "after the coyote window the press is a double jump")
	await physics_frame
	# Jump buffer: a press just before landing fires on touchdown; an early press is forgotten.
	p.global_position = base + Vector3(0, 0.25, 0)
	p.velocity = Vector3(0, -4, 0)
	p.air_jump = false
	p.coyote_time = 0.0
	p.jump_buffer = 0.0
	p.simulate_movement(1.0 / 60, 1)
	check(p.jump_buffer > 0.0, "an unusable press is buffered")
	var best := -99.0
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
		best = maxf(best, p.velocity.y)
		await physics_frame
	check(best > 9.5, "buffered press jumps on landing (peak vy %.1f)" % best)
	p.global_position = base + Vector3(0, 2.0, 0)
	p.velocity = Vector3.ZERO
	p.air_jump = false
	p.coyote_time = 0.0
	p.jump_buffer = 0.0
	p.simulate_movement(1.0 / 60, 1)
	best = -99.0
	for i in range(60):
		p.simulate_movement(1.0 / 60, 0)
		best = maxf(best, p.velocity.y)
		await physics_frame
	check(best < 1.0 and p.jump_buffer == 0.0, "an early press expires instead of jumping on landing (peak vy %.1f)" % best)
	await physics_frame

func test_slide_jump() -> void:
	await physics_frame
	var p: Fighter = game.local_player()
	p.change_class(1)
	p.movement = Vector2.ZERO
	p.yaw = 0.0
	var base := O + Vector3(-30, 0.01, -20)
	var speeds := []
	# Cases: jump from mid-slide, jump just after releasing the slide, jump from a slide already at the cap.
	for variant in range(3):
		p.held = 0
		p.global_position = base
		p.velocity = Vector3.ZERO
		p.slide_cd = 0.0
		p.slide_grace = 0.0
		for i in range(20):
			p.simulate_movement(1.0 / 60, 0)
			await physics_frame
		p.velocity = Vector3(11.8 if variant == 2 else 8.0, 0, 0)
		p.held = 8
		p.simulate_movement(1.0 / 60, 0)
		if variant == 1:
			p.held = 0
			p.simulate_movement(1.0 / 60, 0)
		p.simulate_movement(1.0 / 60, 1)
		speeds.append(Vector2(p.velocity.x, p.velocity.z).length())
		check(p.velocity.y > 9.5 and not p.sliding, "slide-jump %d jumps and ends the slide" % variant)
		await physics_frame
	check(speeds[0] > 10.3 and speeds[0] < 12.1, "jumping from a slide adds speed (%.2f)" % speeds[0])
	check(speeds[1] > 10.0, "jumping just after a slide still gets the boost (%.2f)" % speeds[1])
	check(speeds[2] < 12.1, "slide-jump boost stops at the speed cap (%.2f)" % speeds[2])
	await physics_frame

func test_air_movement() -> void:
	# move_and_slide uses the physics delta only inside a physics frame, so each section starts on one.
	await physics_frame
	var p: Fighter = game.local_player()
	p.change_class(1)
	p.held = 0
	# Jump height: a full jump should clear a 1.9 m ledge but not much more.
	p.global_position = O + Vector3(-30, 0.01, -20)
	p.velocity = Vector3.ZERO
	p.movement = Vector2.ZERO
	for i in range(10):
		p.simulate_movement(1.0 / 60, 0)
		p.simulate_movement(1.0 / 60, 1)
	var apex := 0.0
	for i in range(80):
		p.simulate_movement(1.0 / 60, 0)
		apex = maxf(apex, p.global_position.y)
	check(apex > 1.55 and apex < 2.3, "jump apex is 1.6-2.2 m, up from about 1.4 (%.2f)" % apex)
	await physics_frame
	# Double jump spends the shared air charge and gives a second lift; a dash cannot follow it.
	p.global_position = O + Vector3(-30, 6.0, -20)
	p.velocity = Vector3(0, -2, 0)
	p.simulate_movement(1.0 / 60, 0)
	p.air_jump = true
	p.air_dash = true
	p.simulate_movement(1.0 / 60, 1)
	check(p.velocity.y > 9.0 and not p.air_jump and p.air_dash, "double jump lifts and leaves the dash charge alone")
	p.simulate_movement(1.0 / 60, 2)
	check(p.dash_time > 0.0 and not p.air_dash, "dash is still available after a double jump")
	await physics_frame
	# Dash covers a long horizontal distance and is exclusive with the double jump.
	p.global_position = O + Vector3(-30, 8.0, -20)
	p.velocity = Vector3.ZERO
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	p.air_dash = true
	var start_x := p.global_position.x
	p.simulate_movement(1.0 / 60, 2)
	for i in range(30):
		p.simulate_movement(1.0 / 60, 0)
	check(p.global_position.x - start_x > 4.5, "air dash travels over 4.5 m in half a second (%.1f)" % (p.global_position.x - start_x))
	await physics_frame
	# Air control: forward input at speed adds nothing; strafing adds a bounded amount.
	p.global_position = O + Vector3(-30, 8.0, -20)
	p.velocity = Vector3(8, 0, 0)
	p.air_dash = false
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
	check(absf(p.velocity.x - 8.0) < 0.05, "holding forward in the air adds no speed")
	p.movement = Vector2(1, 0)
	p.velocity = Vector3(8, 0, 0)
	for i in range(30):
		p.simulate_movement(1.0 / 60, 0)
	check(absf(p.velocity.z) > 0.3 and absf(p.velocity.z) < 2.0, "air strafing nudges sideways velocity only slightly (%.2f)" % p.velocity.z)
	await physics_frame
	# Ground momentum: stopping takes noticeable time.
	p.global_position = O + Vector3(-30, 0.01, 5)
	p.velocity = Vector3(8, 0, 0)
	p.movement = Vector2.ZERO
	for i in range(10):
		p.simulate_movement(1.0 / 60, 0)
	check(p.velocity.x > 5.0, "ground friction is weighty, not instant (%.1f after 0.17 s)" % p.velocity.x)
	p.movement = Vector2.ZERO

func test_explore() -> void:
	var g = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	g.start_game("explore")
	check(g.explore and g.fighters.size() == 1, "explore mode spawns only the local player")
	var before: Array = g.match_state.progress.duplicate()
	g.local_player().global_position = g.points[2] + Vector3.UP * 0.1
	for i in range(30):
		await physics_frame
	check(g.match_state.progress == before and g.match_state.winner == -2, "explore mode never ticks the objective")
	check(g.hud.explore, "HUD switches to the exploration layout")
	g.queue_free()
	await process_frame
