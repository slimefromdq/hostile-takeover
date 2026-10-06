extends SceneTree

# Renders map views to res://docs/previews/preview_map_*.png. Usage: --script res://tests/render_map.gd [-- shot names...]
const SHOTS := {
	"top": [Vector3(0, 150, 0.01), Vector3(0, 0, 0), true],
	"iso_w": [Vector3(-125, 75, 70), Vector3(-30, 0, -5), false],
	"spawn_exit": [Vector3(-80.5, 1.6, 0), Vector3(-66, 1.6, 0), false],
	"a_to_b": [Vector3(-66, 1.6, 2), Vector3(-34, 1.6, -1), false],
	"b_hub": [Vector3(-38, 1.6, 3), Vector3(-26, 1.6, -4), false],
	"c_plaza": [Vector3(-17, 1.6, 2), Vector3(0, 1.6, -1), false],
	"roof_overlook": [Vector3(-33, 7.6, -14), Vector3(-30, 1, 2), false],
	"roof_walk": [Vector3(-66, 7.6, -28.5), Vector3(-40, 7.0, -24), false],
	"trench_run": [Vector3(-72, -2.4, 24), Vector3(-40, -2.6, 22), false],
	"trench_ramp": [Vector3(-47, 1.6, 6), Vector3(-47, -2.5, 20), false],
	"alley": [Vector3(-64, 1.6, -33), Vector3(-32, 1.6, -33), false],
	"gallery": [Vector3(-3, 4.6, -10), Vector3(-16, 3.6, -9), false],
	"lobby": [Vector3(-48, 1.6, -8), Vector3(-48, 1.6, -30), false],
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
	if OS.get_cmdline_user_args().has("noshadow"):
		for child in world.get_children():
			if child is DirectionalLight3D:
				child.shadow_enabled = false
	if OS.get_cmdline_user_args().has("std"):
		for child in world.get_children():
			if child is MeshInstance3D:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.6, 0.6, 0.6)
				child.material_override = m
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.far = 500.0
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	for name in SHOTS:
		if wanted.size() > 0 and not wanted.has(name):
			continue
		var s: Array = SHOTS[name]
		if s[2]:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 130.0
			cam.global_position = s[0]
			cam.look_at(s[1], Vector3.FORWARD)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 75
			cam.global_position = s[0]
			cam.look_at(s[1], Vector3.UP)
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/preview_map_%s.png" % name)
		print("SAVED ", name)
	quit()
