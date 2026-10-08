extends SceneTree

# godot --path . --resolution 1920x1080 --script res://tests/render_yacht_club.gd -- --map=res://maps/yacht_club.blockout.json
const SHOTS := {
	"top": [Vector3(0, 180, 0.01), Vector3.ZERO, true],
	"iso": [Vector3(-110, 90, 110), Vector3(0, 1, 0), false],
	"yacht": [Vector3(-53, 7, -18), Vector3(-68, 2, -32), false],
	"lighthouse": [Vector3(39, 5, -22), Vector3(55, 7, -32), false],
	"lighthouse_inside": [Vector3(50, 1.6, -35), Vector3(58, 1.6, -29), false],
	"shack": [Vector3(20, 4, -20), Vector3(0, 3, 0), false],
	"underdock": [Vector3(11, -1.4, -4), Vector3(0, -1.5, 0), false],
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	CivicDividend.build(world)
	for child in world.get_children():
		if child is WorldEnvironment:
			child.environment.fog_enabled = false
			child.environment.glow_enabled = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 1000
	for name in SHOTS:
		var shot: Array = SHOTS[name]
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL if shot[2] else Camera3D.PROJECTION_PERSPECTIVE
		camera.size = 178
		camera.fov = 72
		camera.position = shot[0]
		camera.look_at(shot[1], Vector3.FORWARD if shot[2] else Vector3.UP)
		for i in range(4):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/yacht_club_%s.png" % name)
		print("SAVED yacht_club_", name)
	quit()
