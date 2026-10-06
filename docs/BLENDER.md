# Blender round trip

Block out maps in Blender, export one JSON file, and the game builds the geometry through `MapBuilder`.
Collision, 0.25 m snapping and the audits all behave as for hand-written layout, because the importer calls the same functions.

```
Blender scene  ->  tools/blender/export_blockout.py  ->  maps/blockout.json  ->  BlockoutImporter  ->  MapBuilder
```

## 1. Set up the scene

- Units: metres. Z is up in Blender; the exporter converts to Godot (Blender `x, y, z` becomes Godot `x, z, -y`).
- Turn on grid snapping at 0.25 m. Model with plain boxes and wedges. Each mesh is exported as its **world-space bounding box**,
  so keep pieces axis-aligned (90 degree rotations are fine; other angles trigger a warning).
- Apply scale on every object (Ctrl+A > Scale) so dimensions are real.

## 2. Tag objects

Put each object in a collection named for its role, or set a `role` custom property
(Object properties > Custom Properties): `walk`, `wall`, `tower`, `cover`, `accent`, `hazard`, `glass`.

| Custom property | Meaning |
|---|---|
| `kind` | `block` (default), `ramp`, `cylinder`, `decor` |
| `tag` | Name shown in audits. Defaults to the object name without `.001` |
| `mirror` | `true` also builds the copy mirrored across x = 0 (west half authored, east half generated) |
| `color` | `#rrggbb` override. Defaults come from the palette |
| `ramp_dir` | Ramps only: `+x`, `-x`, `+z`, `-z` (Godot axes), the direction of ascent |
| `ramp_start`, `ramp_end` | Ramp top heights (Godot y). Defaults: box min y and box max y |
| `ramp_floor` | Ramp base height. Default: box min y |
| `decor_mode` | Decor only: `flush` (default, must touch a solid) or `outside` (beyond the bounds) |

Rules from `MAP.md` still apply: no overlapping blocks, no 0.05-2.0 m gaps between parallel faces, ramps 22 degrees or less.
`tests/map_audit.gd` will tell you when a blockout breaks one.

### Bot waypoints

Add empties to a collection named `waypoints`. The empty's name is the node name, and the `links` custom property lists
neighbours with route tags: `B:blv,C:roof`. Tags are `blv` (boulevard), `roof`, `trn` (trench), `aln` (alley).

## 3. Export

Inside Blender: Scripting tab > Open `tools/blender/export_blockout.py` > Run Script. It writes `blockout.json` next to the `.blend`.
Or headless: `blender -b scene.blend -P tools/blender/export_blockout.py -- maps/blockout.json`.
Warnings (missing role, off-grid, rotated) print to Blender's system console.

## 4. Load it in the game

Copy the file to `maps/blockout.json`. `CivicDividend.build` loads it automatically when it exists.

- `"mode": "add"` (default) layers the blockout on top of the current map. Use it to prototype a new area.
- `"mode": "replace"` skips `MapLayout.build`, so the blockout is the whole map. The exporter writes `add`; edit the file to switch.
  In replace mode the bot graph, spawn positions, capture points and bounds still come from `MapLayout`, so bots will not
  navigate a new layout until the waypoint graph is wired in (see Limits).

`maps/blockout.example.json` shows every kind. Rename it to `blockout.json` to see it in the game.

## Checks

- `python3 -I tools/blender/test_export_blockout.py` tests the Blender-side conversion without Blender.
- `godot --headless --path . --script res://tests/blockout_import.gd` tests the importer.
- `godot --headless --path . --script res://tests/map_audit.gd` audits the map with the blockout loaded.

## Limits and next steps

- Only axis-aligned boxes, wedge ramps and cylinders. Angled walls would need a new `MapBuilder` primitive.
- Waypoints are exported and parsed (`BlockoutImporter.graph`) but `MapGraph` still reads `MapLayout.graph()`.
- Bounds, spawn depots and capture points are not part of the file yet.
- Detailed visual meshes (`.glb`) go in `assets/models/` as described in `assets/README.md`; collision always comes from these blocks.
