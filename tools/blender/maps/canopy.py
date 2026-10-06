"""Concrete Canopy: a hero-shooter jungle gym with a city skin (docs/JUNGLE_GYM.md).

Every piece of urban furniture is a traversal tool first and set dressing second:
  cables = ziplines / grind rails      awnings, shelters = bounce pads     fire escapes, scaffolds = climb lanes
  billboards, signs = perches          tunnels = fast flanks               cranes, hoists, trams, the blimp = movers
Four tiers: underground (y -6), street (0), mid-level (6), rooftops (12) and sky (18+, blimp ~34).
Districts: Rail Yard (centre), Construction Site (north), Market + Rooftop Garden (south outer),
Flooded Industrial (south inner). Authored for the west half and mirrored across x = 0.

    python3 tools/blender/generate.py tools/blender/maps/canopy.py maps/canopy.blockout.json
"""
import math

MODE = "replace"
TITLE = "Concrete Canopy"

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
    b.configure(bounds=(-96, -64, 192, 128), spawn_x=90, spawn_z=-7, spawn_step=2.8, depot_limit=86, ceiling=80)
    b.audit(route_families=["blv", "aln", "trn"], min_families=3,
            lanes=[
                {"label": "boulevard", "xs": [-88, 88, 4], "zs": [-10, -6, -2, 2, 6, 10], "y": 0, "rect": [-96, -12, 192, 24], "p50": 30, "p90": 60, "max": 100},
                {"label": "yard lane", "xs": [-22, 22, 4], "zs": [-58, -40, -22, 22, 40, 58], "y": 0, "azimuths": "ns", "rect": [-26, -62, 52, 124], "p50": 45, "p90": 90, "max": 125},
                {"label": "market alley", "xs": [-84, -52, 4], "zs": [30, 46], "y": 0, "rect": [-86, 28, 36, 20], "p90": 45, "p99": 60},
                {"label": "tunnel", "xs": [-88, 88, 4], "zs": [-3, 0, 3], "y": -6, "rect": [-96, -5, 192, 10], "p90": 60, "p99": 80},
            ])
    stage_shell(b)
    stage_underground(b)
    stage_yard(b)
    stage_construction(b)
    stage_market(b)
    stage_industrial(b)
    stage_verbs(b)
    stage_graph(b)


# ---- shell: floor, perimeter, depot, boulevard --------------------------------------------------

STAIR_HOLES = [[-64, -23, -56, -7], [-36, 7, -28, 23], [-4, -23, 0, -7]]
CANAL_HOLES = [[-42, 28, -34, 58]]
VENT_HOLES = [[-56, -2, -52, 2]]


def stage_shell(b):
    slab_with_holes(b, -96, -64, 0, 64, -1, 0, STAIR_HOLES + CANAL_HOLES + VENT_HOLES, "walk", "floor")
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


# ---- rail yard (centre): container lanes, tram viaducts, landmark spires, the blimp -------------------

def stage_yard(b):
    # Container columns (single stack 2.6 m is mantle height, double stack 5.2 m is a sniper perch).
    for z0, z1, h in ((-60, -48, 2.6), (-44, -32, 5.2), (-28, -16, 2.6)):
        b.block(-24, z0, -19, z1, 0, h, "cover", "container_a", mirror=True, color=ORANGE if h > 3 else None)
    for z0, z1, h in ((16, 28, 2.6), (32, 44, 5.2), (48, 60, 2.6)):
        b.block(-24, z0, -19, z1, 0, h, "cover", "container_a", mirror=True, color=ORANGE if h > 3 else None)
    for z0, z1 in ((-44, -32), (16, 28), (32, 44)):
        b.block(-8, z0, -4, z1, 0, 2.6, "cover", "container_b", mirror=True)
    # Cover islands in the centre lane so the long lane never runs end to end.
    for z in (-34, 34):
        b.block(-1.5, z - 1.5, 1.5, z + 1.5, 0, 2.6, "cover", "yard_island")
    # Tram stations: decks at mid-level on piers. The tram car stops just inside each station.
    for z0, z1, tag in ((-58, -50, "station_n"), (50, 58, "station_s")):
        b.block(-16, z0, -8, z1, 5, MID, "walk", tag, mirror=True, color=MOVER)
        for px in (-16, -10):
            for pz in (z0, z1 - 2):
                b.block(px, pz, px + 2, pz + 2, 0, 5, "wall", tag + "_pier", mirror=True)
    # Landmark spires at both ends of the centre lane. The lower body's roof (y 34) is the blimp dock.
    b.block(-6, -62, 6, -50, 0, 34, "tower", "spire_n_base")
    b.block(-3, -62, 3, -56, 34, 62, "tower", "spire_n_top")
    b.block(-6, 50, 6, 62, 0, 34, "tower", "spire_s_base")
    b.block(-3, 56, 3, 62, 34, 62, "tower", "spire_s_top")
    b.climb(-2, -50, 2, -48.8, 0, 34.6, tag="spire_n_ladder", face="-z")
    b.climb(-2, 48.8, 2, 50, 0, 34.6, tag="spire_s_ladder", face="+z")
    b.decor(-2, -50, 2, -49.96, 0, 34, "accent", "flush", "spire_n_ladder_strip", color=CLIMB)
    b.decor(-2, 49.96, 2, 50, 0, 34, "accent", "flush", "spire_s_ladder_strip", color=CLIMB)
    # Timed trams: one per side, out and back along the viaduct with a dwell at each station.
    b.mover("tram", (6, 0.5, 16), [(0, (-12, 5.75, -42)), (8, (-12, 5.75, -42)), (28, (-12, 5.75, 42)),
                                   (36, (-12, 5.75, 42)), (56, (-12, 5.75, -42))], color=MOVER, period=56, mirror=True)
    # The blimp shuttles between the two docks above the centre lane; ride its top.
    # Docks sit 2 m off the spire faces so the climb lanes stay clear of the hull.
    b.mover("blimp", (10, 3, 26), [(0, (0, 32.5, -35)), (12, (0, 32.5, -35)), (30, (0, 32.5, 35)),
                                   (42, (0, 32.5, 35)), (60, (0, 32.5, -35))], color=MOVER, period=60)


# ---- construction site (north): an exposed, vertical district --------------------------------------------

def stage_construction(b):
    # The tower frame: nine columns on a 12 m grid, floor plates at 6, 12, 18 and 24 m (cells between the columns).
    for x in (-56, -44, -32):
        for z in (-56, -44, -32):
            b.block(x, z, x + 2, z + 2, 0, 24, "wall", "frame_column", mirror=True)
    cells = {(0, 0): (-54, -54), (1, 0): (-42, -54), (0, 1): (-54, -42), (1, 1): (-42, -42)}
    levels = {6: [(0, 0), (1, 0), (0, 1), (1, 1)], 12: [(0, 0), (1, 0), (0, 1)], 18: [(0, 0), (1, 0)], 24: [(0, 0)]}
    for level, which in levels.items():
        for ij in which:
            x0, z0 = cells[ij]
            b.block(x0, z0, x0 + 10, z0 + 10, level - 0.5, level, "walk", "frame_plate_%d" % level, mirror=True)
    # Scaffold ladders: each climbs one level and tops out onto the next plate's edge (zig-zag, so every step is a choice).
    b.climb(-52, -31.8, -48, -30, 0, 6.6, mirror=True, tag="ladder_1", face="-z")
    b.climb(-44, -40, -42.8, -36, 6, 12.6, mirror=True, tag="ladder_2", face="-x")
    b.climb(-52, -43.8, -48, -42, 12, 18.6, mirror=True, tag="ladder_3", face="-z")
    b.climb(-43.8, -52, -42, -48, 18, 24.6, mirror=True, tag="ladder_4", face="-x")
    # Material hoist beside the tower: landings at 6, 12 and 18 m, a car that stops at ground and each landing.
    for level in (6, 12, 18):
        b.block(-32, -50, -29, -46, level - 0.5, level, "walk", "hoist_landing_%d" % level, mirror=True)
    keys = [(0, (-27, 0.0, -48)), (8, (-27, 0.0, -48)), (11, (-27, 5.75, -48)), (14, (-27, 5.75, -48)), (17, (-27, 11.75, -48)),
            (20, (-27, 11.75, -48)), (23, (-27, 17.75, -48)), (31, (-27, 17.75, -48)), (40, (-27, 0.0, -48))]
    b.mover("hoist", (4, 0.5, 4), keys, color=MOVER, period=40, mirror=True)
    # Site office: a flat-roofed block across a 16 m gap from the tower's top plate; the crane span closes the gap.
    b.block(-82, -52, -70, -40, 0, 24, "tower", "site_office", mirror=True)
    b.climb(-80, -40, -76, -38.2, 0, 24.6, mirror=True, tag="office_ladder", face="-z")
    b.decor(-80, -39.96, -76, -40, 0, 24, "accent", "flush", "office_ladder_strip", mirror=True, color=CLIMB)
    # Tower crane: mast and jib are landmarks visible from anywhere in the north half.
    b.block(-66, -36, -63, -33, 0, 40, "tower", "crane_mast", mirror=True)
    b.block(-76, -35.5, -56, -33.5, 40, 41.5, "accent", "crane_jib", mirror=True, color=ORANGE)
    # Event: the crane swings a span between the office roof and the tower's top plate (match time 210 s, then returns).
    stowed = ((-62, 32.0, -36), (0, 90, 0))
    placed = ((-62, 23.75, -47), (0, 0, 0))
    b.mover("crane_span", (16, 0.5, 3), [(0, *stowed), (210, *stowed), (216, *placed), (270, *placed), (276, *stowed), (300, *stowed)],
            color=MOVER, period=300, mirror=True)
    b.event(210, "CRANES SWINGING SPANS INTO PLACE")
    # Open yard cover: containers (mantle height), well clear of the stairwell and the stairs' routes.
    for x0, z0, x1, z1 in ((-84, -22, -76, -18), (-52, -22, -44, -18), (-40, -26, -34, -22)):
        b.block(x0, z0, x1, z1, 0, 2.6, "cover", "site_container", mirror=True)


# ---- market and rooftop garden (south outer): tight alleys below, an open roof plateau above -----------------

MARKET_X = [(-86, -77), (-73, -64), (-60, -51)]
MARKET_Z = [(16, 28), (32, 44), (48, 62)]


def stage_market(b):
    for row, (z0, z1) in enumerate(MARKET_Z):
        for col, (x0, x1) in enumerate(MARKET_X):
            if (row, col) == (1, 1):
                continue                                  # the market hall is built separately
            b.block(x0, z0, x1, z1, 0, ROOF, "tower", "market_%d%d" % (row, col), mirror=True)
            # Garden planters on the roof (cover islands up there).
            b.cylinder((x0 + x1) / 2, (z0 + z1) / 2, 1.5, ROOF, ROOF + 1.2, "cover", "planter_%d%d" % (row, col), mirror=True)
    # The hall: walls with a door on each alley, a roof slab with a 6 m skylight, stalls inside.
    b.room(-73, 32, -64, 44, 0, ROOF - 1, 1, "tower", "hall", openings=[("w", 38, 4, 4), ("e", 38, 4, 4)], mirror=True)
    slab_with_holes(b, -73, 32, -64, 44, ROOF - 1, ROOF, [[-71.5, 35, -65.5, 41]], "tower", "hall_roof")
    b.block(-70, 35, -67.5, 37, 0, 2.4, "cover", "hall_stall", mirror=True)
    # Event: the skylight floor collapses into the hall (once, at 150 s): a route from the roofs down to the street.
    b.mover("skylight", (6, 0.5, 6), [(0, (-68.5, ROOF - 0.25, 38)), (150, (-68.5, ROOF - 0.25, 38)), (152.5, (-68.5, -0.75, 38))],
            color=MOVER, mirror=True)
    b.event(150, "MARKET SKYLIGHTS COLLAPSING")
    # Roof bridges (the garden is one connected plateau) and mid-level bridges over the north-south alleys.
    for z0 in (22, 58):
        for x0, x1 in ((-77, -73), (-64, -60)):
            b.block(x0, z0, x1, z0 + 4, ROOF - 0.5, ROOF, "walk", "roof_bridge", mirror=True)
    for x0, x1 in ((-77, -73), (-64, -60)):
        b.block(x0, 18, x1, 20, MID - 0.5, MID, "walk", "mid_bridge", mirror=True)
    # Awnings are bounce pads: launch is strong enough to reach the roofs. Two on each side of the hall, two on the back row.
    for (x0, x1, zs) in ((-77, -75, (35, 41)), (-62, -60, (35, 41)), (-77, -75, (51, 57)), (-62, -60, (51, 57))):
        z0, z1 = zs
        b.block(x0, z0, x1, z1, 3.5, 4.0, "accent", "awning", mirror=True, color=BOUNCE)
        b.bounce(x0, z0, x1, z1, 4.0, 4.7, power=23, mirror=True, tag="awning_bounce")
    # Boulevard-side awnings: gentle hops up to the mid-level bridges.
    for x0, x1 in ((-86, -80), (-60, -54)):
        b.block(x0, 14, x1, 16, 3.5, 4.0, "accent", "awning_blv", mirror=True, color=BOUNCE)
        b.bounce(x0, 14, x1, 16, 4.0, 4.7, power=17, mirror=True, tag="awning_blv_bounce")
    # Fire escapes: climb lanes up the alley faces, topping out onto the roofs.
    for x0 in (-83, -70, -57):
        b.climb(x0, 28, x0 + 3, 29.2, 0, ROOF + 0.6, mirror=True, tag="escape_s", face="-z")
        b.decor(x0, 28, x0 + 3, 28.04, 0, ROOF, "accent", "flush", "escape_s_strip", mirror=True, color=CLIMB)
    for x0 in (-83, -57):
        b.climb(x0, 46.8, x0 + 3, 48, 0, ROOF + 0.6, mirror=True, tag="escape_n", face="+z")
        b.decor(x0, 47.96, x0 + 3, 48, 0, ROOF, "accent", "flush", "escape_n_strip", mirror=True, color=CLIMB)


# ---- flooded industrial (south inner): a sunken canal, chokepoint bridges, silos ---------------------------

def stage_industrial(b):
    # Canal: 8 m wide pit, 3 m deep, entered by a ramp at the north end; the water is a coloured floor for now.
    b.ramp(-42, 28, -34, 38, -4, -3, 0, "-z", "walk", "canal_ramp", mirror=True)
    b.block(-42, 38, -34, 58, -4, -3, "walk", "canal_bed", mirror=True, color="#3a6ea8")
    b.block(-44, 26, -42, 60, -4, -1, "wall", "canal_wall_w", mirror=True)
    b.block(-34, 26, -32, 60, -4, -1, "wall", "canal_wall_e", mirror=True)
    b.block(-42, 58, -34, 60, -4, -1, "wall", "canal_wall_s", mirror=True)
    b.block(-42, 26, -34, 28, -4, -1, "wall", "canal_wall_n", mirror=True)
    # Event: both drawbridges lift at 75 s (about six seconds), stay up until 135 s, then lower again (150 s loop).
    for zc, tag in ((45, "drawbridge_a"), (53, "drawbridge_b")):
        keys = []
        for t, theta in ((0, 0), (75, 0), (76.2, 20), (77.4, 40), (78.6, 60), (79.8, 80), (135, 80), (136.2, 60), (137.4, 40),
                         (138.6, 20), (139.8, 0), (150, 0)):
            r = math.radians(theta)
            keys.append((t, (-42 + 4 * math.cos(r), -0.25 + 4 * math.sin(r), zc), (0, 0, theta)))
        b.mover(tag, (8, 0.5, 6), keys, color=MOVER, period=150, ease=False, mirror=True)
    b.event(75, "DRAWBRIDGES RAISING")
    # Silos (landmarks, 30 m) with a ladder to the top; tanks on the walkways are cover islands.
    for z in (44, 56):
        b.cylinder(-29, z, 3, 0, 30, "tower", "silo", mirror=True)
        b.climb(-33.2, z - 1.5, -32, z + 1.5, 0, 30.6, mirror=True, tag="silo_ladder", face="+x")
    for x, z in ((-46, 36), (-46, 50), (-30, 32)):
        b.cylinder(x, z, 1.75, 0, 3, "cover", "tank", mirror=True)
    # Pump house at the north end: the shoulder that makes the canal approach a chokepoint.
    b.block(-48, 14, -42, 24, 0, 7, "wall", "pump_house", mirror=True)


# ---- the verb layer: shaft, power lines, rails, billboards ---------------------------------------------

def stage_verbs(b):
    # Vent tower on the boulevard: a 4 m shaft from the tunnel floor to the roof with a climb lane inside.
    # Sleeve under the street keeps the lane against a wall all the way down.
    b.block(-58, -4, -56, 4, 0, ROOF, "tower", "vent_w", mirror=True)
    b.block(-52, -4, -50, 4, 0, ROOF, "tower", "vent_e", mirror=True)
    b.block(-56, -4, -52, -2, 0, ROOF, "tower", "vent_n", mirror=True)
    b.block(-56, 2, -52, 4, 0, ROOF, "tower", "vent_s", mirror=True)
    b.block(-56, -5, -52, -2, TUNNEL_Y, -1, "wall", "vent_sleeve", mirror=True)
    b.climb(-55, -2, -53, -0.8, TUNNEL_Y, ROOF + 0.6, mirror=True, tag="vent_ladder", face="-z")
    b.decor(-55, -2, -53, -1.96, 0, ROOF, "accent", "flush", "vent_ladder_strip", mirror=True, color=CLIMB)
    # Power lines. Zips hang you from the wire; jump to let go. They run both ways.
    # A skybridge links the vent tower roof to the garden (the long way across the street).
    b.block(-58, 4, -50, 16, ROOF - 0.5, ROOF, "walk", "vent_bridge", mirror=True)
    # Long fast line from the north spire dock down to the tower top plate (a risky highway above the north yard).
    b.cable((-5.5, 35.8, -56), (-46, 26.4, -49), mode="zip", speed=12, mirror=True, tag="zip_dock_tower", color=CABLE)
    b.cable((-53, 26.4, -49), (-71, 26.2, -46), mode="zip", speed=14, mirror=True, tag="zip_tower_office", color=CABLE)
    b.cable((-29, 31.8, 44), (-5, 35.8, 52), mode="zip", speed=16, mirror=True, tag="zip_silo_dock", color=CABLE)
    # Grind rails along the double container stacks: land on them from above to ride the lane at speed.
    for z0, z1 in ((-43, -33), (33, 43)):
        b.cable((-21.5, 5.7, z0), (-21.5, 5.7, z1), mode="grind", speed=14, mirror=True, tag="grind_stack", color=CABLE)
    # Billboard perch over a market alley, fed by a bounce pad with a kick toward it.
    for x in (-80, -71):
        b.block(x, 52, x + 1, 53, ROOF, 17.5, "wall", "billboard_leg", mirror=True)
        b.block(x, 55, x + 1, 56, ROOF, 17.5, "wall", "billboard_leg", mirror=True)
    b.block(-80, 52, -70, 56, 17.5, 18, "walk", "billboard_deck", mirror=True, color=PERCH)
    b.block(-86, 52, -84.5, 56, ROOF, ROOF + 0.3, "accent", "billboard_pad", mirror=True, color=BOUNCE)
    b.bounce(-86, 52, -84.5, 56, ROOF + 0.3, ROOF + 1.0, power=24, kick=(3.5, 0, 0), mirror=True, tag="billboard_launch")


# ---- bot graph (walk and ramp edges only; verbs are for players) ------------------------------------

def chicane_nodes(b, name, x0, before, after):
    """Waypoints that thread an offset barrier pair at x0 (north wall x0..x0+1, south wall x0+4..x0+5)."""
    b.waypoint(name + "a", x0 - 1, 0, 3.5, name + "p:blv", mirror=True)
    b.waypoint(name + "p", x0 + 2.5, 0, 3.5, name + "m:blv", mirror=True)
    b.waypoint(name + "m", x0 + 2.5, 0, -2.5, name + "b:blv", mirror=True)
    b.waypoint(name + "b", x0 + 6.5, 0, -4, after + ":blv", mirror=True)


def stage_graph(b):
    b.waypoint("S", -90, 0, 0, "gt:blv,Sn:blv,Ss:blv", mirror=True, spawn=True)
    # Room nodes keep bots at the back of the depot from steering straight at the gate jamb.
    b.waypoint("Sn", -90, 0, -6, "", mirror=True)
    b.waypoint("Ss", -90, 0, 6, "", mirror=True)
    b.waypoint("gt", -85.5, 0, 0, "q1:blv", mirror=True)
    b.waypoint("q1", -85, 0, -4.5, "q2:blv", mirror=True)
    b.waypoint("q2", -80, 0, -4.5, "c1a:blv", mirror=True)
    chicane_nodes(b, "c1", -76, "q2", "A")
    b.waypoint("A", -64, 0, 0, "a_s:blv", mirror=True, point=True)
    b.waypoint("a_s", -56, 0, 9, "a_t:blv", mirror=True)
    b.waypoint("a_t", -49, 0, 9, "c2a:blv", mirror=True)
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
    # market alleys: a loop off the boulevard (tag aln)
    b.waypoint("m0", -75, 0, 13, "m1:aln,c1p:aln", mirror=True)
    b.waypoint("m1", -75, 0, 30, "m2:aln,m4:aln", mirror=True)
    b.waypoint("m2", -75, 0, 46, "m3:aln", mirror=True)
    b.waypoint("m3", -75, 0, 56, "", mirror=True)
    b.waypoint("m4", -62, 0, 30, "m5:aln", mirror=True)
    b.waypoint("m5", -62, 0, 14, "A:aln", mirror=True)
    # industrial: west of the stair well down to its top
    b.waypoint("ib", -38, 0, 6, "B:aln,i0:aln", mirror=True)
    b.waypoint("i0", -40, 0, 12, "i1:aln", mirror=True)
    b.waypoint("i1", -40, 0, 26, "s2t:aln", mirror=True)
