extends SceneTree

# Dumps the built-in map (MapLayout) as a blockout JSON, so it can be opened in Blender:
#   godot --headless --path . --script res://tools/export_layout.gd -- maps/layout.blockout.json
#   blender -b -P tools/blender/import_blockout.py -- maps/layout.blockout.json layout.blend
# Mirrored pieces are written once with "mirror": true (the west half), exactly as they are authored in
# MapLayout, so editing and re-exporting keeps the east half in sync. Decals are included as decor.

class Recorder extends MapBuilder:
	var records: Array = []
	var quiet := 0

	func _rec(kind: String, role: String, color: Color, tag: String, lo: Array, hi: Array, mirror: bool, extra: Dictionary = {}) -> void:
		if quiet > 0:
			return
		var r := {"kind": kind, "tag": tag, "role": role, "color": "#" + color.to_html(false), "min": lo, "max": hi}
		if mirror:
			r["mirror"] = true
		r.merge(extra)
		records.append(r)

	func block(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, tag: String = "") -> void:
		super.block(x0, z0, x1, z1, y0, y1, role, color, tag)
		_rec("block", role, color, tag, [snap(minf(x0, x1)), snap(minf(y0, y1)), snap(minf(z0, z1))], [snap(maxf(x0, x1)), snap(maxf(y0, y1)), snap(maxf(z0, z1))], false)

	func pair(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, tag: String = "", east: Color = Color(0, 0, 0, 0)) -> void:
		_rec("block", role, color, tag, [snap(minf(x0, x1)), snap(minf(y0, y1)), snap(minf(z0, z1))], [snap(maxf(x0, x1)), snap(maxf(y0, y1)), snap(maxf(z0, z1))], true)
		quiet += 1
		super.pair(x0, z0, x1, z1, y0, y1, role, color, tag, east)
		quiet -= 1

	func ramp(x0: float, z0: float, x1: float, z1: float, y_floor: float, y_start: float, y_end: float, dir: String, role: String, color: Color, tag: String = "") -> void:
		super.ramp(x0, z0, x1, z1, y_floor, y_start, y_end, dir, role, color, tag)
		_rec("ramp", role, color, tag, [snap(minf(x0, x1)), snap(y_floor), snap(minf(z0, z1))], [snap(maxf(x0, x1)), snap(maxf(y_start, y_end)), snap(maxf(z0, z1))], false,
			{"dir": dir, "y_floor": snap(y_floor), "y_start": snap(y_start), "y_end": snap(y_end)})

	func ramp_pair(x0: float, z0: float, x1: float, z1: float, y_floor: float, y_start: float, y_end: float, dir: String, role: String, color: Color, tag: String = "") -> void:
		_rec("ramp", role, color, tag, [snap(minf(x0, x1)), snap(y_floor), snap(minf(z0, z1))], [snap(maxf(x0, x1)), snap(maxf(y_start, y_end)), snap(maxf(z0, z1))], true,
			{"dir": dir, "y_floor": snap(y_floor), "y_start": snap(y_start), "y_end": snap(y_end)})
		quiet += 1
		super.ramp_pair(x0, z0, x1, z1, y_floor, y_start, y_end, dir, role, color, tag)
		quiet -= 1

	func cylinder(cx: float, cz: float, radius: float, y0: float, y1: float, role: String, color: Color, tag: String = "") -> void:
		super.cylinder(cx, cz, radius, y0, y1, role, color, tag)
		var r := snap(radius)
		_rec("cylinder", role, color, tag, [snap(cx) - r, snap(minf(y0, y1)), snap(cz) - r], [snap(cx) + r, snap(maxf(y0, y1)), snap(cz) + r], false)

	func decor_block(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, mode: String, tag: String = "") -> void:
		super.decor_block(x0, z0, x1, z1, y0, y1, role, color, mode, tag)
		_rec("decor", role, color, tag, [minf(x0, x1), minf(y0, y1), minf(z0, z1)], [maxf(x0, x1), maxf(y0, y1), maxf(z0, z1)], false, {"mode": mode})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "maps/layout.blockout.json"
	var recorder := Recorder.new()
	MapLayout.build(recorder)
	var waypoints: Array = []
	for n in MapLayout.NODES:
		var p: Vector3 = MapLayout.NODES[n]
		var w := {"name": n, "pos": [p.x, p.y, p.z]}
		if not is_zero_approx(p.x):
			w["mirror"] = true
		if ["A", "B", "C"].has(n):
			w["point"] = true
		if n == "S":
			w["spawn"] = true
		waypoints.append(w)
	var doc := {
		"format": BlockoutImporter.FORMAT,
		"units": "m",
		"mode": "replace",
		"source": "MapLayout",
		"settings": {
			"bounds": [MapLayout.BOUNDS.position.x, MapLayout.BOUNDS.position.y, MapLayout.BOUNDS.size.x, MapLayout.BOUNDS.size.y],
			"spawn_x": MapLayout.SPAWN_X, "spawn_z": -7.0, "spawn_step": 2.8, "depot_limit": MapLayout.DEPOT_LIMIT,
			"test_lane": [MapLayout.TEST_LANE.x, MapLayout.TEST_LANE.y, MapLayout.TEST_LANE.z],
		},
		"objects": recorder.records,
		"waypoints": waypoints,
		"links": MapLayout.LINKS,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write ", path)
		quit(1)
		return
	file.store_string(JSON.stringify(doc, " "))
	file.close()
	print("wrote %s: %d objects, %d waypoints" % [path, recorder.records.size(), waypoints.size()])
	quit()
