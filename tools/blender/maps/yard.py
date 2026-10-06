"""Test Yard: a small symmetric replace-mode map (60 x 30 m half-extents) built with blockout_kit.

Authored for the west half and mirrored across x = 0, like the main map. Five capture points (A, B, C, B', A'),
a depot with a gate at each end, cover on the street, and a raised deck reached by a ramp.
    python3 tools/blender/generate.py tools/blender/maps/yard.py maps/blockout.json
"""
MODE = "replace"


def build(b):
    b.configure(bounds=(-62, -32, 124, 64), spawn_x=57, spawn_z=-7, spawn_step=2.8, depot_limit=53)
    # Ground, outer walls and the depot room (gate faces east, toward the boulevard).
    b.block(-62, -32, 62, 32, -1, 0, "walk", "floor")
    b.block(-62, -32, 62, -30, 0, 8, "tower", "wall_n")
    b.block(-62, 30, 62, 32, 0, 8, "tower", "wall_s")
    b.block(-62, -30, -60, 30, 0, 8, "tower", "wall_end", mirror=True)
    b.room(-60, -9, -52, 9, 0, 6, 1, "wall", "depot", openings=[("e", 0, 6, 4)], mirror=True)
    b.block(-60, -9, -52, 9, 6, 7, "tower", "depot_roof", mirror=True)
    # Baffles stop the spawn seeing straight down the street.
    b.block(-49, -6, -47, -1, 0, 3.5, "wall", "baffle_n", mirror=True)
    b.block(-49, 1, -47, 6, 0, 3.5, "wall", "baffle_s", mirror=True)
    # Street cover (kept 5 m clear of every capture point).
    for z in (-12, 12):
        b.block(-34, z - 1, -28, z + 1, 0, 2.6, "cover", "cover_mid", mirror=True)
    b.block(-12, -14, -9, -11, 0, 2.6, "cover", "cover_c_n", mirror=True)
    b.block(-12, 11, -9, 14, 0, 2.6, "cover", "cover_c_s", mirror=True)
    b.cylinder(-26, -20, 1.25, 0, 5, "tower", "column", mirror=True)
    # Raised deck on the south side, reached by a 12 degree ramp.
    b.block(-30, 16, -14, 28, 0, 3, "wall", "deck", mirror=True)
    b.ramp(-42, 18, -30, 24, 0, 0, 3, "+x", "walk", "deck_ramp", mirror=True)
    b.decor(-30.04, 16, -30, 28, 2.6, 2.9, "accent", "flush", "deck_edge_strip", mirror=True)
    # Bot graph: boulevard along z = 0, deck loop on the south side.
    b.waypoint("S", -57, 0, 0, "g:blv", mirror=True, spawn=True)
    b.waypoint("g", -52.5, 0, 0, "A:blv", mirror=True)
    b.waypoint("A", -40, 0, 0, "B:blv", mirror=True, point=True)
    b.waypoint("B", -20, 0, 0, "C:blv", mirror=True, point=True)
    b.waypoint("C", 0, 0, 0, point=True)
    b.waypoint("rb", -43, 0, 21, "A:roof,rt:roof", mirror=True)
    b.waypoint("rt", -28, 3, 21, "dk:roof", mirror=True)
    b.waypoint("dk", -20, 3, 22, "", mirror=True)
