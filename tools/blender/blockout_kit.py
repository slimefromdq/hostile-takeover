"""Generate a Hostile Takeover blockout from Python. No Blender needed.

    from blockout_kit import Blockout
    b = Blockout(mode="replace")
    b.block(-60, -30, 60, 30, -1, 0, "walk", tag="floor")
    b.save("maps/blockout.json")

Coordinates are Godot's: x west to east, z north (-) to south (+), y up, metres. Argument order matches
MapBuilder (x0, z0, x1, z1, y0, y1, role, ...), so layout code ports line by line. Everything snaps to 0.25 m.
`mirror=True` also builds the copy mirrored across x = 0 in the game (author the west half only).
Run `python3 tools/blender/generate.py <script>` to execute a generator script and write the JSON.
"""
import json
import math

FORMAT = 1
SNAP = 0.25
ROLES = ("walk", "wall", "tower", "cover", "accent", "hazard", "glass")
RAMP_DIRS = ("+x", "-x", "+z", "-z")
MAX_RAMP_DEGREES = 22.0


def snap(v):
    return round(v / SNAP) * SNAP


class Blockout:
    def __init__(self, mode="add"):
        self.mode = mode
        self.objects = []
        self.waypoints = []
        self.links = []
        self.settings = {}
        self.features = []
        self.warnings = []

    # ---- solids -------------------------------------------------------------

    def _add(self, kind, role, tag, lo, hi, mirror, color, **extra):
        if role not in ROLES:
            raise ValueError("%s: unknown role %r (expected one of %s)" % (tag, role, ", ".join(ROLES)))
        rec = {"kind": kind, "tag": tag, "role": role, "min": lo, "max": hi}
        if mirror:
            rec["mirror"] = True
        if color:
            rec["color"] = color
        rec.update(extra)
        self.objects.append(rec)
        return rec

    def block(self, x0, z0, x1, z1, y0, y1, role, tag="block", mirror=False, color=None):
        lo = [snap(min(x0, x1)), snap(min(y0, y1)), snap(min(z0, z1))]
        hi = [snap(max(x0, x1)), snap(max(y0, y1)), snap(max(z0, z1))]
        if any(hi[i] - lo[i] < SNAP for i in range(3)):
            raise ValueError("%s: block thinner than %.2f m" % (tag, SNAP))
        return self._add("block", role, tag, lo, hi, mirror, color)

    def ramp(self, x0, z0, x1, z1, y_floor, y_start, y_end, direction, role, tag="ramp", mirror=False, color=None):
        """Wedge. `direction` is the way it ascends; top runs from y_start (low end) to y_end (high end)."""
        if direction not in RAMP_DIRS:
            raise ValueError("%s: ramp direction must be one of %s" % (tag, ", ".join(RAMP_DIRS)))
        lo = [snap(min(x0, x1)), snap(y_floor), snap(min(z0, z1))]
        hi = [snap(max(x0, x1)), snap(max(y_start, y_end)), snap(max(z0, z1))]
        run = (hi[0] - lo[0]) if direction in ("+x", "-x") else (hi[2] - lo[2])
        degrees = math.degrees(math.atan2(abs(y_end - y_start), run))
        if degrees > MAX_RAMP_DEGREES + 1e-6:
            self.warnings.append("%s: ramp is %.1f degrees (limit %d)" % (tag, degrees, MAX_RAMP_DEGREES))
        return self._add("ramp", role, tag, lo, hi, mirror, color, dir=direction,
                         y_floor=snap(y_floor), y_start=snap(y_start), y_end=snap(y_end))

    def stairs(self, x0, z0, x1, z1, y_from, y_to, direction, role, tag="stairs", mirror=False, color=None):
        """Stairs are collision ramps in this game (the steps are visual-only art). `direction` is the way
        you walk from y_from to y_to; going down just flips the wedge."""
        if y_to < y_from:
            direction = {"+x": "-x", "-x": "+x", "+z": "-z", "-z": "+z"}[direction]
            y_from, y_to = y_to, y_from
        return self.ramp(x0, z0, x1, z1, y_from, y_from, y_to, direction, role, tag, mirror, color)

    def cylinder(self, cx, cz, radius, y0, y1, role, tag="cylinder", mirror=False, color=None):
        lo = [snap(cx - radius), snap(min(y0, y1)), snap(cz - radius)]
        hi = [snap(cx + radius), snap(max(y0, y1)), snap(cz + radius)]
        return self._add("cylinder", role, tag, lo, hi, mirror, color)

    def decor(self, x0, z0, x1, z1, y0, y1, role, mode="flush", tag="decor", mirror=False, color=None):
        lo = [min(x0, x1), min(y0, y1), min(z0, z1)]
        hi = [max(x0, x1), max(y0, y1), max(z0, z1)]
        return self._add("decor", role, tag, lo, hi, mirror, color, mode=mode)

    # ---- helpers that expand to several solids -------------------------------

    def room(self, x0, z0, x1, z1, y0, y1, thickness, role, tag="room", openings=(), mirror=False, color=None):
        """Four walls around a rectangle. `openings` is a list of (side, centre, width, height) with side in
        n/s/e/w (north is -z); each opening is a doorway cut from y0 up to y0 + height, with a lintel above."""
        x0, x1 = min(x0, x1), max(x0, x1)
        z0, z1 = min(z0, z1), max(z0, z1)
        t = thickness
        sides = {
            "n": (x0, z0, x1, z0 + t, "x"), "s": (x0, z1 - t, x1, z1, "x"),
            "w": (x0, z0 + t, x0 + t, z1 - t, "z"), "e": (x1 - t, z0 + t, x1, z1 - t, "z"),
        }
        for side, (ax0, az0, ax1, az1, along) in sides.items():
            cuts = sorted((c - w / 2.0, c + w / 2.0, h) for s, c, w, h in openings if s == side)
            start = ax0 if along == "x" else az0
            end = ax1 if along == "x" else az1
            cursor = start
            parts = []
            for lo_c, hi_c, h in cuts:
                if lo_c > cursor:
                    parts.append((cursor, lo_c, y0, y1))
                if y0 + h < y1:
                    parts.append((lo_c, hi_c, y0 + h, y1))
                cursor = hi_c
            if cursor < end:
                parts.append((cursor, end, y0, y1))
            for i, (p0, p1, py0, py1) in enumerate(parts):
                name = "%s_%s%d" % (tag, side, i)
                if along == "x":
                    self.block(p0, az0, p1, az1, py0, py1, role, name, mirror, color)
                else:
                    self.block(ax0, p0, ax1, p1, py0, py1, role, name, mirror, color)

    # ---- bot graph and settings ----------------------------------------------

    def waypoint(self, name, x, y, z, links="", mirror=False, point=False, spawn=False):
        """`links` is "B:blv,C:roof" (tags: blv, roof, trn, aln). `point` marks a capture point, `spawn` the depot node."""
        rec = {"name": name, "pos": [x, y, z]}
        if mirror:
            rec["mirror"] = True
        if point:
            rec["point"] = True
        if spawn:
            rec["spawn"] = True
        self.waypoints.append(rec)
        for part in [p.strip() for p in links.split(",") if p.strip()]:
            target, _, tag = part.partition(":")
            self.links.append([name, target.strip(), (tag or "blv").strip()])

    def configure(self, **settings):
        """bounds=(x, z, width, height), spawn_x, spawn_z, spawn_step, depot_limit, test_lane=(x, y, z)."""
        for key, value in settings.items():
            if key not in ("bounds", "spawn_x", "spawn_z", "spawn_step", "depot_limit", "test_lane"):
                raise ValueError("unknown setting %r" % key)
            self.settings[key] = list(value) if isinstance(value, (tuple, list)) else value

    # ---- output ----------------------------------------------------------------

    def to_document(self, source=""):
        return {
            "format": FORMAT,
            "units": "m",
            "mode": self.mode,
            "source": source,
            "settings": self.settings,
            "features": self.features,
            "objects": self.objects,
            "waypoints": self.waypoints,
            "links": self.links,
        }

    def save(self, path, source=""):
        with open(path, "w") as f:
            json.dump(self.to_document(source), f, indent=1)
            f.write("\n")

    def validate(self):
        """Quick checks without Godot: slopes, unknown link targets, replace-mode requirements, solids that
        interpenetrate (bounding boxes, so a ramp beside a block it only touches is fine). Returns warnings."""
        out = list(self.warnings)
        names = {w["name"] for w in self.waypoints}
        for a, c, _ in self.links:
            if a not in names or c not in names:
                out.append("link %s-%s names a missing waypoint" % (a, c))
        if self.mode == "replace":
            points = sum((2 if w.get("mirror") and abs(w["pos"][0]) > 1e-6 else 1) for w in self.waypoints if w.get("point"))
            spawns = sum((2 if w.get("mirror") and abs(w["pos"][0]) > 1e-6 else 1) for w in self.waypoints if w.get("spawn"))
            if points != 5:
                out.append("replace mode needs 5 capture points, found %d" % points)
            if spawns != 2:
                out.append("replace mode needs 2 spawn nodes, found %d" % spawns)
        solids = []
        for o in self.objects:
            if o["kind"] == "decor":
                continue
            solids.append((o["tag"], o["min"], o["max"]))
            if o.get("mirror"):
                solids.append((o["tag"] + "_e", [-o["max"][0], o["min"][1], o["min"][2]], [-o["min"][0], o["max"][1], o["max"][2]]))
        for i in range(len(solids)):
            for j in range(i + 1, len(solids)):
                (ta, la, ha), (tb, lb, hb) = solids[i], solids[j]
                if all(min(ha[k], hb[k]) - max(la[k], lb[k]) > 1e-6 for k in range(3)):
                    out.append("%s overlaps %s" % (ta, tb))
        return out
