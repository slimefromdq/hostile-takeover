class_name MapBuilder
extends RefCounted

# Single entry point for map geometry. Every solid is created here, so the visible mesh and the
# collider always come from the same snapped dimensions, and every solid is registered in `solids`
# for the audits in tests/map_audit.gd. Meshes are merged per material to keep draw calls low;
# colliders live under one StaticBody3D on layer 1.

const SNAP := 0.25
const LAYER_WORLD := 1

var solids: Array = []
var decor: Array = []
var sunken: Array[Rect2] = []
var _groups: Dictionary = {}
var _shapes: Array = []

static func snap(v: float) -> float:
	return roundf(v / SNAP) * SNAP

# ---- solids ---------------------------------------------------------------

# Axis-aligned block from corner ranges. Coordinates snap to 0.25 m.
func block(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, tag: String = "") -> void:
	var a := Vector3(snap(minf(x0, x1)), snap(minf(y0, y1)), snap(minf(z0, z1)))
	var b := Vector3(snap(maxf(x0, x1)), snap(maxf(y0, y1)), snap(maxf(z0, z1)))
	if b.x - a.x < SNAP or b.y - a.y < SNAP or b.z - a.z < SNAP:
		push_error("MapBuilder: degenerate block %s %s" % [tag, [x0, z0, x1, z1, y0, y1]])
		return
	var box := BoxShape3D.new()
	box.size = b - a
	_shapes.append({"shape": box, "xf": Transform3D(Basis.IDENTITY, (a + b) * 0.5)})
	var g := _group(role, color)
	_add_box(g, a, b)
	solids.append({"kind": "block", "aabb": AABB(a, b - a), "role": role, "tag": tag})

# Block plus its mirror across x=0. `east` optionally recolours the mirrored copy.
func pair(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, tag: String = "", east: Color = Color(0, 0, 0, 0)) -> void:
	block(x0, z0, x1, z1, y0, y1, role, color, tag)
	block(-x1, z0, -x0, z1, y0, y1, role, east if east.a > 0.0 else color, tag + "_e")

# Wedge ramp. `dir` is the direction of ascent ("+x", "-x", "+z", "-z"). The solid fills from y_floor up
# to a sloped top that runs from y_start (at the low end) to y_end (at the high end).
func ramp(x0: float, z0: float, x1: float, z1: float, y_floor: float, y_start: float, y_end: float, dir: String, role: String, color: Color, tag: String = "") -> void:
	var ax := snap(minf(x0, x1))
	var bx := snap(maxf(x0, x1))
	var az := snap(minf(z0, z1))
	var bz := snap(maxf(z0, z1))
	var yf := snap(y_floor)
	var ys := snap(y_start)
	var ye := snap(y_end)
	# Corner heights of the sloped top: lo/hi pair by direction.
	var h00 := ys
	var h10 := ys
	var h01 := ys
	var h11 := ys
	match dir:
		"+x":
			h10 = ye
			h11 = ye
		"-x":
			h00 = ye
			h01 = ye
		"+z":
			h01 = ye
			h11 = ye
		"-z":
			h00 = ye
			h10 = ye
	# Index: (x, z) -> h[xi][zi]; xi 0=ax 1=bx, zi 0=az 1=bz.
	var top := [[h00, h01], [h10, h11]]
	var p_bot := [Vector3(ax, yf, az), Vector3(bx, yf, az), Vector3(bx, yf, bz), Vector3(ax, yf, bz)]
	var p_top := [Vector3(ax, top[0][0], az), Vector3(bx, top[1][0], az), Vector3(bx, top[1][1], bz), Vector3(ax, top[0][1], bz)]
	var pts := PackedVector3Array()
	var low := Vector3(ax, yf, az)
	var high := Vector3(bx, maxf(maxf(h00, h10), maxf(h01, h11)), bz)
	var center := (low + high) * 0.5
	for p in p_bot + p_top:
		# Degenerate top corners (zero height above floor) collapse onto the bottom corner; the hull handles it.
		pts.append(p - center)
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	_shapes.append({"shape": hull, "xf": Transform3D(Basis.IDENTITY, center)})
	var g := _group(role, color)
	# Faces (counter-clockwise seen from outside).
	_quad(g, p_bot[0], p_bot[1], p_bot[2], p_bot[3])            # bottom (normal computed by winding)
	_quad(g, p_top[3], p_top[2], p_top[1], p_top[0])            # sloped top
	_quad(g, p_bot[0], p_top[0], p_top[1], p_bot[1])            # north (z=az)
	_quad(g, p_bot[2], p_top[2], p_top[3], p_bot[3])            # south (z=bz)
	_quad(g, p_bot[3], p_top[3], p_top[0], p_bot[0])            # west (x=ax)
	_quad(g, p_bot[1], p_top[1], p_top[2], p_bot[2])            # east (x=bx)
	var lo_y := minf(minf(h00, h10), minf(h01, h11))
	solids.append({"kind": "ramp", "aabb": AABB(low, Vector3(bx - ax, high.y - yf, bz - az)), "role": role, "tag": tag, "dir": dir, "y_start": ys, "y_end": ye, "y_floor": yf, "low_top": lo_y})

func ramp_pair(x0: float, z0: float, x1: float, z1: float, y_floor: float, y_start: float, y_end: float, dir: String, role: String, color: Color, tag: String = "") -> void:
	ramp(x0, z0, x1, z1, y_floor, y_start, y_end, dir, role, color, tag)
	var mirrored := dir
	if dir == "+x":
		mirrored = "-x"
	elif dir == "-x":
		mirrored = "+x"
	ramp(-x1, z0, -x0, z1, y_floor, y_start, y_end, mirrored, role, color, tag + "_e")

func cylinder(cx: float, cz: float, radius: float, y0: float, y1: float, role: String, color: Color, tag: String = "") -> void:
	var r := snap(radius)
	var c := Vector3(snap(cx), 0, snap(cz))
	var a := snap(minf(y0, y1))
	var b := snap(maxf(y0, y1))
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = b - a
	_shapes.append({"shape": shape, "xf": Transform3D(Basis.IDENTITY, Vector3(c.x, (a + b) * 0.5, c.z))})
	var g := _group(role, color)
	var sides := 16
	for i in range(sides):
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var p0 := Vector3(c.x + cos(t0) * r, 0, c.z + sin(t0) * r)
		var p1 := Vector3(c.x + cos(t1) * r, 0, c.z + sin(t1) * r)
		_quad(g, Vector3(p0.x, a, p0.z), Vector3(p0.x, b, p0.z), Vector3(p1.x, b, p1.z), Vector3(p1.x, a, p1.z))
		_tri(g, Vector3(c.x, b, c.z), Vector3(p1.x, b, p1.z), Vector3(p0.x, b, p0.z))
		_tri(g, Vector3(c.x, a, c.z), Vector3(p0.x, a, p0.z), Vector3(p1.x, a, p1.z))
	solids.append({"kind": "cylinder", "aabb": AABB(Vector3(c.x - r, a, c.z - r), Vector3(r * 2, b - a, r * 2)), "role": role, "tag": tag})

# ---- non-colliding decor --------------------------------------------------
# mode "flush": proud of a solid face (decals, trim). mode "outside": beyond the playable bounds.

func decor_block(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, role: String, color: Color, mode: String, tag: String = "") -> void:
	var a := Vector3(minf(x0, x1), minf(y0, y1), minf(z0, z1))
	var b := Vector3(maxf(x0, x1), maxf(y0, y1), maxf(z0, z1))
	_add_box(_group(role, color), a, b)
	decor.append({"aabb": AABB(a, b - a), "mode": mode, "tag": tag})

# ---- output ---------------------------------------------------------------

func finalize(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "MapGeometry"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	parent.add_child(body)
	for entry in _shapes:
		var cs := CollisionShape3D.new()
		cs.shape = entry.shape
		cs.transform = entry.xf
		body.add_child(cs)
	for key in _groups:
		var g: Dictionary = _groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.norms
		arrays[Mesh.ARRAY_INDEX] = g.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshInstance3D.new()
		node.name = "Mesh_%s" % key.replace(":", "_")
		node.mesh = mesh
		node.material_override = Visuals.surface(g.role, g.color)
		parent.add_child(node)

func shape_count() -> int:
	return _shapes.size()

func mesh_count() -> int:
	return _groups.size()

# Ground-plane footprints of buildings (blocks that stand on or above street level) for the minimap.
func footprints() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for s in solids:
		var box: AABB = s.aabb
		if s.kind != "block" or s.role == "walk" or box.size.y < 1.2 or box.position.y < -0.01:
			continue
		out.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	return out

# ---- mesh helpers -----------------------------------------------------------

func _group(role: String, color: Color) -> Dictionary:
	var key := "%s:%s" % [role, color.to_html()]
	if not _groups.has(key):
		_groups[key] = {"role": role, "color": color, "verts": PackedVector3Array(), "norms": PackedVector3Array(), "idx": PackedInt32Array()}
	return _groups[key]

func _tri(g: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.00001:
		return
	n = n.normalized()
	var base: int = g.verts.size()
	# Godot treats clockwise triangles as front faces, so emit (a, c, b) while keeping the outward normal.
	g.verts.append_array(PackedVector3Array([a, c, b]))
	g.norms.append_array(PackedVector3Array([n, n, n]))
	g.idx.append_array(PackedInt32Array([base, base + 1, base + 2]))

func _quad(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(g, a, b, c)
	_tri(g, a, c, d)

func _add_box(g: Dictionary, a: Vector3, b: Vector3) -> void:
	var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	_quad(g, p[0], p[1], p[2], p[3])  # bottom (-y)
	_quad(g, p[4], p[7], p[6], p[5])  # top (+y)
	_quad(g, p[0], p[4], p[5], p[1])  # north (-z)
	_quad(g, p[2], p[6], p[7], p[3])  # south (+z)
	_quad(g, p[3], p[7], p[4], p[0])  # west (-x)
	_quad(g, p[1], p[5], p[6], p[2])  # east (+x)
