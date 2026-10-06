"""Concrete Canopy: a hero-shooter jungle gym with a city skin (docs/JUNGLE_GYM.md).

Every piece of urban furniture is a traversal tool first and set dressing second:
  cables = ziplines / grind rails      awnings, shelters = bounce pads     fire escapes, scaffolds = climb lanes
  billboards, signs = perches          tunnels = fast flanks               cranes, hoists, trams, the blimp = movers
Four tiers: underground (y -6), street (0), mid-level (6), rooftops (12) and sky (18+, blimp ~34).
Districts: Rail Yard (centre), Construction Site (north), Market + Rooftop Garden (south outer),
Flooded Industrial (south inner). Authored for the west half and mirrored across x = 0.

    python3 tools/blender/generate.py tools/blender/maps/canopy.py maps/canopy.blockout.json
"""
MODE = "replace"

TUNNEL_Y = -6.0          # top of the tunnel floor
MID = 6.0
ROOF = 12.0

# Verb colours (greybox readability: one colour per verb, everywhere on the map).
BOUNCE = "#ff3fa4"       # magenta  awnings and shelters
CLIMB = "#3fd96b"        # green    fire escapes and scaffolding
CABLE = "#38d6ff"        # cyan     power lines
PERCH = "#ffc928"        # yellow   billboards and signs
MOVER = "#a38bff"        # violet   elevators, trams, cranes, the blimp
ORANGE = "#ff6a2b"


def slab_with_holes(b, x0, z0, x1, z1, y0, y1, holes, role, tag):
    """A mirrored slab with rectangular holes, tiled from blocks (holes are [x0, z0, x1, z1])."""
    xs = sorted({x0, x1} | {min(max(h[0], x0), x1) for h in holes} | {min(max(h[2], x0), x1) for h in holes})
    for xa, xb in zip(xs, xs[1:]):
        cuts = sorted((h[1], h[3]) for h in holes if h[0] < xb and h[2] > xa)
        cursor = z0
        for c0, c1 in cuts:
            if c0 > cursor:
                b.block(xa, cursor, xb, c0, y0, y1, role, tag, mirror=True)
            cursor = max(cursor, c1)
        if cursor < z1:
            b.block(xa, cursor, xb, z1, y0, y1, role, tag, mirror=True)


def build(b):
    b.configure(bounds=(-96, -64, 192, 128), spawn_x=90, spawn_z=-7, spawn_step=2.8, depot_limit=86)
    b.audit(route_families=["blv", "aln", "trn"], min_families=3,
            lanes=[
                {"label": "boulevard", "xs": [-88, 88, 4], "zs": [-10, -6, -2, 2, 6, 10], "y": 0, "rect": [-96, -12, 192, 24], "p50": 30, "p90": 60, "max": 100},
                {"label": "tunnel", "xs": [-88, 88, 4], "zs": [-3, 0, 3], "y": -6, "rect": [-96, -5, 192, 10], "p90": 60, "p99": 80},
            ])
    stage_shell(b)
    stage_underground(b)
    stage_graph(b)


# ---- shell: floor, perimeter, depot, boulevard --------------------------------------------------

STAIR_HOLES = [[-64, -23, -56, -7], [-36, 7, -28, 23], [-4, -23, 0, -7]]


def stage_shell(b):
    slab_with_holes(b, -96, -64, 0, 64, -1, 0, STAIR_HOLES, "walk", "floor")
    b.block(-96, -64, 96, -62, 0, 34, "tower", "wall_n")
    b.block(-96, 62, 96, 64, 0, 34, "tower", "wall_s")
    # Depot: a cavity (x -93..-87, z -8..8) carved from touching blocks: back wall, north/south masses, roof and a
    # gate wall with a 6 m opening. A baffle in front means the spawn never sees the boulevard.
    b.block(-96, -62, -93, 62, 0, 34, "tower", "depot_back", mirror=True)
    b.block(-93, -62, -86, -8, 0, 14, "tower", "end_mass_n", mirror=True)
    b.block(-93, 8, -86, 62, 0, 14, "tower", "end_mass_s", mirror=True)
    b.block(-93, -8, -86, 8, 6, 14, "tower", "depot_roof", mirror=True)
    b.block(-87, -8, -86, -3, 0, 6, "wall", "gate_n", mirror=True)
    b.block(-87, 3, -86, 8, 0, 6, "wall", "gate_s", mirror=True)
    b.block(-87, -3, -86, 3, 4, 6, "wall", "gate_lintel", mirror=True)
    b.block(-84, -2.5, -82, 2.5, 0, 3.5, "wall", "baffle", mirror=True)
    # Offset barrier pairs break the long boulevard sightline (24 m wide street).
    for x0 in (-76, -48, -20):
        b.block(x0, -12, x0 + 1, 1, 0, 3, "wall", "chicane_n", mirror=True)
        b.block(x0 + 4, -1, x0 + 5, 12, 0, 3, "wall", "chicane_s", mirror=True)
        b.decor(x0, -12, x0 + 1, 1, 3.0, 3.1, "accent", "flush", "chicane_cap", mirror=True, color=ORANGE)


# ---- underground: subway tunnel and stairwells ------------------------------------------------------

def stage_underground(b):
    b.block(-90, -7, 0, 7, TUNNEL_Y - 1, TUNNEL_Y, "walk", "tunnel_floor", mirror=True)
    b.block(-92, -7, -90, 7, TUNNEL_Y - 1, -1, "wall", "tunnel_end", mirror=True)
    # North wall: openings for stairwells S1 (x -64..-56) and S3 (centre). South wall: opening for S2 (x -36..-28).
    for x0, x1 in ((-90, -64), (-56, -4)):
        b.block(x0, -7, x1, -5, TUNNEL_Y, -1, "wall", "tunnel_wall_n", mirror=True)
    for x0, x1 in ((-90, -36), (-28, 0)):
        b.block(x0, 5, x1, 7, TUNNEL_Y, -1, "wall", "tunnel_wall_s", mirror=True)
    # Stairwells: long gentle ramps (20 degrees) up to street level, enclosed so no void is exposed.
    b.ramp(-64, -23, -56, -7, TUNNEL_Y - 1, TUNNEL_Y, 0, "-z", "walk", "stair_s1", mirror=True)
    b.block(-66, -23, -64, -7, TUNNEL_Y, -1, "wall", "stair_s1_wall_w", mirror=True)
    b.block(-56, -23, -54, -7, TUNNEL_Y, -1, "wall", "stair_s1_wall_e", mirror=True)
    b.ramp(-36, 7, -28, 23, TUNNEL_Y - 1, TUNNEL_Y, 0, "+z", "walk", "stair_s2", mirror=True)
    b.block(-38, 7, -36, 23, TUNNEL_Y, -1, "wall", "stair_s2_wall_w", mirror=True)
    b.block(-28, 7, -26, 23, TUNNEL_Y, -1, "wall", "stair_s2_wall_e", mirror=True)
    b.ramp(-4, -23, 4, -7, TUNNEL_Y - 1, TUNNEL_Y, 0, "-z", "walk", "stair_s3")
    b.block(-6, -23, -4, -7, TUNNEL_Y, -1, "wall", "stair_s3_wall", mirror=True)
    # Staggered pillar pairs (A covers z -5..1, B covers z -1..5) break the 180 m tunnel into short runs.
    for x0 in (-80, -50, -22):
        b.block(x0, -5, x0 + 2, 1, TUNNEL_Y, -1, "wall", "tunnel_pillar_a", mirror=True)
        b.block(x0 + 6, -1, x0 + 8, 5, TUNNEL_Y, -1, "wall", "tunnel_pillar_b", mirror=True)
    # Stairs are marked in green-white; tunnels read as fast lanes with orange strips.
    b.decor(-90, -5.04, 0, -5, -5.0, -4.75, "accent", "flush", "tunnel_strip_n", mirror=True, color=ORANGE)


# ---- bot graph (walk and ramp edges only; verbs are for players) ------------------------------------

def chicane_nodes(b, name, x0, before, after):
    """Waypoints that thread an offset barrier pair at x0 (north wall x0..x0+1, south wall x0+4..x0+5)."""
    b.waypoint(name + "a", x0 - 1, 0, 3.5, name + "p:blv", mirror=True)
    b.waypoint(name + "p", x0 + 2.5, 0, 3.5, name + "m:blv", mirror=True)
    b.waypoint(name + "m", x0 + 2.5, 0, -2.5, name + "b:blv", mirror=True)
    b.waypoint(name + "b", x0 + 6.5, 0, -4, after + ":blv", mirror=True)


def stage_graph(b):
    b.waypoint("S", -90, 0, 0, "gt:blv", mirror=True, spawn=True)
    b.waypoint("gt", -85.5, 0, 0, "q1:blv", mirror=True)
    b.waypoint("q1", -85, 0, -4.5, "q2:blv", mirror=True)
    b.waypoint("q2", -80, 0, -4.5, "c1a:blv", mirror=True)
    chicane_nodes(b, "c1", -76, "q2", "A")
    b.waypoint("A", -64, 0, 0, "c2a:blv", mirror=True, point=True)
    chicane_nodes(b, "c2", -48, "A", "B")
    b.waypoint("B", -32, 0, 0, "c3a:blv", mirror=True, point=True)
    chicane_nodes(b, "c3", -20, "B", "C")
    b.waypoint("C", 0, 0, 0, point=True)
    # underground: tunnel line and the three stairwells (tag trn)
    b.waypoint("tW", -86, -6, 0, "p1a:trn", mirror=True)
    for name, x0, nxt in (("p1", -80, "tA"), ("p2", -50, "tB"), ("p3", -22, "tC")):
        b.waypoint(name + "a", x0 + 1, -6, 3.5, name + "b:trn", mirror=True)
        b.waypoint(name + "b", x0 + 4, -6, 0, name + "c:trn", mirror=True)
        b.waypoint(name + "c", x0 + 7, -6, -3.5, nxt + ":trn", mirror=True)
    b.waypoint("tA", -60, -6, 0, "p2a:trn,s1b:trn", mirror=True)
    b.waypoint("tB", -32, -6, 0, "p3a:trn,s2b:trn", mirror=True)
    b.waypoint("tC", 0, -6, 0, "s3b:trn")
    b.waypoint("s1b", -60, -6, -6, "s1m:trn", mirror=True)
    b.waypoint("s1m", -60, -3, -15, "s1t:trn", mirror=True)
    b.waypoint("s1t", -60, 0, -23, "n1a:aln", mirror=True)
    # Street-level exits are reached around the open stair well (its north end is the top).
    b.waypoint("n1a", -60, 0, -25, "n1b:aln", mirror=True)
    b.waypoint("n1b", -68, 0, -25, "n1c:aln", mirror=True)
    b.waypoint("n1c", -68, 0, -12, "A:aln", mirror=True)
    b.waypoint("s2b", -32, -6, 6, "s2m:trn", mirror=True)
    b.waypoint("s2m", -32, -3, 15, "s2t:trn", mirror=True)
    b.waypoint("s2t", -32, 0, 23, "", mirror=True)
    b.waypoint("s3b", 0, -6, -6, "s3m:trn")
    b.waypoint("s3m", 0, -3, -15, "s3t:trn")
    b.waypoint("s3t", 0, 0, -23, "n3a:aln")
    b.waypoint("n3a", 0, 0, -25, "n3b:aln")
    b.waypoint("n3b", -8, 0, -25, "n3c:aln", mirror=True)
    b.waypoint("n3c", -8, 0, -12, "C:aln", mirror=True)
