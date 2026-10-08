extends SceneTree

# Renders the character rig lineup into res://docs/previews/characters.png (a row of looks in both team trims, 3/4
# view) and characters_close.png (one head-on close-up), for checking the squat low-poly style by eye.
#   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/render_characters.gd

const LOOKS := [
	{"body": 1, "skin": 1, "eyes": 0, "hair": 0, "hair_color": 9, "headgear": 3, "top": 2, "top_color": 3, "bottom": 0, "bottom_color": 4, "shoes": 0, "shoe_color": 0},
	{"body": 0, "skin": 4, "eyes": 1, "hair": 1, "hair_color": 9, "headgear": 5, "top": 4, "top_color": 6, "bottom": 3, "bottom_color": 8, "shoes": 2, "shoe_color": 0},
	{"body": 2, "skin": 2, "eyes": 2, "hair": 3, "hair_color": 0, "headgear": 2, "top": 3, "top_color": 4, "bottom": 1, "bottom_color": 3, "shoes": 1, "shoe_color": 1},
	{"body": 1, "skin": 0, "eyes": 5, "hair": 4, "hair_color": 7, "headgear": 0, "top": 0, "top_color": 0, "bottom": 2, "bottom_color": 5, "shoes": 0, "shoe_color": 9},
	{"body": 1, "skin": 6, "eyes": 3, "hair": 5, "hair_color": 3, "headgear": 1, "top": 1, "top_color": 7, "bottom": 1, "bottom_color": 1, "shoes": 2, "shoe_color": 11},
	{"body": 0, "skin": 3, "eyes": 6, "hair": 2, "hair_color": 6, "headgear": 4, "top": 1, "top_color": 9, "bottom": 0, "bottom_color": 1, "shoes": 1, "shoe_color": 2},
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2a2d33")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c2dc")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	floor_mesh.material_override = Visuals.solid(Color("6b5a4a"))
	world.add_child(floor_mesh)
	var rigs := []
	for i in range(LOOKS.size()):
		var holder := Node3D.new()
		world.add_child(holder)
		holder.position = Vector3((i - (LOOKS.size() - 1) / 2.0) * 1.15, 0, 0)
		holder.rotation.y = PI - 0.45  # rigs face -Z: turn them three-quarters toward the camera
		var outlines: Array = []
		var rig := CharacterRig.build(holder, Visuals.team_color(i % 2), outlines, false, i % 3, i % 3, i % 3, Appearance.encode(LOOKS[i]))
		for o in outlines:
			o.set_shader_parameter("outline_color", Visuals.ALLY_OUTLINE if i % 2 == 0 else Visuals.ENEMY_OUTLINE)
		CharacterRig.set_active_slot(rig, 0)
		rigs.append(rig)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 34
	cam.position = Vector3(0, 1.5, 8.6)
	cam.look_at(Vector3(0, 0.95, 0))
	for i in range(3):
		for rig in rigs:
			CharacterRig.animate(rig, 1.0 / 60, 0.0, true, 0.0, false)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/characters.png")
	print("SAVED characters")
	cam.fov = 30
	cam.position = Vector3(rigs[0].get_parent().position.x + 0.6, 1.7, 2.1)
	cam.look_at(rigs[0].get_parent().position + Vector3(0, 1.25, 0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/previews/characters_close.png")
	print("SAVED characters_close")
	quit()
