# Concrete Canopy: the jungle gym with a city skin

A 192 x 128 m greybox in which every piece of urban furniture is a traversal tool first and set dressing second.
Authored for the west half and mirrored across x = 0 (Helix west, Monarch east). Pick it in the start menu
(**Map: ... click to switch**) or copy `maps/canopy.blockout.json` to `maps/blockout.json`.

![Isometric](previews/canopy_iso.png)

## Game mode (assumption: ask me to change it)

The map is built for the game's existing mode: **5v5 team objective, five capture points, bots fill empty slots**.
The objective unlocks from the centre outward, so the contest starts at C (the rail yard) and teams push toward A or A'.
Depots sit at both ends and nothing in a depot can see the street. **Explore mode** (single-player free roam, no bots) is the sandbox
for learning the verbs. A free-for-all would want more spawn points spread across districts instead of two sealed depots, and
a sandbox wants nothing from the objective at all. Say which you want and I will adapt spawns and loops.

## Movement grammar

One colour per verb, everywhere. Learn it once and it applies on the whole map.

| Verb | The furniture | What it does | Colour |
|---|---|---|---|
| Zipline | Power lines (zip) | Jump into the wire to hang from it, ride at up to 12-16 m/s in the direction you face, jump to let go with a hop | cyan |
| Grind rail | Power lines (grind) | Land on the rail from above to ride it standing at 14 m/s | cyan |
| Bounce | Awnings, shelters, billboard pads | Landing launches you 17 m/s (hop) or 23-24 m/s (to the roofs); some carry a sideways kick | magenta |
| Climb | Fire escapes, scaffolds, ladders, vent shaft, silo and spire ladders | Hold forward to climb at 6.5 m/s, back to descend, strafe to shuffle, jump to kick off; topping out steps you onto the platform | green |
| Perch | Billboards, signs, dock roofs | Standing room with long sightlines; fed by a bounce pad or a ladder | yellow |
| Moving platform | Elevators, trams, cranes, drawbridges, collapsing floors, the blimp | A platform on a keyframed timeline that carries whoever stands on it | violet |
| Tunnel | Subway, Foundation Line, culvert, cellars, sump | Fast, tight flanks under the whole map, with a deeper tier below the subway | orange strips |

Every climb lane draws its own ladder and every cable draws its own wire, so the grammar needs no manual dressing.
Tuning constants live at the top of `scripts/map_verbs.gd`.

## Four tiers, each connected to at least two others

| Tier | Height | What lives there | Connects to |
|---|---|---|---|
| Sump | y -11 | **Pump hall** under A and the **cistern** under C (each entered by a 14 m ramp slot cut in the tunnel floor), 4 m ceilings | Tunnel by the ramp slots and the pump-hall ladder hatch |
| Underground | y -6 | 180 m subway tunnel with staggered pillar pairs, plus three branches: the **Foundation Line** (north, to a pit under the tower frame and the hoist), the **culvert** (south, surfaces beside the canal) and the **market cellars** (south, under the alley) | Street by **four** 20-degree stairwells (S0 sits beside the depots), the culvert slot, **the hoist** (foundation stop), ladder hatches in the pit and the market hall, a **launch vent** at the end of the cellars; **roofs by the vent-tower shaft** (18 m climb) |
| Street | y 0 | Boulevard with offset barrier chicanes, rail yard lanes, market alleys, the canal, construction yard | everything |
| Mid-level | y 6 | Tram stations, tower plates, market bridges, hoist landings, **The Span** over C | Street (ladders, hoist, ramps), roofs (ladders, hoist) |
| Rooftops and sky | y 12 to 40 | Roof garden (one connected plateau), **north warehouse roofs**, **the Span's control booth**, tower top plates, silo tops, spire docks, billboard perches, the blimp at y 34 | Mid and street by ladders, bounce awnings, zips and the hoist |

## The new vertical layer

- **The Span (centre point C).** A 6 m deck at y 6 runs 22 m across the street over the capture disc, joined to two 4 m arms (one each side) that rest on pylons at the boulevard edges. A gatehouse of two walls carries a 14 x 10.5 m **control booth** at y 12. Up: ladders on all four pylon ends and on both gate walls, and a magenta launch pad on each side of the deck that throws you onto the booth. The disc itself stays flat and cover-free: the audit keeps every non-walk solid 4.5 m clear, so the gate walls and booth rails sit just outside that radius. Capture needs street level, so the Span defends the point without capturing it.
- **North warehouse row.** Two 12 m warehouses in the north strip (x -86..-68) are the market roof garden's twin: a roof bridge, planters, bounce awnings on the street face and two fire escapes each.
- **Yard gantries.** Two portal cranes at z = +-22 carry 52 m catwalks at y 9 over the rail-yard lanes, with a ladder on each west leg.
- **Pump-house perch.** A ladder to the pump house roof (y 7) with cover, overlooking the approach to B.

## The deeper underground

Everything runs as `trn` waypoints so bots use it: S0, the Foundation Line, the culvert, the cellars, the pump hall and the cistern are all walk/ramp routes (the culvert comes up into the market's east-west alley, so it joins the street graph).

| Piece | Where | What |
|---|---|---|
| Stairwell S0 | x -84..-76, north | Second northern exit, 25 m from the depot gates |
| Foundation Line | x -42..-36, z -44..-7 | 37 m tunnel with offset baffles to a pit under the tower frame; the **hoist now has a foundation stop (y -6)** and a ladder hatch leads to the street |
| Culvert | x -50..-44, z 7..40 | Runs under the pump house and surfaces on a 20-degree ramp beside the canal |
| Market cellars | x -78..-72, z 7..62 | Spine under the market alley, a vault under the hall with a **ladder up into it**, and a **launch vent** at the far end |
| Pump hall | x -90..-62, y -11 | Ramp slot down from the tunnel, tanks for cover, ladder hatch back up |
| Cistern | x -28..28, y -11 | A ramp slot on each side meets under C; buttresses break its sightline |

Moving between layers: stairs (slow, safe, bots use them), ladders (fast, exposed, one at a time), launch pads (up only) and the hoist.

## Five districts

| District | Where | How it plays |
|---|---|---|
| **Rail Yard** | Centre, x -26..26, full length | Long N-S lanes between container stacks, two cover islands per lane, two timed trams on mid-level stations, the blimp overhead. Capture point C |
| **Construction Site** | North, x -86..-26, z -62..-14 | Vertical and exposed: a 24 m column frame with plates at 6/12/18/24 m, a zig-zag of four scaffold ladders, a hoist (ground to 18 m), a site office reached by ladder or zip, a crane mast and jib (41 m landmark) |
| **Market** | South outer, x -86..-51, z 16..62 | Tight 4 m alleys, a hollow market hall, awnings that launch to the roofs, fire escapes, mid-level bridges |
| **Rooftop Garden** | Over the market, y 12 | Open plateau of connected roofs with planters, roof bridges, a billboard perch, a skylight that collapses |
| **Flooded Industrial** | South inner, x -48..-26, z 14..60 | An 8 m canal pit with a ramp in, two drawbridges (chokepoints), silos with ladders (30 m landmarks), tanks as cover |

Landmarks visible from anywhere: the two **spires** (62 m, with climbable faces and blimp docks at 34 m), the **crane**, the **silos**.

## Flow and sightlines

- **Loops, not dead ends:** boulevard to market alleys and back; boulevard, stairwell, tunnel, stairwell, boulevard; roof loops by bridges and zips.
- **Highways over backroads:** zips and the blimp are fast and exposed; the tunnel and alleys are slow and safe from above.
- **Sightlines:** the boulevard has three offset barrier pairs (longest free run 36 m), the tunnel has pillar pairs (36 m), the rail yard lanes are long by design but broken by islands.
  Free runs are measured per lane in `settings.audit` in the map file (budgets in `tools/blender/maps/canopy.py`).

## Interactivity: three dramatic changes per match

| When | What | Announcement |
|---|---|---|
| 75 s (then every 150 s: up at 75, down at 135) | The canal **drawbridges lift** and stand upright, splitting the flooded zone | DRAWBRIDGES RAISING |
| 150 s (once) | The market hall **skylight collapses**, opening a route from the roof garden to the street | MARKET SKYLIGHTS COLLAPSING |
| 210 s (then returns at 276 s) | The **crane swings a 16 m span** between the site office roof and the tower's top plate | CRANES SWINGING SPANS INTO PLACE |

Always running: **trams** (56 s loop, dwell at each station), the **construction hoist** (40 s loop), the **blimp** (60 s loop, 12 s dwell at each dock).
Everything dynamic is a pure function of the match clock the server broadcasts, so a client needs no extra network traffic, and a restart resets it.

## What was verified (Godot 4.7, headless, with the real physics)

| Check | Result |
|---|---|
| `tests/map_audit.gd` on this map | 38 checks, 0 failures (geometry, clearance, waypoint edges, spawns, capture discs, sightline budgets including the sump, Foundation Line and cellar lanes) |
| `tests/map_walk.gd` | Skyrunner and Enforcer walk 64 routes, 0 failures |
| `tests/verbs_map.gd` | 461 checks, 0 failures: every one of 50 climb lanes tops out onto solid ground, 22 bounce pads reach their apex, 6 zips are ridden both ways and land the hero within 10 m of the far end, 4 grind rails carry the hero the full length, and every tram/hoist/blimp carries a standing hero; both heroes |
| `tests/verbs_test.gd`, `run_tests.gd`, `network_test.gd`, `blockout_import.gd` | pass |
| `match_smoke.gd` on this map | bots leave the depots, contest points and capture them |
| Blender round trip (`tools/blender/test_roundtrip.py`, real Blender 5.0) | 183 objects, 60 waypoints and 37 features survive import and export unchanged |

Greybox tests with the **fastest hero (Skyrunner) and the heaviest (Enforcer)** found and fixed geometry problems rather than hero tuning:
the Enforcer's wider capsule clipped the blimp hull at the spire ladder (blimp docks moved 2 m off the faces), and awnings sat under a roof bridge that cut their launch short.

## Not done yet

- **Hijackable elevators and shutters.** The hoist and tram are on a fixed timeline; letting a team call or hold them needs a small server state.
- **More pickups.** Health packs and the timed items in `scripts/items.gd` (bubble, armor1, armor2) exist (19, hidden in high and secluded spots, listed in `stage_healpacks`; the minimap marks them). Ammo or ability charge pickups at dead ends would follow the same `pickup` feature.
- **Bots only use walk and ramp routes** (stairs, boulevard, alleys, the tunnel, its branches and the sump). They do not use ziplines, ladders, launch pads or the hoist, so the mid and roof tiers (including the Span) are for players.
- Water is a coloured floor; there is no swimming or slowing.
- It has not been play-tested by people. The numbers (bounce power, zip speed, dwell times) are first guesses.

## Rebuilding and testing

```
python3 tools/blender/generate.py tools/blender/maps/canopy.py maps/canopy.blockout.json     # regenerate (or --blend to open in Blender)
cp maps/canopy.blockout.json maps/blockout.json                                              # developer override of the menu choice
godot --headless --fixed-fps 60 --path . --script res://tests/map_audit.gd
godot --headless --fixed-fps 60 --path . --script res://tests/verbs_map.gd
godot --headless --fixed-fps 60 --path . --script res://tests/map_walk.gd
```

In-engine screenshots: `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --script res://tests/render_canopy.gd`
writes `docs/previews/canopy_*.png` (top, iso, street, tunnel, each district, and the three events).
