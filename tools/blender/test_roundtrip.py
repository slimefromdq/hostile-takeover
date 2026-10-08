"""Blender round trip: generate -> import into Blender -> export -> compare. Needs the `bpy` module (pip install bpy)
or run it with Blender:  blender -b -P tools/blender/test_roundtrip.py

Skips (exit 0) when Blender is not available."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    import bpy  # noqa: F401
except ImportError:
    print("SKIP: bpy not available")
    sys.exit(0)

import export_blockout  # noqa: E402
import generate  # noqa: E402
import import_blockout  # noqa: E402
from blockout_kit import Blockout  # noqa: E402


def key(rec):
    return (rec["kind"], rec["tag"], tuple(rec["min"]), tuple(rec["max"]))


def roundtrip(map_name):
    module = generate.load_generator(os.path.join(HERE, "maps", map_name + ".py"))
    b = Blockout(mode=module.MODE, title=getattr(module, "TITLE", None))
    module.build(b)
    src = b.to_document(map_name)
    import_blockout.build_scene(src)
    out = os.path.join(tempfile.mkdtemp(), "out.json")
    doc = export_blockout.export_scene(out)
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append("%s: %s" % (map_name, msg))

    check(doc["mode"] == "replace", "mode survives")
    check(doc.get("title") == src.get("title"), "title survives")
    check(len(doc["objects"]) == len(src["objects"]), "object count %d vs %d" % (len(doc["objects"]), len(src["objects"])))
    got = {key(r): r for r in doc["objects"]}
    for rec in src["objects"]:
        k = key(rec)
        if k not in got:
            failures.append("%s: missing or moved after round trip: %s" % (map_name, k))
            continue
        out_rec = got[k]
        check(out_rec["role"] == rec["role"], "role of %s" % rec["tag"])
        check(bool(out_rec.get("mirror")) == bool(rec.get("mirror")), "mirror of %s" % rec["tag"])
        if rec["kind"] == "ramp":
            for f in ("dir", "y_floor", "y_start", "y_end"):
                check(out_rec[f] == rec[f], "ramp %s of %s: %s vs %s" % (f, rec["tag"], out_rec.get(f), rec[f]))
    check(doc["settings"] == src["settings"], "settings %s vs %s" % (doc["settings"], src["settings"]))
    check(doc["features"] == src["features"], "features (%d vs %d) survive unchanged" % (len(doc["features"]), len(src["features"])))
    check(sorted(map(tuple, doc["links"])) == sorted(map(tuple, src["links"])), "links survive")
    wp = {w["name"]: w for w in doc["waypoints"]}
    for w in src["waypoints"]:
        o = wp.get(w["name"])
        check(o is not None and o["pos"] == w["pos"], "waypoint %s position" % w["name"])
        check(o is not None and all(bool(o.get(f)) == bool(w.get(f)) for f in ("mirror", "point", "spawn")), "waypoint %s flags" % w["name"])
    previews = [o for o in bpy.context.scene.objects if o.get("ht_preview")]
    check(len(previews) == sum(1 for r in src["objects"] if r.get("mirror")), "one preview per mirrored object")
    return failures, len(doc["objects"]), len(doc["waypoints"]), len(doc["features"])


def main():
    failures = []
    for name in ("yard", "canopy", "yacht_club"):
        f, objects, waypoints, features = roundtrip(name)
        failures.extend(f)
        print("%s: %d objects, %d waypoints, %d features" % (name, objects, waypoints, features))
    if failures:
        print("ROUND TRIP FAILED")
        for f in failures[:30]:
            print("  -", f)
        sys.exit(1)
    print("ROUND TRIP OK")


if __name__ == "__main__":
    main()
