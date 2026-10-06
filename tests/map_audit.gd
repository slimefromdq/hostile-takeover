extends SceneTree

# Geometry, traversal and sightline audit for the map.
#   godot --headless --path . --script res://tests/map_audit.gd
# Exits non-zero when any check fails. Metrics are printed so layout changes can be judged by number.

const CAPSULE_RADIUS := 0.52
const CAPSULE_HEIGHT := 1.9
const HEAD := 1.6

var checks := 0
var printed := {}
var failures := 0
var space: PhysicsDirectSpaceState3D
var world: Node3D
var builder: MapBuilder
var graph: Dictionary

func note(kind: String, message: String) -> void:
	printed[kind] = printed.get(kind, 0) + 1
	if printed[kind] <= 12:
		printerr("  ", message)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	CivicDividend.build(world)
	builder = CivicDividend.builder
	graph = CivicDividend.graph_data
	await physics_frame
	await physics_frame
	space = world.get_world_3d().direct_space_state
	audit_registry()
	audit_clearance()
	audit_edges()
	audit_connectivity()
	audit_sightlines()
	print("MAP AUDIT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

# ---- registry: containment, overlaps, z-fighting, wedge gaps, symmetry ---------------------

func audit_registry() -> void:
	var solids: Array = builder.solids
	var rb := CivicDividend.bounds
	var y_min := -12.01 if CivicDividend.replaced else -5.01
	var bounds := AABB(Vector3(rb.position.x - 0.01, y_min, rb.position.y - 0.01), Vector3(rb.size.x + 0.02, 40.01 - y_min, rb.size.y + 0.02))
	var outside := 0
	for s in solids:
		if not bounds.encloses(s.aabb):
			outside += 1
			note("outside", "outside bounds: %s %s" % [s.tag, s.aabb])
	check(outside == 0, "all solids inside the play bounds")
	var overlaps := 0
	var zfight := 0
	var wedge := 0
	var narrow := 0
	var n := solids.size()
	for i in range(n):
		var a: AABB = solids[i].aabb
		for j in range(i + 1, n):
			var c: AABB = solids[j].aabb
			var inter := a.intersection(c)
			var both_blocks: bool = solids[i].kind == "block" and solids[j].kind == "block"
			if inter.size.x > 0.001 and inter.size.y > 0.001 and inter.size.z > 0.001:
				if both_blocks or inter.get_volume() > 0.5:
					# Ramps are wedges inside their bounding box, so only block/block overlap is exact.
					if both_blocks:
						overlaps += 1
						note("overlap", "overlap: %s %s | %s %s" % [solids[i].tag, a, solids[j].tag, c])
			if not both_blocks:
				continue
			zfight += _coplanar_faces(solids[i], solids[j])
			var w := _gap_flags(solids[i], solids[j])
			wedge += w[0]
			narrow += w[1]
	check(overlaps == 0, "no interpenetrating blocks (%d)" % overlaps)
	check(zfight == 0, "no coplanar same-facing overlapping faces (%d)" % zfight)
	check(wedge == 0, "no wedge-trap gaps between 0.05 m and 1.2 m (%d)" % wedge)
	check(narrow == 0, "no passage narrower than 2.0 m between parallel faces (%d)" % narrow)
	var keys := {}
	for s in solids:
		keys[_key(s.aabb)] = true
	var asym := 0
	for s in solids:
		var box: AABB = s.aabb
		var mirrored := AABB(Vector3(-(box.position.x + box.size.x), box.position.y, box.position.z), box.size)
		if not keys.has(_key(mirrored)):
			asym += 1
			note("mirror", "no mirror: %s %s" % [s.tag, box])
	check(asym == 0, "east half mirrors the west half (%d unmatched)" % asym)
	var off_grid := 0
	for s in solids:
		var box: AABB = s.aabb
		for v in [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z]:
			if absf(v / MapBuilder.SNAP - roundf(v / MapBuilder.SNAP)) > 0.0001:
				off_grid += 1
	check(off_grid == 0, "all solids snap to the 0.25 m grid")
	var decor_bad := 0
	for d in builder.decor:
		if d.mode == "outside":
			if BOUNDS_INSIDE(d.aabb):
				decor_bad += 1
		else:
			if not _decor_touches_solid(d.aabb):
				decor_bad += 1
				note("decor", "floating decor: %s %s" % [d.tag, d.aabb])
	check(decor_bad == 0, "decor is flush on a solid or outside the bounds (%d)" % decor_bad)
	print("  solids=%d meshes=%d shapes=%d decor=%d" % [solids.size(), builder.mesh_count(), builder.shape_count(), builder.decor.size()])

func BOUNDS_INSIDE(box: AABB) -> bool:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(CivicDividend.bounds)

func _key(box: AABB) -> String:
	return "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z]

func _overlap_1d(a0: float, a1: float, b0: float, b1: float) -> float:
	return minf(a1, b1) - maxf(a0, b0)

func _coplanar_faces(sa: Dictionary, sb: Dictionary) -> int:
	var a: AABB = sa.aabb
	var b: AABB = sb.aabb
	var count := 0
	for axis in range(3):
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		var ov1 := _overlap_1d(a.position[o1], a.end[o1], b.position[o1], b.end[o1])
		var ov2 := _overlap_1d(a.position[o2], a.end[o2], b.position[o2], b.end[o2])
		if ov1 <= 0.001 or ov2 <= 0.001 or ov1 * ov2 <= 0.01:
			continue
		if absf(a.position[axis] - b.position[axis]) < 0.001 or absf(a.end[axis] - b.end[axis]) < 0.001:
			count += 1
			note("coplanar", "coplanar: %s %s | %s %s" % [sa.tag, a, sb.tag, b])
	return count

# Returns [wedge_traps, narrow_passages] for two blocks that face each other across a small gap.
func _gap_flags(sa: Dictionary, sb: Dictionary) -> Array:
	var a: AABB = sa.aabb
	var b: AABB = sb.aabb
	if sa.role == "walk" and a.size.y <= 1.0 and sa.tag.begins_with("floor"):
		return [0, 0]
	if sb.role == "walk" and b.size.y <= 1.0 and sb.tag.begins_with("floor"):
		return [0, 0]
	var wedge := 0
	var narrow := 0
	for axis in [0, 2]:
		var other := 2 if axis == 0 else 0
		var gap := maxf(b.position[axis] - a.end[axis], a.position[axis] - b.end[axis])
		if gap <= 0.001 or gap >= 2.0:
			continue
		var along := _overlap_1d(a.position[other], a.end[other], b.position[other], b.end[other])
		var up := _overlap_1d(a.position.y, a.end.y, b.position.y, b.end.y)
		if along < 1.0 or up < 1.2:
			continue
		if gap < 1.2:
			wedge += 1
			note("wedge", "wedge gap %.2f: %s %s | %s %s" % [gap, sa.tag, a, sb.tag, b])
		else:
			narrow += 1
			note("narrow", "narrow %.2f: %s %s | %s %s" % [gap, sa.tag, a, sb.tag, b])
	return [wedge, narrow]

func _decor_touches_solid(box: AABB) -> bool:
	var grown := box.grow(0.06)
	for s in builder.solids:
		if grown.intersects(s.aabb):
			return true
	return false

# ---- clearance --------------------------------------------------------------------------

func capsule_blocked(pos: Vector3, radius: float = CAPSULE_RADIUS) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = CAPSULE_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * (CAPSULE_HEIGHT / 2.0 + 0.12))
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()

func ground_at(x: float, y_hint: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, y_hint + 1.5, z), Vector3(x, y_hint - 2.5, z), 1)
	return space.intersect_ray(query)

func audit_clearance() -> void:
	var bad := 0
	for name in graph.nodes:
		var p: Vector3 = graph.nodes[name]
		var g := ground_at(p.x, p.y, p.z)
		if g.is_empty() or absf(g.position.y - p.y) > 0.3:
			bad += 1
			printerr("  node ground mismatch: ", name, " ", p, " ground=", g.get("position", "none"))
		elif capsule_blocked(Vector3(p.x, g.position.y, p.z)):
			bad += 1
			printerr("  node inside geometry: ", name, " ", p)
	check(bad == 0, "every waypoint stands on ground with capsule clearance (%d bad)" % bad)
	bad = 0
	for side in [0, 1]:
		for id in range(6):
			var sp := Vector3(-CivicDividend.spawn_x if side == 0 else CivicDividend.spawn_x, 0.0, CivicDividend.spawn_z + id * CivicDividend.spawn_step)
			if capsule_blocked(sp):
				bad += 1
				printerr("  spawn blocked: ", sp)
	check(bad == 0, "all twelve spawn positions are clear")
	bad = 0
	for p in CivicDividend.capture_points:
		for k in range(12):
			var a := TAU * k / 12.0
			var s := p + Vector3(cos(a), 0, sin(a)) * 4.4
			var g := ground_at(s.x, 0, s.z)
			if g.is_empty() or absf(g.position.y) > 0.05 or g.normal.y < 0.99:
				bad += 1
				printerr("  capture disc not flat near ", p, " at ", s)
	check(bad == 0, "capture discs sit on flat street-level floor (%d bad)" % bad)
	bad = 0
	for p in CivicDividend.capture_points:
		if capsule_blocked(p, 4.2) and false:
			bad += 1
	# Cover inside the capture radius would make parts of the disc unusable.
	var in_disc := 0
	for s in builder.solids:
		var box: AABB = s.aabb
		if s.role == "walk" or box.position.y < -0.01 or box.size.y < 0.5:
			continue
		for p in CivicDividend.capture_points:
			var nearest := Vector2(clampf(p.x, box.position.x, box.end.x), clampf(p.z, box.position.z, box.end.z))
			if nearest.distance_to(Vector2(p.x, p.z)) < 4.5:
				in_disc += 1
				printerr("  solid inside capture radius: ", s.tag, " ", box)
	check(in_disc == 0, "no cover inside a capture radius (%d)" % in_disc)

# ---- edges: sweep + ground following ---------------------------------------------------------

func audit_edges() -> void:
	var bad := 0
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	for link in graph.links:
		var a: Vector3 = graph.nodes[link[0]]
		var b: Vector3 = graph.nodes[link[1]]
		var lift := Vector3.UP * (CAPSULE_HEIGHT / 2.0 + 0.12)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, a + lift)
		q.motion = b - a
		q.collision_mask = 1
		var result := space.cast_motion(q)
		if result[0] < 0.999:
			bad += 1
			var at := a.lerp(b, result[0])
			printerr("  edge blocked: %s -> %s near %s" % [link[0], link[1], at])
			continue
		var length := a.distance_to(b)
		var steps := maxi(2, int(length / 0.5))
		var previous := a.y
		for i in range(steps + 1):
			var t := float(i) / steps
			var p := a.lerp(b, t)
			var g := ground_at(p.x, p.y, p.z)
			if g.is_empty():
				bad += 1
				printerr("  edge has no ground: %s -> %s at %s" % [link[0], link[1], p])
				break
			if absf(g.position.y - p.y) > 0.45 or g.normal.y < 0.88 or absf(g.position.y - previous) > 0.35:
				bad += 1
				printerr("  edge ground issue: %s -> %s at %s ground=%s normal_y=%.2f" % [link[0], link[1], p, g.position, g.normal.y])
				break
			previous = g.position.y
	check(bad == 0, "every waypoint edge is a clear, walkable, ramp-slope path (%d bad of %d)" % [bad, graph.links.size()])

# ---- connectivity and route diversity --------------------------------------------------------------

func audit_connectivity() -> void:
	var adj := {}
	for l in graph.links:
		adj[l[0]] = adj.get(l[0], []) + [[l[1], l[2]]]
		adj[l[1]] = adj.get(l[1], []) + [[l[0], l[2]]]
	for start in CivicDividend.spawn_nodes:
		var seen := {start: true}
		var queue := [start]
		while not queue.is_empty():
			var n: String = queue.pop_front()
			for e in adj.get(n, []):
				if not seen.has(e[0]):
					seen[e[0]] = true
					queue.append(e[0])
		check(seen.size() == graph.nodes.size(), "%s reaches every waypoint (%d/%d)" % [start, seen.size(), graph.nodes.size()])
	var profile: Dictionary = CivicDividend.audit_profile
	var all_families: Array = profile.get("route_families", ["blv", "roof", "trn", "aln"])
	var need: int = int(profile.get("min_families", 4))
	for target in CivicDividend.goal_names.slice(1):
		var families := []
		for family in all_families:
			if _reach_with_family(CivicDividend.spawn_nodes[0], target, family, adj):
				families.append(family)
		check(families.size() >= need, "route families from the Helix depot to %s: %s (need %d)" % [target, families, need])

func _reach_with_family(start: String, target: String, family: String, adj: Dictionary) -> bool:
	# BFS on (node, used_family); a family counts only when a path uses at least one of its edges.
	var seen := {}
	var queue := [[start, family == "blv"]]
	seen[start + (":1" if family == "blv" else ":0")] = true
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		if cur[0] == target and cur[1]:
			return true
		for e in adj.get(cur[0], []):
			var used: bool = cur[1] or e[1] == family
			var key: String = e[0] + (":1" if used else ":0")
			if not seen.has(key):
				seen[key] = true
				queue.append([e[0], used])
	return false

# ---- sightlines ------------------------------------------------------------------------------------

func free_run(from: Vector3, dir: Vector3, limit: float = 140.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * limit, 1)
	var hit := space.intersect_ray(q)
	return limit if hit.is_empty() else from.distance_to(hit.position)

# Distance along a ray until it leaves the lane rectangle (sightlines out of a lane are not lane runs).
func _exit_distance(origin: Vector2, dir: Vector2, lane: Rect2) -> float:
	var best := 1000.0
	if absf(dir.x) > 0.0001:
		best = minf(best, maxf((lane.end.x - origin.x) / dir.x, (lane.position.x - origin.x) / dir.x))
	if absf(dir.y) > 0.0001:
		best = minf(best, maxf((lane.end.y - origin.y) / dir.y, (lane.position.y - origin.y) / dir.y))
	return best

func lane_stats(label: String, xs: Array, zs: Array, y: float, azimuths: Array, lane: Rect2) -> Dictionary:
	var runs: Array = []
	var worst := [0.0, Vector3.ZERO, 0.0]
	for x in xs:
		for z in zs:
			var p := Vector3(x, y + HEAD, z)
			if capsule_blocked(Vector3(x, y, z)):
				continue
			for az in azimuths:
				var dir := Vector3(cos(az), 0, sin(az))
				var run_len := minf(free_run(p, dir), _exit_distance(Vector2(p.x, p.z), Vector2(dir.x, dir.z), lane))
				runs.append(run_len)
				if run_len > worst[0]:
					worst = [run_len, p, az]
	runs.sort()
	var n := runs.size()
	if n == 0:
		return {}
	var out := {"p50": runs[n / 2], "p90": runs[int(n * 0.9)], "p99": runs[int(n * 0.99)], "max": runs[n - 1], "n": n}
	print("  %-22s n=%5d  p50=%5.1f  p90=%5.1f  p99=%5.1f  max=%5.1f   (longest from %s dir %.0f deg)" % [label, n, out.p50, out.p90, out.p99, out.max, worst[1], rad_to_deg(worst[2])])
	return out

func audit_sightlines() -> void:
	print("Sightlines (free head-height run in metres, lane-aligned directions +-15 deg):")
	var along: Array = []
	for d in [-15.0, -7.0, 0.0, 7.0, 15.0]:
		along.append(deg_to_rad(d))
		along.append(deg_to_rad(180.0 + d))
	var across: Array = []
	for d in [-60.0, -30.0, 30.0, 60.0, 120.0, 150.0, 210.0, 240.0]:
		across.append(deg_to_rad(d))
	if CivicDividend.audit_profile.has("lanes"):
		audit_profile_lanes(along, across)
		audit_spawn_and_points()
		return
	var xs := range(-78, 79, 4)
	var blv := lane_stats("boulevard", xs, [-10, -6, -2, 2, 6, 10], 0.0, along, Rect2(-82, -12, 164, 24))
	lane_stats("boulevard (cross)", xs, [-10, -2, 6], 0.0, across, Rect2(-82, -12, 164, 24))
	var trn := lane_stats("trench", xs, [16, 20, 24, 27], -4.0, along, Rect2(-82, 13, 164, 16))
	var aln_n := lane_stats("north alley", xs, [-34, -32], 0.0, along, Rect2(-82, -36, 164, 6))
	var aln_s := lane_stats("south alley", xs, [37, 39], 0.0, along, Rect2(-82, 35, 164, 6))
	var roof := lane_stats("north roofs", [-80, -66, -57, -50, -44, -36, -28, -22, -14, -7], [-27, -21, -15], 6.0, along, Rect2(-82, -30, 164, 18))
	check(not blv.is_empty() and blv.p50 <= 30.0, "boulevard median free run <= 30 m (%s)" % [blv.get("p50", -1)])
	check(not blv.is_empty() and blv.p90 <= 60.0, "boulevard p90 free run <= 60 m (%s)" % [blv.get("p90", -1)])
	check(not blv.is_empty() and blv.max < 100.0, "boulevard has no 100 m line (%s)" % [blv.get("max", -1)])
	check(not trn.is_empty() and trn.p90 <= 60.0, "trench p90 free run <= 60 m (%s)" % [trn.get("p90", -1)])
	check(not aln_n.is_empty() and aln_n.p99 <= 60.0 and not aln_s.is_empty() and aln_s.p99 <= 60.0, "alley p99 free run <= 60 m")
	check(not roof.is_empty() and roof.p99 <= 60.0, "roof route p99 free run <= 60 m (%s)" % [roof.get("p99", -1)])
	audit_spawn_and_points()

# Lanes, budgets and spawn-sight targets from the map's own audit profile (blockout settings.audit).
func audit_profile_lanes(along: Array, across: Array) -> void:
	for lane in CivicDividend.audit_profile.lanes:
		var xr: Array = lane.xs
		var zs: Array = lane.zs
		var r: Array = lane.rect
		var stats := lane_stats(lane.label, range(int(xr[0]), int(xr[1]) + 1, int(xr[2])), zs, float(lane.get("y", 0.0)), across if lane.get("azimuths", "along") == "across" else along, Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
		if stats.is_empty():
			check(false, "%s lane has no free sample points" % lane.label)
			continue
		for key in ["p50", "p90", "p99", "max"]:
			if lane.has(key):
				check(stats[key] <= float(lane[key]), "%s %s free run <= %s m (%s)" % [lane.label, key, lane[key], stats[key]])

func audit_spawn_and_points() -> void:
	# Spawn dogleg: nothing standing in the depot can see the open street.
	var seen := 0
	var sight: Variant = CivicDividend.audit_profile.get("spawn_sight", true)
	var sight_xs: Array = range(-70, 60, 10)
	var sight_zs: Array = [-8, 0, 8]
	if sight is Dictionary:
		sight_xs = range(int(sight.xs[0]), int(sight.xs[1]) + 1, int(sight.xs[2]))
		sight_zs = sight.zs
	for spawn_index in range(6):
		var sp_z := CivicDividend.spawn_z + spawn_index * CivicDividend.spawn_step
		var from := Vector3(-CivicDividend.spawn_x, HEAD, sp_z)
		if sight is bool and not sight:
			break
		for tx in sight_xs:
			for tz in sight_zs:
				var to := Vector3(tx, HEAD, tz)
				var q := PhysicsRayQueryParameters3D.create(from, to, 1)
				if space.intersect_ray(q).is_empty():
					seen += 1
	check(seen == 0, "spawn has no line of sight onto the open street (%d clear rays)" % seen)
	# No capture point sees a point two or more steps away.
	var pts := CivicDividend.capture_points
	var long_sight := 0
	for i in range(5):
		for j in range(i + 2, 5):
			var q := PhysicsRayQueryParameters3D.create(pts[i] + Vector3.UP * HEAD, pts[j] + Vector3.UP * HEAD, 1)
			if space.intersect_ray(q).is_empty():
				long_sight += 1
	print("  point pairs two or more steps apart with a clear line: ", long_sight, " of 6")
