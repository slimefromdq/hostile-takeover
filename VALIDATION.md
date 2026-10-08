# Validation

## Yacht Club — 2026-10-08

Verified on Windows with Godot **4.7.2 stable**, Forward+ renders on an NVIDIA RTX 3080. Console binary located at
`C:/Users/lukep/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.

| Check | Result |
|---|---|
| Strict generation / Python navigation | PASS: 573 solids, 98 waypoints, no validation warnings |
| Python kit / export conversion | **13 / 8 tests**, all pass; includes rotational geometry, navigation and settings serialization |
| Behavioral suite on built-in map | **562 checks, 0 failures**, including explicit objective order, map catalog, settings validation and reset/defaults |
| Blockout importer | **137 checks, 0 failures** |
| Yacht Club map audit | **25 checks, 0 failures**: grid, overlaps, clearance, rotational symmetry, spawn slots and cabin sightlines, capture discs, graph and sightline budgets |
| Walking objective routes | **48 routes, 0 failures**, both yachts to all opposing/intermediate objectives; three route families, Shotgun and SMG, no jumps |
| Yacht Club scenarios | **79 checks, 0 failures**: ground and vertical capture exclusion, lethal ocean through protection, server-only elimination, credit/expiry/feed, Explore, yacht loadout changes, both teams' ordered bot paths and final wins, 12 vertical/diagonal walking trials and paired advanced shortcuts |
| Bot match smoke | PASS: ten fighters, seven advancing, center owned, finite motion |
| Two-minute simulated soak | PASS: nodes 1232 / 1259 / 1258 / 1272, zero orphan nodes |
| Host/client, same Yacht Club map | Both PASS: local UDP with 80 ms latency and every fifth motion/snapshot packet dropped; ten-player roster, 972-byte sampled compressed snapshot, loadouts, utilities, projectiles, prediction and recoil |
| Editor import and previews | PASS: top-down, isometric, yacht, lighthouse, interior, shack and underdock rendered and visually inspected |
| Blender scene round trip | **Unavailable**: neither `bpy` nor a Blender executable is installed; pure import/export metadata code is covered where possible, full Blender round trip is not verified here |

Local UDP initially failed inside the sandbox and passed with broader process/network permissions. LAN validation uses
two processes on this machine, not two physical computers. Human playtesting, route fairness under combat and sustained
performance measurements remain unverified. Timings, reproducible commands and reference differences are in
[Yacht Club](docs/YACHT_CLUB.md). The older Linux results below are retained as historical checks.

Godot **4.7.2 stable**, Linux. Headless runs for logic, xvfb with software OpenGL for renders and probes. Everything
below is automated; nothing here replaces human playtesting or measurement on real hardware.

| Check | Command | Result |
|---|---|---|
| Behavioral suite | `--headless --script res://tests/run_tests.gd` | **341 checks, 0 failures**, no script errors (Godot 4.7.2): acquisition rules, loadout tables and packing, movement (jump, double jump, dash, air control, friction, wall kick, mantle, slide, wall run, ledge grab), guns (live TTK for every primary and sidearm, falloff, pellets, role ordering), sidearm swaps (timing, separate magazines, reload cancel, rig, snapshot), character looks (packing, every option builds, snapshot sync), every utility, every melee (damage, reach, arc, backstab, refill, recovery), armor, authority and respawn, kills/deaths, kill feed, scoreboard, minimap, menu, effect cap, sound synthesis, shader pipeline. Movement sections must run on a physics frame (`await physics_frame`) and clear stale floor/coyote state after a teleport (`place`), or `move_and_slide` and coyote time give wrong answers |
| Map audit | `--headless --script res://tests/map_audit.gd` | **26 checks, 0 failures**: containment, no overlaps / z-fighting / wedge or narrow gaps, 0.25 m grid, east-west mirror, waypoint ground and capsule clearance, edge sweeps, flat capture discs, four route families to B and C, sightline budgets, spawn dogleg |
| Walker | `--headless --script res://tests/map_walk.gd` | **64 routes, 0 failures** (Shotgun and SMG move speeds, 4 route families, both depots, every point, no jumping) |
| Bot match | `--headless --fixed-fps 60 --script res://tests/match_smoke.gd` | PASS (10 fighters, bots advance, objective pressure) |
| Movement Course | `--headless --path . --script res://tests/movement_course.gd` | Slide hill, 5 m / 7 m gaps with and without slide-jump, hurdle vaults (Shotgun, SMG), ledge ladder, wall-to-wall corridor. **18 checks, 0 failures** on Godot 4.7.1 (the 7 m gap is crossed plain only through the ledge-grab rescue, a slide-jump lands it outright) |
| Map verbs | `--headless --path . --script res://tests/verbs_test.gd` | **37 checks, 0 failures**: bounce, climb (top-out and kick-off), zipline attach/ride/release, grind rail, elevator ride, tram loop, events, mirror; Shotgun and SMG |
| Blockout importer | `--headless --fixed-fps 60 --script res://tests/blockout_import.gd` | **88 checks, 0 failures**: format, replace-mode settings, catalog and selection, the built-in map dumped by `tools/export_layout.gd` rebuilds exactly (loaded as the active map it passes the full audit and walker) |
| Concrete Canopy | `tests/map_audit.gd`, `map_walk.gd`, `verbs_map.gd` with `maps/blockout.json` set | audit **30/0**, walker **64/0**, verbs **461/0** (every climb lane, bounce pad, cable and mover, holding the Shotgun and the SMG); see `docs/JUNGLE_GYM.md` |
| Overpass District | same, `maps/overpass.blockout.json` | audit **27/0**, walker **64/0** |
| Blender round trip | `python3 tools/blender/test_roundtrip.py` (needs `bpy`) | real Blender 5.0: 183 objects, 60 waypoints, 37 features survive import and export |
| Bot route spread | `tests/bot_routes.gd` | boulevard ~48%, trench ~15%, alleys ~11%, cross streets/lobbies ~9%, roofs ~7% of bot samples |
| Host/client | `tests/network_test.gd` server + client, `--latency-ms=80 --drop-every=5` | PASS after the loadout rework at 10 fighters (compressed snapshot 1103 bytes): loadout assignment, replicated launch pad and cooldown, sidearm swap and back, predicted movement |
| Soak | `--headless --fixed-fps 60 --script res://tests/soak.gd -- minutes=10` | PASS: nodes stayed within 953-1025, zero orphans over ten simulated minutes |
| Render cost | `xvfb-run ... tests/perf_probe.gd` | primitives per frame about 1.33 M -> 0.11-0.13 M after lowering character mesh resolution; peak draw calls about 630-780; 220-node cap on live effects; baked low-poly characters (one mesh per bone): peak draw calls 649 -> 599 and primitives 98 K -> 39 K on the same run |
| Renders | `tests/render_*.gd` | gameplay, HUD, scoreboard, menu, loadout lineup (not re-rendered since the rework), effects and 13 map views regenerated and inspected (`docs/previews/`) |
| In-engine renders | `xvfb-run` with software Vulkan (`mesa-vulkan-drivers`), `tests/render_canopy.gd` | 16 views of Concrete Canopy including the three events (`docs/previews/canopy_*.png`) |
| Startup | `--headless --quit-after 120`, `--check-only` per script | no errors or warnings |

## Character redesign — 2026-10-08

Verified on Windows with Godot 4.7.2 and an NVIDIA RTX 3080:

- Behavioral suite: **346 checks, 0 failures**. New checks cover finite, clockwise, nondegenerate character geometry,
  the mesh/triangle budget, seated slide and standing recovery, aimed weapons, melee poses and material fading.
- Every existing appearance option builds the required bones. Maximum measured across those option tests:
  **13 mesh instances, 4,100 baked triangles** per rig.
- Offline match smoke: **PASS**, 10 fighters, 6 advancing, objective pressure, finite positions/velocities.
- Two-minute soak: **PASS**, node samples 837 / 848 / 838 / 842, **zero orphan nodes**.
- Forward+ lineup, face detail, run/slide/melee poses and menu portrait rendered and visually inspected. The character
  render script also ran successfully with the Compatibility renderer. Editor import completed without errors.
- Short 180-frame Forward+ render probe: peak **618 draw calls**, **145,557 primitives**, zero orphan nodes.
  This is a render-count sample, not a sustained frame-rate benchmark or a comparison to the Linux measurements above.

The geometry adds sculpted profiles and flat face patches while retaining the existing mesh baker, bone paths,
appearance packing, collider and gameplay tuning. See [character design notes](docs/CHARACTERS.md).

## Movement arsenal — 2026-10-08

Verified on Windows with Godot 4.7.2; Forward+ renders used an NVIDIA RTX 3080.

- Editor import: completed without script or resource errors. The runs used a writable workspace profile for
  `APPDATA` and `LOCALAPPDATA`, and absolute engine log paths.
- Behavioral suite: **527 checks, 0 failures**. All fourteen guns build and their live default-fire cadence agrees
  with ideal first-impact TTK within one 60 Hz simulation step. Separate fixtures cover projectile travel delay,
  swept collisions, splash occlusion/falloff, direct-hit deduplication, allies, deployables, cached launch damage,
  self-damage/armor and suicide scoring. Ordinary full-health one-shot damage limits are asserted.
- Weapon movement checks cover floor/wall explosive jumps, double-barrel recoil, speed caps, interrupted movement
  states, cable/climb reattachment prevention, preserved movement resources and single-delivery client impulses.
  Projectile checks cover grenade fuse/arming/detonation, disc bounce limits, input priority, ammo/reload/swap locks,
  spawn budgets, expiry, snapshots and lifecycle cleanup.
- The baseline restart failure is corrected: restart removes combat entities and projectiles, restores fighters,
  and recreates map pickups. The inspected baseline had **346 checks, one failure** on the old assertion.
- Movement Course: **18 checks, 0 failures**. Map verbs: **37 checks, 0 failures**. Walker: **64 routes, 0 failures**.
  Canopy bot tower: **PASS**, power-up collected at 8 seconds, best height 17.1 m. Offline match smoke: **PASS**,
  ten fighters, five advancing, objective pressure and finite positions/velocities.
- LAN server/client with `--latency-ms=80 --drop-every=5`: **PASS**. Covers existing movement/utility/swap behavior,
  appended weapon indices, grenade and disc reconciliation, reliable detonation and recoil launch without duplicate
  impulse delivery. Bots remain in the replicated roster but are held dead in this deterministic fixture so random
  combat cannot interrupt its staged actions. This is a correctness test, not a full-combat bandwidth benchmark.
- Final two-minute soak: **PASS**, node samples **860 / 872 / 882 / 854**, peak **882**, **zero orphan nodes**.
- Complete fourteen-gun lineup rendered and visually inspected in [arsenal.png](docs/previews/arsenal.png).
  Enlarged menu (including its lower scroll position) and HUD rendered and inspected at **1280×720**, **2560×1080**
  and **1024×768** using `tests/render_arsenal.gd` and `tests/render_resolutions.gd`.

Human balance/feel playtests and listening checks for the new synthesized cues remain outstanding. The existing
20 Hz authoritative snapshot model is retained; these tests do not establish production netcode or rollback support.

## What changed on the way (for context)
Two defects were found by looking at real renders and fixed with regression tests: the opaque map shader wrote ALPHA, which
forced every map mesh into the transparent pipeline so walls drew over each other, and character meshes used default
high-resolution primitives (about 540 k triangles for twelve fighters, not re-measured at 5v5).

## Not verified
- Human playtests: feel and balance of the retuned movement (gravity 26, jump 10 m/s, double jump, dash 22 m/s for 0.28 s,
  Source-style air control) on the new map. Roofs and the gallery are now easy to reach.
- Real-hardware 1080p / 60 fps. Software-rendered timings are only comparable run to run.
- Audio quality: sounds are procedural and were only checked for synthesis and error-free playback, not by ear.
- Production netcode (rollback, lag compensation), dedicated server, matchmaking, progression, persistence.
