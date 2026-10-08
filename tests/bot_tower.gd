extends SceneTree

# A bot starting north of point C climbs the gatehouse on Concrete Canopy (span ladder, then the launch pad or booth
# ladder) and takes the power-up on the booth over C, 12 m up. Run: godot --headless --fixed-fps 60 --path . --script res://tests/bot_tower.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var previous := BlockoutImporter.selected_path()
	BlockoutImporter.select("res://maps/canopy.blockout.json")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	var tower: Deployable = null
	for e in game.entities.values():
		if e.kind == "power":
			tower = e
	var bot: Fighter = null
	for p in game.fighters.values():
		if p.bot and p.team == 0:
			bot = p
	var passed := tower != null and bot != null
	var best_height := 0.0
	if passed:
		# Everyone else keeps to the depot so only this bot goes for it.
		for p in game.fighters.values():
			if p != bot:
				p.global_position = CivicDividend.spawn_slot_position(p.team, p.spawn_slot)
				p.bot = false
		tower.used = false
		tower.timer = 0.0
		tower.hp = float(Items.POWER_QUAD)
		var start: Vector3 = game.bot_graph.positions[game.bot_graph.node("n3b")]
		bot.global_position = start + Vector3(0, 0.2, 0)
		bot.velocity = Vector3.ZERO
		bot.hp = Fighter.MAX_HEALTH
		var elapsed := 0.0
		while elapsed < 60.0 and bot.power_pickups == 0:
			await create_timer(0.25).timeout
			elapsed += 0.25
			best_height = maxf(best_height, bot.global_position.y)
			if bot.bot_item < 0 and bot.hp > 0:
				game.choose_bot_item(bot, game.frontier_point(bot), Time.get_ticks_msec() / 1000.0)
		passed = bot.power_pickups == 1 and bot.power != 0
		print("BOT TOWER: took=%d at t=%.1f s, best height %.1f, now at %s" % [bot.power_pickups, elapsed, best_height, bot.global_position])
	print("BOT TOWER RESULT: ", "PASS" if passed else "FAIL")
	BlockoutImporter.select(previous)
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
