"""Navigation and clearance checks for a blockout, without Godot (an approximation of tests/map_audit.gd).

    python3 tools/blender/blockout_check.py maps/blockout.json

Checks, using the same capsule as the game (radius 0.52, height 1.9):
  - every waypoint stands on ground and has capsule clearance,
  - every edge is walkable (ground never jumps more than STEP between 0.25 m samples, no solid in the way),
  - the depot reaches every waypoint and every capture point,
  - spawns are clear, capture discs are flat street level with no cover inside 4.5 m.
The audit in Godot remains the authority; this catches layout mistakes in seconds.
"""
import json
import math
import sys

RADIUS = 0.52
HEIGHT = 1.9
STEP = 0.6          # largest ground rise the walker climbs without jumping
FEET = 0.35         # anything lower than this above the feet is walked over
SAMPLE = 0.25


def mirror_rec(r):
    lo, hi = r["min"], r["max"]
    m = dict(r, min=[-hi[0], lo[1], lo[2]], max=[-lo[0], hi[1], hi[2]])
    if r["kind"] == "ramp":
        m["dir"] = {"+x": "-x", "-x": "+x"}.get(r["dir"], r["dir"])
    return m


def solids_of(doc):
    out = []
    for r in doc["objects"]:
        if r["kind"] == "decor":
            continue
        out.append(r)
        if r.get("mirror"):
            out.append(mirror_rec(r))
    return out


def surface_y(r, x, z):
    """Top surface height of solid r at (x, z), or None when (x, z) is outside it."""
    lo, hi = r["min"], r["max"]
    if r["kind"] == "cylinder":
        cx, cz, rad = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, (hi[0] - lo[0]) / 2
        return hi[1] if (x - cx) ** 2 + (z - cz) ** 2 <= rad * rad else None
    if not (lo[0] <= x <= hi[0] and lo[2] <= z <= hi[2]):
        return None
    if r["kind"] != "ramp":
        return hi[1]
    d, a, b = r["dir"], r["y_start"], r["y_end"]
    if d in ("+x", "-x"):
        t = (x - lo[0]) / (hi[0] - lo[0])
    else:
        t = (z - lo[2]) / (hi[2] - lo[2])
    if d in ("-x", "-z"):
        t = 1 - t
    return a + (b - a) * t


class World:
    def __init__(self, doc):
        self.solids = solids_of(doc)

    def ground(self, x, z, y_hint):
        """Highest surface not more than STEP above y_hint (the walker climbs, it does not teleport)."""
        best = None
        for r in self.solids:
            y = surface_y(r, x, z)
            if y is not None and y <= y_hint + STEP and (best is None or y > best):
                best = y
        return best

    def blocked(self, x, y, z):
        """Is the standing capsule at feet (x, y, z) inside any solid above the step height?"""
        for r in self.solids:
            lo, hi = r["min"], r["max"]
            if hi[1] <= y + FEET or lo[1] >= y + HEIGHT:
                continue
            if r["kind"] == "cylinder":
                cx, cz, rad = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2, (hi[0] - lo[0]) / 2
                if math.hypot(x - cx, z - cz) < rad + RADIUS:
                    return r["tag"]
                continue
            nx = min(max(x, lo[0]), hi[0])
            nz = min(max(z, lo[2]), hi[2])
            if math.hypot(x - nx, z - nz) >= RADIUS:
                continue
            if r["kind"] == "ramp":
                # Only the part of the wedge poking above the walker's feet blocks.
                top = max(surface_y(r, nx, nz) or -1e9, -1e9)
                if top <= y + FEET:
                    continue
            return r["tag"]
        return None


def nodes_of(doc):
    nodes = {}
    for w in doc["waypoints"]:
        nodes[w["name"]] = w["pos"]
        if w.get("mirror") and abs(w["pos"][0]) > 1e-6:
            nodes["e_" + w["name"]] = [-w["pos"][0], w["pos"][1], w["pos"][2]]
    mirrored = {w["name"] for w in doc["waypoints"] if w.get("mirror") and abs(w["pos"][0]) > 1e-6}
    links = []
    for a, b, tag in doc["links"]:
        links.append((a, b, tag))
        ma = "e_" + a if a in mirrored else a
        mb = "e_" + b if b in mirrored else b
        if (ma, mb) != (a, b):
            links.append((ma, mb, tag))
    return nodes, links


def check(doc):
    world = World(doc)
    problems = []
    nodes, links = nodes_of(doc)
    for name, p in sorted(nodes.items()):
        g = world.ground(p[0], p[2], p[1])
        if g is None or abs(g - p[1]) > 0.1:
            problems.append("waypoint %s at %s: ground is %s" % (name, p, g))
            continue
        hit = world.blocked(p[0], g, p[2])
        if hit:
            problems.append("waypoint %s at %s: capsule inside %s" % (name, p, hit))
    for a, b, tag in links:
        if a not in nodes or b not in nodes:
            problems.append("link %s-%s: missing waypoint" % (a, b))
            continue
        if tag in ("lad", "jmp"):
            continue  # ladders and gap jumps are verbs, not walks (the game's bot_tower test covers them)
        pa, pb = nodes[a], nodes[b]
        length = math.dist((pa[0], pa[2]), (pb[0], pb[2]))
        n = max(1, int(length / SAMPLE))
        y = pa[1]
        for i in range(1, n + 1):
            t = i / n
            x, z = pa[0] + (pb[0] - pa[0]) * t, pa[2] + (pb[2] - pa[2]) * t
            g = world.ground(x, z, y)
            if g is None:
                problems.append("edge %s-%s (%s): no ground at %.1f,%.1f" % (a, b, tag, x, z))
                break
            if g < y - 0.45:
                problems.append("edge %s-%s (%s): drops %.1f m at %.1f,%.1f" % (a, b, tag, y - g, x, z))
                break
            hit = world.blocked(x, g, z)
            if hit:
                problems.append("edge %s-%s (%s): %s in the way at %.1f,%.1f" % (a, b, tag, hit, x, z))
                break
            y = g
        else:
            if abs(y - pb[1]) > 0.35:
                problems.append("edge %s-%s (%s): ends %.1f m off the node height" % (a, b, tag, abs(y - pb[1])))
    # Connectivity from the depots.
    adj = {}
    for a, b, _ in links:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    spawns = [n for n in nodes if any(w["name"] == n.replace("e_", "", 1) and w.get("spawn") for w in doc["waypoints"])]
    for s in spawns:
        seen, queue = {s}, [s]
        while queue:
            cur = queue.pop()
            for m in adj.get(cur, ()):
                if m not in seen:
                    seen.add(m)
                    queue.append(m)
        if len(seen) != len(nodes):
            problems.append("%s cannot reach: %s" % (s, ", ".join(sorted(set(nodes) - seen))))
    # Spawns and capture discs.
    s = doc.get("settings", {})
    teams = s.get("team_spawns", [[[side * s.get("spawn_x", 0), 0.2,
                                   s.get("spawn_z", -7) + s.get("spawn_step", 2.8) * (i + 0.5)]
                                  for i in range(5)] for side in (-1, 1)])
    for side, slots in enumerate(teams):
        for i, (x, y, z) in enumerate(slots):
            g = world.ground(x, z, y)
            if g is None or abs(g - (y - 0.2)) > 0.3 or world.blocked(x, g, z):
                problems.append("spawn %d,%d blocked at %.1f,%.1f" % (side, i, x, z))
    points = [p for n, p in nodes.items() if any(w["name"] == n.replace("e_", "", 1) and w.get("point") for w in doc["waypoints"])]
    for p in points:
        for k in range(12):
            a = math.tau * k / 12
            x, z = p[0] + 4.4 * math.cos(a), p[2] + 4.4 * math.sin(a)
            g = world.ground(x, z, 0.5)
            if g is None or abs(g) > 0.05:
                problems.append("capture disc at %s not flat near %.1f,%.1f (ground %s)" % (p, x, z, g))
                break
        for r in world.solids:
            lo, hi = r["min"], r["max"]
            if r.get("role") == "walk" or lo[1] < -0.01 or lo[1] >= HEIGHT + 0.12 or hi[1] - lo[1] < 0.5:
                continue      # same rule as tests/map_audit.gd: overhead walkways may cross a disc
            nx, nz = min(max(p[0], lo[0]), hi[0]), min(max(p[2], lo[2]), hi[2])
            if math.hypot(p[0] - nx, p[2] - nz) < 4.5:
                problems.append("solid %s inside the capture radius of %s" % (r["tag"], p))
    return problems


if __name__ == "__main__":
    doc = json.load(open(sys.argv[1]))
    found = check(doc)
    for p in found:
        print("PROBLEM:", p)
    print("%d problems" % len(found))
    sys.exit(1 if found else 0)
