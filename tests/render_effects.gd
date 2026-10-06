extends SceneTree

# Renders res://docs/previews/preview_effects.png: tracer styles, rings, impacts and deployable models.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	game.set_physics_process(false)
	ProvingGround.build(game)
	var O := ProvingGround.ORIGIN
	for p in game.fighters.values():
		p.global_position = Vector3(0, -50, 80)
	var me: Fighter = game.local_player()
	me.global_position = O + Vector3(30, 0, -3)
	me.camera.current = false
	var kinds := ["turret", "pad", "cover", "smoke"]
	for i in range(4):
		game.create_entity(me, kinds[i], O + Vector3(-6 + i * 4.0, 0.05, -14), 100, 90)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.fov = 60
	cam.global_position = O + Vector3(0, 2.2, 1.0)
	cam.look_at(O + Vector3(0, 1.2, -12))
	cam.current = true
	game.hud.hide()
	Vfx.time_scale = 12.0
	await create_timer(0.6).timeout
	var col: Color = game.team_color(0)
	var styles := [1, 2, 3, 4, 5, 6, 7]
	for i in range(styles.size()):
		var x := -6.0 + i * 2.0
		game.show_trace(O + Vector3(x, 1.5, -4), O + Vector3(x, 1.5 + 0.2 * i, -16), col, styles[i], true)
	game.show_ring(O + Vector3(0, 0, -9), 2.5, Color("ffde8d"))
	game.show_trace(O + Vector3(-1, 1.2, -4), O + Vector3(-1, 1.2, -9), Color.WHITE, 8)
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/preview_effects.png")
	print("EFFECTS SAVED")
	quit()
