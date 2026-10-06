# Validation

Godot **4.7.2 stable**, Linux. Headless runs for logic, xvfb with software OpenGL for renders and probes. Everything
below is automated; nothing here replaces human playtesting or measurement on real hardware.

| Check | Command | Result |
|---|---|---|
| Behavioral suite | `--headless --script res://tests/run_tests.gd` | **106 checks, 0 failures**: acquisition rules, class specs and TTK, movement (jump, double jump, dash, air control, friction, wall kick, mantle, slide), weapons, abilities, deployables, authority and respawn, kills/deaths, kill feed, scoreboard, minimap, menu, effect cap, sound synthesis, shader pipeline |
| Map audit | `--headless --script res://tests/map_audit.gd` | **26 checks, 0 failures**: containment, no overlaps / z-fighting / wedge or narrow gaps, 0.25 m grid, east-west mirror, waypoint ground and capsule clearance, edge sweeps, flat capture discs, four route families to B and C, sightline budgets, spawn dogleg |
| Walker | `--headless --script res://tests/map_walk.gd` | **64 routes, 0 failures** (Skyrunner and Enforcer, 4 route families, both depots, every point, no jumping) |
| Bot match | `--headless --fixed-fps 60 --script res://tests/match_smoke.gd` | PASS (12 fighters, bots advance, objective pressure) |
| Bot route spread | `tests/bot_routes.gd` | boulevard ~48%, trench ~15%, alleys ~11%, cross streets/lobbies ~9%, roofs ~7% of bot samples |
| Host/client | `tests/network_test.gd` server + client, `--latency-ms=80 --drop-every=5` | PASS; compressed twelve-fighter snapshot about 1.2 KB |
| Soak | `--headless --fixed-fps 60 --script res://tests/soak.gd -- minutes=10` | PASS: nodes stayed within 953-1025, zero orphans over ten simulated minutes |
| Render cost | `xvfb-run ... tests/perf_probe.gd` | primitives per frame about 1.33 M -> 0.11-0.13 M after lowering character mesh resolution; peak draw calls about 630-780; 220-node cap on live effects |
| Renders | `tests/render_*.gd` | gameplay, HUD, scoreboard, menu, class lineup, effects and 13 map views regenerated and inspected (`docs/previews/`) |
| Startup | `--headless --quit-after 120`, `--check-only` per script | no errors or warnings |

## What changed on the way (for context)
Two defects were found by looking at real renders and fixed with regression tests: the opaque map shader wrote ALPHA, which
forced every map mesh into the transparent pipeline so walls drew over each other, and character meshes used default
high-resolution primitives (about 540 k triangles for twelve fighters).

## Not verified
- Human playtests: feel and balance of the retuned movement (gravity 26, jump 10 m/s, double jump, dash 22 m/s for 0.28 s,
  Source-style air control) on the new map. Roofs and the gallery are now easy to reach.
- Real-hardware 1080p / 60 fps. Software-rendered timings are only comparable run to run.
- Audio quality: sounds are procedural and were only checked for synthesis and error-free playback, not by ear.
- Production netcode (rollback, lag compensation), dedicated server, matchmaking, progression, persistence.
