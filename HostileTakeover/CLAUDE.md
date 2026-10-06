# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The Godot project lives in `HostileTakeover/` (the repo root only contains that folder). All paths and commands below are relative to it.

## What this is

"Hostile Takeover": a Godot **4.7.x** (GL Compatibility) GDScript graybox prototype — four fighter classes, five-point "Acquisition" objective, offline 6v6 bots, LAN host/join. No plugins or external assets required; art, map and sound are generated in code. `README.md` has controls, class kits and balance numbers; `MAP.md` has map design and geometry rules; `VALIDATION.md` lists what the automated checks cover.

## Running and testing

Open `project.godot` in Godot 4.7.x (F5 runs `scenes/main.tscn`). There is no build step or linter; tests are standalone `SceneTree` scripts run headless (`godot` = your Godot 4.7 console binary):

```
godot --headless --path . --script res://tests/run_tests.gd        # behavioral suite (acquisition, specs/TTK, movement, weapons, abilities, authority, HUD...)
godot --headless --path . --script res://tests/map_audit.gd        # geometry / clearance / route / sightline audit
godot --headless --path . --script res://tests/map_walk.gd         # real Fighter walks every route from both depots
godot --headless --fixed-fps 60 --script res://tests/match_smoke.gd
godot --headless --fixed-fps 60 --script res://tests/soak.gd -- minutes=10   # node/orphan leak check
# network: start the server first, then the client (separate terminals)
godot --headless --path . --script res://tests/network_test.gd -- --server --latency-ms=80 --drop-every=5
godot --headless --path . --script res://tests/network_test.gd -- --latency-ms=80 --drop-every=5
```

- There is no single-test runner: `tests/run_tests.gd` is one `run()` calling `test_*` functions with a `check(cond, msg)` helper; comment out calls or add a new `test_*` function to isolate.
- `tests/render_*.gd` and `tests/perf_probe.gd` need a display (`xvfb-run` with software GL); renders write into `docs/previews/` (which has a `.gdignore`).
- Open the project in the editor once after adding assets so `.import` files exist; headless runs need them. `.uid` files are committed alongside scripts.

## Architecture

- **`scripts/game.gd` (main scene root, ~1100 lines) is the hub**: lobby/start, networking, input submission, snapshot encode/decode, combat (`fire_ray`, `damage_fighter`, `activate` for every class ability), deployable entities, objective ticking, bot AI, and HUD/FX plumbing. Look here first for almost any gameplay change.
- **Server-authoritative model**: the host (or offline player, `authoritative = true`) simulates everything. Clients send inputs/actions via RPCs (`submit_input` unreliable, `submit_actions` reliable) and receive compressed world snapshots (`snapshot` / `initial_sync`); effects go out as `authority` RPCs (`trace_visual`, `ring_visual`, `kill_feed`...). Clients predict local movement with snapshot correction and interpolate remotes. Bots fill to 12 fighters and are replaced by joining players. Port is UDP 27847; the `--latency-ms`/`--drop-every` flags are test-only network simulation.
- **Fighters**: `scripts/fighter.gd` holds momentum-based Source-style movement (jump, double jump/dash sharing one charge, wall kick, mantle, slide, sprint). Per-class data lives in `resources/*.tres` (typed by `class_spec.gd`); `scenes/<class>.tscn` instances the shared `fighter.tscn`. TTK numbers in README are asserted by tests — retuning a spec usually requires updating `run_tests.gd`.
- **Objective**: `acquisition.gd` is a pure rules object (A–B–C–D–E, capture times, contest/decay, overtime) with no scene dependencies; `civic_dividend.gd` ties it to the map.
- **Map**: data in `map_layout.gd` (authored for the west half, mirrored across x=0), built **only** through `MapBuilder` (`map_builder.gd`), which snaps to a 0.25 m grid and makes mesh and collider share dimensions. `map_graph.gd` is the waypoint graph for bots. `tests/map_audit.gd` enforces the geometry rules listed in `MAP.md`; run it after any layout change. Authoritative out-of-bounds kill lives in `game.gd` (`out_of_bounds`).
- **Visuals/audio are procedural**: `visuals.gd`, `character_rig.gd`, `vfx.gd` (pooled, capped at 220 live effect nodes), `sfx.gd` (synthesized sound), `hud.gd`/`minimap.gd`/`menu.gd`. `asset_library.gd` swaps in authored `.glb`/texture files from `assets/` when present (naming in `assets/README.md`); collision still comes from `MapBuilder`, never from imported meshes.
- **Test fixtures**: `tests/proving_ground.gd` builds an open floor, crate, wall and block at z=300, far outside the real map, so movement/weapon tests don't depend on map geometry.
