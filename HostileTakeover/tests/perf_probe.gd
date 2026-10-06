extends SceneTree

# Samples render/object counts during a simulated 12-fighter match.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tests/perf_probe.gd [-- frames=N]
# Software rendering makes timings meaningless; compare counts and before/after A/B runs.

func _initialize() -> void:
	call_deferred("run")

func monitor(m: int) -> float:
	return Performance.get_monitor(m)

func run() -> void:
	var frames := 600
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("frames="):
			frames = arg.get_slice("=", 1).to_int()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	var peak := {"draw": 0.0, "objects": 0.0, "prims": 0.0, "nodes": 0.0, "orphans": 0.0, "tracers": 0.0}
	var sum_process := 0.0
	var sum_physics := 0.0
	var samples := 0
	for i in range(frames):
		await process_frame
		if i < 60:
			continue
		peak.draw = maxf(peak.draw, monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		peak.objects = maxf(peak.objects, monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		peak.prims = maxf(peak.prims, monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		peak.nodes = maxf(peak.nodes, monitor(Performance.OBJECT_NODE_COUNT))
		peak.orphans = maxf(peak.orphans, monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		peak.tracers = maxf(peak.tracers, game.tracer_root.get_child_count())
		sum_process += monitor(Performance.TIME_PROCESS)
		sum_physics += monitor(Performance.TIME_PHYSICS_PROCESS)
		samples += 1
	print("PERF frames=%d draw_calls_peak=%d objects_peak=%d primitives_peak=%d nodes_peak=%d orphans_peak=%d effect_nodes_peak=%d process_ms_avg=%.2f physics_ms_avg=%.2f" % [frames, peak.draw, peak.objects, peak.prims, peak.nodes, peak.orphans, peak.tracers, sum_process / maxi(1, samples) * 1000.0, sum_physics / maxi(1, samples) * 1000.0])
	game.queue_free()
	await process_frame
	quit()
