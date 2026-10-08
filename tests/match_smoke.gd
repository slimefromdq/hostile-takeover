extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	await create_timer(120).timeout
	var advancing := 0
	var finite := true
	for p in game.fighters.values():
		if p.bot and absf(p.global_position.x) < 60:
			advancing += 1
		finite = finite and p.global_position.is_finite() and p.velocity.is_finite()
	var objective_pressure: bool = game.match_state.owners[2] != -1 or game.match_state.progress[2] > 0
	var passed: bool = game.fighters.size() == CivicDividend.TEAM_SIZE * 2 and advancing >= 3 and finite and objective_pressure and game.match_state.unlocked.count(true) <= 2
	print("MATCH SMOKE: roster=%d advancing=%d center_owner=%d center_progress=%.2f finite=%s" % [game.fighters.size(), advancing, game.match_state.owners[2], game.match_state.progress[2], finite])
	print("MATCH RESULT: ", "PASS" if passed else "FAIL")
	if not passed:
		for p in game.fighters.values():
			print("BOT POSITION: ", p.fighter_id, " ", p.global_position, " hp=", p.hp)
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
