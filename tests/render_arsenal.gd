extends SceneTree

# Procedural gun gallery, rendered at 1920x1080 to docs/previews/arsenal.png.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color("141b29")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var heading := Label.new()
	heading.text = "HOSTILE TAKEOVER / MOVEMENT ARSENAL"
	heading.position = Vector2(28, 15)
	heading.add_theme_font_size_override("font_size", 32)
	background.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(20, 70)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	background.add_child(grid)
	for i in range(14):
		var sidearm := i >= Loadout.PRIMARIES.size()
		var index := i - Loadout.PRIMARIES.size() if sidearm else i
		var spec: WeaponSpec = Loadout.SIDEARMS[index] if sidearm else Loadout.PRIMARIES[index]
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(366, 300)
		grid.add_child(card)
		var title := Label.new()
		title.text = spec.title
		title.add_theme_font_size_override("font_size", 19)
		card.add_child(title)
		var container := SubViewportContainer.new()
		container.custom_minimum_size = Vector2(366, 242)
		card.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(366, 242)
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("273247")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d7e5ff")
		environment.environment.ambient_light_energy = 0.6
		world.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, -35, 0)
		world.add_child(sun)
		var holder := Node3D.new()
		holder.rotation.y = PI - 0.6
		world.add_child(holder)
		var outlines: Array = []
		var rig := CharacterRig.build(holder, Visuals.team_color(i % 2), outlines, false, 0 if sidearm else index, index if sidearm else 0, 0)
		CharacterRig.set_active_slot(rig, 1 if sidearm else 0)
		CharacterRig.animate(rig, 0.016, 0, true, 0, false)
		var cam := Camera3D.new()
		cam.position = Vector3(0, 1.25, 3.5)
		cam.fov = 40
		world.add_child(cam)
		cam.look_at(Vector3(0, 1, 0))
		cam.current = true
		var info := Label.new()
		info.text = "%s · ideal body TTK %.2fs" % ["SIDEARM" if sidearm else "PRIMARY", spec.body_ttk()]
		info.add_theme_font_size_override("font_size", 14)
		card.add_child(info)
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/arsenal.png")
	print("SAVED arsenal.png")
	quit()
