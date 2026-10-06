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
SUMP_Y = -11.0           # top of the sump floor (pump hall, cistern): 4 m of headroom under the tunnel floor
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
                {"label": "pump hall", "xs": [-88, -64, 4], "zs": [-3, 0, 3], "y": -11, "rect": [-90, -5, 28, 10], "p90": 30, "p99": 40},
                {"label": "cistern", "xs": [-26, 26, 4], "zs": [-3, 0, 3], "y": -11, "rect": [-28, -5, 56, 10], "p90": 40, "p99": 56},
                {"label": "foundation line", "xs": [-41, -37, 2], "zs": [-40, -34, -26, -16, -10], "y": -6, "azimuths": "ns", "rect": [-42, -44, 6, 37], "p90": 25, "p99": 40},
                {"label": "cellar spine", "xs": [-77, -73, 2], "zs": [12, 20, 30, 40, 50, 58], "y": -6, "azimuths": "ns", "rect": [-78, 7, 6, 55], "p90": 55, "p99": 56},
            ])
    stage_shell(b)
    stage_underground(b)
    stage_yard(b)
    stage_construction(b)
    stage_market(b)
    stage_industrial(b)
    stage_verbs(b)
    stage_vertical(b)
    stage_graph(b)


# ---- shell: floor, perimeter, depot, boulevard --------------------------------------------------

STAIR_HOLES = [[-84, -23, -76, -7], [-64, -23, -56, -7], [-36, 7, -28, 23], [-4, -23, 0, -7]]
CANAL_HOLES = [[-42, 28, -34, 58]]
VENT_HOLES = [[-56, -2, -52, 2]]
# Access into the new underground: culvert stair slot, hoist well, foundation ladder hatch, market-hall hatch, cellar launch vent.
DEPTH_HOLES = [[-50, 24, -44, 40.5], [-29.5, -50.5, -24.5, -45.5], [-44, -52, -41, -48], [-72, 40, -68, 43], [-77, 58, -73, 62]]
# Holes in the tunnel floor (over the sump): pump-hall ramp slot, pump-hall ladder hatch, cistern ramp slot.
TUNNEL_HOLES = [[-76, -2, -62, 2], [-90, 2, -87, 5], [-28, -2, -14, 2]]


def stage_shell(b):
    slab_with_holes(b, -96, -64, 0, 64, -1, 0, STAIR_HOLES + CANAL_HOLES + VENT_HOLES + DEPTH_HOLES, "walk", "floor")
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
    slab_with_holes(b, -90, -7, 0, 7, TUNNEL_Y - 1, TUNNEL_Y, TUNNEL_HOLES, "walk", "tunnel_floor")
    b.block(-92, -7, -90, 7, TUNNEL_Y - 1, -1, "wall", "tunnel_end", mirror=True)
    # North wall: openings for stairwells S0 (x -84..-76), S1 (-64..-56), the Foundation Line (-42..-36) and S3 (centre).
    for x0, x1 in ((-90, -84), (-76, -64), (-56, -42), (-36, -4)):
        b.block(x0, -7, x1, -5, TUNNEL_Y, -1, "wall", "tunnel_wall_n", mirror=True)
    # South wall: openings for the market cellars (-78..-72), the culvert (-50..-44) and S2 (-36..-28).
    for x0, x1 in ((-90, -78), (-72, -50), (-44, -36), (-28, 0)):
        b.block(x0, 5, x1, 7, TUNNEL_Y, -1, "wall", "tunnel_wall_s", mirror=True)
    # Stairwells: long gentle ramps (20 degrees) up to street level, enclosed so no void is exposed.
    b.ramp(-84, -23, -76, -7, TUNNEL_Y - 1, TUNNEL_Y, 0, "-z", "walk", "stair_s0", mirror=True)
    b.block(-86, -23, -84, -7, TUNNEL_Y, -1, "wall", "stair_s0_wall_w", mirror=True)
    b.block(-76, -23, -74, -7, TUNNEL_Y, -1, "wall", "stair_s0_wall_e", mirror=True)
    b.ramp(-64, -23, -56, -7, TUNNEL_Y - 1, TUNNEL_Y, 0, "-z", "walk", "stair_s1", mirror=True)
    b.block(-66, -23, -64, -7, TUNNEL_Y, -1, "wall", "stair_s1_wall_w", mirror=True)
    b.block(-56, -23, -54, -7, TUNNEL_Y, -1, "wall", "stair_s1_wall_e", mirror=True)
    b.ramp(-36, 7, -28, 23, TUNNEL_Y - 1, TUNNEL_Y, 0, "+z", "walk", "stair_s2", mirror=True)
    b.block(-38, 7, -36, 23, TUNNEL_Y, -1, "wall", "stair_s2_wall_w", mirror=True)
    b.block(-28, 7, -26, 23, TUNNEL_Y, -1, "wall", "stair_s2_wall_e", mirror=True)
    b.ramp(-4, -23, 4, -7, TUNNEL_Y - 1, TUNNEL_Y, 0, "-z", "walk", "stair_s3")
    b.block(-6, -23, -4, -7, TUNNEL_Y, -1, "wall", "stair_s3_wall", mirror=True)
    # Staggered pillar pairs (A covers z -5..1, B covers z -1..5) break the 180 m tunnel into short runs. They stand clear of
    # every stair mouth and sump slot.
    for x0 in (-86, -50, -12):
        b.block(x0, -5, x0 + 2, 1, TUNNEL_Y, -1, "wall", "tunnel_pillar_a", mirror=True)
        b.block(x0 + 6, -1, x0 + 8, 5, TUNNEL_Y, -1, "wall", "tunnel_pillar_b", mirror=True)
    # Stairs are marked in green-white; tunnels read as fast lanes with orange strips.
    b.decor(-90, -5.04, 0, -5, -5.0, -4.75, "accent", "flush", "tunnel_strip_n", mirror=True, color=ORANGE)
    stage_sump(b)
    stage_branches(b)


# ---- sump tier (y -11): pump hall under A and the cistern under C ----------------------------------------------

def sump_ramp(b, x0, x1, direction, tag):
    """A 14 m ramp slot (20 degrees) in the tunnel floor, 4 m wide, with solid fill either side so no void shows."""
    b.ramp(x0, -2, x1, 2, SUMP_Y - 1, SUMP_Y, TUNNEL_Y, direction, "walk", tag, mirror=True)
    b.block(x0, -5, x1, -2, SUMP_Y - 1, TUNNEL_Y - 1, "wall", tag + "_fill_n", mirror=True)
    b.block(x0, 2, x1, 5, SUMP_Y - 1, TUNNEL_Y - 1, "wall", tag + "_fill_s", mirror=True)


def stage_sump(b):
    top = TUNNEL_Y - 1          # underside of the tunnel floor
    # Pump hall (x -90..-76) with its ramp slot (-76..-62). Walls run under the tunnel walls.
    b.block(-90, -5, -76, 5, SUMP_Y - 1, SUMP_Y, "walk", "pump_floor", mirror=True)
    b.block(-92, -7, -90, 7, SUMP_Y - 1, top, "wall", "pump_end", mirror=True)
    b.block(-90, -7, -60, -5, SUMP_Y - 1, top, "wall", "pump_wall_n", mirror=True)
    b.block(-90, 5, -60, 7, SUMP_Y - 1, top, "wall", "pump_wall_s", mirror=True)
    b.block(-62, -5, -60, 5, SUMP_Y - 1, top, "wall", "pump_wall_e", mirror=True)
    sump_ramp(b, -76, -62, "+x", "pump_ramp")
    b.block(-90, 0, -87, 2, SUMP_Y, top, "wall", "pump_pier", mirror=True)
    b.climb(-89, 2, -88, 3.2, SUMP_Y, TUNNEL_Y + 0.6, mirror=True, tag="pump_ladder", face="-z")
    b.decor(-89, 1.96, -88, 2, SUMP_Y, TUNNEL_Y, "accent", "flush", "pump_ladder_strip", mirror=True, color=CLIMB)
    for z in (-3, 3):
        b.cylinder(-82, z, 1.5, SUMP_Y, SUMP_Y + 3, "cover", "pump_tank", mirror=True)
    # Cistern under C (x -14..14, mirrored through x = 0) with a ramp slot from each side.
    b.block(-14, -5, 0, 5, SUMP_Y - 1, SUMP_Y, "walk", "cistern_floor", mirror=True)
    b.block(-28, -7, 0, -5, SUMP_Y - 1, top, "wall", "cistern_wall_n", mirror=True)
    b.block(-28, 5, 0, 7, SUMP_Y - 1, top, "wall", "cistern_wall_s", mirror=True)
    b.block(-30, -5, -28, 5, SUMP_Y - 1, top, "wall", "cistern_wall_w", mirror=True)
    sump_ramp(b, -28, -14, "-x", "cistern_ramp")
    # Buttresses break the long hall into short runs.
    b.block(-12, -5, -10, -2, SUMP_Y, top, "wall", "cistern_buttress_n", mirror=True)
    b.block(-4, 2, -2, 5, SUMP_Y, top, "wall", "cistern_buttress_s", mirror=True)


# ---- branch tunnels off the transit tunnel: Foundation Line (N), Culvert (S), Market cellars (S) -----------------------

def corridor(b, x0, x1, z0, z1, tag, wall_z0=None):
    """A 6 m tunnel under the street slab: floor, and a wall each side (west and east of x0..x1)."""
    b.block(x0, z0, x1, z1, TUNNEL_Y - 1, TUNNEL_Y, "walk", tag + "_floor", mirror=True)
    wz = z0 if wall_z0 is None else wall_z0
    b.block(x0 - 2, wz, x0, z1, TUNNEL_Y, -1, "wall", tag + "_wall_w", mirror=True)
    b.block(x1, wz, x1 + 2, z1, TUNNEL_Y, -1, "wall", tag + "_wall_e", mirror=True)


def stage_branches(b):
    # Foundation Line: x -42..-36 from the tunnel to a pit under the tower frame and the construction hoist.
    corridor(b, -42, -36, -44, -7, "found", wall_z0=-42)
    b.block(-42, -30, -40, -22, TUNNEL_Y, -1, "wall", "found_baffle_a", mirror=True)
    b.block(-38, -38, -36, -30, TUNNEL_Y, -1, "wall", "found_baffle_b", mirror=True)
    b.block(-44, -56, -24, -44, TUNNEL_Y - 1, TUNNEL_Y, "walk", "pit_floor", mirror=True)
    b.block(-46, -58, -22, -56, TUNNEL_Y, -1, "wall", "pit_wall_n", mirror=True)
    b.block(-46, -56, -44, -44, TUNNEL_Y, -1, "wall", "pit_wall_w", mirror=True)
    b.block(-24, -56, -22, -42, TUNNEL_Y, -1, "wall", "pit_wall_e", mirror=True)
    b.block(-46, -44, -42, -42, TUNNEL_Y, -1, "wall", "pit_wall_sw", mirror=True)
    b.block(-36, -44, -24, -42, TUNNEL_Y, -1, "wall", "pit_wall_se", mirror=True)
    b.block(-36, -54, -33, -51, TUNNEL_Y, TUNNEL_Y + 2.6, "cover", "pit_crate", mirror=True)
    b.climb(-44, -51, -42.8, -49, TUNNEL_Y, 0.6, mirror=True, tag="pit_ladder", face="-x")
    b.decor(-44.04, -51, -44, -49, TUNNEL_Y, 0, "accent", "flush", "pit_ladder_strip", mirror=True, color=CLIMB)
    # Culvert: x -50..-44 south from the tunnel under the pump house to a stair slot that surfaces beside the canal.
    corridor(b, -50, -44, 7, 24, "culvert")
    b.ramp(-50, 24, -44, 40.5, TUNNEL_Y - 1, TUNNEL_Y, 0, "+z", "walk", "culvert_ramp", mirror=True)
    b.block(-52, 24, -50, 40.5, TUNNEL_Y, -1, "wall", "culvert_slot_wall_w", mirror=True)
    b.block(-44, 24, -42, 26, TUNNEL_Y, -1, "wall", "culvert_slot_wall_e", mirror=True)
    b.block(-44, 26, -42, 40.5, TUNNEL_Y, -4, "wall", "culvert_slot_wall_e2", mirror=True)
    # Market cellars: x -78..-72 under the market alley, a vault under the hall (ladder up into it) and a launch vent at the end.
    b.block(-78, 7, -72, 62, TUNNEL_Y - 1, TUNNEL_Y, "walk", "cellar_floor", mirror=True)
    b.block(-80, 7, -78, 62, TUNNEL_Y, -1, "wall", "cellar_wall_w", mirror=True)
    b.block(-72, 7, -70, 31, TUNNEL_Y, -1, "wall", "cellar_wall_e1", mirror=True)
    b.block(-72, 45, -70, 62, TUNNEL_Y, -1, "wall", "cellar_wall_e2", mirror=True)
    b.block(-80, 62, -70, 64, TUNNEL_Y, -1, "wall", "cellar_wall_s", mirror=True)
    b.block(-72, 33, -65, 43, TUNNEL_Y - 1, TUNNEL_Y, "walk", "vault_floor", mirror=True)
    b.block(-72, 31, -63, 33, TUNNEL_Y, -1, "wall", "vault_wall_n", mirror=True)
    b.block(-72, 43, -63, 45, TUNNEL_Y, -1, "wall", "vault_wall_s", mirror=True)
    b.block(-65, 33, -63, 43, TUNNEL_Y, -1, "wall", "vault_wall_e", mirror=True)
    b.block(-68, 40, -65, 43, TUNNEL_Y, -1, "wall", "vault_pier", mirror=True)
    b.climb(-69.2, 40.5, -68, 42.5, TUNNEL_Y, 0.6, mirror=True, tag="vault_ladder", face="+x")
    b.decor(-68.04, 40.5, -68, 42.5, TUNNEL_Y, 0, "accent", "flush", "vault_ladder_strip", mirror=True, color=CLIMB)
    # Launch vent: step on the pad and it throws you up the shaft and out toward the alley.
    b.block(-77, 60, -73, 62, TUNNEL_Y, TUNNEL_Y + 0.3, "accent", "cellar_pad", mirror=True, color=BOUNCE)
    b.bounce(-77, 60, -73, 62, TUNNEL_Y + 0.3, TUNNEL_Y + 1.0, power=20, kick=(0, 0, -4), mirror=True, tag="cellar_launch")


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
    # Material hoist beside the tower: landings at 6, 12 and 18 m, a car that stops at the foundation pit (y -6), ground and each landing.
    for level in (6, 12, 18):
        b.block(-32, -50, -29, -46, level - 0.5, level, "walk", "hoist_landing_%d" % level, mirror=True)
    keys = [(0, (-27, -6.0, -48)), (6, (-27, -6.0, -48)), (9, (-27, 0.0, -48)), (15, (-27, 0.0, -48)), (18, (-27, 5.75, -48)),
            (21, (-27, 5.75, -48)), (24, (-27, 11.75, -48)), (27, (-27, 11.75, -48)), (30, (-27, 17.75, -48)), (38, (-27, 17.75, -48)),
            (46, (-27, -6.0, -48)), (52, (-27, -6.0, -48))]
    b.mover("hoist", (4, 0.5, 4), keys, color=MOVER, period=52, mirror=True)
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
    for x0, z0, x1, z1 in ((-75, -22, -70, -18), (-52, -22, -44, -18), (-40, -26, -34, -22)):
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
    for x, z in ((-46, 50), (-30, 32)):
        b.cylinder(x, z, 1.75, 0, 3, "cover", "tank", mirror=True)
    # Pump house at the north end: the shoulder that makes the canal approach a chokepoint.
    b.block(-48, 14, -42, 24, 0, 7, "wall", "pump_house", mirror=True)


# ---- verticality set pieces: The Span over C, the north warehouse row, yard gantries, the pump-house perch --------------

def stage_vertical(b):
    stage_span(b)
    stage_north_row(b)
    stage_gantries(b)
    stage_perch(b)


def stage_span(b):
    """A mid-level (y 6) bridge over the centre point C with a gatehouse and a control booth at y 12 on top.
    Everything stays overhead or well outside the 4.5 m capture disc; pylons stand clear of the S3 stair slot and the chicane routes."""
    deck0, deck1 = MID - 0.5, MID
    b.block(-11, -3, 0, 3, deck0, deck1, "walk", "span_deck", mirror=True)
    b.block(-15, -11, -11, 11, deck0, deck1, "walk", "span_arm", mirror=True)
    b.block(-15, -11, -11, -9, 0, deck0, "wall", "span_pylon_n", mirror=True)
    b.block(-15, 9, -11, 11, 0, deck0, "wall", "span_pylon_s", mirror=True)
    b.block(-15, -9, -14.5, 9, MID, MID + 1.1, "wall", "span_parapet", mirror=True, color=ORANGE)
    # Gatehouse: two walls carry the booth and leave the deck open between them (5.5 m of headroom).
    # (the audit keeps all non-walk solids 4.5 m from a capture point, so the gate walls and rails sit just outside that radius)
    b.block(-7, -3, -6, 3, MID, ROOF - 0.5, "wall", "span_gate", mirror=True)
    b.block(-7, -5.25, 7, 5.25, ROOF - 0.5, ROOF, "walk", "span_booth", color=PERCH)
    b.block(-7, -5.25, 7, -4.75, ROOF, ROOF + 1.1, "wall", "span_booth_rail_n", color=ORANGE)
    b.block(-7, 4.75, 7, 5.25, ROOF, ROOF + 1.1, "wall", "span_booth_rail_s", color=ORANGE)
    # Up to the deck: a ladder on each pylon end. Up to the booth: a ladder on each gatehouse wall and a launch pad.
    b.climb(-14, -12.2, -12, -11, 0, MID + 0.6, mirror=True, tag="span_ladder_n", face="+z")
    b.decor(-14, -11.04, -12, -11, 0, MID, "accent", "flush", "span_ladder_n_strip", mirror=True, color=CLIMB)
    b.climb(-14, 11, -12, 12.2, 0, MID + 0.6, mirror=True, tag="span_ladder_s", face="-z")
    b.decor(-14, 11, -12, 11.04, 0, MID, "accent", "flush", "span_ladder_s_strip", mirror=True, color=CLIMB)
    b.climb(-8.2, -1, -7, 1, MID, ROOF + 0.6, mirror=True, tag="span_booth_ladder", face="+x")
    b.decor(-7.04, -1, -7, 1, MID, ROOF - 0.5, "accent", "flush", "span_booth_ladder_strip", mirror=True, color=CLIMB)
    b.block(-10.5, -1.5, -8.5, 1.5, MID, MID + 0.3, "accent", "span_pad", mirror=True, color=BOUNCE)
    b.bounce(-10.5, -1.5, -8.5, 1.5, MID + 0.3, MID + 1.0, power=23, kick=(4, 0, 0), mirror=True, tag="span_launch")


def stage_north_row(b):
    """Two 12 m warehouses in the north strip: the market's roof garden gets a northern twin."""
    for x0, x1, tag in ((-86, -78, "w1"), (-75, -68, "w2")):
        b.block(x0, -36, x1, -27, 0, ROOF, "tower", "warehouse_" + tag, mirror=True)
        b.cylinder((x0 + x1) / 2.0, -31.5, 1.5, ROOF, ROOF + 1.2, "cover", "planter_" + tag, mirror=True)
    b.block(-78, -34, -75, -30, ROOF - 0.5, ROOF, "walk", "roof_bridge_n", mirror=True)
    # Awnings launch to the roofs (double jump gets you onto them); fire escapes climb the street face.
    for x0, x1 in ((-86, -82), (-75, -72)):
        b.block(x0, -27, x1, -25.5, 3.5, 4.0, "accent", "awning_n", mirror=True, color=BOUNCE)
        b.bounce(x0, -27, x1, -25.5, 4.0, 4.7, power=23, mirror=True, tag="awning_n_bounce")
    for x0, x1 in ((-81, -78), (-71, -68)):
        b.climb(x0, -27, x1, -25.8, 0, ROOF + 0.6, mirror=True, tag="escape_nw", face="-z")
        b.decor(x0, -26.96, x1, -26.92 + 0.0, 0, ROOF, "accent", "flush", "escape_nw_strip", mirror=True, color=CLIMB)


def stage_gantries(b):
    """Portal cranes over the rail-yard lanes: a 52 m catwalk at y 9, ladders on the west legs, one at each end of the yard."""
    for z in (-22, 22):
        b.block(-26, z - 1, -24, z + 1, 0, 8.5, "wall", "gantry_leg", mirror=True)
        b.block(-26, z - 1, 0, z + 1, 8.5, 9, "walk", "gantry_beam", mirror=True, color=MOVER)
        face = "+x"
        b.climb(-27.2, z - 0.75, -26, z + 0.75, 0, 9.6, mirror=True, tag="gantry_ladder", face=face)
        b.decor(-26.04, z - 0.75, -26, z + 0.75, 0, 8.5, "accent", "flush", "gantry_ladder_strip", mirror=True, color=CLIMB)


def stage_perch(b):
    """The pump house roof (y 7) becomes a sniper perch over the boulevard approach to B: a ladder on its north face and cover up top."""
    b.climb(-47, 12.8, -45, 14, 0, 7.6, mirror=True, tag="pump_house_ladder", face="+z")
    b.decor(-47, 13.96, -45, 14, 0, 7, "accent", "flush", "pump_house_ladder_strip", mirror=True, color=CLIMB)
    b.block(-47, 17, -43, 18, 7, 8.2, "cover", "pump_house_cover", mirror=True)


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
    # underground: tunnel line, stairwells, the sump and the branch tunnels (tag trn). Pillars and ramp slots are threaded on z = +-3.5.
    b.waypoint("tW", -88, -6, 0, "p1a:trn", mirror=True)
    b.waypoint("p1a", -85, -6, 3.5, "p1b:trn", mirror=True)
    b.waypoint("p1b", -82, -6, 0, "p1c:trn", mirror=True)
    b.waypoint("p1c", -79, -6, -3.5, "p1e:trn,s0b:trn", mirror=True)
    b.waypoint("p1e", -77, -6, -3.5, "p1d:trn,cm1:trn", mirror=True)
    b.waypoint("p1d", -61, -6, -3.5, "tA:trn", mirror=True)
    b.waypoint("tA", -60, -6, 0, "p2a:trn,s1b:trn,pt:trn", mirror=True)
    b.waypoint("p2a", -49, -6, 3.5, "p2b:trn", mirror=True)
    b.waypoint("p2b", -46, -6, 0, "p2c:trn,cu0:trn", mirror=True)
    b.waypoint("p2c", -43, -6, -3.5, "tB:trn,fb:trn", mirror=True)
    b.waypoint("tB", -32, -6, 0, "tBs:trn,s2b:trn,cw0:trn", mirror=True)
    b.waypoint("tBs", -30, -6, 3.5, "p3a:trn", mirror=True)
    b.waypoint("p3a", -13, -6, 4, "p3b:trn", mirror=True)
    b.waypoint("p3b", -8, -6, 1.5, "p3c:trn", mirror=True)
    b.waypoint("p3c", -8, -6, -3.5, "tC:trn", mirror=True)
    b.waypoint("tC", 0, -6, 0, "s3b:trn")
    # sump: pump hall under A, cistern under C (the ramp slots are 14 m, 5 m drop)
    def pump_y(x):
        return round(SUMP_Y + (x + 76) / 14.0 * 5.0, 2)

    def cist_y(x):
        return round(TUNNEL_Y - (x + 28) / 14.0 * 5.0, 2)

    b.waypoint("pt", -62, TUNNEL_Y, 0, "pm:trn", mirror=True)
    b.waypoint("pm", -69, pump_y(-69), 0, "pb:trn", mirror=True)
    b.waypoint("pb", -75, pump_y(-75), 0, "pr:trn", mirror=True)
    b.waypoint("pr", -84, SUMP_Y, 0, "", mirror=True)
    b.waypoint("cw0", -28, TUNNEL_Y, 0, "cw1:trn", mirror=True)
    b.waypoint("cw1", -21, cist_y(-21), 0, "cw2:trn", mirror=True)
    b.waypoint("cw2", -15, cist_y(-15), 0, "cw3:trn", mirror=True)
    b.waypoint("cw3", -10, SUMP_Y, 0, "cC:trn", mirror=True)
    b.waypoint("cC", 0, SUMP_Y, 0, "")
    # stairwell S0 (near the depot), Foundation Line, culvert (surfaces beside the canal), market cellars
    b.waypoint("s0b", -80, -6, -6, "s0m:trn", mirror=True)
    b.waypoint("s0m", -80, -3, -15, "s0t:trn", mirror=True)
    b.waypoint("s0t", -80, 0, -23, "s0n:aln", mirror=True)
    b.waypoint("s0n", -80, 0, -25, "n1b:aln", mirror=True)
    b.waypoint("fb", -39, -6, -6, "f1:trn", mirror=True)
    b.waypoint("f1", -39, -6, -15, "f2:trn", mirror=True)
    b.waypoint("f2", -38, -6, -26, "f3:trn", mirror=True)
    b.waypoint("f3", -40, -6, -34, "f4:trn", mirror=True)
    b.waypoint("f4", -39, -6, -42, "pit1:trn", mirror=True)
    b.waypoint("pit1", -39, -6, -48, "pit2:trn", mirror=True)
    b.waypoint("pit2", -31, -6, -49, "", mirror=True)
    b.waypoint("cu0", -47, -6, 6, "cu1:trn", mirror=True)
    b.waypoint("cu1", -47, -6, 16, "cu2:trn", mirror=True)
    b.waypoint("cu2", -47, -6, 24, "cu3:trn", mirror=True)
    b.waypoint("cu3", -47, round(-6 + (32.25 - 24) / 16.5 * 6, 2), 32.25, "cu4:trn", mirror=True)
    b.waypoint("cu4", -47, 0, 40.5, "cu5:trn", mirror=True)
    b.waypoint("cu5", -47, 0, 42, "e3:aln", mirror=True)
    b.waypoint("e3", -52, 0, 46, "e2:aln", mirror=True)
    b.waypoint("e2", -62, 0, 46, "m2:aln", mirror=True)
    b.waypoint("cm1", -77, -6, 3.5, "cs0:trn", mirror=True)
    b.waypoint("cs0", -75, -6, 9, "cs2:trn", mirror=True)
    b.waypoint("cs2", -75, -6, 30, "cs2b:trn", mirror=True)
    b.waypoint("cs2b", -75, -6, 36, "cs3:trn,vv:trn", mirror=True)
    b.waypoint("vv", -69, -6, 37, "", mirror=True)
    b.waypoint("cs3", -75, -6, 48, "cs4:trn", mirror=True)
    b.waypoint("cs4", -75, -6, 57, "", mirror=True)
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
