extends SceneTree

# Samples where bots are during a simulated match to confirm they spread across the routes.
func _initialize() -> void:
	call_deferred("run")

func level_of(p: Vector3) -> String:
	if absf(p.x) > 80:
		return "depot"
	if p.y > 4.0:
		return "roof"
	if p.y < -2.0:
		return "trench"
	if absf(p.z) > 30.0:
		return "alley"
	if absf(p.z) > 12.0:
		return "block"
	return "boulevard"

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	var totals := {}
	var samples := 0
	for t in range(0, 180, 3):
		await create_timer(3.0).timeout
		for p in game.fighters.values():
			if p.bot and p.hp > 0:
				var k := level_of(p.global_position)
				totals[k] = totals.get(k, 0) + 1
				samples += 1
	print("BOT ROUTES (samples=%d): %s" % [samples, totals])
	print("OWNERS ", game.match_state.owners)
	game.queue_free()
	await process_frame
	quit()
