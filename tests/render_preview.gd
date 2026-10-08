extends SceneTree

# Renders res://docs/previews/preview.png (gameplay view) and res://docs/previews/preview_loadouts.png (loadout lineup).
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	game.local_player().global_position = Vector3(-50, 0.1, -2)
	game.local_player().yaw = -PI / 2
	game.local_player().pitch = -0.05
	await create_timer(3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/preview.png")
	# Lineup: the shared body holding each primary and sidearm, facing the camera.
	for p in game.fighters.values():
		p.global_position = Vector3(0, -50, 80)
	var spots := []
	var lineup := [Loadout.encode(0, 0, 0, 0), Loadout.encode(1, 1, 0, 1), Loadout.encode(2, 2, 0, 2), Loadout.encode(1, 0, 0, 2), Loadout.encode(0, 2, 0, 1)]
	for i in range(lineup.size()):
		var ally: Fighter = game.fighters[1] if i == 0 else game.fighters[100 + i - 1]
		spots.append(ally)
	var x := -6.0
	game.set_physics_process(false)
	for i in range(lineup.size()):
		var f: Fighter = spots[i]
		f.team = 0
		f.apply_loadout(lineup[i])
		if i >= 3:
			f.swap_weapon()  # the last two show their sidearm
		f.global_position = Vector3(x + i * 3.0, 0, -12)
		f.yaw = PI
		f.pitch = 0.0
		f.velocity = Vector3.ZERO
		f.hp = Fighter.MAX_HEALTH
	game.local_player().camera.current = false
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = Vector3(0, 1.5, -6.5)
	cam.fov = 55
	cam.look_at(Vector3(0, 1.0, -12))
	cam.current = true
	game.hud.hide()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/preview_loadouts.png")
	print("RENDER PREVIEW SAVED")
	game.queue_free()
	await process_frame
	quit()
