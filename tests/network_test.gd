extends SceneTree

var game: Node3D
var failed := false

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, value: String) -> void:
	print("PASS: " if condition else "FAIL: ", value)
	failed = failed or not condition

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.selected_loadout = Loadout.encode(1, 2, Loadout.Utility.LAUNCH_PAD, Loadout.Melee.KNIFE)
	game.selected_look = Appearance.encode({"body": 2, "skin": 5, "hair": 1, "hair_color": 6, "headgear": 2, "top": 4, "top_color": 7})
	var server := "--server" in OS.get_cmdline_user_args()
	game.start_game("host" if server else "join")
	print("NETWORK START: ", "server" if server else "client", " running=", game.running, " status=", game.menu_status.text)
	if server:
		# Faster guns make random bot combat unsuitable for input/replication assertions.
		for fighter in game.fighters.values():
			if fighter.bot:
				fighter.hp = 0
				fighter.dead_time = 1000
				fighter.update_visual()
		var humans := 0
		for i in range(200):
			humans = 0
			for p in game.fighters.values():
				if not p.bot:
					humans += 1
			if humans == 2:
				break
			await create_timer(0.1).timeout
		verify(humans == 2, "server admits a second human")
		verify(game.fighters.size() == CivicDividend.TEAM_SIZE * 2, "joining human replaces bot, keeping a full roster")
		verify(game.match_state.unlocked.count(true) <= 2, "server frontier remains valid")
		# Test movement and swaps in a clear lane, independent of random spawn traffic.
		for p in game.fighters.values():
			if not p.bot and p.fighter_id != 1:
				p.global_position = CivicDividend.test_lane
				p.velocity = Vector3.ZERO
		print("COMPRESSED SNAPSHOT: ", game.encode_world().size(), " bytes")
		await create_timer(4).timeout
		var visitor: Fighter
		for fighter in game.fighters.values():
			if not fighter.bot and fighter.fighter_id != 1:
				visitor = fighter
		if visitor != null:
			visitor.global_position = game.spawn_position(visitor)
			visitor.velocity = Vector3.ZERO
			var stage := 0
			for i in range(200):
				if stage == 0 and visitor.primary.title == "Grenade Launcher":
					visitor.global_position = CivicDividend.test_lane
					visitor.velocity = Vector3.ZERO
					stage = 1
				elif stage == 1 and visitor.weapon.title == "Disc Launcher" and visitor.ammo < visitor.weapon.magazine:
					visitor.global_position = game.spawn_position(visitor)
					visitor.velocity = Vector3.ZERO
					stage = 2
				elif stage == 2 and visitor.primary.title == "Double-Barrel Shotgun":
					visitor.global_position = CivicDividend.test_lane
					visitor.velocity = Vector3.ZERO
					stage = 3
				elif stage == 3 and visitor.ammo == 0 and visitor.weapon_impulse_sequence > 0:
					stage = 4
					await create_timer(2).timeout
					break
				await create_timer(0.1).timeout
			verify(stage == 4, "server executes new loadouts, projectiles and recoil alternate fire")
	else:
		for i in range(80):
			if game.local_player() != null:
				break
			await create_timer(0.1).timeout
		verify(game.local_player() != null, "client receives fighter snapshot")
		if game.local_player() != null:
			await create_timer(0.5).timeout
			verify(not game.authoritative and game.fighters.size() == CivicDividend.TEAM_SIZE * 2, "client is nonauthoritative and receives roster")
			var p: Fighter = game.local_player()
			verify(p.loadout == game.selected_loadout, "requested loadout assigned by server")
			verify(p.weapon.title == "Rifle" and p.sidearm.title == "Revolver", "loadout guns replicated to the client")
			verify(p.look == game.selected_look, "the chosen look reaches the server and comes back in snapshots")
			var bot_looks := {}
			for other in game.fighters.values():
				bot_looks[other.look] = true
			verify(bot_looks.size() >= 5, "the client sees the bots' varied looks")
			verify(p.global_position.distance_to(CivicDividend.test_lane) < 10, "client receives server relocation into clear test lane")
			# Place a launch pad on flat ground: a reliable utility action, replicated back as an entity.
			p.pitch = -0.25
			game.input_edges |= game.EDGE_UTILITY
			await create_timer(0.6).timeout
			var pads: Array = game.entities.values().filter(func(e): return e.kind == "pad" and e.owner_id == p.fighter_id)
			verify(pads.size() == 1, "reliable utility action creates a replicated launch pad")
			verify(p.utility_cd > 0.0, "server starts the utility cooldown and replicates it")
			# Swap to the sidearm and back; the server owns the slot and both magazines.
			game.input_edges |= game.EDGE_SWAP
			await create_timer(0.6).timeout
			verify(p.slot == 1 and p.weapon.title == "Revolver" and p.stowed_ammo == p.primary.magazine, "server swaps to the sidearm and replicates it")
			game.input_edges |= game.EDGE_SWAP
			await create_timer(0.6).timeout
			verify(p.slot == 0 and p.weapon.title == "Rifle", "server swaps back to the primary")
			Input.action_press("back")
			var before := p.global_position
			await create_timer(0.4).timeout
			Input.action_release("back")
			verify(p.global_position.distance_to(before) > 0.5, "predicted movement survives latency and dropped motion packets")
			for i in range(50):
				if absf(p.global_position.x) > 80:
					break
				await create_timer(0.1).timeout
			game.selected_loadout = Loadout.encode(4, 4, Loadout.Utility.LAUNCH_PAD, Loadout.Melee.KNIFE)
			game.request_loadout(game.selected_loadout, game.selected_look)
			for i in range(40):
				if p.primary.title == "Grenade Launcher" and absf(p.global_position.x) < 80:
					break
				await create_timer(0.1).timeout
			verify(p.primary.title == "Grenade Launcher" and p.sidearm.title == "Disc Launcher", "new loadout indices replicate through the existing RPC")
			p.pitch = 0.6
			await create_timer(0.2).timeout
			Input.action_press("fire")
			await create_timer(0.15).timeout
			Input.action_release("fire")
			await create_timer(0.35).timeout
			verify(game.launcher_grenade_count(p.fighter_id) == 1 and p.ammo == 3, "client sees authoritative grenade projectile and ammo (%d active, %d rounds)" % [game.launcher_grenade_count(p.fighter_id), p.ammo])
			await create_timer(0.6).timeout
			game.input_edges |= game.EDGE_ALT
			await create_timer(0.4).timeout
			verify(game.launcher_grenade_count(p.fighter_id) == 0 and p.ammo == 3, "reliable alternate action detonates and reconciles the projectile")
			game.input_edges |= game.EDGE_SWAP
			await create_timer(0.4).timeout
			Input.action_press("fire")
			await create_timer(0.12).timeout
			Input.action_release("fire")
			await create_timer(0.3).timeout
			verify(game.projectiles.values().any(func(shot): return shot.owner_id == p.fighter_id and shot.spec.title == "Disc Launcher"), "disc sidearm projectile appears on the client")
			for i in range(40):
				if absf(p.global_position.x) > 80:
					break
				await create_timer(0.1).timeout
			game.selected_loadout = Loadout.encode(8, 4, Loadout.Utility.LAUNCH_PAD, Loadout.Melee.KNIFE)
			game.request_loadout(game.selected_loadout, game.selected_look)
			for i in range(40):
				if p.primary.title == "Double-Barrel Shotgun" and absf(p.global_position.x) < 80:
					break
				await create_timer(0.1).timeout
			p.pitch = -1.2
			await create_timer(0.2).timeout
			var impulse_before := p.weapon_impulse_sequence
			var launch_height := p.global_position.y
			game.input_edges |= game.EDGE_ALT
			await create_timer(0.5).timeout
			verify(p.ammo == 0 and p.weapon_impulse_sequence == impulse_before + 1 and p.global_position.y > launch_height + 0.25, "recoil launch survives latency and dropped snapshots")
			await create_timer(0.2).timeout
			verify(p.weapon_impulse_sequence == impulse_before + 1, "repeated snapshots cannot duplicate the launch")
		await create_timer(0.5).timeout
	print("NETWORK RESULT: ", "FAIL" if failed else "PASS")
	game.running = false
	game.set_physics_process(false)
	await create_timer(0.6).timeout
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
