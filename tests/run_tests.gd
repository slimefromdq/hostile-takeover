extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
const O := ProvingGround.ORIGIN
const GameScript := preload("res://scripts/game.gd")
# The reference body for movement and pickup tests: a Rifle loadout holding its Pistol (move speed multiplier 1.0).
const REFERENCE := 1  # Loadout.encode(1, 0, 0, 0)

# A teleport keeps is_on_floor() and the coyote/jump-buffer windows from the last position; clear them so the
# next simulated tick judges the fighter where it now is.
func place(p: Fighter, at: Vector3, velocity := Vector3.ZERO) -> void:
	p.global_position = at
	p.velocity = velocity
	p.coyote_time = 0.0
	p.jump_buffer = 0.0
	p.slide_grace = 0.0

func neutral(p: Fighter, loadout_code: int = REFERENCE) -> void:
	p.apply_loadout(loadout_code)
	p.swap_weapon()
	p.swap_timer = 0.0

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
	test_armor_rules()
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
	await test_sidearm_swap()
	await test_utilities()
	await test_melee()
	await test_armor_and_snapshot()
	test_healpack()
	test_items()
	test_bot_items()
	test_power_ups()
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
	check(Fighter.MAX_HEALTH == 200.0, "every fighter has the same 200 HP")
	var sizes := Loadout.slot_sizes()
	check(sizes == [3, 3, 7, 3], "loadout tables: 3 primaries, 3 sidearms, 7 utilities, 3 melee weapons")
	for slot in range(4):
		var names := {}
		for i in range(sizes[slot]):
			var item := Loadout.item_name(slot, i)
			check(item != "" and not names.has(item) and Loadout.item_blurb(slot, i) != "", "item is named, unique and described: %s" % item)
			names[item] = true
	for u in Loadout.UTILITIES:
		check(u.cooldown > 0.0, "utility has a cooldown: " + u.name)
	for m in Loadout.MELEES:
		check(m.damage > 0.0 and m.reach > 0.0 and m.recovery > 0.0, "melee has damage, reach and recovery: " + m.name)
		check(m.damage * m.backstab < Fighter.MAX_HEALTH, "no single melee hit kills a full-health fighter: " + m.name)
	for code in [Loadout.encode(0, 0, 0, 0), Loadout.encode(2, 2, 6, 2), Loadout.encode(1, 2, 3, 0)]:
		var ids := Loadout.decode(code)
		check(Loadout.encode(ids[0], ids[1], ids[2], ids[3]) == code, "loadout encode/decode round trip (%d)" % code)
	check(Loadout.encode(1, 0, 0, 0) == REFERENCE, "reference loadout code")
	check(Loadout.decode(Loadout.encode(9, -3, 99, 7)) == [2, 0, 6, 2], "loadout slots clamp into their tables")
	check(Loadout.decode(-1) == [2, 2, 6, 2] and Loadout.decode(0xFFFF) == [2, 2, 6, 2], "any network int decodes to a valid loadout")
	check(Loadout.with_slot(Loadout.encode(0, 0, 0, 0), 2, 4) == Loadout.encode(0, 0, 4, 0), "with_slot changes one slot")
	check(Loadout.describe(REFERENCE) == "Rifle · Pistol · Grapple · Knife", "loadout description")
	var limited := WeaponSpec.new()
	limited.damage = 50
	limited.magazine = 2
	limited.interval = 0.5
	limited.reload_time = 1.4
	check(is_equal_approx(limited.body_ttk(), 2.4), "weapon model includes reload time")

func test_movement() -> void:
	var p: Fighter = game.local_player()
	p.global_position = O + Vector3(-10, 0.01, -21)
	neutral(p)
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
	check(not p.air_dash and p.velocity.x > 12, "air dash consumed and propels")
	p.global_position = O + Vector3(-10, 0, -21)
	p.velocity = Vector3.ZERO
	for i in range(20):
		p.simulate_movement(1.0 / 60, 0)
	check(not p.air_dash and p.dash_cd > 0.5, "landing does not restore the dash; 2.5 s cooldown applies")
	for i in range(150):
		p.simulate_movement(1.0 / 60, 0)
	check(p.air_dash, "dash recharges after its 2.5 s cooldown")
	for primary_id in range(Loadout.PRIMARIES.size()):
		await physics_frame  # move_and_slide uses the physics delta only inside a physics frame
		p.apply_loadout(Loadout.encode(primary_id, 0, 0, 0))
		place(p, O + Vector3(88.8, 3, 20))
		p.wall_repeats = 0
		p.wall_normal = Vector3.ZERO
		p.velocity = Vector3.ZERO
		p.yaw = -PI / 2
		p.movement = Vector2.ZERO
		p.simulate_movement(1.0 / 60, 0)
		p.coyote_time = 0.0  # the tick above still saw the floor contact from before the teleport
		p.simulate_movement(1.0 / 60, 1)
		check(p.velocity.x < -6 and p.velocity.y >= 10.4, "universal wall kick: %s (v %s)" % [p.weapon.title, p.velocity])
	neutral(p)
	await physics_frame
	place(p, O + Vector3(-10, 0, -21))
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
	await physics_frame
	place(p, O + Vector3(-10, 0, -21))
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
	await physics_frame
	place(p, O + Vector3(-5.2, 0.3, 5))
	p.yaw = -PI / 2  # facing the crate (x -4.5..-1.5); the slide checks left the view facing -z
	p.movement = Vector2.ZERO
	p.held = 0
	p.simulate_movement(1.0 / 60, 0)
	p.held = 16
	p.velocity.y = 0
	p.simulate_movement(1.0 / 60, 0)
	var rise := p.velocity.y * p.velocity.y / (2.0 * Fighter.GRAVITY)
	check(p.vault_time > 0.0 and rise > 1.2 - (p.global_position.y - O.y), "held jump vaults the low crate with lift to clear it (rise %.2f m)" % rise)
	p.held = 0
	await physics_frame
	await process_frame
	await test_air_movement()
	await test_input_forgiveness()
	await test_slide_jump()
	await test_wall_run()
	await test_ledges()
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

# Live cadence for every gun, primary and sidearm, at a range inside its full-damage band (shotguns point blank).
const LIVE_RANGES := {"Shotgun": 3.0, "Rifle": 20.0, "SMG": 10.0, "Pistol": 10.0, "Burst Pistol": 10.0, "Revolver": 10.0}

func test_weapons() -> void:
	var p: Fighter = game.local_player()
	var target: Fighter = game.fighters[105]
	target.team = 1 - p.team  # with 5v5 rosters bot 105 may start as a teammate
	var guns: Array = []
	for i in range(Loadout.PRIMARIES.size()):
		guns.append([Loadout.encode(i, 0, 0, 0), false])
	for i in range(Loadout.SIDEARMS.size()):
		guns.append([Loadout.encode(1, i, 0, 0), true])
	for entry in guns:
		p.apply_loadout(entry[0])
		if entry[1]:
			p.swap_weapon()
			p.swap_timer = 0.0
		var w: WeaponSpec = p.weapon
		var distance: float = LIVE_RANGES[w.title]
		check(p.ammo == w.magazine, "equip %s with a full magazine" % w.title)
		p.global_position = O + Vector3(-distance, 0, -21)
		p.velocity = Vector3.ZERO
		p.held = 1
		neutral(target)
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
		print("LIVE TTK %s: %.3fs at %.0f m (model %.3fs)" % [w.title, ttk, distance, w.body_ttk(200.0, distance)])
		check(target.hp <= 0, "authoritative fire kills: " + w.title)
		check(absf(ttk - w.body_ttk(200.0, distance)) <= 0.15, "live cadence matches model: " + w.title)
		p.held = 0
	# Shotgun out of range: falloff and reach both bite.
	p.apply_loadout(Loadout.encode(0, 0, 0, 0))
	neutral(target)  # the last gun killed it: restore its collider
	target.global_position = O + Vector3(0, 0, -21)
	p.global_position = O + Vector3(-3, 0, -21)
	await physics_frame
	aim_at(p, target.global_position + Vector3.UP * 1.1)
	game.fire_ray(p, p.weapon.damage)
	check(target.hp < 200 and target.hp >= 200 - p.weapon.damage * p.weapon.pellets * p.weapon.headshot_mult, "one shotgun blast damages the target once")
	target.hp = 200
	p.global_position = O + Vector3(-40, 0, -21)
	aim_at(p, target.global_position + Vector3.UP * 1.1)
	game.fire_ray(p, p.weapon.damage)
	check(target.hp == 200, "shotgun cannot reach 40 m")
	# Friendly hits cannot award damage.
	target.team = p.team
	game.apply_hit(p, {"collider": target, "position": target.global_position + Vector3.UP}, 100)
	check(target.hp == Fighter.MAX_HEALTH, "friendly fire disabled")
	target.team = 1 - p.team
	neutral(p)

func test_sidearm_swap() -> void:
	var p: Fighter = game.local_player()
	var target: Fighter = game.fighters[105]
	target.team = 1 - p.team
	neutral(target)
	p.apply_loadout(Loadout.encode(0, 0, 0, 0))  # Shotgun + Pistol
	check(p.slot == 0 and p.weapon == Loadout.PRIMARIES[0] and p.ammo == p.primary.magazine and p.stowed_ammo == p.sidearm.magazine, "spawn with the primary out and both magazines full")
	p.global_position = O + Vector3(-10, 0, -21)
	p.velocity = Vector3.ZERO
	p.held = 0
	target.global_position = O + Vector3(0, 0, -21)
	target.hp = 200
	await physics_frame
	await process_frame
	aim_at(p, target.global_position + Vector3.UP * 1.1)
	p.ammo = 0
	p.edges = GameScript.EDGE_RELOAD
	game.combat_tick(p, 1.0 / 60)
	check(p.reload_timer > 0.0, "reloading the empty primary")
	p.edges = GameScript.EDGE_SWAP
	game.combat_tick(p, 1.0 / 60)
	check(p.slot == 1 and p.weapon == p.sidearm and p.reload_timer == 0.0, "swap draws the sidearm and drops the reload in progress")
	check(p.ammo == p.sidearm.magazine and p.stowed_ammo == 0, "each gun keeps its own magazine")
	p.edges = 0
	p.held = 1
	game.combat_tick(p, 1.0 / 60)
	check(target.hp == 200 and p.ammo == p.sidearm.magazine, "the sidearm cannot fire mid-swap")
	var elapsed := 2.0 / 60
	while p.ammo == p.sidearm.magazine and elapsed < 1.0:
		game.combat_tick(p, 1.0 / 60)
		elapsed += 1.0 / 60
	check(elapsed <= Fighter.SWAP_TIME + 0.05 and target.hp < 200, "the sidearm fires once the swap finishes (%.2f s)" % elapsed)
	for w in Loadout.PRIMARIES:
		check(Fighter.SWAP_TIME * 4.0 <= w.reload_time, "swapping is far faster than reloading the %s" % w.title)
	p.held = 0
	p.edges = GameScript.EDGE_SWAP
	game.combat_tick(p, 1.0 / 60)
	check(p.slot == 0 and p.ammo == 0 and p.stowed_ammo < p.sidearm.magazine, "swapping back keeps both magazines as they were")
	# The rig shows only the gun in hand.
	var guns: Node3D = p.equipment.get_node_or_null("Body/Weapon")
	check(guns != null and guns.get_node("Primary").visible and not guns.get_node("Sidearm").visible, "rig shows the primary in hand")
	p.edges = GameScript.EDGE_SWAP
	game.combat_tick(p, 1.0 / 60)
	p.edges = 0
	check(not guns.get_node("Primary").visible and guns.get_node("Sidearm").visible, "rig shows the sidearm after a swap")
	# The snapshot carries the loadout, the gun in hand and the holstered magazine.
	var state := p.pack()
	check(state["lo"] == p.loadout and state.get("slot", 0) == 1 and state.get("ammo2", -1) == 0 and state.has("swap"), "snapshot carries loadout, slot, swap and stowed magazine")
	var mirror: Fighter = game.fighters[107]
	var mirror_loadout: int = mirror.loadout
	mirror.unpack(state, false)
	check(mirror.loadout == p.loadout and mirror.slot == 1 and mirror.weapon == mirror.sidearm and mirror.stowed_ammo == 0, "snapshot restores the loadout and the gun in hand")
	mirror.apply_loadout(mirror_loadout)
	mirror.global_position = O + Vector3(60, 0, 20)  # unpack moved it onto the player
	game.respawn(p)
	check(p.slot == 0 and p.ammo == p.primary.magazine and p.stowed_ammo == p.sidearm.magazine, "respawn draws the primary with both magazines full")
	check(not p.pack().has("slot") and not p.pack().has("ammo2") and not p.pack().has("swap"), "idle snapshots omit sidearm fields")
	neutral(p)

# Puts the utility `kind` in the local player's loadout and stands them at `at`, facing +x.
func with_utility(p: Fighter, kind: int, at: Vector3) -> void:
	p.apply_loadout(Loadout.encode(1, 0, kind, 0))
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = -PI / 2
	p.pitch = 0.0
	p.held = 0
	p.edges = 0

func owned(p: Fighter, kind: String) -> Array:
	return game.entities.values().filter(func(e): return e.owner_id == p.fighter_id and e.kind == kind)

func test_utilities() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	foe.team = 1 - p.team
	neutral(foe)
	foe.global_position = O + Vector3(60, 0, 20)
	var start := O + Vector3(-10, 0, -21)
	# Grapple: nothing in reach costs nothing; a hook starts the cooldown; Q again lets go into Hot Lap.
	with_utility(p, Loadout.Utility.GRAPPLE, start)
	p.yaw = PI / 2
	await physics_frame
	game.use_utility(p)
	check(p.grapple_time == 0.0 and p.utility_cd == 0.0, "a grapple with nothing to hook costs no cooldown")
	with_utility(p, Loadout.Utility.GRAPPLE, O + Vector3(70, 0, 0))
	await physics_frame
	p.edges = GameScript.EDGE_UTILITY
	game.combat_tick(p, 1.0 / 60)
	p.edges = 0
	check(p.grapple_time > 0.0 and is_equal_approx(p.utility_cd, 7.0), "Q grapples to the wall and starts the 7 s cooldown")
	game.use_utility(p)
	check(p.grapple_time == 0.0 and p.hot_lap > 0.0, "Q again lets go and grants Hot Lap")
	# Frag Grenade: thrown along the aim, bursts on the target.
	with_utility(p, Loadout.Utility.FRAG_GRENADE, start)
	foe.global_position = O + Vector3(-2, 0, -21)
	foe.hp = 200
	await physics_frame
	game.use_utility(p)
	check(is_equal_approx(p.utility_cd, 9.0), "Frag Grenade starts its cooldown")
	for i in range(40):
		await physics_frame
	check(foe.hp == 165.0 or foe.hp == 185.0, "Frag Grenade deals 35 direct or 15 splash (%.0f left)" % foe.hp)
	# Smoke Grenade: smoke and concealment; firing ends it, damage only reveals.
	with_utility(p, Loadout.Utility.SMOKE_GRENADE, start)
	game.use_utility(p)
	check(owned(p, "smoke").size() == 1 and p.conceal == 2.5, "Smoke Grenade lays smoke and conceals")
	p.conceal = 2.0
	game.damage_fighter(p, 10, foe.fighter_id)
	check(p.conceal == 2.0 and p.reveal > 0.0, "damage reveals without cancelling concealment")
	p.held = 1
	p.shot_timer = 0
	game.combat_tick(p, 1.0 / 60)
	p.held = 0
	check(p.conceal == 0.0, "firing ends concealment")
	# Launch Pad: one per owner, throws anyone upward.
	with_utility(p, Loadout.Utility.LAUNCH_PAD, start)
	game.use_utility(p)
	p.utility_cd = 0.0
	game.use_utility(p)
	var pads := owned(p, "pad")
	check(pads.size() == 1 and is_equal_approx(p.utility_cd, 10.0), "one launch pad at a time, 10 s cooldown")
	if pads.size() == 1:
		var pad: Deployable = pads[0]
		p.global_position = pad.global_position
		game.entities_tick(0.01)
		check(p.velocity.y == 14.5, "launch pad propels its owner")
		foe.global_position = pad.global_position + Vector3(0.5, 0, 0)
		foe.velocity = Vector3.ZERO
		pad.timer = 0
		game.entities_tick(0.01)
		check(foe.velocity.y == 14.5, "enemies can use a launch pad too")
		game.remove_entity(pad.entity_id)
	# Sentry Turret: one per owner, fires in its arc, repairs near its owner while undamaged.
	with_utility(p, Loadout.Utility.SENTRY_TURRET, start)
	game.use_utility(p)
	p.utility_cd = 0.0
	game.use_utility(p)
	check(owned(p, "turret").size() == 1 and is_equal_approx(p.utility_cd, 12.0), "one sentry turret at a time, 12 s cooldown")
	game.remove_owned(p.fighter_id)
	var turret_id: int = game.create_entity(p, "turret", p.global_position + Vector3(1, 0, 0), 100, 90)
	var turret: Deployable = game.entities[turret_id]
	turret.hp = 50
	turret.age = 5
	game.entities_tick(1)
	check(turret.hp > 50, "a sentry repairs while its owner is near")
	turret.last_damage = turret.age
	var repaired := turret.hp
	game.entities_tick(1)
	check(turret.hp == repaired, "recent damage stops the repair")
	turret.rotation.y = 0
	foe.hp = 200
	foe.global_position = turret.global_position + Vector3(0, 0, 3)
	await physics_frame
	await process_frame
	turret.timer = 0
	game.entities_tick(0.1)
	check(foe.hp == 200, "the sentry cannot fire outside its arc")
	foe.global_position = turret.global_position + Vector3(0, 0, -4)
	await physics_frame
	await process_frame
	turret.timer = 0
	game.entities_tick(0.1)
	check(foe.hp < 200, "the sentry fires on an enemy in its arc")
	turret.hp = 0
	game.entities_tick(0.01)
	check(not game.entities.has(turret_id), "a destroyed sentry is removed")
	# Barricade: placed cover that expires; no ground to stand on means no cost.
	with_utility(p, Loadout.Utility.BARRICADE, O + Vector3(0, 0, 39))
	p.yaw = PI
	game.use_utility(p)
	check(owned(p, "cover").is_empty() and p.utility_cd == 0.0, "a placement with no ground costs no cooldown")
	with_utility(p, Loadout.Utility.BARRICADE, start)
	game.use_utility(p)
	var covers := owned(p, "cover")
	check(covers.size() == 1 and covers[0].hp == 180.0 and is_equal_approx(p.utility_cd, 14.0), "Barricade places 180 HP of cover")
	game.entities_tick(8.1)
	check(owned(p, "cover").is_empty(), "the barricade expires after 8 s")
	# Breach Charge: damages and launches close enemies, triple damage to their deployables.
	with_utility(p, Loadout.Utility.BREACH_CHARGE, start)
	foe.global_position = start + Vector3(3, 0, 0)
	foe.velocity = Vector3.ZERO
	foe.hp = 200
	var enemy_turret: int = game.create_entity(foe, "turret", start + Vector3(2.5, 0, 1.0), 100, 90)
	await physics_frame
	await process_frame
	game.use_utility(p)
	check(foe.hp == 180.0 and foe.velocity.length() > 5.0, "Breach Charge deals 20 and launches")
	check(game.entities[enemy_turret].hp == 40.0, "Breach Charge deals triple damage to deployables")
	check(is_equal_approx(p.utility_cd, 8.0), "Breach Charge has an 8 s cooldown")
	game.remove_entity(enemy_turret)
	game.remove_owned(p.fighter_id)
	foe.hp = 200
	foe.velocity = Vector3.ZERO
	foe.global_position = O + Vector3(60, 0, 20)
	neutral(p)
	await create_timer(0.2).timeout

func test_melee() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	foe.team = 1 - p.team
	neutral(foe)
	var start := O + Vector3(-10, 0, -21)
	for m in range(Loadout.MELEES.size()):
		var spec: Dictionary = Loadout.MELEES[m]
		p.apply_loadout(Loadout.encode(1, 0, 0, m))
		p.global_position = start
		p.yaw = -PI / 2
		p.pitch = 0
		foe.global_position = start + Vector3(2, 0, 0)
		foe.yaw = PI / 2  # facing the attacker
		foe.velocity = Vector3.ZERO
		foe.hp = 200
		await physics_frame
		await process_frame
		p.edges = GameScript.EDGE_MELEE
		game.combat_tick(p, 1.0 / 60)
		check(is_equal_approx(foe.hp, 200.0 - spec.damage), "%s hits for %d" % [spec.name, int(spec.damage)])
		check(is_equal_approx(p.melee_cd, spec.recovery), "%s recovery is %.2f s" % [spec.name, spec.recovery])
		var after: float = foe.hp
		game.combat_tick(p, 1.0 / 60)
		p.edges = 0
		check(foe.hp == after, "no second swing during recovery: " + spec.name)
		p.held = 1
		var ammo := p.ammo
		game.combat_tick(p, 1.0 / 60)
		p.held = 0
		check(p.ammo == ammo, "recovery holds the gun: " + spec.name)
	# Knife: double damage from behind, nothing past its reach.
	p.apply_loadout(Loadout.encode(1, 0, 0, Loadout.Melee.KNIFE))
	foe.yaw = -PI / 2  # facing away
	foe.hp = 200
	game.use_melee(p)
	check(foe.hp == 130.0, "Knife backstab deals double (70)")
	p.melee_cd = 0
	foe.yaw = PI / 2
	foe.hp = 200
	foe.global_position = start + Vector3(3, 0, 0)
	await physics_frame
	game.use_melee(p)
	check(foe.hp == 200.0, "Knife cannot reach 3 m")
	# Sword: the wide arc reaches the side, which the Knife's does not; a hit refills the magazine.
	foe.global_position = start + Vector3(0.2, 0, 2.0)
	await physics_frame
	p.melee_cd = 0
	game.use_melee(p)
	check(foe.hp == 200.0, "Knife misses a target at your side")
	p.apply_loadout(Loadout.encode(1, 0, 0, Loadout.Melee.SWORD))
	p.ammo = 0
	game.use_melee(p)
	check(foe.hp == 150.0 and p.ammo == p.weapon.magazine, "Sword's arc reaches the side and a hit refills the magazine")
	foe.global_position = O + Vector3(60, 0, 20)
	await physics_frame
	p.melee_cd = 0
	p.ammo = 0
	game.use_melee(p)
	check(p.ammo == 0, "a Sword whiff refills nothing")
	# Sledgehammer knocks back.
	p.apply_loadout(Loadout.encode(1, 0, 0, Loadout.Melee.SLEDGEHAMMER))
	foe.global_position = start + Vector3(2, 0, 0)
	foe.velocity = Vector3.ZERO
	foe.hp = 200
	await physics_frame
	game.use_melee(p)
	check(foe.hp == 125.0 and foe.velocity.x > 2.0, "Sledgehammer hits for 75 and knocks back")
	foe.hp = 200
	foe.velocity = Vector3.ZERO
	foe.global_position = O + Vector3(60, 0, 20)
	neutral(p)
	await physics_frame

func test_armor_rules() -> void:
	check(Fighter.ARMOR_MAX == 100.0 and GameScript.ARMOR_DROP == 15.0 and GameScript.ARMOR_DROP_BEHIND == 10.0, "light armor: 15 per kill, +10 per point behind, capped at 100")

# Armor soaks damage before health, a kill drops armor for the killer's team (more when behind), and it is lost on death.
func test_armor_and_snapshot() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	var helper: Fighter = game.fighters[102]  # a teammate: with 5v5, bots 100-103 share the player's team
	check(foe.team != p.team and helper.team == p.team, "armor test fighters are on the expected teams")
	neutral(foe)
	neutral(helper)
	neutral(p)
	p.global_position = O + Vector3(-10, 0, -21)
	foe.global_position = O + Vector3(-4, 0, -21)
	helper.global_position = O + Vector3(60, 0, 20)
	foe.hp = 200
	foe.armor = 30.0
	game.damage_fighter(foe, 100.0, p.fighter_id)
	check(foe.armor == 0.0 and is_equal_approx(foe.hp, 130.0), "armor absorbs damage 1:1 before health")
	for e in game.entities.values():
		if e.kind == "armor":
			game.remove_entity(e.entity_id)
	foe.hp = 30
	foe.armor = 20.0
	game.damage_fighter(foe, 5.0, helper.fighter_id)
	game.damage_fighter(foe, 50.0, p.fighter_id)
	check(foe.hp <= 0 and p.kills >= 1, "the killer scores a kill")
	check(foe.armor == 0.0, "armor is lost on death")
	var drop: Deployable = null
	for e in game.entities.values():
		if e.kind == "armor":
			drop = e
	check(drop != null and drop.team == p.team and is_equal_approx(drop.hp, GameScript.ARMOR_DROP), "a kill drops light armor for the killer's team")
	game.match_state.owners.assign([1 - p.team, 1 - p.team, -1, 1 - p.team, p.team])
	game.drop_armor(O, p.team)
	var behind_drop: Deployable = null
	for e in game.entities.values():
		if e.kind == "armor" and e != drop:
			behind_drop = e
	check(behind_drop != null and is_equal_approx(behind_drop.hp, GameScript.ARMOR_DROP + 2.0 * GameScript.ARMOR_DROP_BEHIND), "a team two points behind gets a bigger drop")
	game.remove_entity(behind_drop.entity_id)
	game.match_state.reset()
	helper.global_position = O + Vector3(40, 0, 40)
	p.global_position = drop.global_position
	p.hp = Fighter.MAX_HEALTH
	p.armor = 0.0
	game.entities_tick(0.016)
	check(is_equal_approx(p.armor, GameScript.ARMOR_DROP) and not game.entities.has(drop.entity_id), "the killer's team picks the armor up")
	foe.hp = 200
	foe.dead_time = 0
	# Snapshot round trip carries armor and item cooldowns, and omits them when idle.
	p.armor = 31.2
	p.utility_cd = 3.5
	p.melee_cd = 0.4
	var mirror: Fighter = game.fighters[107]
	var mirror_loadout: int = mirror.loadout
	mirror.unpack(p.pack(), false)
	check(mirror.armor == 32.0 and mirror.utility_cd == 3.5 and mirror.melee_cd == 0.4, "snapshot carries armor and item cooldowns")
	mirror.apply_loadout(mirror_loadout)
	mirror.global_position = O + Vector3(60, 0, 20)  # unpack moved it onto the player
	p.apply_loadout(REFERENCE)
	check(not p.pack().has("ar") and not p.pack().has("ucd") and not p.pack().has("mcd"), "idle snapshots carry no extra fields")
	check(p.armor == 0.0 and p.utility_cd == 0.0, "a new loadout clears armor and cooldowns")
	neutral(p)
	await physics_frame
	await process_frame

func test_healpack() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	neutral(p)
	p.global_position = O + Vector3(30, 0, 30)
	var data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": "healpack", "hp": 1.0, "life": 1e9, "pos": p.global_position, "yaw": 0.0, "used": false}
	game.entity_next += 1
	game.create_entity_from(data)
	var pack: Deployable = game.entities[data.id]
	game.entities_tick(0.1)
	check(not pack.used and p.hp == Fighter.MAX_HEALTH, "health pack ignores a fighter at full health")
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

func test_items() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	neutral(p)
	p.global_position = O + Vector3(30, 0, 30)
	foe.global_position = O + Vector3(60, 0, 60)
	check(Items.entity_kind("bubble") == "bubble" and Items.entity_kind("armor2") == "armor2" and Items.entity_kind("health") == "healpack", "blockout pickup kinds map to entity kinds")
	var ids := {}
	for kind in ["bubble", "armor1", "armor2"]:
		var data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": kind, "hp": 1.0, "life": 1e9, "pos": p.global_position, "yaw": 0.0, "used": false}
		game.entity_next += 1
		game.create_entity_from(data)
		ids[kind] = data.id
		game.entities[data.id].visible = true
	# Only the bubble is in reach at first: park the armors away until needed.
	game.entities[ids.armor1].global_position = O + Vector3(30, 0, 40)
	game.entities[ids.armor2].global_position = O + Vector3(30, 0, 50)
	var bubble: Deployable = game.entities[ids.bubble]
	game.entities_tick(0.1)
	check(not bubble.used and p.hp == Fighter.MAX_HEALTH, "a health bubble ignores a fighter at full health")
	p.hp = 100.0
	game.entities_tick(0.1)
	check(is_equal_approx(p.hp, 115.0) and bubble.used and p.heal_left == 0.0, "a health bubble heals 15 at once with no regen tail")
	p.hp = 50.0
	game.entities_tick(0.1)
	check(p.hp == 50.0, "a taken bubble heals nobody until it respawns")
	game.entities_tick(Items.KINDS.bubble.respawn + 1.0)
	check(not bubble.used, "a health bubble respawns after 10 s")
	p.hp = Fighter.MAX_HEALTH - 5.0
	game.entities_tick(0.1)
	check(p.hp == Fighter.MAX_HEALTH, "a bubble never heals past full health")
	game.entities_tick(Items.KINDS.bubble.respawn + 1.0)
	# Armor tiers: stack up to the cap, either team may take them.
	p.armor = 0.0
	game.entities[ids.armor1].global_position = p.global_position
	game.entities_tick(0.1)
	check(is_equal_approx(p.armor, 50.0) and game.entities[ids.armor1].used, "armor tier 1 gives 50")
	p.armor = 20.0
	game.entities[ids.armor2].global_position = p.global_position
	game.entities_tick(0.1)
	check(is_equal_approx(p.armor, 100.0) and game.entities[ids.armor2].used, "armor tier 2 gives up to the 100 cap")
	check(Items.KINDS.armor1.respawn == 30.0 and Items.KINDS.armor2.respawn == 45.0, "armor tiers respawn after 30 s and 45 s")
	game.entities_tick(46.0)
	p.armor = Fighter.ARMOR_MAX
	game.entities_tick(0.1)
	check(not game.entities[ids.armor2].used, "armor ignores a fighter already at the cap")
	p.global_position = O + Vector3(80, 0, 80)
	foe.global_position = game.entities[ids.armor2].global_position
	foe.armor = 0.0
	foe.hp = 1.0
	foe.dead_time = 0.0
	game.entities_tick(0.1)
	check(foe.armor == 100.0 and foe.team != p.team, "the other team can take a map armor too")
	for id in ids.values():
		game.remove_entity(id)

func test_bot_items() -> void:
	var bot: Fighter = null
	for p in game.fighters.values():
		if p.bot and p.team == 0:
			bot = p
	var base := O + Vector3(100, 0, 100)
	bot.global_position = base
	bot.bot_role = Fighter.BotRole.ROAM
	neutral(bot)
	bot.bot_item = -1
	var ids := {}
	for entry in [["bubble", Vector3(8, 0, 0)], ["armor1", Vector3(12, 0, 0)], ["armor2", Vector3(0, 0, 40)]]:
		var data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": entry[0], "hp": 1.0, "life": 1e9, "pos": base + entry[1], "yaw": 0.0, "used": false}
		game.entity_next += 1
		game.create_entity_from(data)
		ids[entry[0]] = data.id
	var now := 1000.0
	bot.armor = Fighter.ARMOR_MAX
	check(not game.choose_bot_item(bot, 2, now) and bot.bot_item == -1, "a full-health, fully armored bot ignores items")
	bot.armor = 0.0
	check(game.choose_bot_item(bot, 2, now) and bot.bot_item == ids.armor1, "a bot with no armor prefers armor over a closer bubble")
	check(bot.bot_target.is_equal_approx(game.entities[ids.armor1].global_position), "the detour steers at the item")
	game.entities[ids.armor1].used = true
	game.update_bot_item(bot, now + 1.0)
	check(bot.bot_item == -1 and bot.bot_path.is_empty(), "a detour ends when the item is taken")
	bot.armor = 55.0
	bot.hp = Fighter.MAX_HEALTH
	check(not game.choose_bot_item(bot, 2, now), "a healthy bot with armor above 50 and no way to use armor 2 in range ignores everything")
	bot.hp = Fighter.MAX_HEALTH * 0.5
	check(game.choose_bot_item(bot, 2, now) and bot.bot_item == ids.bubble, "a hurt bot takes the bubble")
	game.update_bot_item(bot, now + GameScript.BOT_ITEM_TIME + 1.0)
	check(bot.bot_item == -1, "a detour times out")
	game.entities[ids.bubble].used = true
	check(not game.choose_bot_item(bot, 2, now), "a taken bubble is ignored")
	for id in ids.values():
		game.remove_entity(id)
	bot.hp = Fighter.MAX_HEALTH
	bot.armor = 0.0

func test_power_ups() -> void:
	var p: Fighter = game.local_player()
	var foe: Fighter = game.fighters[105]
	if foe.team == p.team:
		foe = game.fighters[106]
	neutral(p)
	neutral(foe)
	p.global_position = O + Vector3(0, 0, -21)
	foe.global_position = O + Vector3(0, 0, -25)
	p.hp = Fighter.MAX_HEALTH
	foe.hp = Fighter.MAX_HEALTH
	p.power = 0
	foe.power = 0
	var data := {"id": game.entity_next, "owner": -1, "team": 0, "kind": "power", "hp": float(Items.POWER_QUAD), "life": 1e9, "pos": p.global_position, "yaw": 0.0, "used": false}
	game.entity_next += 1
	game.create_entity_from(data)
	var item: Deployable = game.entities[data.id]
	game.entities_tick(0.1)
	check(p.power == Items.POWER_QUAD and is_equal_approx(p.power_time, 12.0) and item.used, "touching the power-up grants triple damage for 12 s")
	var before := foe.hp
	game.damage_fighter(foe, 10.0, p.fighter_id)
	check(is_equal_approx(before - foe.hp, 30.0), "triple damage triples what the holder deals")
	game.damage_fighter(p, 10.0, foe.fighter_id)
	check(is_equal_approx(p.hp, Fighter.MAX_HEALTH - 10.0), "the holder takes normal damage")
	check(Items.KINDS.power.respawn == 90.0, "the power-up respawns after 90 s")
	check(Items.POWER_TAKEN_CUES[1] != Items.POWER_TAKEN_CUES[2] and Sfx.stream(Items.POWER_TAKEN_CUES[1]) != Sfx.stream(Items.POWER_TAKEN_CUES[2]) and not Items.POWER_TAKEN_CUES.values().has(Items.KINDS.power.sound), "each power-up type has its own pickup cue, different from the spawn chime")
	check(Items.power_cue(16.0, 15.0) == Sfx.Kind.POWER_WARN and Items.power_cue(15.0, 14.0) == -1 and Items.power_cue(3.05, 2.95) == Sfx.Kind.POWER_TICK and Items.power_cue(1.1, 0.9) == Sfx.Kind.POWER_TICK and Items.power_cue(8.0, 7.9) == -1, "the countdown cues once at 15 s and ticks at 3, 2 and 1 s")
	check(is_equal_approx(item.pack().t, 90.0) and not Items.power_spawning_soon(true, 60.0) and Items.power_spawning_soon(true, 12.0) and not Items.power_spawning_soon(false, 12.0) and not Items.power_spawning_soon(true, 0.0), "the minimap warns only in the last 15 s of a taken power-up's timer")
	# One power-up at a time, and it respawns with a fresh roll.
	game.entities_tick(91.0)
	check(not item.used and (int(item.hp) == Items.POWER_INVULNERABLE or int(item.hp) == Items.POWER_QUAD), "the power-up respawns as one of the two types")
	game.entities_tick(0.1)
	check(not item.used and p.power == Items.POWER_QUAD, "a holder cannot take a second power-up")
	# Expiry.
	p.power_time = 0.05
	game.combat_tick(p, 0.1)
	check(p.power == 0, "a power-up ends after its timer")
	# Streak announcements: kills during one power-up escalate; the count restarts with the next pickup.
	check(Items.streak_name(1) == "" and Items.streak_name(2) == "DOUBLE KILL" and Items.streak_name(3) == "TRIPLE KILL" and Items.streak_name(4) == "QUAD KILL" and Items.streak_name(7) == "RAMPAGE", "streak names escalate from the second kill")
	p.power = Items.POWER_QUAD
	p.power_time = Items.POWER_DURATION
	p.power_kills = 0
	for i in range(2):
		foe.hp = Fighter.MAX_HEALTH
		foe.dead_time = 0.0
		game.damage_fighter(foe, 10000.0, p.fighter_id)
	check(p.power_kills == 2, "kills while holding a power-up build a streak")
	foe.hp = Fighter.MAX_HEALTH
	foe.dead_time = 0.0
	p.power = 0
	game.damage_fighter(foe, 10000.0, p.fighter_id)
	check(p.power_kills == 2, "kills without a power-up do not extend it")
	foe.hp = Fighter.MAX_HEALTH
	foe.dead_time = 0.0
	# Invincibility: nothing hurts the holder except the out-of-bounds kill.
	item.hp = float(Items.POWER_INVULNERABLE)
	item.global_position = foe.global_position
	game.entities_tick(0.1)
	check(foe.power == Items.POWER_INVULNERABLE and item.used, "the other team can take it too")
	check(foe.power_pickups == 1 and p.power_pickups >= 1, "each power-up taken counts toward the scoreboard column")
	var row_pp := 0
	for team_rows in Hud.scoreboard_rows(game):
		for row in team_rows:
			row_pp += row.pp
	check(row_pp == p.power_pickups + foe.power_pickups, "scoreboard rows carry power-up pickups")
	before = foe.hp
	game.damage_fighter(foe, 50.0, p.fighter_id)
	check(foe.hp == before, "invincibility blocks enemy damage")
	game.damage_fighter(foe, 10000.0, -1)
	check(foe.hp <= 0, "invincibility does not stop the out-of-bounds kill")
	check(foe.power == 0, "a power-up is lost on death")
	foe.hp = Fighter.MAX_HEALTH
	foe.dead_time = 0.0
	# Snapshot round trip.
	p.power = Items.POWER_INVULNERABLE
	p.power_time = 5.5
	var mirror: Fighter = game.fighters[107]
	mirror.unpack(p.pack(), false)
	check(mirror.power_pickups == p.power_pickups, "snapshot carries the power-up pickup count")
	check(mirror.power == Items.POWER_INVULNERABLE and is_equal_approx(mirror.power_time, 5.5), "snapshot carries the active power-up")
	neutral(mirror)
	p.power = 0
	check(not p.pack().has("pw"), "idle fighters carry no power-up fields")
	game.remove_entity(data.id)

func test_weapon_specs() -> void:
	var shotgun: WeaponSpec = Loadout.PRIMARIES[0]
	var rifle: WeaponSpec = Loadout.PRIMARIES[1]
	var smg: WeaponSpec = Loadout.PRIMARIES[2]
	check(shotgun.title == "Shotgun" and rifle.title == "Rifle" and smg.title == "SMG", "primary table: shotgun, rifle, smg")
	# Falloff: flat inside the start range, linear to the floor, flat after.
	check(is_equal_approx(shotgun.falloff_at(3.0), 1.0), "shotgun full damage up close")
	check(is_equal_approx(shotgun.falloff_at(13.0), 0.6), "shotgun falloff is linear (13 m of 6..20)")
	check(is_equal_approx(shotgun.falloff_at(60.0), shotgun.falloff_min), "shotgun falloff floors")
	check(is_equal_approx(rifle.falloff_at(30.0), 1.0) and rifle.falloff_at(80.0) >= 0.7 - 0.001, "rifle barely falls off")
	var last := 2.0
	for d in range(0, 100, 5):
		var f := smg.falloff_at(float(d))
		check(f <= last + 0.0001, "smg falloff never increases (%d m)" % d)
		last = f
	# Role ordering: the shotgun wins up close, the rifle at range, and reach grows shotgun < smg < rifle.
	check(shotgun.reach < smg.reach and smg.reach < rifle.reach, "reach order shotgun < smg < rifle")
	check(shotgun.body_ttk(200.0, 3.0) < smg.body_ttk(200.0, 3.0), "shotgun kills fastest point blank")
	check(rifle.body_ttk(200.0, 40.0) < smg.body_ttk(200.0, 28.0), "rifle out-trades the smg at range")
	check(shotgun.body_ttk(200.0, 19.0) > 3.0 * shotgun.body_ttk(200.0, 3.0), "shotgun collapses at range")
	check(smg.interval < 0.1 and smg.magazine >= 30, "smg is rapid fire")
	for w in Loadout.PRIMARIES:
		var t: float = w.body_ttk(200.0, 10.0)
		check(t > 0.5 and t < 4.0, "primary time-to-kill in band: %s (%.2fs)" % [w.title, t])
		print("PRIMARY TTK %s: %.2fs at 3 m, %.2fs at 25 m" % [w.title, w.body_ttk(200.0, 3.0), w.body_ttk(200.0, 25.0)])
	# Sidearms are the fallback: quick to draw, a little weaker than each primary in that primary's own range.
	for w in Loadout.SIDEARMS:
		var t: float = w.body_ttk(200.0, 10.0)
		print("SIDEARM TTK %s: %.2fs at 10 m, %.2fs at 30 m" % [w.title, t, w.body_ttk(200.0, 30.0)])
		check(t > 2.0 and t < 3.5, "sidearm time-to-kill in band: %s (%.2fs)" % [w.title, t])
		check(shotgun.body_ttk(200.0, 3.0) < w.body_ttk(200.0, 3.0), "shotgun beats the %s point blank" % w.title)
		check(smg.body_ttk(200.0, 10.0) < t, "smg beats the %s at 10 m" % w.title)
		check(rifle.body_ttk(200.0, 30.0) < w.body_ttk(200.0, 30.0), "rifle beats the %s at 30 m" % w.title)
		check(w.reach <= rifle.reach, "sidearm reach stays under the rifle's: " + w.title)
	check(Loadout.SIDEARMS[2].ricochet and not Loadout.SIDEARMS[0].ricochet, "only the revolver ricochets")

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
	check(p.hp == Fighter.MAX_HEALTH and p.ammo == p.weapon.magazine and p.slot == 0, "respawn restores health and ammunition")
	var chosen := Loadout.encode(2, 1, Loadout.Utility.BARRICADE, Loadout.Melee.SWORD)
	game.apply_loadout(p.fighter_id, chosen)
	check(p.loadout == chosen and p.weapon.title == "SMG", "loadout change permitted at spawn")
	p.global_position = Vector3.ZERO
	game.apply_loadout(p.fighter_id, REFERENCE)
	check(p.loadout == chosen, "loadout change forbidden away from spawn")
	neutral(p)
	game.last_world_tick = 100
	var count: int = game.fighters.size()
	game.apply_world({"tick": 99, "players": [], "entities": [], "match": game.match_state.pack()})
	check(game.fighters.size() == count, "stale snapshot cannot erase newly joined fighters")
	game.last_world_tick = -1
	game.match_state.winner = 1
	game.start_game("restart")
	check(game.match_state.winner == -2 and game.match_state.remaining == 720, "host restart resets round")
	check(game.entities.is_empty() and p.hp == Fighter.MAX_HEALTH, "restart clears deployables and restores fighters")

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
	var primaries := {}
	var valid := true
	for p in game.fighters.values():
		var ids := Loadout.decode(p.loadout)
		valid = valid and Loadout.encode(ids[0], ids[1], ids[2], ids[3]) == p.loadout and p.hp <= Fighter.MAX_HEALTH
		if p.bot:
			primaries[ids[0]] = true
	check(valid, "every fighter carries a valid loadout")
	check(primaries.size() == Loadout.PRIMARIES.size(), "bots carry every primary")
	game.refresh_bot_enemies()
	for p in game.fighters.values():
		if p.bot:
			p.hp = Fighter.MAX_HEALTH
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
	check(roamers >= 2, "surplus bots roam or defend instead of stacking on the point (%d)" % roamers)
	check(valid_roam, "every roaming bot has a graph node and a route")

func test_hud() -> void:
	game.set_physics_process(false)
	var victim: Fighter = game.fighters[100]
	var killer: Fighter = game.fighters[105]
	victim.team = 0
	killer.team = 1
	victim.global_position = O + Vector3(0, 0, 20)
	killer.global_position = O + Vector3(1, 0, 20)
	victim.hp = Fighter.MAX_HEALTH
	var before: int = game.hud.feed.size()
	var kills_before: int = killer.kills
	var deaths_before: int = victim.deaths
	game.damage_fighter(victim, 10000, 105)
	check(killer.kills == kills_before + 1 and victim.deaths == deaths_before + 1, "kill increments killer kills and victim deaths")
	check(game.hud.feed.size() == mini(5, before + 1) and game.hud.feed[0].killer == "%s · %s" % [killer.callsign(), killer.weapon.title] and game.hud.feed[0].victim == victim.callsign(), "kill feed records the kill and the weapon")
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
	game.hud.refresh(game, 0.016)  # physics is off in tests, so nothing has handed the HUD its game yet
	check(mini.game == game, "the HUD wires the minimap to the game")
	# Drawing only works inside a draw notification: let the minimap redraw itself with the pack above the player.
	var drawn := [false]
	var on_draw := func(): drawn[0] = true
	mini.draw.connect(on_draw)
	mini.queue_redraw()
	await process_frame
	await process_frame
	mini.draw.disconnect(on_draw)
	check(drawn[0], "minimap redraws with a health pack on another tier")
	game.remove_entity(pack_data.id)
	check(not CivicDividend.footprints.is_empty(), "map records building footprints for the minimap")
	var row_sizes: Array = game.menu.item_buttons.map(func(row): return row.size())
	check(row_sizes == Loadout.slot_sizes(), "menu has a button per item in every loadout slot")
	var picked: int = game.selected_loadout
	game.menu._pick(2, Loadout.Utility.SENTRY_TURRET)
	check(Loadout.utility(game.selected_loadout) == Loadout.Utility.SENTRY_TURRET and Loadout.primary(game.selected_loadout) == Loadout.primary(picked), "picking a menu item changes only its slot")
	game.selected_loadout = picked
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
	check(Sfx.stream(Sfx.Kind.SHOT_SHOTGUN) == Sfx.stream(Sfx.Kind.SHOT_SHOTGUN), "cues are cached")

func test_effect_pool() -> void:
	var root_node: Node3D = game.tracer_root
	for i in range(600):
		Vfx.tracer(root_node, Vector3(0, 1, 0), Vector3(20, 1, 0), Vfx.Style.REVOLVER, Color.WHITE, true)
	check(root_node.get_child_count() <= Vfx.MAX_EFFECT_NODES + 40, "effect nodes stay capped under a tracer flood (%d)" % root_node.get_child_count())

func test_visual_pipeline() -> void:
	# Writing ALPHA in the opaque map shader moves every map mesh into the transparent pipeline
	# (no depth writes), which made walls draw on top of each other.
	check(Visuals.SURFACE_SHADER.find("ALPHA") == -1, "map surface shader stays in the opaque pipeline")
	check(Visuals.surface("glass", Color.WHITE) is StandardMaterial3D, "glass uses its own transparent material")

func test_input_forgiveness() -> void:
	await physics_frame
	var p: Fighter = game.local_player()
	neutral(p)
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
	neutral(p)
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

func test_wall_run() -> void:
	await physics_frame
	var p: Fighter = game.local_player()
	neutral(p)
	p.held = 0
	# The proving-ground end wall faces -x at x=89.5; running along -z keeps it on the right-hand side.
	var start := O + Vector3(88.9, 6.0, 25.0)
	p.yaw = 0.0
	p.movement = Vector2(0, -1)
	p.wall_normal = Vector3.ZERO
	p.wall_repeats = 0
	place(p, start, Vector3(0, 0, -9))
	p.air_jump = false
	p.air_dash = false
	p.dash_cd = Fighter.DASH_COOLDOWN  # a spent dash: it would otherwise recharge on its (finished) timer
	for i in range(3):
		p.simulate_movement(1.0 / 60, 0)
	check(p.wall_running, "running along a wall at speed attaches a wall run")
	var top := p.global_position.y
	var frames := 3
	while p.wall_running and frames < 120:
		p.simulate_movement(1.0 / 60, 0)
		frames += 1
	check(frames >= 45 and frames <= 66, "wall run lasts about 0.9 s (%d frames)" % frames)
	check(top - p.global_position.y < 3.0, "wall run barely loses height (%.2f m, free fall is about 10 m)" % (top - p.global_position.y))
	check(not p.air_jump and not p.air_dash, "wall run restores neither the double jump nor the dash")
	check(p.wall_run_cd > 0.0, "ending a wall run starts a re-attach cooldown")
	await physics_frame
	# Space exits with the wall kick, away from the wall.
	p.wall_run_cd = 0.0
	p.global_position = start
	p.velocity = Vector3(0, 0, -9)
	for i in range(10):
		p.simulate_movement(1.0 / 60, 0)
	var attached := p.wall_running
	p.simulate_movement(1.0 / 60, 1)
	check(attached and not p.wall_running and p.velocity.x < -6.0 and p.velocity.y > 9.5, "jump kicks off a wall run away from the wall (%s)" % p.velocity)
	await physics_frame
	# Head-on contact and slow speed do not attach.
	p.wall_run_cd = 0.0
	p.yaw = -PI / 2
	p.global_position = O + Vector3(88.4, 6.0, 10.0)
	p.velocity = Vector3(9, 0, 0)
	for i in range(3):
		p.simulate_movement(1.0 / 60, 0)
	check(not p.wall_running, "a head-on hit does not start a wall run")
	await physics_frame
	p.yaw = 0.0
	p.global_position = start
	p.velocity = Vector3(0, 0, -3)
	for i in range(3):
		p.simulate_movement(1.0 / 60, 0)
	check(not p.wall_running, "moving too slowly does not start a wall run")
	await physics_frame
	# Hot Lap (after letting go of a Grapple) runs longer.
	p.hot_lap = 2.0
	p.movement = Vector2(0, -1)
	p.global_position = start
	p.velocity = Vector3(0, 0, -9)
	for i in range(3):
		p.simulate_movement(1.0 / 60, 0)
	check(p.wall_running and p.wall_run_time > 1.2, "Hot Lap extends the wall run (%.2f s)" % p.wall_run_time)
	neutral(p)
	await physics_frame

func test_ledges() -> void:
	await physics_frame
	var p: Fighter = game.local_player()
	neutral(p)
	p.held = 0
	# Vault: running into the 1.2 m crate (x -4.5..-1.5) carries you over without stopping.
	p.yaw = -PI / 2
	p.movement = Vector2(0, -1)
	p.global_position = O + Vector3(-10, 0, 5)
	p.velocity = Vector3(8, 0, 0)
	var vaulted := false
	var crossed_at := -1
	for i in range(150):
		p.simulate_movement(1.0 / 60, 0)
		vaulted = vaulted or p.vault_time > 0.0
		if crossed_at < 0 and p.global_position.x > O.x - 1.0:
			crossed_at = i
	check(vaulted and crossed_at >= 0 and crossed_at < 120, "running into a low crate vaults over it (crossed at frame %d)" % crossed_at)
	await physics_frame
	# Ledge grab: reaching a 2.4 m ledge (x from 20) in the air hangs briefly, then pulls up.
	var ledge_start := O + Vector3(19.5, 0.9, 6.0)
	p.yaw = -PI / 2
	p.movement = Vector2.ZERO
	place(p, ledge_start)
	p.simulate_movement(1.0 / 60, 0)  # let the floor contact from the vault run clear
	p.velocity = Vector3(2, 0, 0)
	p.movement = Vector2(0, -1)
	p.hang_cd = 0.0
	p.ledge_cd = 0.0
	p.simulate_movement(1.0 / 60, 0)
	check(p.hang_time > 0.0 and p.velocity.length() < 0.01, "a high ledge reached in the air is grabbed")
	var peak := -99.0
	for i in range(30):
		p.simulate_movement(1.0 / 60, 0)
		peak = maxf(peak, p.velocity.y)
	check(peak > 8.0 and p.hang_time <= 0.0, "the hang ends in a pull-up (peak vy %.1f)" % peak)
	await physics_frame
	# Jump during a hang kicks off the ledge face.
	p.global_position = ledge_start
	p.velocity = Vector3(2, 0, 0)
	p.hang_cd = 0.0
	p.ledge_cd = 0.0
	p.wall_normal = Vector3.ZERO
	p.wall_repeats = 0
	p.simulate_movement(1.0 / 60, 0)
	var hung := p.hang_time > 0.0
	p.simulate_movement(1.0 / 60, 1)
	check(hung and p.hang_time == 0.0 and p.velocity.x < -5.0 and p.velocity.y > 9.5, "jump kicks off a ledge hang (%s)" % p.velocity)
	await physics_frame
	# Back or slide drops from the ledge without being pulled up again.
	p.global_position = ledge_start
	p.velocity = Vector3(2, 0, 0)
	p.hang_cd = 0.0
	p.ledge_cd = 0.0
	p.simulate_movement(1.0 / 60, 0)
	var hung_again := p.hang_time > 0.0
	p.movement = Vector2(0, 1)
	p.simulate_movement(1.0 / 60, 0)
	check(hung_again and p.hang_time == 0.0 and p.velocity.y < 4.0 and p.ledge_cd > 0.0, "holding back drops from a ledge hang")
	p.movement = Vector2.ZERO
	await physics_frame

func test_air_movement() -> void:
	# move_and_slide uses the physics delta only inside a physics frame, so each section starts on one.
	await physics_frame
	var p: Fighter = game.local_player()
	neutral(p)
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
	place(p, O + Vector3(-30, 6.0, -20), Vector3(0, -2, 0))
	p.simulate_movement(1.0 / 60, 0)
	p.coyote_time = 0.0  # the tick above still saw the old floor contact
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
	check(p.global_position.x - start_x > 3.5, "air dash travels over 3.5 m in half a second (%.1f)" % (p.global_position.x - start_x))
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
