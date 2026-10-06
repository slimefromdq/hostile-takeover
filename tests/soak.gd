extends SceneTree

# Long bot match: watches node/orphan counts for leaks and fails on runtime errors.
#   godot --headless --fixed-fps 60 --path . --script res://tests/soak.gd [-- minutes=10]
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var minutes := 10
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("minutes="):
			minutes = arg.get_slice("=", 1).to_int()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game("offline")
	var series: Array = []
	for step in range(minutes * 2):
		await create_timer(30.0).timeout
		if game.match_state.winner != -2:
			game.start_game("restart")
		series.append([int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), game.tracer_root.get_child_count(), game.entities.size()])
	var first: Array = series[1]
	var peak_nodes := 0
	var peak_orphans := 0
	for s in series:
		peak_nodes = maxi(peak_nodes, s[0])
		peak_orphans = maxi(peak_orphans, s[1])
	var bounded: bool = peak_nodes <= first[0] + 400 and peak_orphans <= 50
	print("SOAK minutes=%d first_nodes=%d peak_nodes=%d peak_orphans=%d series=%s" % [minutes, first[0], peak_nodes, peak_orphans, series.map(func(s): return s[0])])
	print("SOAK RESULT: ", "PASS" if bounded else "FAIL")
	game.queue_free()
	await process_frame
	quit(0 if bounded else 1)
