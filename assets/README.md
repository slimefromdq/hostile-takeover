# Authored assets (Blender MCP drop-in folder)

The game builds everything procedurally. Anything placed here replaces the matching
procedural stand-in automatically; nothing needs code changes. Lookups go through
`scripts/asset_library.gd`.

## Layout and names

| Path | Used for |
|---|---|
| `models/characters/operative.glb` | The shared fighter body rig (every fighter uses it) |
| `models/deployables/<kind>.glb` | `turret` (Sentry Turret), `pad` (Launch Pad), `cover` (Barricade), `smoke` |
| `textures/icon_utility_<id>.png`, `icon_melee_<id>.png` | HUD item icons; ids are the `Loadout.Utility` / `Loadout.Melee` order |
| `models/props/<name>.glb` | Map dressing (vehicles, lamps, kiosks, signs) |
| `models/buildings/<name>.glb` | Tower and building shells |
| `textures/<role>_albedo.png` | Surface texture for a map role: `walk`, `wall`, `tower`, `cover`, `glass`, `accent`, `hazard` |

## Export rules (Blender)

- Format: glTF binary (`.glb`), Y-up, metres, origin at the feet / base centre, facing -Z (Godot forward).
- Characters: about 1.9 m tall, capsule radius 0.42 m. Collision is separate and unchanged, so meshes only need to look right.
- Optional named empties in a character: `Muzzle` (weapon tip), `Head` (nameplate anchor), `TeamTint` (meshes whose material should take the team colour).
- Textures: power-of-two, tileable, one metre per tile for surface roles.
- Open the project in the Godot editor once after adding files so `.import` files are generated; headless runs need them.
