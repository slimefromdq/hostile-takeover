"""Yacht Club: rotationally symmetric Z-shaped Acquisition marina.

Generate with tools/blender/generate.py; all collision stays in MapBuilder.
The ground deck is a union on the 0.25 m grid, partitioned without overlapping slabs.
"""
import copy
import math

MODE = "replace"
TITLE = "Yacht Club"
WOOD = "#987452"
WHITE = "#edf1ef"
RED = "#dd553d"
BLUE = "#388cc6"
DARK = "#31495b"
STEP = 0.25


class Deck:
    def __init__(self):
        self.cells = set()

    def rectangle(self, x0, z0, x1, z1):
        for z in range(round(z0 / STEP), round(z1 / STEP)):
            for x in range(round(x0 / STEP), round(x1 / STEP)):
                self.cells.add((x, z))

    def circle(self, x, z, radius):
        for iz in range(round((z - radius) / STEP), round((z + radius) / STEP)):
            for ix in range(round((x - radius) / STEP), round((x + radius) / STEP)):
                if math.hypot((ix + 0.5) * STEP - x, (iz + 0.5) * STEP - z) <= radius:
                    self.cells.add((ix, iz))

    def bridge(self, a, c, width=6):
        dx, dz = c[0] - a[0], c[1] - a[1]
        length2 = dx * dx + dz * dz
        for iz in range(math.floor((min(a[1], c[1]) - width / 2) / STEP), math.ceil((max(a[1], c[1]) + width / 2) / STEP)):
            for ix in range(math.floor((min(a[0], c[0]) - width / 2) / STEP), math.ceil((max(a[0], c[0]) + width / 2) / STEP)):
                px, pz = (ix + 0.5) * STEP, (iz + 0.5) * STEP
                t = max(0, min(1, ((px - a[0]) * dx + (pz - a[1]) * dz) / length2))
                if math.hypot(px - a[0] - t * dx, pz - a[1] - t * dz) <= width / 2:
                    self.cells.add((ix, iz))

    def emit(self, b, y=-0.5, top=0, tag="deck"):
        # Equal spans on consecutive rows merge into one slab; no internal overlap faces.
        spans = {}
        for x, z in self.cells:
            spans.setdefault(z, []).append(x)
        active = {}
        count = 0
        for z in range(min(spans), max(spans) + 2):
            xs = sorted(spans.get(z, []))
            runs = []
            for x in xs:
                if runs and runs[-1][1] == x:
                    runs[-1] = (runs[-1][0], x + 1)
                else:
                    runs.append((x, x + 1))
            for run in list(active):
                if run not in runs:
                    b.block(run[0] * STEP, active.pop(run) * STEP, run[1] * STEP, z * STEP,
                            y, top, "walk", "%s_%d" % (tag, count), color=WOOD)
                    count += 1
            for run in runs:
                active.setdefault(run, z)


def rotate_objects(b, start):
    for rec in b.objects[start:].copy():
        r = copy.deepcopy(rec)
        lo, hi = r["min"], r["max"]
        r["min"], r["max"] = [-hi[0], lo[1], -hi[2]], [-lo[0], hi[1], -lo[2]]
        r["tag"] += "_r"
        if r["kind"] == "ramp":
            r["dir"] = {"+x": "-x", "-x": "+x", "+z": "-z", "-z": "+z"}[r["dir"]]
        b.objects.append(r)


def lighthouse(b):
    b.room(49, -38, 61, -26, 0, 5.5, 0.5, "wall", "lighthouse_room",
           openings=[("w", -32, 3, 3.5), ("n", 55, 3, 3.5), ("s", 55, 3, 3.5)], color=WHITE)
    b.block(49, -38, 61, -26, 5.5, 6, "walk", "lighthouse_balcony", color=WHITE)
    for i in range(5):
        b.cylinder(55, -32, 3, 6 + i * 2, 8 + i * 2, "tower", "tower_band_%d" % i, color=WHITE if i % 2 == 0 else RED)
    # Two right-angle flights give a continuous walk to the balcony, outside its capture room.
    b.ramp(47, -42, 55, -39, 0, 0, 3, "+x", "walk", "lighthouse_stairs_1", color=WHITE)
    b.block(55, -42, 61, -38, 0, 3, "walk", "lighthouse_landing", color=WHITE)
    b.block(61, -42, 64, -39, 0, 3, "walk", "lighthouse_landing_elbow", color=WHITE)
    b.ramp(61, -39, 64, -31, 0, 3, 6, "+z", "walk", "lighthouse_stairs_2", color=WHITE)
    b.block(61, -31, 64, -26, 5.5, 6, "walk", "lighthouse_landing_top", color=WHITE)
    # Open south/west arcs; opposite low rails identify the ring without enclosing it.
    b.block(48, -42.5, 62, -42, 0, 1, "wall", "ring_rail_n", color=WHITE)
    b.block(65.5, -36, 66, -28, 0, 1, "wall", "ring_rail_e", color=WHITE)


def yacht(b):
    b.block(-78, -42, -54, -22, -2, -0.5, "wall", "yacht_hull", color=WHITE)
    b.room(-76, -40, -62, -24, 0, 4, 0.5, "wall", "yacht_cabin",
           openings=[("e", -37, 3, 3.5), ("e", -27, 3, 3.5)], color=WHITE)
    b.block(-76, -40, -62, -24, 4, 4.5, "walk", "yacht_roof", color=WHITE)
    b.block(-78, -42, -54, -41.5, 0, 1, "wall", "yacht_rail_n", color=WHITE)
    b.block(-78, -22.5, -54, -22, 0, 1, "wall", "yacht_rail_s", color=WHITE)
    b.block(-78, -41.5, -77.5, -22.5, 0, 1, "wall", "yacht_stern", color=WHITE)
    # Front wall hides both protected doorways; exit around its ends.
    b.block(-59, -40, -58.5, -24, 0, 3, "wall", "yacht_baffle", color=BLUE)
    b.block(-76, -40, -62, -24, 4.5, 4.75, "wall", "yacht_trim", color=BLUE)


def shed(b, x, z, tag):
    b.room(x - 4, z - 3, x + 4, z + 3, 0, 3, 0.5, "wall", tag,
           openings=[("w", z, 3, 3), ("e", z, 3, 3)], color=WHITE)
    b.block(x - 4, z - 3, x + 4, z + 3, 3, 3.5, "walk", tag + "_roof", color=RED)


def build(b):
    slots = [[-68, 0.2, -37 + i * 2.5] for i in range(5)]
    b.configure(bounds=(-80, -55, 160, 110), goal_order=["A", "B", "C", "D", "E"],
                team_spawns=[slots, [[-x, y, -z] for x, y, z in slots]],
                spawn_zones=[{"min": [-76, -1, -40], "max": [-62, 4, -24]},
                             {"min": [62, -1, 24], "max": [76, 4, 40]}],
                kill_floor=-8, test_lane=(-18, 0.05, -32))
    b.audit(symmetry="rotate180", route_families=["blv", "aln", "trn"], min_families=3,
            spawn_sight={"targets": [[-46, 0, -32], [-50, 0, -37], [-50, 0, -27], [0, 0, 0], [55, 0, -32]]},
            lanes=[{"label": "north boardwalk", "xs": [-45, 43, 4], "zs": [-33, -31], "y": 0,
                    "rect": [-53, -35, 99, 6], "p50": 30, "p90": 60, "max": 100},
                   {"label": "shack approaches", "xs": [-35, 35, 5], "zs": [-16, -8, 0, 8, 16], "y": 0,
                    "rect": [-38, -24, 76, 48], "p90": 60, "max": 100}])
    deck = Deck()
    deck.rectangle(-15, -15, 15, 15)
    # Build one half's decks and then rotate the cells before emitting the shared union.
    half = Deck()
    half.rectangle(-78, -42, -54, -22)
    half.rectangle(-53, -39, -39, -25)
    half.rectangle(-54, -39, -53, -25)
    half.bridge((-39, -32), (44, -32))
    half.circle(55, -32, 12)
    half.rectangle(46, -42, 64, -26)
    half.bridge((48, -32), (12, -8))
    half.rectangle(24, -16, 28, -3)
    half.bridge((24, -16), (32, -13))
    half.rectangle(30, -13, 34, -10)
    half.rectangle(38, -21, 44, -15)
    half.bridge((36, -24), (41, -21))
    # Parallel shed loop on the ocean-facing side of the northern boardwalk.
    half.bridge((-35, -32), (-35, -46))
    half.bridge((-35, -46), (35, -46))
    half.bridge((35, -46), (43, -32))
    half.rectangle(-27, -49, -19, -43)
    half.rectangle(19, -49, 27, -43)
    deck.cells.update(half.cells)
    deck.cells.update((-x - 1, -z - 1) for x, z in half.cells)
    deck.emit(b)
    start = len(b.objects)
    yacht(b)
    lighthouse(b)
    shed(b, -23, -46, "shed_w")
    shed(b, 23, -46, "shed_e")
    b.room(38, -21, 44, -15, 0, 3, 0.5, "wall", "boathouse",
           openings=[("w", -18, 3, 3), ("e", -18, 3, 3)], color=WHITE)
    b.ramp(38, -21, 44, -15, 3, 3, 4, "+x", "walk", "boathouse_launch", color=RED)
    for x, z, tag in [(44, -26, "lighthouse_transfer"), (24, -16, "shack_transfer")]:
        b.block(x - 1.5, z - 1.5, x + 1.5, z + 1.5, 5, 5.5, "walk", tag, color=WOOD)
        b.block(x - 1.5, z - 1.5, x - 1, z - 1, -7, -0.5, "wall", tag + "_pile", color=DARK)
        b.block(x - 1.5, z - 1.5, x - 1, z - 1, 0, 5, "wall", tag + "_support", color=DARK)
    for i, (x, z) in enumerate([(-32, -32), (-16, -32), (0, -32), (16, -32), (32, -32), (63, -24), (47, -24)]):
        b.cylinder(x, z, 0.5, -7, -0.5, "wall", "pier_pile_%d" % i, color=DARK)
    for i, x in enumerate((-30, -6, 18, 38)):
        z0, z1 = (-35, -32) if i % 2 == 0 else (-32, -29)
        b.block(x, z0, x + 1, z1, 0, 2.5, "cover", "pier_cover_%d" % i, color=DARK)
    rotate_objects(b, start)
    # Four doors and raised windows preserve a clear disc and a symmetrical interior fight.
    b.room(-7, -6, 7, 6, 0, 6.5, 0.5, "wall", "shack",
           openings=[("w", 0, 4, 3.5), ("e", 0, 4, 3.5), ("n", 0, 4, 3.5), ("s", 0, 4, 3.5)], color=WOOD)
    b.block(-7, -6, 7, 6, 6.5, 7, "walk", "shack_roof", color=RED)
    for x in (-12, 12):
        for z in (-12, 12):
            b.cylinder(x, z, 0.5, -7, -0.5, "wall", "shack_pile_%d_%d" % (x, z), color=DARK)
    start = len(b.objects)
    # Walkable roof access doubles as a boathouse launch surface; no movement tuning changes.
    b.ramp(30, -10, 34, 11, 0, 0, 7, "+z", "walk", "shack_roof_ramp", color=WOOD)
    b.block(7, 11, 34, 14, 6.5, 7, "walk", "shack_roof_landing", color=WOOD)
    b.block(7, 6, 10, 11, 6.5, 7, "walk", "shack_roof_bridge", color=WOOD)
    b.block(7, 3, 10, 6, 6.5, 7, "walk", "shack_roof_join", color=WOOD)
    rotate_objects(b, start)
    # Underdock ramps are beside the central slab rather than buried in it.
    start = len(b.objects)
    b.ramp(15, -6, 24, -3, -3.5, -3, 0, "+x", "walk", "underdock_ramp", color=WOOD)
    b.block(12, -6, 15, -3, -3.5, -3, "walk", "underdock_entry", color=WOOD)
    b.block(12, -3, 15, 3, -3.5, -3, "walk", "underdock_turn", color=WOOD)
    rotate_objects(b, start)
    b.block(-12, -1.5, 12, 1.5, -3.5, -3, "walk", "underdock_span", color=WOOD)
    # Optional beam-hop/Death Dive lanes: seven and ten metre ocean gaps, rotational pairs.
    start = len(b.objects)
    b.ramp(15, 10, 24, 13, -3.5, -3, 0, "-x", "walk", "death_dive", color=RED)
    b.block(24, 10, 28, 13, -3.5, -3, "walk", "dive_takeoff", color=WOOD)
    b.block(35, 10, 39, 13, -3.5, -3, "walk", "beam_landing", color=WOOD)
    b.block(49, 10, 55, 16, -3.5, -3, "walk", "grapple_landing", color=WOOD)
    b.block(52, 14, 52.5, 14.5, -3, 2, "wall", "grapple_anchor", color=WHITE)
    b.ramp(49, 16, 52, 25, -3.5, -3, 0, "+z", "walk", "shortcut_return", color=WOOD)
    rotate_objects(b, start)
    b.pickup(0, -3, 0, kind="power", tag="underdock_power")
    for x in (-23, 23):
        b.pickup(x, 0, -46, tag="shed_health_%d" % x)
        b.pickup(-x, 0, 46, tag="shed_health_%d_r" % x)
    graph(b)


def graph(b):
    # Explicit copies make the route order independent of x and preserve rotational team identity.
    nodes = {
        "S": (-68, 0, -32, "cabin_n:blv,cabin_s:blv"),
        "cabin_n": (-65, 0, -37, "door_n:blv"), "cabin_s": (-65, 0, -27, "door_s:blv"),
        "door_n": (-61, 0, -37, "turn_n:blv"),
        "door_s": (-61, 0, -27, "turn_s:blv"),
        "turn_n": (-61, 0, -40.75, "exit_n:blv"), "turn_s": (-61, 0, -23.25, "exit_s:blv"),
        "exit_n": (-56, 0, -40.75, "A:blv"), "exit_s": (-56, 0, -23.25, "A:blv"),
        "A": (-46, 0, -32, "p0:blv"),
        "p0": (-35, 0, -32, "p1:blv,f0:aln"),
        "p1": (-28, 0, -30, "p2:blv"),
        "p2": (-10, 0, -30, "p3:blv"),
        "p3": (-4, 0, -34, "p4:blv"),
        "p4": (16, 0, -30, "p5:blv"),
        "p5": (21, 0, -30, "p6:blv"),
        "p6": (36, 0, -34, "p7:blv"),
        "p7": (41, 0, -34, "B:blv"),
        "B": (55, 0, -32, "diag0:blv"),
        "diag0": (47, 0, -32, "diag1:blv,ln:roof"),
        "diag1": (36, 0, -24, "diag2:blv"),
        "diag2": (24, 0, -16, "diag3:blv,ut:trn"),
        "diag3": (12, 0, -8, "ce:blv"),
        "ce": (12, 0, -1, "C:blv"),
        "f0": (-35, 0, -46, "f1:aln"), "f1": (-23, 0, -46, "f2:aln"),
        "f2": (0, 0, -46, "f3:aln"), "f3": (23, 0, -46, "f4:aln"),
        "f4": (35, 0, -46, "p7:aln"),
        "ln": (46, 0, -40.5, "l0:roof"), "l0": (47, 0, -40.5, "l1:roof"),
        "l1": (55, 3, -40.5, "l2:roof"), "l2": (62.5, 3, -39, "l3:roof"),
        "l3": (62.5, 6, -31, "l4:roof"), "l4": (60, 6, -28, "l5:roof"),
        "l5": (55, 6, -28, ""),
        "ut": (25, 0, -4.5, "u0:trn"), "u0": (24, 0, -4.5, "u1:trn"),
        "u1": (15, -3, -4.5, "u2:trn"), "u2": (13.5, -3, -4.5, "u3:trn"),
        "u3": (13.5, -3, 0, "U:trn"),
        "r_entry": (32, 0, -13, "diag2:roof,r0:roof"),
        "r0": (32, 0, -10, "r1:roof"), "r1": (32, 7, 11, "r_turn:roof"),
        "r_turn": (8.5, 7, 12.5, "r2:roof"),
        "r2": (8.5, 7, 7.5, "r3:roof"), "r3": (8.5, 7, 4.5, "r4:roof"),
        "r4": (5, 7, 4.5, ""),
    }
    names = {"A": "E", "B": "D", "S": "e_S"}
    for name in nodes:
        names.setdefault(name, "e_" + name)
    for name, (x, y, z, links) in nodes.items():
        b.waypoint(name, x, y, z, links, point=name in ("A", "B"), spawn=name == "S")
        rotated_links = ",".join(names.get(target, target) + ":" + tag for target, tag in
                                 (part.split(":") for part in links.split(",") if part))
        b.waypoint(names[name], -x, y, -z, rotated_links, point=name in ("A", "B"), spawn=name == "S")
    b.waypoint("C", 0, 0, 0, "e_ce:blv", point=True)
    b.waypoint("U", 0, -3, 0, "e_u3:trn")
