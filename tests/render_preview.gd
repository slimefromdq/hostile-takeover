extends SceneTree

# Renders res://docs/previews/preview.png (gameplay view) and res://docs/previews/preview_classes.png (class lineup).
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
	# Lineup: every hero, allies (left row) and enemies (right row) facing the camera.
	for p in game.fighters.values():
		p.global_position = Vector3(0, -50, 80)
	var spots := []
	for i in range(Fighter.SPECS.size()):
		var ally: Fighter = game.fighters[1] if i == 0 else game.fighters[100 + i - 1]
		spots.append(ally)
	var x := -6.0
	game.set_physics_process(false)
	var order := range(Fighter.SPECS.size())
	for i in range(Fighter.SPECS.size()):
		var f: Fighter = spots[i]
		f.team = 0
		f.change_class(order[i])
		f.global_position = Vector3(x + i * 3.0, 0, -12)
		f.yaw = PI
		f.pitch = 0.0
		f.velocity = Vector3.ZERO
		f.hp = f.spec.health
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
	root.get_texture().get_image().save_png("res://docs/previews/preview_classes.png")
	print("RENDER PREVIEW SAVED")
	game.queue_free()
	await process_frame
	quit()
