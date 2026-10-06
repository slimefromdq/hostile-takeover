extends SceneTree

# Renders res://docs/previews/preview_hud.png, preview_scoreboard.png and preview_menu.png.
func _initialize() -> void:
	call_deferred("run")

func shot(path: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	await shot("res://docs/previews/preview_menu.png")
	game.start_game("offline")
	var p: Fighter = game.local_player()
	p.global_position = Vector3(-57, 0.1, 5)
	p.yaw = -PI / 2
	p.hp = 60.0
	p.ammo = 17
	p.cooldowns[0] = 3.5
	p.cooldowns[2] = 1.2
	game.match_state.progress[2] = 0.45
	game.match_state.owners[2] = 1
	game.match_state.unlocked.assign([false, false, true, true, false])
	game.hud.add_kill("Skyrunner", 0, "Enforcer", 1)
	game.hud.add_kill("Mirage Agent", 1, "Field Engineer", 0)
	game.hud.hit(1)
	game.hud.damaged(p.global_position + Vector3(10, 0, 4))
	game.announce("NEW CONTRACT · Center point unlocked.")
	for f in game.fighters.values():
		f.kills = f.fighter_id % 4
		f.deaths = f.fighter_id % 3
	await shot("res://docs/previews/preview_hud.png")
	Input.action_press("scoreboard")
	await shot("res://docs/previews/preview_scoreboard.png")
	Input.action_release("scoreboard")
	print("HUD SAVED")
	quit()
