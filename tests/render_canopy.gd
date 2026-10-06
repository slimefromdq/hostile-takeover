extends SceneTree

# Renders the active blockout map (maps/blockout.json) from named vantage points into docs/previews/canopy_*.png.
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --script res://tests/render_canopy.gd [-- shot ...]
# [eye, target, orthographic, match time in seconds]. Time poses the movers (drawbridges, crane, skylight, blimp).
const SHOTS := {
	"top": [Vector3(0, 220, 0.01), Vector3(0, 0, 0), true, 0.0],
	"iso": [Vector3(-105, 85, 85), Vector3(-5, 6, -2), false, 0.0],
	"iso_north": [Vector3(-75, 70, -110), Vector3(-30, 8, -10), false, 0.0],
	"spawn_exit": [Vector3(-89, 1.6, 0), Vector3(-66, 1.8, -1), false, 0.0],
	"boulevard": [Vector3(-82, 1.7, 4), Vector3(-42, 3.0, -3), false, 0.0],
	"rail_yard": [Vector3(0, 1.7, 26), Vector3(0, 14, -60), false, 0.0],
	"tunnel": [Vector3(-86, -4.4, 1), Vector3(-30, -4.4, -1), false, 0.0],
	"construction": [Vector3(-40, 1.7, -14), Vector3(-46, 16, -44), false, 0.0],
	"market_alley": [Vector3(-75, 1.7, 14), Vector3(-75, 5, 48), false, 0.0],
	"garden": [Vector3(-84, 13.7, 18), Vector3(-62, 13, 52), false, 0.0],
	"canal": [Vector3(-50, 1.7, 22), Vector3(-38, -1.5, 46), false, 0.0],
	"blimp_dock": [Vector3(0, 35.7, -53), Vector3(0, 33, -30), false, 0.0],
	"vent_shaft": [Vector3(-54, -4.4, 0.5), Vector3(-54, 12, -1.5), false, 0.0],
	"span": [Vector3(-34, 3.5, 14), Vector3(0, 7, -2), false, 0.0],
	"span_booth": [Vector3(-14, 15, 9), Vector3(0, 11, -2), false, 0.0],
	"north_row": [Vector3(-78, 1.7, -14), Vector3(-76, 10, -34), false, 0.0],
	"gantry": [Vector3(-27, 1.7, -14), Vector3(0, 9, -22), false, 0.0],
	"pump_hall": [Vector3(-66, -8.4, 0), Vector3(-86, -10, 0), false, 0.0],
	"cistern": [Vector3(-26, -7.5, 0), Vector3(-4, -10, 0), false, 0.0],
	"foundation_pit": [Vector3(-39, -4.4, -40), Vector3(-30, -5, -50), false, 0.0],
	"cellar": [Vector3(-75, -4.4, 10), Vector3(-75, -4.4, 50), false, 0.0],
	"event_bridges": [Vector3(-52, 6, 22), Vector3(-38, 0, 48), false, 82.0],
	"event_collapse": [Vector3(-68, 14, 28), Vector3(-68, 0, 38), false, 156.0],
	"event_crane": [Vector3(-60, 30, -20), Vector3(-62, 24, -45), false, 220.0],
}

# Movers only take a new pose inside a physics callback, so a node poses them for the shot's time.
class Stub extends Node:
	var authoritative := false

class Driver extends Node:
	var t := 0.0
	var game: Node
	func _physics_process(_dt: float) -> void:
		MapVerbs.update(t, game)

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
	var driver := Driver.new()
	driver.game = Stub.new()
	root.add_child(driver)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.far = 600.0
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	for shot in SHOTS:
		if wanted.size() > 0 and not wanted.has(shot):
			continue
		var s: Array = SHOTS[shot]
		driver.t = s[3]
		if s[2]:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 135.0
			cam.global_position = s[0]
			cam.look_at(s[1], Vector3.FORWARD)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 80
			cam.global_position = s[0]
			cam.look_at(s[1], Vector3.UP)
		for i in range(4):
			await physics_frame
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/previews/canopy_%s.png" % shot)
		print("SAVED ", shot)
	quit()
