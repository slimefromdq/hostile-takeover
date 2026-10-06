# Validation

Godot **4.7.2 stable**, Linux. Headless runs for logic, xvfb with software OpenGL for renders and probes. Everything
below is automated; nothing here replaces human playtesting or measurement on real hardware.

| Check | Command | Result |
|---|---|---|
| Behavioral suite | `--headless --script res://tests/run_tests.gd` | **109 checks, 0 failures**: acquisition rules, class specs and TTK, movement (jump, double jump, dash, air control, friction, wall kick, mantle, slide), weapons (Signature and the three shared guns, falloff, pellets, loadout sync), abilities, deployables, authority and respawn, kills/deaths, kill feed, scoreboard, minimap, menu, effect cap, sound synthesis, shader pipeline |
| Map audit | `--headless --script res://tests/map_audit.gd` | **26 checks, 0 failures**: containment, no overlaps / z-fighting / wedge or narrow gaps, 0.25 m grid, east-west mirror, waypoint ground and capsule clearance, edge sweeps, flat capture discs, four route families to B and C, sightline budgets, spawn dogleg |
| Walker | `--headless --script res://tests/map_walk.gd` | **64 routes, 0 failures** (Skyrunner and Enforcer, 4 route families, both depots, every point, no jumping) |
| Bot match | `--headless --fixed-fps 60 --script res://tests/match_smoke.gd` | PASS (20 fighters, bots advance, objective pressure) |
| Map verbs | `--headless --path . --script res://tests/verbs_test.gd` | **37 checks, 0 failures**: bounce, climb (top-out and kick-off), zipline attach/ride/release, grind rail, elevator ride, tram loop, events, mirror; Skyrunner and Enforcer |
| Blockout importer | `--headless --fixed-fps 60 --script res://tests/blockout_import.gd` | **88 checks, 0 failures**: format, replace-mode settings, catalog and selection, the built-in map dumped by `tools/export_layout.gd` rebuilds exactly (loaded as the active map it passes the full audit and walker) |
| Concrete Canopy | `tests/map_audit.gd`, `map_walk.gd`, `verbs_map.gd` with `maps/blockout.json` set | audit **30/0**, walker **64/0**, verbs **333/0** (every climb lane, bounce pad, cable and mover, both heroes); see `docs/JUNGLE_GYM.md` |
| Overpass District | same, `maps/overpass.blockout.json` | audit **27/0**, walker **64/0** |
| Blender round trip | `python3 tools/blender/test_roundtrip.py` (needs `bpy`) | real Blender 5.0: 183 objects, 60 waypoints, 37 features survive import and export |
| Bot route spread | `tests/bot_routes.gd` | boulevard ~48%, trench ~15%, alleys ~11%, cross streets/lobbies ~9%, roofs ~7% of bot samples |
| Host/client | `tests/network_test.gd` server + client, `--latency-ms=80 --drop-every=5` | PASS at 12 fighters (snapshot about 1.2 KB); 10v10 snapshot size not yet re-measured |
| Soak | `--headless --fixed-fps 60 --script res://tests/soak.gd -- minutes=10` | PASS: nodes stayed within 953-1025, zero orphans over ten simulated minutes |
| Render cost | `xvfb-run ... tests/perf_probe.gd` | primitives per frame about 1.33 M -> 0.11-0.13 M after lowering character mesh resolution; peak draw calls about 630-780; 220-node cap on live effects |
| Renders | `tests/render_*.gd` | gameplay, HUD, scoreboard, menu, class lineup, effects and 13 map views regenerated and inspected (`docs/previews/`) |
| In-engine renders | `xvfb-run` with software Vulkan (`mesa-vulkan-drivers`), `tests/render_canopy.gd` | 16 views of Concrete Canopy including the three events (`docs/previews/canopy_*.png`) |
| Startup | `--headless --quit-after 120`, `--check-only` per script | no errors or warnings |

## What changed on the way (for context)
Two defects were found by looking at real renders and fixed with regression tests: the opaque map shader wrote ALPHA, which
forced every map mesh into the transparent pipeline so walls drew over each other, and character meshes used default
high-resolution primitives (about 540 k triangles for twelve fighters, not re-measured at 10v10).

## Not verified
- Human playtests: feel and balance of the retuned movement (gravity 26, jump 10 m/s, double jump, dash 22 m/s for 0.28 s,
  Source-style air control) on the new map. Roofs and the gallery are now easy to reach.
- Real-hardware 1080p / 60 fps. Software-rendered timings are only comparable run to run.
- Audio quality: sounds are procedural and were only checked for synthesis and error-free playback, not by ear.
- Production netcode (rollback, lag compensation), dedicated server, matchmaking, progression, persistence.
