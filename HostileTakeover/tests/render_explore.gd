extends SceneTree

# Renders the menu and exploration HUD at the window size given with --resolution, to check scaling/layout.
# Usage: godot --path . --resolution 2560x1080 --script res://tests/render_resolutions.gd -- tag=ultrawide
func _initialize() -> void:
	call_deferred("run")

func shot(path: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var tag := "default"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("tag="):
			tag = arg.get_slice("=", 1)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	await shot("res://docs/previews/explore_%s_menu.png" % tag)
	game.start_game("explore")
	var p: Fighter = game.local_player()
	p.global_position = Vector3(-57, 0.1, 5)
	p.yaw = -PI / 2
	game.announce("EXPLORATION · Free roam. No objectives, no opposition.")
	await shot("res://docs/previews/explore_%s_hud.png" % tag)
	print("%s window=%s content=%s" % [tag, root.size, root.get_visible_rect().size])
	quit()
