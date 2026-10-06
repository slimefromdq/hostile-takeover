extends SceneTree

# Walker test: a real Fighter walks every route family from the depot to every point using the game's
# own movement code (no jumping), proving the geometry is traversable and nothing snags.
#   godot --headless --path . --script res://tests/map_walk.gd

var failures := 0
var runs := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_game("offline")
	game.set_physics_process(false)
	for p in game.fighters.values():
		p.global_position = Vector3(0, -50, 300)
	await physics_frame
	await physics_frame
	var graph: MapGraph = game.bot_graph
	var me: Fighter = game.local_player()
	for class_id in [0, 2]:
		me.change_class(class_id)
		for family in ["blv", "roof", "trn", "aln"]:
			for start in CivicDividend.spawn_nodes:
				for goal in CivicDividend.goal_names:
					# A depot's own point is next door; walk to the other four.
					if goal == CivicDividend.goal_names[0] and start == CivicDividend.spawn_nodes[0] or goal == CivicDividend.goal_names[4] and start == CivicDividend.spawn_nodes[1]:
						continue
					walk(me, game, graph, family, start, goal, class_id)
					await physics_frame
	print("MAP WALK: %d runs, %d failures" % [runs, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func walk(p: Fighter, game: Node3D, graph: MapGraph, family: String, start: String, goal: String, class_id: int) -> void:
	runs += 1
	var weights := {"blv": 5.0, "roof": 5.0, "trn": 5.0, "aln": 5.0}
	weights[family] = 0.3
	var route := graph.path(graph.node(start), graph.node(goal), weights)
	if route.size() < 2:
		failures += 1
		printerr("FAIL: no route %s %s->%s" % [family, start, goal])
		return
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i].distance_to(route[i - 1])
	p.global_position = route[0] + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	p.hp = p.spec.health
	p.held = 0
	p.idle_weapon = 2.0
	var index := 1
	var limit := int((length / 4.0 + 12.0) * 60.0)
	var steps := 0
	var worst_fall := 0.0
	while steps < limit and index < route.size():
		var wp: Vector3 = route[index]
		var to := wp - p.global_position
		if Vector2(to.x, to.z).length() < 1.2 and absf(to.y) < 2.0:
			index += 1
			continue
		p.yaw = atan2(-to.x, -to.z)
		p.movement = Vector2(0, -1)
		p.simulate_movement(1.0 / 60.0, 0)
		steps += 1
		worst_fall = minf(worst_fall, p.global_position.y - wp.y)
	var arrived := index >= route.size()
	if not arrived or worst_fall < -6.0:
		failures += 1
		var at := p.global_position
		printerr("FAIL: %s class %d %s->%s stuck near %s heading to node %d/%d %s" % [family, class_id, start, goal, at, index, route.size(), route[mini(index, route.size() - 1)]])
