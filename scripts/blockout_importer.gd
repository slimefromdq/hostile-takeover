class_name BlockoutImporter
extends RefCounted

# Builds map geometry from a Blender blockout exported by tools/blender/export_blockout.py.
# Every solid goes through MapBuilder, so snapping, colliders and audits behave as for hand-written layout.
# CivicDividend.build loads res://maps/blockout.json when it exists: mode "add" layers it on the built-in
# map, mode "replace" skips MapLayout.build. See docs/BLENDER.md.

const FORMAT := 1
const ACTIVE_PATH := "res://maps/blockout.json"
const RAMP_DIRS := ["+x", "-x", "+z", "-z"]

# Parsed document, or {} when the file is missing or not a supported format.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("format", 0)) != FORMAT:
		push_warning("BlockoutImporter: %s is not a format-%d blockout" % [path, FORMAT])
		return {}
	return parsed

# Adds every object to the builder. Returns one message per object that could not be built.
static func build(b: MapBuilder, data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for item in data.get("objects", []):
		var message := _add(b, item)
		if message != "":
			errors.append(message)
	return errors

# Bot waypoint graph in the same shape as MapLayout.graph(): {"nodes": {name: Vector3}, "links": [[a, b, tag]]}.
static func graph(data: Dictionary) -> Dictionary:
	var nodes := {}
	for n in data.get("waypoints", {}):
		var p: Array = data.waypoints[n]
		nodes[n] = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var links: Array = []
	for l in data.get("links", []):
		if nodes.has(l[0]) and nodes.has(l[1]):
			links.append([l[0], l[1], l[2]])
	return {"nodes": nodes, "links": links}

static func default_color(role: String) -> Color:
	match role:
		"walk":
			return MapLayout.PAVE
		"tower":
			return MapLayout.TOWER_COOL
		"cover":
			return MapLayout.COVER
		"accent":
			return Visuals.PAL.accent
		"hazard":
			return Visuals.PAL.guide
		"glass":
			return Color("bfe9ff")
	return MapLayout.NEUTRAL

static func _add(b: MapBuilder, item: Dictionary) -> String:
	var tag: String = item.get("tag", "")
	var lo: Array = item.get("min", [])
	var hi: Array = item.get("max", [])
	if lo.size() != 3 or hi.size() != 3:
		return "%s: missing min/max" % tag
	var x0 := float(lo[0])
	var y0 := float(lo[1])
	var z0 := float(lo[2])
	var x1 := float(hi[0])
	var y1 := float(hi[1])
	var z1 := float(hi[2])
	var role: String = item.get("role", "wall")
	var color: Color = Color(str(item.color)) if item.has("color") else default_color(role)
	var mirror: bool = item.get("mirror", false)
	match item.get("kind", "block"):
		"block":
			if mirror:
				b.pair(x0, z0, x1, z1, y0, y1, role, color, tag)
			else:
				b.block(x0, z0, x1, z1, y0, y1, role, color, tag)
		"ramp":
			var dir: String = item.get("dir", "")
			if not RAMP_DIRS.has(dir):
				return "%s: bad ramp dir '%s'" % [tag, dir]
			var floor_y := float(item.get("y_floor", y0))
			var start_y := float(item.get("y_start", y0))
			var end_y := float(item.get("y_end", y1))
			if mirror:
				b.ramp_pair(x0, z0, x1, z1, floor_y, start_y, end_y, dir, role, color, tag)
			else:
				b.ramp(x0, z0, x1, z1, floor_y, start_y, end_y, dir, role, color, tag)
		"cylinder":
			var radius := maxf(x1 - x0, z1 - z0) * 0.5
			b.cylinder((x0 + x1) * 0.5, (z0 + z1) * 0.5, radius, y0, y1, role, color, tag)
			if mirror:
				b.cylinder(-(x0 + x1) * 0.5, (z0 + z1) * 0.5, radius, y0, y1, role, color, tag + "_e")
		"decor":
			var mode: String = item.get("mode", "flush")
			b.decor_block(x0, z0, x1, z1, y0, y1, role, color, mode, tag)
			if mirror:
				b.decor_block(-x1, z0, -x0, z1, y0, y1, role, color, mode, tag + "_e")
		_:
			return "%s: unknown kind" % tag
	return ""
