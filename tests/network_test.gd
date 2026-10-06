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
	game.selected_class = 3
	var server := "--server" in OS.get_cmdline_user_args()
	game.start_game("host" if server else "join")
	print("NETWORK START: ", "server" if server else "client", " running=", game.running, " status=", game.menu_status.text)
	if server:
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
		verify(game.fighters.size() == 12, "joining human replaces bot, keeping 6v6")
		verify(game.match_state.unlocked.count(true) <= 2, "server frontier remains valid")
		# Test movement and swaps in a clear lane, independent of random spawn traffic.
		for p in game.fighters.values():
			if not p.bot and p.fighter_id != 1:
				p.global_position = CivicDividend.test_lane
				p.velocity = Vector3.ZERO
		print("COMPRESSED SNAPSHOT: ", game.encode_world().size(), " bytes")
		await create_timer(4).timeout
	else:
		for i in range(80):
			if game.local_player() != null:
				break
			await create_timer(0.1).timeout
		verify(game.local_player() != null, "client receives fighter snapshot")
		if game.local_player() != null:
			await create_timer(0.5).timeout
			verify(not game.authoritative and game.fighters.size() == 12, "client is nonauthoritative and receives roster")
			var p: Fighter = game.local_player()
			verify(p.class_id == 3, "requested class assigned by server")
			verify(p.global_position.distance_to(CivicDividend.test_lane) < 10, "client receives server relocation into clear test lane")
			# Place and exchange with a nearby double on flat ground.
			p.pitch = -0.25
			game.input_edges |= 8
			await create_timer(0.6).timeout
			verify(p.double_id >= 0 and game.entities.has(p.double_id), "reliable ability action creates replicated double")
			if game.entities.has(p.double_id):
				var original := p.global_position
				game.input_edges |= 8
				await create_timer(0.6).timeout
				verify(game.entities[p.double_id].used, "server swaps double once")
				verify(p.global_position.distance_to(original) > 0.5, "client reconciles authoritative teleport")
			Input.action_press("back")
			var before := p.global_position
			await create_timer(0.4).timeout
			Input.action_release("back")
			verify(p.global_position.distance_to(before) > 0.5, "predicted movement survives latency and dropped motion packets")
		await create_timer(0.5).timeout
	print("NETWORK RESULT: ", "FAIL" if failed else "PASS")
	game.running = false
	game.set_physics_process(false)
	await create_timer(0.6).timeout
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
