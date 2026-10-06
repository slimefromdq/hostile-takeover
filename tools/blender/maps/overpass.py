"""Overpass District: a dense city canyon under stacked highways, built from the reference set.

Authored for the west half and mirrored across x = 0 (Helix west, Monarch east). 164 x 96 m.

  Boulevard (street, y 0) runs between the depots; capture points A, B, C sit at the three cross streets.
  North: an elevated highway deck (y 6) over a ground-level service lane of piers (the "under" route).
         A gas station with a canopy and pumps sits on the deck. A long ramp from the west plaza reaches it;
         another descends to the boulevard between A and B.
  South: terraced park steps (1.5 m each) climb to a plaza at y 6 with a bridge over cross street B;
         ramps on both sides give the walking route. Rear towers close both ends of the cross streets.

Route tags for the bot graph: blv (boulevard), roof (highway deck), aln (under-deck lane and south cross
streets), trn (park terraces and plazas).
    python3 tools/blender/generate.py tools/blender/maps/overpass.py maps/overpass.blockout.json
    python3 tools/blender/blockout_check.py maps/overpass.blockout.json
"""
MODE = "replace"
TITLE = "Overpass District"

DECK_TOP = 6.0
DECK = (DECK_TOP - 1.5, DECK_TOP)       # slab thickness
ORANGE = "#ff6a2b"
RED = "#d9342b"


def build(b):
    b.configure(bounds=(-82, -48, 164, 96), spawn_x=76, spawn_z=-7, spawn_step=2.8, depot_limit=72)
    b.audit(route_families=["blv", "roof", "aln", "trn"], min_families=4,
            lanes=[
                {"label": "boulevard", "xs": [-78, 78, 4], "zs": [-10, -6, -2, 2, 6, 10], "y": 0, "rect": [-82, -12, 164, 24], "p50": 30, "p90": 60, "max": 100},
                {"label": "service lane", "xs": [-60, 60, 4], "zs": [-33, -30, -27], "y": 0, "rect": [-62, -36, 124, 12], "p90": 60, "p99": 120},
                {"label": "highway deck", "xs": [-60, 60, 4], "zs": [-33, -30, -27], "y": 6, "rect": [-62, -36, 124, 12], "p90": 45, "p99": 125},
            ])

    # ---- ground, perimeter, rear towers ---------------------------------------------------------
    b.block(-82, -48, 82, 48, -1, 0, "walk", "floor")
    b.block(-82, -48, 82, -46, 0, 30, "tower", "wall_n")
    b.block(-82, 46, 82, 48, 0, 30, "tower", "wall_s")
    # Depot: a cavity (x -79..-73, z -8..8) carved from touching blocks, a gate wall with a 6 m opening, a baffle outside.
    b.block(-82, -46, -79, 46, 0, 30, "tower", "depot_back", mirror=True)
    b.block(-79, -36, -72, -8, 0, 12, "tower", "end_mass_n", mirror=True)
    b.block(-79, 8, -72, 36, 0, 12, "tower", "end_mass_s", mirror=True)
    b.block(-79, -8, -72, 8, 6, 12, "tower", "depot_roof", mirror=True)
    b.block(-73, -8, -72, -3, 0, 6, "wall", "gate_n", mirror=True)
    b.block(-73, 3, -72, 8, 0, 6, "wall", "gate_s", mirror=True)
    b.block(-73, -3, -72, 3, 4, 6, "wall", "gate_lintel", mirror=True)
    b.block(-70, -3.5, -68, 3.5, 0, 3.5, "wall", "baffle", mirror=True)
    for (x0, x1, h) in ((-79, -62, 30), (-50, -34, 38), (-22, -6, 26)):
        b.block(x0, -46, x1, -36, 0, h, "tower", "rear_n", mirror=True)
    for (x0, x1, h) in ((-79, -62, 26), (-50, -34, 34), (-22, -6, 30)):
        b.block(x0, 36, x1, 46, 0, h, "tower", "rear_s", mirror=True)

    # ---- north: highway deck, ramps, piers, gas station ----------------------------------------
    # West ramp from the plaza up to a landing, then onto the deck.
    b.ramp(-72, -30, -60, -12, 0, 0, DECK_TOP, "-z", "walk", "deck_ramp_w", mirror=True)
    b.block(-72, -36, -60, -30, 0, DECK_TOP, "wall", "deck_landing", mirror=True)
    b.block(-60, -36, -6, -24, DECK[0], DECK[1], "walk", "deck", mirror=True)
    b.block(-6, -36, 6, -24, DECK[0], DECK[1], "walk", "deck_bridge_c")
    # Descent to the boulevard between A and B.
    b.ramp(-42, -24, -36, -6, 0, 0, DECK_TOP, "-z", "walk", "deck_ramp_mid", mirror=True)
    # Piers hold the deck and cut sightlines in the service lane (alternating sides).
    for x, z in ((-58, -34), (-52, -26), (-44, -34), (-32, -26), (-24, -34), (-16, -26), (-10, -34)):
        b.cylinder(x, z, 1.0, 0, DECK[0], "wall", "pier", mirror=True)
    # Centre islands (under the bridge and on top of it) break the lanes where the two halves meet.
    b.block(-1.5, -31.5, 1.5, -28.5, 0, 2.6, "cover", "lane_island")
    b.block(-1.5, -33, 1.5, -29.5, DECK_TOP, DECK_TOP + 2.6, "cover", "deck_island")
    # Parapets: waist-high cover along the deck edges, gaps for the ramps.
    b.block(-60, -24.5, -43, -24, DECK_TOP, DECK_TOP + 1.0, "wall", "parapet_s1", mirror=True)
    b.block(-35, -24.5, -6, -24, DECK_TOP, DECK_TOP + 1.0, "wall", "parapet_s2", mirror=True)
    b.decor(-60, -24.04, -6, -24, 5.0, 5.25, "accent", "flush", "deck_edge_strip", mirror=True, color=ORANGE)
    # Gas station: four pillars, a red canopy, pumps and a kiosk on the deck.
    for x, z in ((-48.5, -33.5), (-48.5, -26.5), (-37.5, -33.5), (-37.5, -26.5)):
        b.block(x, z, x + 1, z + 1, DECK_TOP, 11, "wall", "station_pillar", mirror=True)
    b.block(-49.5, -33.5, -36.5, -25.5, 11, 11.75, "accent", "station_canopy", mirror=True, color=RED)
    for x in (-45.5, -42.0):
        b.block(x, -28.5, x + 1, -27.5, DECK_TOP, DECK_TOP + 1.4, "cover", "pump", mirror=True)
    b.block(-44, -33.5, -40.5, -31, DECK_TOP, DECK_TOP + 3, "wall", "kiosk", mirror=True)
    # Vent unit mid-deck breaks the long sightline along the highway.
    b.block(-27, -33, -25, -29.5, DECK_TOP, DECK_TOP + 2.6, "cover", "deck_vent", mirror=True)
    # Frontage cover on the north sidewalk (kept off the capture discs).
    for x0, x1 in ((-48, -44), (-20, -16)):
        b.block(x0, -18, x1, -15, 0, 2.5, "wall", "frontage", mirror=True)
    b.decor(-72, -11.5, -60, -11, 0, 0.04, "hazard", "flush", "ramp_foot_w", mirror=True)
    b.decor(-42, -5.5, -36, -5, 0, 0.04, "hazard", "flush", "ramp_foot_mid", mirror=True)

    # ---- south: terraced park, plazas, bridge ----------------------------------------------------
    for i, (z0, z1) in enumerate(((12, 17), (17, 22), (22, 27))):
        h = 1.5 * (i + 1)
        b.block(-44, z0, -34, z1, 0, h, "walk", "terrace_a%d" % (i + 1), mirror=True)
        b.block(-22, z0, -12, z1, 0, h, "walk", "terrace_b%d" % (i + 1), mirror=True)
    b.block(-44, 27, -34, 34, 0, DECK_TOP, "walk", "plaza_a", mirror=True)
    b.block(-22, 27, -12, 34, 0, DECK_TOP, "walk", "plaza_b", mirror=True)
    b.block(-34, 28, -22, 33, DECK[0], DECK[1], "walk", "bridge_b", mirror=True)
    b.ramp(-50, 12, -44, 30, 0, 0, DECK_TOP, "+z", "walk", "park_ramp_a", mirror=True)
    b.block(-50, 30, -44, 34, 0, DECK_TOP, "wall", "park_landing_a", mirror=True)
    b.ramp(-12, 12, -6, 30, 0, 0, DECK_TOP, "+z", "walk", "park_ramp_b", mirror=True)
    b.block(-12, 30, -6, 34, 0, DECK_TOP, "wall", "park_landing_b", mirror=True)
    # Planters on the terraces and a railing along the plaza edge toward the street.
    for x, z, y in ((-39, 14.5, 1.5), (-17, 19.5, 3.0)):
        b.cylinder(x, z, 1.0, y, y + 1.2, "cover", "planter", mirror=True)
    b.block(-44, 33.5, -34, 34, DECK_TOP, DECK_TOP + 1.0, "wall", "plaza_rail_a", mirror=True)
    b.decor(-44.04, 27, -44, 34, 5.0, 5.25, "accent", "flush", "plaza_strip_a", mirror=True, color=ORANGE)
    b.decor(-50, 11.5, -44, 12, 0, 0.04, "hazard", "flush", "ramp_foot_a", mirror=True)
    b.decor(-12, 11.5, -6, 12, 0, 0.04, "hazard", "flush", "ramp_foot_b", mirror=True)
    # End plaza: benches and trees as cover.
    b.block(-70, 20, -66, 22, 0, 1.0, "wall", "bench", mirror=True)
    b.cylinder(-68, 28, 1.25, 0, 3.5, "cover", "tree", mirror=True)
    b.cylinder(-68, 14, 1.25, 0, 3.5, "cover", "tree_s", mirror=True)

    # ---- boulevard ----------------------------------------------------------------------------
    for x in range(-66, 0, 8):
        if all(abs(x + 1.5 - px) > 7 for px in (-56, -28, 0)):
            b.decor(x, -0.1, x + 3, 0.1, 0, 0.04, "accent", "flush", "lane_dash", mirror=True, color="#e8e4d0")
    # Offset barrier pairs (traffic chicanes): no straight line runs the length of the street.
    for x0 in (-50, -20):
        b.block(x0, -12, x0 + 1, 1, 0, 3, "wall", "chicane_n", mirror=True)
        b.block(x0 + 4, -1, x0 + 5, 12, 0, 3, "wall", "chicane_s", mirror=True)
        b.decor(x0, -12, x0 + 1, 1, 3.0, 3.1, "accent", "flush", "chicane_cap_n", mirror=True, color=ORANGE)

    # ---- bot graph ------------------------------------------------------------------------------
    b.configure(test_lane=(-42, 0.05, 0))
    b.waypoint("S", -76, 0, 0, "gt:blv", mirror=True, spawn=True)
    b.waypoint("gt", -71.5, 0, 0, "q1:blv", mirror=True)
    b.waypoint("q1", -71, 0, -5, "q2:blv", mirror=True)
    b.waypoint("q2", -66, 0, -5, "A:blv", mirror=True)
    b.waypoint("A", -56, 0, 0, "c1a:blv", mirror=True, point=True)
    b.waypoint("c1a", -49.5, 0, 4, "c1m:blv,t0:trn", mirror=True)
    b.waypoint("c1m", -47.5, 0, 0, "c1b:blv", mirror=True)
    b.waypoint("c1b", -45.5, 0, -4, "a1:blv", mirror=True)
    b.waypoint("a1", -41, 0, 0, "B:blv", mirror=True)
    b.waypoint("B", -28, 0, 0, "c2a:blv", mirror=True, point=True)
    b.waypoint("c2a", -21, 0, 3.5, "c2p:blv", mirror=True)
    b.waypoint("c2p", -17.5, 0, 3, "c2m:blv", mirror=True)
    b.waypoint("c2m", -17.5, 0, -2.5, "c2b:blv", mirror=True)
    b.waypoint("c2b", -13, 0, -4, "C:blv,t8:trn", mirror=True)
    b.waypoint("C", 0, 0, 0, point=True)
    # roof: west ramp, deck, gas station, descent between A and B
    b.waypoint("r0", -66, 0, -12, "q2:blv,r1:roof", mirror=True)
    b.waypoint("r1", -66, 3.0, -21, "r2:roof", mirror=True)
    b.waypoint("r2", -66, 6, -30, "d1:roof", mirror=True)
    b.waypoint("d1", -58, 6, -30, "d2:roof", mirror=True)
    b.waypoint("d2", -46, 6, -30, "d3:roof", mirror=True)
    b.waypoint("d3", -38.5, 6, -30, "d4:roof", mirror=True)
    b.waypoint("d4", -39, 6, -24, "m1:roof", mirror=True)
    b.waypoint("m1", -39, 4.5, -19.5, "m2:roof", mirror=True)
    b.waypoint("m2", -39, 1.5, -10.5, "m3:roof", mirror=True)
    b.waypoint("m3", -39, 0, -5.5, "a1:blv,c1b:blv", mirror=True)
    b.waypoint("d5", -24, 6, -27.5, "d3:roof,d6:roof", mirror=True)
    b.waypoint("d6", -12, 6, -28, "d7:roof", mirror=True)
    b.waypoint("d7", 0, 6, -28, "d6:roof")
    # aln: cross street A north, under-deck lane, cross streets B and C
    b.waypoint("nA1", -56, 0, -14, "A:aln,nA2:aln", mirror=True)
    b.waypoint("nA2", -56, 0, -24, "u1:aln", mirror=True)
    b.waypoint("u1", -56, 0, -30, "u2:aln", mirror=True)
    b.waypoint("u2", -46, 0, -30, "u3:aln", mirror=True)
    b.waypoint("u3", -36, 0, -30, "ub:aln", mirror=True)
    b.waypoint("ub", -28, 0, -30, "nB2:aln,u4:aln", mirror=True)
    b.waypoint("nB2", -28, 0, -24, "nB1:aln", mirror=True)
    b.waypoint("nB1", -28, 0, -14, "B:aln", mirror=True)
    b.waypoint("u4", -20, 0, -30, "u5:aln", mirror=True)
    b.waypoint("u5", -9, 0, -30, "nC2:aln", mirror=True)
    b.waypoint("nC2", -2, 0, -24, "nC1:aln")
    b.waypoint("nC1", -2, 0, -14, "C:aln")
    b.waypoint("sA1", -56, 0, 14, "A:aln,sA2:aln", mirror=True)
    b.waypoint("sA2", -56, 0, 28, "sA3:aln", mirror=True)
    b.waypoint("sA3", -56, 0, 40, "", mirror=True)
    b.waypoint("sB1", -28, 0, 14, "B:aln,sB2:aln", mirror=True)
    b.waypoint("sB2", -28, 0, 28, "sB3:aln", mirror=True)
    b.waypoint("sB3", -28, 0, 40, "", mirror=True)
    b.waypoint("sC1", -2, 0, 14, "C:aln,sC2:aln")
    b.waypoint("sC2", -2, 0, 28, "")
    # trn: park ramps, plazas, bridge over B
    b.waypoint("t0", -47, 0, 10.5, "t1:trn", mirror=True)
    b.waypoint("t1", -47, 3.0, 21, "t2:trn", mirror=True)
    b.waypoint("t2", -47, 6, 30, "t3:trn", mirror=True)
    b.waypoint("t3", -40, 6, 31, "t4:trn", mirror=True)
    b.waypoint("t4", -30, 6, 30.5, "t5:trn", mirror=True)
    b.waypoint("t5", -20, 6, 31, "t6:trn", mirror=True)
    b.waypoint("t6", -9, 6, 30, "t7:trn", mirror=True)
    b.waypoint("t7", -9, 3.0, 21, "t8:trn", mirror=True)
    b.waypoint("t8", -9, 0, 10.5, "", mirror=True)
