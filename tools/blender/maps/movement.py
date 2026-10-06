"""Movement Course: a replace-mode sandbox for feeling every movement verb (slide, slide-jump, wall run, vault, ledge grab).

Pick it in the start menu (Map: ...) and use "Explore map" for free roam without bots. Layout and what each station
tests are described in docs/MOVEMENT_COURSE.md. Reuses the Test Yard shell (flat 124 x 64 m floor, 8 m outer walls, a
depot with a gate at each end) so spawns, bounds and the five points are valid; all stations are on the open street.
    python3 tools/blender/generate.py tools/blender/maps/movement.py maps/movement.blockout.json
"""
MODE = "replace"
TITLE = "Movement Course"


def build(b):
    b.configure(bounds=(-62, -32, 124, 64), spawn_x=57, spawn_z=-7, spawn_step=2.8, depot_limit=53)
    # Shell: floor, 8 m perimeter walls (the 124 m long north and south walls are the wall-run strips), depots.
    b.block(-62, -32, 62, 32, -1, 0, "walk", "floor")
    b.block(-62, -32, 62, -30, 0, 8, "tower", "wall_n")
    b.block(-62, 30, 62, 32, 0, 8, "tower", "wall_s")
    b.block(-62, -30, -60, 30, 0, 8, "tower", "wall_end", mirror=True)
    b.room(-60, -9, -52, 9, 0, 6, 1, "wall", "depot", openings=[("e", 0, 6, 4)], mirror=True)
    b.block(-60, -9, -52, 9, 6, 7, "tower", "depot_roof", mirror=True)
    b.block(-49, -6, -47, -1, 0, 3.5, "wall", "baffle_n", mirror=True)
    b.block(-49, 1, -47, 6, 0, 3.5, "wall", "baffle_s", mirror=True)

    # Station 1, slide hill (NW): ramp up to a 3 m platform. Run up, turn round and slide down: slope adds speed.
    b.ramp(-46, -16, -34, -10, 0, 0, 3, "+x", "walk", "slide_hill")
    b.block(-34, -16, -28, -10, 0, 3, "wall", "slide_hill_top")

    # Station 2, slide-jump gaps (NW lane, z -27..-21): 1 m platforms with 5, 7 and 9 m gaps. A run-jump (8 m/s) covers
    # about 6.2 m, so only the 5 m gap is plain; the 7 m gap needs a slide-jump (11 m/s); the 9 m gap needs a slide-jump
    # plus the double jump or dash.
    for x0, x1 in ((-48, -36), (-31, -25), (-18, -12), (-3, 3)):
        b.block(x0, -27, x1, -21, 0, 1, "wall", "gap_platform")

    # Station 3, ledge ladder (south-east of centre): 0.6 and 1.2 m are stepped/vaulted, 1.8 and 2.4 m are grabbed in the
    # air, 3.0 m is beyond mantle reach (needs a wall kick or double jump).
    for i, h in enumerate((0.6, 1.2, 1.8, 2.4, 3.0)):
        x0 = 6 + 6 * i
        b.block(x0, 8, x0 + 4, 12, 0, h, "wall", "ledge_%d" % int(h * 10))

    # Station 4, vault hurdles (north-east lane): 1.1 m hurdles every 8 m. Run at them.
    for x in (10, 18, 26, 34, 42):
        b.block(x, -18, x + 1, -10, 0, 1.1, "cover", "hurdle")

    # Station 5, wall-run corridor (south-east): two 30 m walls 7 m apart for wall-to-wall kicks.
    b.block(4, 18, 34, 19, 0, 8, "tower", "run_wall_a")
    b.block(4, 26, 34, 27, 0, 8, "tower", "run_wall_b")

    # Bot graph: boulevard only (Explore mode has no bots, replace mode just needs a valid graph).
    b.waypoint("S", -57, 0, 0, "g:blv", mirror=True, spawn=True)
    b.waypoint("g", -52.5, 0, 0, "A:blv", mirror=True)
    b.waypoint("A", -40, 0, 0, "B:blv", mirror=True, point=True)
    b.waypoint("B", -20, 0, 0, "C:blv", mirror=True, point=True)
    b.waypoint("C", 0, 0, 0, point=True)
