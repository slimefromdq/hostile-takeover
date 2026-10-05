# Validation — October 5, 2026

Tested with Godot **4.7.2 stable**, Windows, compatibility renderer.

| Check | Result |
|---|---|
| Behavioral suite | **82 checks passed**, zero failures or runtime errors |
| Host/client integration | Both processes passed with 80 ms outgoing delay on each side and every fifth unreliable motion/state packet dropped |
| Network behaviors | Human replaces bot; twelve-player roster; class assignment; reliable double deployment; one-use swap; authoritative relocation and teleport correction; predicted movement |
| Packet size | Compressed twelve-fighter snapshot measured **897 bytes** in the final network test |
| Two-minute simulated match | Passed: twelve valid fighters, ten bots advanced out of spawn, center acquired, valid frontier |
| Render verification | OpenGL 3.3 on Intel Arc; gameplay screenshot saved and inspected; no rendering errors |

Live authoritative body-shot measurements against 200 HP:

- Skyrunner: **2.083 seconds**.
- Mirage Agent: **2.250 seconds**.
- Field Engineer: **2.800 seconds**.
- Enforcer: **2.600 seconds**, excluding its initial spin-up.

The behavioral suite covers capture progression and counterpushes, locks, both final-point victories, contested capture, decay, overtime, simultaneous opposing captures, reload-aware damage timing, primary hits, friendly-fire exclusion, automatic sprint, air dash, all-class wall kicks, sliding, mantling, double exchange and obstruction, double destruction and expiry, objective exclusion, concealment, turret arcs and repair, shared launch pads, Enforcer passive triggers, server authority, respawn, class changes, stale-snapshot rejection, and round restart.

Run the bot-match check with:

```powershell
& 'path\to\godot_console.exe' --headless --fixed-fps 60 --path . --script res://tests/match_smoke.gd
```

`--fixed-fps` accelerates the simulation without establishing real rendered performance. **Human playtests, final balance, production networking, and the 1080p/60-fps target remain unverified.**


# Validation addendum - Phases 1-5 (visual, HUD and map overhaul)

Godot 4.7.2 stable, Linux, headless plus xvfb/llvmpipe renders. These are automated checks only.

| Check | Result |
|---|---|
| Behavioral suite (`run_tests.gd`) | **103 checks passed**, zero failures (82 original + kills/deaths, kill feed, scoreboard, minimap, menu, new air movement, render pipeline) |
| Map audit (`map_audit.gd`) | **26 checks passed**: bounds, no overlaps/z-fighting/wedge gaps/narrow gaps, 0.25 m grid, mirror symmetry, waypoint ground and capsule clearance, edge sweeps, flat capture discs, 4 route families to B and C, sightline budgets, spawn dogleg |
| Walker (`map_walk.gd`) | **64 routes walked, 0 failures** (Skyrunner and Enforcer, 4 route families, both depots, all points) |
| Bot match (`match_smoke.gd`) | PASS, 11 of 12 fighters advanced; bots spread over boulevard, trench, alleys and roofs (`bot_routes.gd`) |
| Host/client (`network_test.gd`, 80 ms, drop every 5th) | PASS; compressed twelve-fighter snapshot about 1.2 KB (includes kills/deaths) |
| Renders | Gameplay, HUD, scoreboard, menu, class lineup, effects and 13 map views inspected under xvfb (`docs/previews/`) |

Measured map sightlines (free head-height run, lane-aligned): boulevard median 10 m, p90 26 m, max 57 m; trench max 46 m;
alleys max 40 m; roofs max 58 m. No capture point sees a point two or more steps away.

Not verified: human playtests, balance on the new map, and the 1080p/60 fps target on reference hardware. Software
rendering here says nothing about real frame rates.

Follow-up fixes: the map surface shader no longer writes ALPHA (it forced every map mesh into the transparent
pipeline, so walls drew over each other; a regression check guards this), and movement was retuned (gravity 26,
jump 10 m/s, double jump, dash 22 m/s for 0.28 s, wall kick 10.5 m/s up, mantle to about 2.6 m, Source-style
air control and ground friction). Feel and balance of the new movement still need human playtests.
