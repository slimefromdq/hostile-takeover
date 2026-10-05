extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	game.local_player().global_position = Vector3(-11, 0.1, -7)
	game.local_player().yaw = -PI / 2
	game.local_player().pitch = -0.08
	await create_timer(3).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://preview.png")
	print("RENDER PREVIEW SAVED")
	game.queue_free()
	await process_frame
	quit()
