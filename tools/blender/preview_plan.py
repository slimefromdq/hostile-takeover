"""Draw a top-down plan and an isometric view of a blockout JSON. Needs matplotlib, not Blender.

    python3 tools/blender/preview_plan.py maps/blockout.json docs/previews/blockout   # writes _plan.png, _iso.png

Mirrored halves are drawn. Colours follow the role palette; waypoints and capture points are overlaid on the plan.
"""
import json
import math
import sys

COLORS = {"walk": "#c9cfd4", "wall": "#e4e6e8", "tower": "#b9c7d8", "cover": "#ff6a2b", "accent": "#ff6a2b",
          "hazard": "#ffc928", "glass": "#bfe9ff"}
MIRROR_DIR = {"+x": "-x", "-x": "+x", "+z": "+z", "-z": "-z"}


def expand(doc):
    out = []
    for r in doc["objects"]:
        out.append(r)
        if r.get("mirror"):
            lo, hi = r["min"], r["max"]
            m = dict(r, min=[-hi[0], lo[1], lo[2]], max=[-lo[0], hi[1], hi[2]])
            if r["kind"] == "ramp":
                m["dir"] = MIRROR_DIR[r["dir"]]
            out.append(m)
    return out


def faces(r):
    """Polygons (lists of (x, y, z) in Godot coordinates) for one record."""
    lo, hi = r["min"], r["max"]
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    if r["kind"] == "ramp":
        h = {"+x": (r["y_start"], r["y_end"], r["y_end"], r["y_start"]), "-x": (r["y_end"], r["y_start"], r["y_start"], r["y_end"]),
             "+z": (r["y_start"], r["y_start"], r["y_end"], r["y_end"]), "-z": (r["y_end"], r["y_end"], r["y_start"], r["y_start"])}[r["dir"]]
        c = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
        top = [(x, hh, z) for (x, z), hh in zip(c, h)]
        bot = [(x, r["y_floor"], z) for x, z in c]
        sides = [[bot[i], bot[(i + 1) % 4], top[(i + 1) % 4], top[i]] for i in range(4)]
        return [top] + sides
    if r["kind"] == "cylinder":
        cx, cz, rad = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2
        pts = [(cx + rad * math.cos(t * math.tau / 16), cz + rad * math.sin(t * math.tau / 16)) for t in range(16)]
        polys = [[(x, y1, z) for x, z in pts]]
        for i in range(16):
            (xa, za), (xb, zb) = pts[i], pts[(i + 1) % 16]
            polys.append([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)])
        return polys
    return [
        [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)],
        [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
        [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)],
    ]


def main(json_path, prefix):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    doc = json.load(open(json_path))
    objs = [r for r in expand(doc) if r["kind"] != "decor"]
    s = doc.get("settings", {})
    # Plan: lower solids first so tall ones draw on top.
    fig, ax = plt.subplots(figsize=(14, 8))
    for r in sorted(objs, key=lambda r: r["max"][1]):
        lo, hi = r["min"], r["max"]
        shade = min(1.0, 0.55 + 0.45 * (hi[1] / 8.0))
        ax.add_patch(plt.Rectangle((lo[0], lo[2]), hi[0] - lo[0], hi[2] - lo[2], fc=COLORS[r["role"]], ec="#44505c", lw=0.5, alpha=shade))
    nodes = {w["name"]: w["pos"] for w in doc.get("waypoints", [])}
    for w in list(doc.get("waypoints", [])):
        if w.get("mirror") and w["pos"][0]:
            nodes["e_" + w["name"]] = [-w["pos"][0], w["pos"][1], w["pos"][2]]
    for a, b, tag in doc.get("links", []):
        for na, nb in ((a, b), ("e_" + a, "e_" + b)):
            if na in nodes and nb in nodes:
                ax.plot([nodes[na][0], nodes[nb][0]], [nodes[na][2], nodes[nb][2]], color="#2a5bd7", lw=1, alpha=0.6)
    for n, p in nodes.items():
        ax.plot(p[0], p[2], "o", ms=3, color="#2a5bd7")
    points = [w for w in doc.get("waypoints", []) if w.get("point")]
    for w in points:
        for x in ([w["pos"][0], -w["pos"][0]] if w["pos"][0] else [0]):
            ax.add_patch(plt.Circle((x, w["pos"][2]), 4.5, fill=False, ec="#ff6a2b", lw=2))
            ax.text(x, w["pos"][2], w["name"].replace("e_", ""), ha="center", va="center", fontsize=11, weight="bold")
    b = s.get("bounds")
    if b:
        ax.add_patch(plt.Rectangle((b[0], b[1]), b[2], b[3], fill=False, ec="#999", ls="--"))
    ax.set_aspect("equal")
    ax.autoscale_view()
    ax.invert_yaxis()
    ax.set_title("Plan view (north up, x west to east); blue = bot graph, orange = capture radius 4.5 m")
    fig.tight_layout()
    fig.savefig(prefix + "_plan.png", dpi=110)
    plt.close(fig)
    fig = plt.figure(figsize=(14, 8))
    ax = fig.add_subplot(111, projection="3d")
    polys, cols = [], []
    for r in objs:
        for poly in faces(r):
            polys.append([(x, z, y) for x, y, z in poly])  # plot x, z (depth), y (up)
            cols.append(COLORS[r["role"]])
    ax.add_collection3d(Poly3DCollection(polys, facecolors=cols, edgecolors="#44505c", linewidths=0.3, alpha=0.95))
    xs = [v for r in objs for v in (r["min"][0], r["max"][0])]
    zs = [v for r in objs for v in (r["min"][2], r["max"][2])]
    ax.set_xlim(min(xs), max(xs))
    ax.set_ylim(max(zs), min(zs))
    ax.set_zlim(0, max(r["max"][1] for r in objs) * 3)
    ax.set_box_aspect((max(xs) - min(xs), max(zs) - min(zs), (max(xs) - min(xs)) * 0.35))
    ax.view_init(elev=38, azim=-62)
    ax.set_axis_off()
    fig.tight_layout()
    fig.savefig(prefix + "_iso.png", dpi=110)
    print("wrote %s_plan.png and %s_iso.png" % (prefix, prefix))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: preview_plan.py in.json output_prefix")
    main(sys.argv[1], sys.argv[2])
