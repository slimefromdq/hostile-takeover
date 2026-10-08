# Blender round trip

Block out maps in Blender (or generate them from a Python script), export one JSON file, and the game builds the
geometry through `MapBuilder`. Collision, 0.25 m snapping and the audits behave as for hand-written layout, because the
importer calls the same functions.

```
 generator script ──► blockout_kit ──┐
                                      ├──► maps/blockout.json ──► BlockoutImporter ──► MapBuilder / bots / HUD
 Blender scene ──► export_blockout ───┘            ▲
        ▲                                          │
        └── import_blockout ◄── JSON      tools/export_layout.gd dumps the built-in map
```

## Three ways to author

### A. Generate with Python (automated, no Blender needed)

`tools/blender/blockout_kit.py` is a small builder API whose argument order matches `MapBuilder`. Write a generator
script with `build(b)` and run it:

```
python3 tools/blender/generate.py tools/blender/maps/yard.py maps/blockout.json
python3 tools/blender/generate.py tools/blender/maps/yard.py maps/blockout.json --blend yard.blend   # also open it in Blender
```

`maps/yard.py` is a complete small replace-mode map (five points, two depots, cover, a raised deck). The kit has
`block`, `ramp`, `stairs` (a ramp that flips when you go down), `cylinder`, `decor`, `room` (four walls with doorways and
lintels), `waypoint` and `configure`. `generate.py` prints validation warnings (ramp slopes over 22 degrees, interpenetrating
solids, missing waypoints, replace-mode requirements); `--strict` makes them fail. This is the fastest way to have an AI
or a script lay out a map: describe it in a generator file, run it, look at it in Blender, tweak by hand if you like.

### B. Edit in Blender

`blender -b -P tools/blender/import_blockout.py -- maps/blockout.json scene.blend` builds a scene from any blockout JSON
(including generated ones and the built-in map, see C). Edit it, then export with Scripting tab > Run `export_blockout.py`
or `blender -b scene.blend -P tools/blender/export_blockout.py -- maps/blockout.json`.

- Units in metres, Z up. The exporter converts (Blender `x, y, z` becomes Godot `x, z, -y`).
- Each mesh exports as its **world-space bounding box**: keep pieces axis-aligned (90 degree turns are fine) and snap to 0.25 m.
- Role = collection name or `role` property: `walk`, `wall`, `tower`, `cover`, `accent`, `hazard`, `glass`.
- Mirrored objects show a wireframe preview in `_MirrorPreview` (never exported).

| Object property | Meaning |
|---|---|
| `kind` | `block` (default), `ramp`, `cylinder`, `decor` |
| `tag` | Name in audits. Defaults to the object name without `.001` |
| `mirror` | `true` also builds the copy mirrored across x = 0 (author the west half) |
| `color` | `#rrggbb` override |
| `ramp_dir` | `+x`, `-x`, `+z`, `-z` (Godot axes), direction of ascent |
| `ramp_start`, `ramp_end`, `ramp_floor` | Top heights and base height in Godot y (defaults from the box) |
| `decor_mode` | `flush` (default, must touch a solid) or `outside` (beyond the bounds) |

Waypoints are empties in a collection named `waypoints`; the empty's name is the node name. Properties: `links`
(`B:blv,C:roof`; tags `blv`, `roof`, `trn`, `aln`, or any name), `mirror`, `point` (capture point), `spawn` (depot node).

Map settings are **scene** custom properties: `ht_mode` (`add` or `replace`), `ht_bounds` (x, z, width, height),
`ht_spawn_x`, `ht_spawn_z`, `ht_spawn_step`, `ht_depot_limit`, `ht_test_lane`.

### C. Start from the built-in map

```
godot --headless --path . --script res://tools/export_layout.gd -- maps/layout.blockout.json
blender -b -P tools/blender/import_blockout.py -- maps/layout.blockout.json layout.blend
```

The dump keeps mirrored pieces as one object with `mirror: true`, so editing the west half in Blender updates both
sides. With `maps/layout.blockout.json` present, `tests/blockout_import.gd` also checks that it rebuilds the built-in map
exactly (same solids, decor, capture points and graph).

## Loading it in the game

Copy the file to `maps/blockout.json`; `CivicDividend.build` loads it automatically when it exists (delete it to go
back to the built-in map).

- `"mode": "add"` layers the blockout on top of the built-in map. Use it to prototype a new area.
- `"mode": "replace"` skips `MapLayout.build` and takes everything else from the file:
  - **Bounds**, `spawn_x/z/step` (ten spawn slots per team (two rows of five) at x = -spawn_x and +spawn_x), `depot_limit` (spawn protection
    ends beyond it), `test_lane` (defaults to the middle capture point).
  - **Capture points**: waypoints with `point`; mirrored ones count twice. Exactly five are required and they are ordered
    west to east (Helix owns the west end), so the usual shape is A and B mirrored plus C on x = 0.
  - **Spawn nodes**: exactly two (a mirrored `spawn` waypoint), where bots start planning routes.
  - **Bot graph**: every waypoint and link; bots walk from the depot to the points along it. Bots only use walk and
    ramp edges, so every waypoint must sit on ground.
  - If anything required is missing, the game logs why and **falls back to the built-in map** instead of starting broken.
  - Hardcoded wall signs are skipped in replace mode.
- A walk floor whose top is below -1 m is treated as sunken (a trench) for the minimap.

## Maps in the repo

| File | What it is |
|---|---|
| `tools/blender/maps/yard.py` | Small test map (replace mode) used by the round-trip test |
| `tools/blender/maps/canopy.py` | **Concrete Canopy**: the jungle gym (`docs/JUNGLE_GYM.md`), 192 x 128 m, four tiers, five districts, climb/bounce/cable/mover verbs and three timed events |
| `tools/blender/maps/overpass.py` | **Overpass District**: a full 164 x 96 m replace-mode map built from the reference set. Highway deck with gas stations over a service lane, terraced park with plazas and a bridge, offset barrier chicanes on the boulevard |
| `maps/*.blockout.json` | Generated output. Maps with a `title` appear in the start menu (**Map: ... click to switch**); copying one to `maps/blockout.json` overrides the menu |

`python3 tools/blender/blockout_check.py maps/overpass.blockout.json` checks navigation (waypoint ground and clearance,
walkable edges, depot reachability, spawns, capture discs) in seconds without Godot. `tests/map_audit.gd` stays the authority.

## Map features, titles and the audit profile

Besides geometry a blockout can carry `features` (the traversal verbs of `scripts/map_verbs.gd`), a `title` and extra settings.
The kit exposes them as `b.bounce`, `b.climb`, `b.cable`, `b.mover`, `b.event`, `b.audit` and `b.configure(ceiling=...)`;
`TITLE = "..."` in a generator script names the map. Features and the audit profile are stored on the Blender scene as JSON
(`ht_features`, `ht_audit`) and written back unchanged by the exporter.

- `climb` takes a `face` (the direction you look to climb); each lane draws its own ladder.
- `mover` keys are `(seconds, (x, y, z), (rx, ry, rz) optional)`; `period > 0` loops. Mirrored movers reflect position and yaw/roll.
- `settings.audit` gives the audit its own sightline lanes (`azimuths` `along`, `across` or `ns`), route families and spawn-sight
  targets, so a new map is judged by its own layout instead of the built-in map's.
- `settings.ceiling` raises the kill height (default 40 m) for tall landmarks.

`tests/verbs_map.gd` drives every feature of the active map holding the slowest (Shotgun) and fastest (SMG) primary: climb lanes must top out onto solid ground,
bounce pads reach their apex, cables catch and land within 10 m of the far end, movers carry a rider.

## Previewing without Godot

`python3 tools/blender/preview_plan.py maps/blockout.json docs/previews/blockout` (needs `pip install matplotlib`) draws a
top-down plan (solids, capture radii, bot graph) and an isometric view. `docs/previews/yard_plan.png` is the Test Yard.

## Checks

- `python3 -I tools/blender/test_export_blockout.py` and `python3 -I tools/blender/test_blockout_kit.py`: no Blender needed.
- `python3 -I tools/blender/test_roundtrip.py`: generates the yard, imports it into Blender, exports it and compares
  (needs the `bpy` module: `pip install bpy`, or run it with `blender -b -P`). Skips when Blender is missing.
- `godot --headless --path . --script res://tests/blockout_import.gd`: importer, yard replace settings, malformed input.
- With a blockout loaded, `tests/map_audit.gd` and `tests/map_walk.gd` audit that map. The audit still contains some
  expectations from the built-in map (four route families from the depot to each point, sightline budgets), so a simple map
  can fail those without being broken. The geometry, clearance, spawn and capture-disc checks apply to any map.

## Limits

- Only axis-aligned boxes, wedge ramps (22 degrees or less) and cylinders. Angled walls need a new `MapBuilder` primitive.
- Five capture points and two teams are fixed by the game.
- Detailed visual meshes (`.glb`) go in `assets/models/` as described in `assets/README.md`; collision always comes from these blocks.
