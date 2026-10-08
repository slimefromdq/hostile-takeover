class_name BlockoutImporter
extends RefCounted

# Builds map geometry from a Blender blockout exported by tools/blender/export_blockout.py.
# Every solid goes through MapBuilder, so snapping, colliders and audits behave as for hand-written layout.
# CivicDividend.build loads res://maps/blockout.json when it exists: mode "add" layers it on the built-in
# map, mode "replace" skips MapLayout.build and takes bounds, spawns, capture points and the bot graph
# from the file (see resolve). See docs/BLENDER.md.

const FORMAT := 1
const ACTIVE_PATH := "res://maps/blockout.json"
const RAMP_DIRS := ["+x", "-x", "+z", "-z"]
const SETTINGS_PATH := "user://settings.cfg"
const MAPS_DIR := "res://maps"

# The blockout in use: a developer override file (maps/blockout.json) wins, then the menu's choice, else none
# (the built-in map).
static func active_path() -> String:
	if FileAccess.file_exists(ACTIVE_PATH):
		return ACTIVE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map=res://maps/"):
			var path := argument.trim_prefix("--map=")
			if path.ends_with(".blockout.json") and FileAccess.file_exists(path):
				return path
	return selected_path()

static func selected_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	var path: String = cfg.get_value("map", "path", "")
	return path if path != "" and FileAccess.file_exists(path) else ""

static func select(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("map", "path", path)
	cfg.save(SETTINGS_PATH)

# Menu entries: the built-in map first, then every maps/*.blockout.json that names itself with a "title".
static func catalog() -> Array:
	var out: Array = [{"path": "", "title": "Civic Dividend (built-in)"}]
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".blockout.json"):
			continue
		var data := read("%s/%s" % [MAPS_DIR, file_name])
		if not data.is_empty() and data.has("title"):
			out.append({"path": "%s/%s" % [MAPS_DIR, file_name], "title": str(data.title)})
	return out

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

# Everything replace mode needs besides geometry. Returns:
#   graph {"nodes": {name: Vector3}, "links": [[a, b, tag]]}, points (west to east), goal_names (same order),
#   spawn_nodes [west, east], bounds, spawn_x, spawn_z, spawn_step, depot_limit, test_lane, audit, errors.
# Waypoints with "mirror" also create an "e_<name>" node at -x, and links touching a mirrored node are mirrored,
# exactly like MapLayout.graph(). Waypoints flagged "point" are the five capture points; "spawn" marks the depot node.
static func resolve(data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var settings: Dictionary = data.get("settings", {})
	var nodes := {}
	var is_point := {}
	var is_spawn := {}
	var mirrored := {}
	for w in _waypoint_list(data):
		var name: String = w.get("name", "")
		var pos := _vec(w.get("pos", [0, 0, 0]))
		nodes[name] = pos
		is_point[name] = bool(w.get("point", false))
		is_spawn[name] = bool(w.get("spawn", false))
		if w.get("mirror", false) and not is_zero_approx(pos.x):
			mirrored[name] = true
			nodes["e_" + name] = Vector3(-pos.x, pos.y, pos.z)
			is_point["e_" + name] = is_point[name]
			is_spawn["e_" + name] = is_spawn[name]
	var links: Array = []
	for l in data.get("links", []):
		var a: String = l[0]
		var b: String = l[1]
		if not nodes.has(a) or not nodes.has(b):
			errors.append("link %s-%s names a missing waypoint" % [a, b])
			continue
		links.append([a, b, str(l[2])])
		var ma := ("e_" + a) if mirrored.has(a) else a
		var mb := ("e_" + b) if mirrored.has(b) else b
		if ma != a or mb != b:
			links.append([ma, mb, str(l[2])])
	var points: Array[Vector3] = []
	var goal_names: Array[String] = []
	var spawn_nodes: Array[String] = []
	var names: Array = nodes.keys()
	names.sort_custom(func(x: String, y: String) -> bool: return nodes[x].x < nodes[y].x)
	for n in names:
		if is_point[n]:
			points.append(nodes[n])
			goal_names.append(n)
		if is_spawn[n]:
			spawn_nodes.append(n)
	if points.size() != 5:
		errors.append("replace mode needs exactly 5 capture points (waypoints with point=true, mirrored ones count twice); found %d" % points.size())
	if spawn_nodes.size() != 2:
		errors.append("replace mode needs exactly 2 spawn nodes (spawn=true, mirrored); found %d" % spawn_nodes.size())
	if settings.has("goal_order"):
		var order: Variant = settings.goal_order
		if not order is Array or order.size() != 5:
			errors.append("goal_order must name all five capture waypoints once")
		else:
			var ordered: Array[String] = []
			for name in order:
				if not name is String or not goal_names.has(name) or ordered.has(name):
					errors.append("goal_order contains a missing, duplicate or non-capture waypoint")
					break
				ordered.append(name)
			if ordered.size() == 5:
				goal_names = ordered
				points.clear()
				for name in ordered:
					points.append(nodes[name])
	var spawn_x: float = float(settings.get("spawn_x", absf(nodes[spawn_nodes[0]].x) if spawn_nodes.size() == 2 else 0.0))
	var bounds := _auto_bounds(data)
	if settings.has("bounds"):
		var r: Array = settings.bounds
		bounds = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var team_spawns: Array = []
	if settings.has("team_spawns"):
		var teams: Variant = settings.team_spawns
		if not teams is Array or teams.size() != 2:
			errors.append("team_spawns must contain two teams")
		else:
			for slots in teams:
				if not slots is Array or slots.size() != CivicDividend.TEAM_SIZE:
					errors.append("team_spawns needs five positions per team")
					continue
				var positions: Array[Vector3] = []
				for at in slots:
					if not _valid_position(at):
						errors.append("team_spawns contains an invalid position")
						continue
					var p := _vec(at)
					if not bounds.has_point(Vector2(p.x, p.z)) or positions.has(p):
						errors.append("team_spawns contains an outside or duplicate position")
					positions.append(p)
				team_spawns.append(positions)
	var spawn_zones: Array[AABB] = []
	if settings.has("spawn_zones"):
		var zones: Variant = settings.spawn_zones
		if not zones is Array or zones.size() != 2:
			errors.append("spawn_zones must contain two min/max volumes")
		else:
			for zone in zones:
				if not zone is Dictionary or not _valid_position(zone.get("min")) or not _valid_position(zone.get("max")):
					errors.append("spawn_zones contains an invalid volume")
					continue
				var lo := _vec(zone.min)
				var hi := _vec(zone.max)
				if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z or not bounds.encloses(Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z)):
					errors.append("spawn_zones contains an empty or outside volume")
				spawn_zones.append(AABB(lo, hi - lo))
	var kill_floor := -INF
	if settings.has("kill_floor"):
		if not _finite_number(settings.kill_floor):
			errors.append("kill_floor must be a finite number")
		else:
			kill_floor = float(settings.kill_floor)
			for slots in team_spawns:
				for at in slots:
					if at.y <= kill_floor:
						errors.append("kill_floor must be below every spawn")
			for at in points:
				if at.y <= kill_floor:
					errors.append("kill_floor must be below every capture point")
			if team_spawns.is_empty():
				for name in spawn_nodes:
					if nodes[name].y <= kill_floor:
						errors.append("kill_floor must be below every spawn")
	if not team_spawns.is_empty() and spawn_zones.size() == 2:
		for side in range(team_spawns.size()):
			for at in team_spawns[side]:
				if not spawn_zones[side].has_point(at):
					errors.append("team spawn must be inside its protection volume")
	for zone in spawn_zones:
		for at in points:
			var expanded := AABB(zone.position - Vector3(4.5, 0, 4.5), zone.size + Vector3(9, 0, 9))
			if expanded.has_point(at + Vector3.UP * 0.2):
				errors.append("spawn protection must not overlap a capture disc")
	var test_lane := Vector3.ZERO
	if settings.has("test_lane"):
		test_lane = _vec(settings.test_lane)
	elif points.size() == 5:
		test_lane = points[2] + Vector3(0, 0.05, 0)
	return {
		"graph": {"nodes": nodes, "links": links},
		"points": points,
		"goal_names": goal_names,
		"spawn_nodes": spawn_nodes,
		"bounds": bounds,
		"spawn_x": spawn_x,
		"spawn_z": float(settings.get("spawn_z", (nodes[spawn_nodes[0]].z - 7.0) if spawn_nodes.size() == 2 else 0.0)),
		"spawn_step": float(settings.get("spawn_step", 2.8)),
		"depot_limit": float(settings.get("depot_limit", spawn_x - 3.0)),
		"ceiling": float(settings.get("ceiling", 40.0)),
		"team_spawns": team_spawns,
		"spawn_zones": spawn_zones,
		"kill_floor": kill_floor,
		"test_lane": test_lane,
		"audit": settings.get("audit", {}),
		"errors": errors,
	}

# Map verb features (see MapVerbs) with mirror applied: "mirror": true adds the copy reflected across x = 0.
static func features(data: Dictionary) -> Array:
	var out: Array = []
	for f in data.get("features", []):
		out.append(f)
		if f.get("mirror", false):
			out.append(_mirror_feature(f))
	return out

static func _flip(p: Array) -> Array:
	return [-float(p[0]), p[1], p[2]]

static func _mirror_feature(f: Dictionary) -> Dictionary:
	var m: Dictionary = f.duplicate(true)
	m.erase("mirror")
	if m.has("tag"):
		m.tag = str(m.tag) + "_e"
	if m.has("pos"):
		m.pos = _flip(f.pos)
	if m.has("min"):
		var lo: Array = f.min
		var hi: Array = f.max
		m.min = [-float(hi[0]), lo[1], lo[2]]
		m.max = [-float(lo[0]), hi[1], hi[2]]
		if m.has("kick"):
			m.kick = _flip(f.kick)
	if m.has("face"):
		m.face = {"+x": "-x", "-x": "+x"}.get(str(f.face), f.face)
	if m.has("from"):
		m["from"] = _flip(f["from"])
		m["to"] = _flip(f["to"])
	if m.has("keys"):
		var keys: Array = []
		for k in f.keys:
			var key: Array = [k[0], _flip(k[1])]
			if k.size() > 2:
				key.append([k[2][0], -float(k[2][1]), -float(k[2][2])])
			keys.append(key)
		m.keys = keys
	return m

# Graph only, same shape as MapLayout.graph().
static func graph(data: Dictionary) -> Dictionary:
	return resolve(data).graph

static func _waypoint_list(data: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = data.get("waypoints", [])
	if typeof(raw) == TYPE_ARRAY:
		return raw
	# Older files stored {name: [x, y, z]}.
	for n in raw:
		out.append({"name": n, "pos": raw[n]})
	return out

static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid_position(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _finite_number(value[0]) and _finite_number(value[1]) and _finite_number(value[2])

# Ground rectangle of all geometry (mirrored copies included), used when settings.bounds is missing.
static func _auto_bounds(data: Dictionary) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for item in data.get("objects", []):
		if item.get("kind", "block") == "decor" and item.get("mode", "flush") == "outside":
			continue
		var a: Array = item.get("min", [0, 0, 0])
		var b: Array = item.get("max", [0, 0, 0])
		var xs: Array = [float(a[0]), float(b[0])]
		if item.get("mirror", false):
			xs.append(-float(a[0]))
			xs.append(-float(b[0]))
		for x in xs:
			lo.x = minf(lo.x, x)
			hi.x = maxf(hi.x, x)
		lo.y = minf(lo.y, float(a[2]))
		hi.y = maxf(hi.y, float(b[2]))
	if lo.x == INF:
		return Rect2(-50, -50, 100, 100)
	return Rect2(lo, hi - lo)

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
			# A walk floor sunk below street level is the minimap's "sunken" area (e.g. a trench).
			if role == "walk" and y1 < -1.0:
				b.sunken.append(Rect2(x0, z0, x1 - x0, z1 - z0))
				if mirror:
					b.sunken.append(Rect2(-x1, z0, x1 - x0, z1 - z0))
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
