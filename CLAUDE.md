# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The Godot project is the repo root (`project.godot` is at the top level). All paths and commands below are relative to it.

## Git workflow (owner's standing rule)

The owner only uses GitHub to continue work across devices. Commit and push every change **directly to `main`**. Do not create
branches or pull requests, and do not wait for a merge. Before starting, `git pull origin main`; after finishing, push to `main`.
If a session was handed a feature branch to develop on, this rule overrides it. Never commit conflict markers: resolve merges
before committing (a stray `<<<<<<<` in `project.godot` once made Godot report the project as missing).

## What this is

"Hostile Takeover": a Godot **4.7.x** (Forward+) GDScript graybox prototype — four fighter classes plus the Gunblade hero (Reave), five-point "Acquisition" objective, offline 5v5 bots, LAN host/join. No plugins or external assets required; art, map and sound are generated in code. `README.md` has controls, class kits and balance numbers; `MAP.md` has map design and geometry rules; `VALIDATION.md` lists what the automated checks cover.

## Running and testing

Open `project.godot` in Godot 4.7.x (F5 runs `scenes/main.tscn`). There is no build step or linter; tests are standalone `SceneTree` scripts run headless (`godot` = your Godot 4.7 console binary):

```
godot --headless --path . --script res://tests/run_tests.gd        # behavioral suite (acquisition, specs/TTK, movement, weapons, abilities, authority, HUD...)
godot --headless --path . --script res://tests/map_audit.gd        # geometry / clearance / route / sightline audit
godot --headless --path . --script res://tests/map_walk.gd         # real Fighter walks every route from both depots
godot --headless --path . --script res://tests/verbs_test.gd             # map verbs with Skyrunner and Enforcer
godot --headless --path . --script res://tests/movement_course.gd        # real Fighters on every Movement Course station (docs/MOVEMENT_COURSE.md)
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
- **Server-authoritative model**: the host (or offline player, `authoritative = true`) simulates everything. Clients send inputs/actions via RPCs (`submit_input` unreliable, `submit_actions` reliable) and receive compressed world snapshots (`snapshot` / `initial_sync`); effects go out as `authority` RPCs (`trace_visual`, `ring_visual`, `kill_feed`...). Clients predict local movement with snapshot correction and interpolate remotes. Bots fill to 10 fighters (`CivicDividend.TEAM_SIZE` per team) and are replaced by joining players; bot roles (attack/roam/defend) live in `game.gd`. Port is UDP 27847; the `--latency-ms`/`--drop-every` flags are test-only network simulation.
- **Fighters**: `scripts/fighter.gd` holds momentum-based Source-style movement (jump with coyote time and buffering, double jump, air dash, wall kick, slide and slide-jump, wall run, vault/ledge grab/mantle, sprint). Each verb is a small helper (`_update_slide_state`, `_try_jump`, `_update_wall_run`, `_ledge_step`...) with its tuning constants at the top of the file; `docs/MOVEMENT_COURSE.md` describes the sandbox map for trying them. Per-class data lives in `resources/*.tres` (typed by `class_spec.gd`); `scenes/<class>.tscn` instances the shared `fighter.tscn`. TTK numbers in README are asserted by tests — retuning a spec usually requires updating `run_tests.gd`.
- **Heroes and armor**: fighters are heroes, not classes (`docs/HEROES.md`): a shared movement language and light armor dropped by kills (`Game.drop_armor`, an `armor` entity picked up by the killer's team), with ultimates on X running on a per-hero cooldown, but each hero chooses its own weapon, ability count (0-3 plus an optional ultimate), alternate fire and resource. Reave (class 4) is the reference hero; her guard interception lives in `Game.damage_fighter` and her ultimate is `scripts/pyre_edge.gd`.
- **Objective**: `acquisition.gd` is a pure rules object (A–B–C–D–E, capture times, contest/decay, overtime) with no scene dependencies; `civic_dividend.gd` ties it to the map.
- **Map**: data in `map_layout.gd` (authored for the west half, mirrored across x=0), built **only** through `MapBuilder` (`map_builder.gd`), which snaps to a 0.25 m grid and makes mesh and collider share dimensions. `map_graph.gd` is the waypoint graph for bots. `tests/map_audit.gd` enforces the geometry rules listed in `MAP.md`; run it after any layout change. Authoritative out-of-bounds kill lives in `game.gd` (`out_of_bounds`).
- **Map verbs and blockouts**: `scripts/map_verbs.gd` implements map-placed traversal (bounce, climb, cables, keyframed movers, timed events) from a blockout's `features`, called from `Fighter.simulate_movement` (`pre_move`/`zip_move`/`post_move`) and driven by `game.map_clock`, which the server broadcasts in snapshots. `scripts/blockout_importer.gd` loads blockout JSON (`maps/*.blockout.json`, made by `tools/blender/generate.py` or Blender); "replace" mode takes bounds, spawns, points, the bot graph and an audit profile from the file. The start menu lists titled maps; `maps/blockout.json` overrides the choice for development. See `docs/BLENDER.md` and `docs/JUNGLE_GYM.md`.
- **Visuals/audio are procedural**: `visuals.gd`, `character_rig.gd`, `vfx.gd` (pooled, capped at 220 live effect nodes), `sfx.gd` (synthesized sound), `hud.gd`/`minimap.gd`/`menu.gd`. `asset_library.gd` swaps in authored `.glb`/texture files from `assets/` when present (naming in `assets/README.md`); collision still comes from `MapBuilder`, never from imported meshes.
- **Test fixtures**: `tests/proving_ground.gd` builds an open floor, crate, wall and block at z=300, far outside the real map, so movement/weapon tests don't depend on map geometry.
