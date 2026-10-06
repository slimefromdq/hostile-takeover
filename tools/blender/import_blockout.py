"""Build a Blender scene from a blockout JSON (the format export_blockout.py writes and blockout_kit.py generates).

    blender -b -P tools/blender/import_blockout.py -- maps/blockout.json out.blend

Each object becomes a mesh in a collection named for its role, with the custom properties the exporter reads.
Mirrored pieces get a read-only preview copy in the "_MirrorPreview" collection (never exported).
Waypoints become empties in "Waypoints". Map settings become scene custom properties.
"""
import json
import sys

ROLE_COLORS = {
    "walk": (0.87, 0.89, 0.90, 1), "wall": (0.89, 0.90, 0.91, 1), "tower": (0.86, 0.90, 0.94, 1),
    "cover": (1.0, 0.42, 0.17, 1), "accent": (1.0, 0.42, 0.17, 1), "hazard": (1.0, 0.79, 0.16, 1),
    "glass": (0.75, 0.91, 1.0, 0.4),
}
SETTING_PROPS = {
    "bounds": "ht_bounds", "spawn_x": "ht_spawn_x", "spawn_z": "ht_spawn_z", "spawn_step": "ht_spawn_step",
    "depot_limit": "ht_depot_limit", "test_lane": "ht_test_lane", "ceiling": "ht_ceiling",
}
MIRROR_DIR = {"+x": "-x", "-x": "+x", "+z": "+z", "-z": "-z"}


def godot_to_blender(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def wedge_heights(direction, y_start, y_end):
    """Top heights at corners [(x0, z0), (x1, z0), (x1, z1), (x0, z1)] (min/max x and z), like MapBuilder.ramp."""
    h00 = h10 = h01 = h11 = y_start
    if direction == "+x":
        h10 = h11 = y_end
    elif direction == "-x":
        h00 = h01 = y_end
    elif direction == "+z":
        h01 = h11 = y_end
    elif direction == "-z":
        h00 = h10 = y_end
    return [h00, h10, h11, h01]


def mesh_data(rec):
    """(verts, faces) in Godot world coordinates for a block, decor or ramp record."""
    lo, hi = rec["min"], rec["max"]
    if rec["kind"] == "ramp":
        heights = wedge_heights(rec["dir"], rec["y_start"], rec["y_end"])
        corners = [(lo[0], lo[2]), (hi[0], lo[2]), (hi[0], hi[2]), (lo[0], hi[2])]
        verts = [(x, rec["y_floor"], z) for x, z in corners] + [(x, h, z) for (x, z), h in zip(corners, heights)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (3, 0, 4, 7), (1, 2, 6, 5)]
        return verts, faces
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (3, 0, 4, 7), (1, 2, 6, 5)]
    return verts, faces


def _material(bpy, role):
    name = "ht_" + role
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = ROLE_COLORS.get(role, (0.8, 0.8, 0.8, 1))
    return mat


def _collection(bpy, scene, name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
    return col


def _make_object(bpy, bmesh, name, rec, col):
    if rec["kind"] == "cylinder":
        lo, hi = rec["min"], rec["max"]
        centre = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=(hi[0] - lo[0]) / 2, radius2=(hi[0] - lo[0]) / 2, depth=hi[1] - lo[1])
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
    else:
        verts_g, faces = mesh_data(rec)
        xs = [v[0] for v in verts_g]
        ys = [v[1] for v in verts_g]
        zs = [v[2] for v in verts_g]
        centre = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
        local = [godot_to_blender((v[0] - centre[0], v[1] - centre[1], v[2] - centre[2])) for v in verts_g]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(local, [], faces)
        mesh.validate()
        mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = godot_to_blender(centre)
    obj.data.materials.append(_material(bpy, rec["role"]))
    obj.color = ROLE_COLORS.get(rec["role"], (0.8, 0.8, 0.8, 1))
    col.objects.link(obj)
    return obj


def _set_props(obj, rec, mirror_dir=None):
    obj["kind"] = rec["kind"]
    obj["tag"] = rec["tag"]
    obj["role"] = rec["role"]
    if rec.get("mirror"):
        obj["mirror"] = True
    if rec.get("color"):
        obj["color"] = rec["color"]
    if rec["kind"] == "ramp":
        obj["ramp_dir"] = rec["dir"]
        obj["ramp_floor"] = rec["y_floor"]
        obj["ramp_start"] = rec["y_start"]
        obj["ramp_end"] = rec["y_end"]
    if rec["kind"] == "decor":
        obj["decor_mode"] = rec.get("mode", "flush")


def build_scene(doc, clear=True):
    import bpy
    import bmesh

    if clear:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene["ht_mode"] = doc.get("mode", "add")
    if doc.get("title"):
        scene["ht_title"] = doc["title"]
    for key, prop in SETTING_PROPS.items():
        if key in doc.get("settings", {}):
            scene[prop] = doc["settings"][key]
    scene["ht_features"] = json.dumps(doc.get("features", []))
    if doc.get("settings", {}).get("audit"):
        scene["ht_audit"] = json.dumps(doc["settings"]["audit"])
    for rec in doc.get("objects", []):
        name = rec["tag"]
        col = _collection(bpy, scene, rec["role"].capitalize())
        obj = _make_object(bpy, bmesh, name, rec, col)
        _set_props(obj, rec)
        if rec.get("mirror"):
            lo, hi = rec["min"], rec["max"]
            mrec = dict(rec)
            mrec["min"] = [-hi[0], lo[1], lo[2]]
            mrec["max"] = [-lo[0], hi[1], hi[2]]
            if rec["kind"] == "ramp":
                mrec["dir"] = MIRROR_DIR[rec["dir"]]
            prev = _make_object(bpy, bmesh, rec["tag"] + "_e", mrec, _collection(bpy, scene, "_MirrorPreview"))
            prev["ht_preview"] = True
            prev.display_type = "WIRE"
    links = {}
    for a, b, tag in doc.get("links", []):
        links.setdefault(a, []).append("%s:%s" % (b, tag))
    wp_col = _collection(bpy, scene, "Waypoints")
    for w in doc.get("waypoints", []):
        empty = bpy.data.objects.new(w["name"], None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.6
        empty.location = godot_to_blender(w["pos"])
        empty["links"] = ",".join(links.get(w["name"], []))
        for flag in ("mirror", "point", "spawn"):
            if w.get(flag):
                empty[flag] = True
        wp_col.objects.link(empty)
    bpy.context.view_layer.update()
    return scene


def import_file(json_path, blend_path=None):
    with open(json_path) as f:
        doc = json.load(f)
    build_scene(doc)
    if blend_path:
        import bpy
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return doc


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        sys.exit("Run this script inside Blender.")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        sys.exit("usage: blender -b -P import_blockout.py -- in.json [out.blend]")
    import_file(argv[0], argv[1] if len(argv) > 1 else None)
