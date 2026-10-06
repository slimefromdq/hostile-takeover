"""Export a Blender blockout to JSON for Hostile Takeover (Godot).

Run inside Blender (Scripting tab > Open > Run Script) or headless:
    blender -b scene.blend -P tools/blender/export_blockout.py -- maps/blockout.json

Conventions (full guide: docs/BLENDER.md)
- Model in metres, Blender Z-up. Godot is Y-up, so (x, y, z) in Blender becomes (x, z, -y) in Godot.
- Every mesh object is exported as its world-space bounding box, so keep pieces axis-aligned
  (rotations in 90 degree steps are fine). Snap to a 0.25 m grid.
- Role = custom property `role`, else the name of a collection the object is in:
  walk, wall, tower, cover, accent, hazard, glass.
- Custom properties on an object:
    kind    block (default) | ramp | cylinder | decor
    tag     name used in audits (default: object name without the .001 suffix)
    mirror  true = also build the copy mirrored across x = 0
    color   "#rrggbb" override
    ramp:   ramp_dir "+x" | "-x" | "+z" | "-z" (Godot axes, direction of ascent),
            ramp_start / ramp_end top heights in Godot y (default: box min y and box max y),
            ramp_floor base height (default: box min y)
    decor:  decor_mode "flush" (default) | "outside"
- Empties in a collection named "waypoints" become bot waypoints. Properties: `links` ("B:blv,C:roof"; tags blv,
  roof, trn, aln), `mirror`, `point` (capture point), `spawn` (depot node).
- Scene custom properties (Scene tab > Custom Properties) become map settings: ht_mode ("add" | "replace"),
  ht_bounds (x, z, width, height), ht_spawn_x, ht_spawn_z, ht_spawn_step, ht_depot_limit, ht_test_lane (x, y, z).
- Traversal-verb features (bounce, climb, cable, mover, event) and the audit profile are stored on the scene as JSON
  strings (ht_features, ht_audit) by import_blockout.py and written back unchanged; edit them in the Scene tab or
  regenerate the map from a generator script.
- Objects in collections whose name starts with "_" (e.g. the mirror preview) and objects with `ht_preview` are skipped.
"""
import json
import math
import re
import sys

FORMAT = 1
SNAP = 0.25
ROLES = ("walk", "wall", "tower", "cover", "accent", "hazard", "glass")
KINDS = ("block", "ramp", "cylinder", "decor")
RAMP_DIRS = ("+x", "-x", "+z", "-z")
SCENE_SETTINGS = {
    "ht_bounds": "bounds", "ht_spawn_x": "spawn_x", "ht_spawn_z": "spawn_z", "ht_spawn_step": "spawn_step",
    "ht_depot_limit": "depot_limit", "ht_test_lane": "test_lane",
}


def to_godot(p):
    """Blender world (x, y, z) -> Godot (x, z, -y)."""
    return (p[0], p[2], -p[1])


def godot_box(corners):
    pts = [to_godot(c) for c in corners]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return lo, hi


def clean_tag(name):
    return re.sub(r"\.\d{3}$", "", name)


def off_grid(values):
    return any(abs(v / SNAP - round(v / SNAP)) > 1e-3 for v in values)


def _num(v):
    v = round(float(v), 4)
    return int(v) if v == int(v) else v


def convert_object(name, corners, props, collection_names):
    """Pure conversion of one object. Returns (record or None, [warnings])."""
    warnings = []
    lo, hi = godot_box(corners)
    kind = str(props.get("kind", "block")).lower()
    if kind not in KINDS:
        return None, ["%s: unknown kind '%s'" % (name, kind)]
    role = props.get("role")
    if role is None:
        role = next((c.lower() for c in collection_names if c.lower() in ROLES), None)
    if role is None:
        role = "wall"
        warnings.append("%s: no role (collection or property); using 'wall'" % name)
    role = str(role).lower()
    if role not in ROLES:
        return None, ["%s: unknown role '%s'" % (name, role)]
    if any(hi[i] - lo[i] < SNAP for i in range(3)) and kind != "decor":
        return None, ["%s: thinner than %.2f m, skipped" % (name, SNAP)]
    if kind != "decor" and off_grid(lo + hi):
        warnings.append("%s: not on the %.2f m grid (MapBuilder will snap it)" % (name, SNAP))
    rec = {
        "kind": kind,
        "tag": str(props.get("tag", clean_tag(name))),
        "role": role,
        "min": [_num(v) for v in lo],
        "max": [_num(v) for v in hi],
    }
    if props.get("mirror"):
        rec["mirror"] = True
    if props.get("color"):
        rec["color"] = str(props["color"])
    if kind == "ramp":
        direction = str(props.get("ramp_dir", ""))
        if direction not in RAMP_DIRS:
            return None, ["%s: ramp needs ramp_dir one of %s" % (name, ", ".join(RAMP_DIRS))]
        rec["dir"] = direction
        rec["y_floor"] = _num(props.get("ramp_floor", lo[1]))
        rec["y_start"] = _num(props.get("ramp_start", lo[1]))
        rec["y_end"] = _num(props.get("ramp_end", hi[1]))
    if kind == "decor":
        rec["mode"] = str(props.get("decor_mode", "flush"))
    return rec, warnings


def parse_links(text):
    out = []
    for part in str(text).split(","):
        part = part.strip()
        if not part:
            continue
        target, _, tag = part.partition(":")
        out.append([target.strip(), (tag or "blv").strip()])
    return out


def build_document(objects, waypoints, mode="add", source="", settings=None, features=None):
    wps, links = [], []
    for w in waypoints:
        rec = {"name": w["name"], "pos": w["pos"]}
        for flag in ("mirror", "point", "spawn"):
            if w.get(flag):
                rec[flag] = True
        wps.append(rec)
        links.extend([w["name"], t, tag] for t, tag in w["links"])
    return {
        "format": FORMAT,
        "units": "m",
        "mode": mode,
        "source": source,
        "settings": settings or {},
        "features": features or [],
        "objects": objects,
        "waypoints": wps,
        "links": links,
    }


def _is_90(angle):
    q = angle / (math.pi / 2)
    return abs(q - round(q)) < 1e-3


def _plain(value):
    try:
        return [_num(v) for v in value]
    except TypeError:
        return _num(value)


def scene_settings(scene):
    out = {}
    for key, name in SCENE_SETTINGS.items():
        if key in scene.keys():
            out[name] = _plain(scene[key])
    if "ht_audit" in scene.keys():
        out["audit"] = json.loads(scene["ht_audit"])
    return out


def export_scene(path, mode=None):
    import bpy  # only available inside Blender
    from mathutils import Vector

    scene = bpy.context.scene
    bpy.context.view_layer.update()  # world matrices are stale until the depsgraph runs (headless scripts)
    objects, waypoints, warnings = [], [], []
    for obj in scene.objects:
        cols = [c.name for c in obj.users_collection]
        props = {k: obj[k] for k in obj.keys() if not k.startswith("_")}
        if props.get("ht_preview") or any(c.startswith("_") for c in cols):
            continue
        if obj.type == "EMPTY" and "waypoints" in [c.lower() for c in cols]:
            pos = to_godot(tuple(obj.matrix_world.translation))
            waypoints.append({"name": clean_tag(obj.name), "pos": [_num(v) for v in pos],
                              "links": parse_links(props.get("links", "")), "mirror": bool(props.get("mirror")),
                              "point": bool(props.get("point")), "spawn": bool(props.get("spawn"))})
            continue
        if obj.type != "MESH" or obj.hide_viewport or obj.hide_get():
            continue
        if not all(_is_90(a) for a in obj.matrix_world.to_euler()):
            warnings.append("%s: rotated off 90 degree steps; only its bounding box is exported" % obj.name)
        corners = [tuple(obj.matrix_world @ Vector(c)) for c in obj.bound_box]
        rec, warns = convert_object(obj.name, corners, props, cols)
        warnings.extend(warns)
        if rec:
            objects.append(rec)
    mode = mode or str(scene.get("ht_mode", "add"))
    features = json.loads(scene["ht_features"]) if "ht_features" in scene.keys() else []
    doc = build_document(objects, waypoints, mode, bpy.path.basename(bpy.data.filepath), scene_settings(scene), features)
    with open(path, "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    print("Exported %d objects, %d waypoints to %s (mode %s)" % (len(objects), len(waypoints), path, mode))
    for w in warnings:
        print("WARNING:", w)
    return doc


if __name__ == "__main__":
    try:
        import bpy
    except ImportError:
        sys.exit("Run this script inside Blender.")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    export_scene(argv[0] if argv else bpy.path.abspath("//blockout.json"))
