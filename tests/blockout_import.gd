extends SceneTree

# Checks the Blender blockout importer against maps/blockout.example.json.
#   godot --headless --path . --script res://tests/blockout_import.gd

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := BlockoutImporter.read("res://maps/blockout.example.json")
	check(not data.is_empty(), "example blockout parses")
	var b := MapBuilder.new()
	var errors := BlockoutImporter.build(b, data)
	check(errors.is_empty(), "example builds without errors: %s" % [errors])
	# floor + mirrored wall (2) + ramp + mirrored column (2)
	check(b.solids.size() == 6, "six solids built (got %d)" % b.solids.size())
	check(b.decor.size() == 1, "one decor block built (got %d)" % b.decor.size())
	var kinds := {}
	for s in b.solids:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
	check(kinds.get("ramp", 0) == 1 and kinds.get("cylinder", 0) == 2, "ramp and mirrored cylinder present")
	var tags := []
	for s in b.solids:
		tags.append(s.tag)
	check(tags.has("plaza_wall") and tags.has("plaza_wall_e"), "mirrored wall carries _e tag")
	for s in b.solids:
		var box: AABB = s.aabb
		check(is_equal_approx(fposmod(box.position.x, MapBuilder.SNAP), 0.0) or is_equal_approx(fposmod(box.position.x, MapBuilder.SNAP), MapBuilder.SNAP), "%s sits on the 0.25 m grid" % s.tag)
	var graph := BlockoutImporter.graph(data)
	check(graph.nodes.size() == 2 and graph.links.size() == 1, "waypoint graph has 2 nodes and 1 link")
	var bad := BlockoutImporter.build(MapBuilder.new(), {"objects": [
		{"kind": "ramp", "tag": "r", "min": [0, 0, 0], "max": [4, 2, 4], "dir": "up"},
		{"kind": "block", "tag": "x"},
		{"kind": "teapot", "tag": "t", "min": [0, 0, 0], "max": [1, 1, 1]},
	]})
	check(bad.size() == 3, "three malformed objects are reported (got %d)" % bad.size())
	check(BlockoutImporter.read("res://maps/does_not_exist.json").is_empty(), "missing file reads as empty")
	print("blockout import: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
