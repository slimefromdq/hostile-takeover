# AGENTS.md: guide for AI agents (ChatGPT, Codex, Claude and others)

Read this before changing anything. It covers what the game is, how the code fits together, and how to add to it
**without rewriting existing systems**. More detail is in `CLAUDE.md` (commands and architecture), `README.md` (player-facing rules and
numbers), `docs/LOADOUTS.md`, `MAP.md`, `docs/JUNGLE_GYM.md`, `docs/BLENDER.md` and `VALIDATION.md`.

## 1. What the game is

**Hostile Takeover** is a Godot **4.7.x** (Forward+) GDScript graybox prototype of a team arena shooter.

- **One shared body, Splatoon-style loadouts.** There are no heroes, classes or ultimates. Every fighter has 200 HP
  (`Fighter.MAX_HEALTH`), the same hitbox and the full movement set. A loadout is four picks: **primary** (Shotgun,
  Rifle, SMG), **sidearm** (Pistol, Burst Pistol, Revolver; quick swap, own magazine), **utility on Q** (Grapple, Frag,
  Smoke, Launch Pad, Sentry Turret, Barricade, Breach Charge) and **melee on F** (Knife, Sledgehammer, Sword).
- **Character look (cosmetic).** In the start menu's LOOK tab you pick build, skin, eyes, hairstyle and hair colour,
  headgear, top, bottoms, shoes and garment colours. The look is drawn as a squat low-poly person, and team colour shows
  as trim.
- **Mode: Acquisition.** There are five points, A–B–C–D–E. C opens first. Capturing a point unlocks the next one toward
  the enemy, and taking the enemy's final point wins. Points are contested, decay when abandoned, and the match goes to
  overtime.
- **5v5** (`CivicDividend.TEAM_SIZE = 5`). Bots fill empty slots (attack/roam/defend roles) and joining humans replace
  them. **Offline**, **Explore** (free roam) and **LAN host/join** (UDP 27847, server-authoritative) are all supported.
- **Momentum movement** in the Source tradition: coyote-time jump, double jump, air dash, wall kick, slide and
  slide-jump, wall run, vault, ledge grab and mantle. Maps add more verbs: bounce pads, ladders, ziplines, moving
  platforms and timed events.
- **Pickups:** hidden health packs; timed bubbles and armor (Canopy map); kill-drop armor; and a power-up (invincibility
  or triple damage, 12 s). On Concrete Canopy the power-up sits on the booth over point C.
- **Maps:** the built-in Civic Dividend, plus blockout maps in `maps/*.blockout.json` (Concrete Canopy, Overpass, Yard,
  Movement Course), picked in the start menu.
- **Everything is procedural.** Art, map, sound and UI are generated in code. No plugins or external assets are required;
  optional `.glb` and texture overrides go in `assets/` (`assets/README.md`).

## 2. How the code works

The project root is the Godot project (`project.godot`). The main scene is `scenes/main.tscn`, whose root runs `scripts/game.gd`.

| File | Role |
|---|---|
| `scripts/game.gd` | **The hub.** Lobby and start, networking RPCs, input submission, snapshot encode/decode, combat (`fire_ray`, `damage_fighter`, `hit_fighter`, `use_utility`, `use_melee`), entities (deployables and pickups), objective ticking, bot AI (`bot_*`, `choose_bot_item`, `bot_kit`), HUD/FX plumbing. Start here for most gameplay changes. |
| `scripts/fighter.gd` | One `CharacterBody3D` per fighter. Movement verbs are small helpers whose tuning constants sit at the top of the file. Also holds loadout state (`equip`, `apply_loadout`, `swap_weapon`), look (`set_look`), `pack()` / `unpack()` for snapshots, and the rig and nameplate. |
| `scripts/loadout.gd` | Pure data: the gun tables (`resources/weapons/*.tres`, typed by `weapon_spec.gd`), the `UTILITIES` and `MELEES` dictionaries, and `encode` / `decode` of a loadout into one int (4 bits per slot). |
| `scripts/appearance.gd` | Pure data: character-creator option tables, plus `encode` / `decode` of a look into one int (clamped, so network-safe), and save/load to `user://settings.cfg`. |
| `scripts/character_rig.gd` | Builds the fighter model from a look and loadout. Box and prism parts are baked into one vertex-coloured mesh per bone. Procedural animation is in `animate()`. **Bone names are a contract:** `Legs/LegL`, `Legs/LegR`, `Body/Head`, `Body/ArmL/Melee`, `Body/Weapon/{Primary,Sidearm}`. |
| `scripts/items.gd` | Pickup kinds (`KINDS`: heal, armor, respawn, colour, sound) and power-up rules. |
| `scripts/deployable.gd` | The entity node for turrets, pads, barricades, smoke, armor drops and pickups (`pack()` for snapshots). |
| `scripts/acquisition.gd` | Pure objective rules (no scene dependencies). `civic_dividend.gd` ties them to the map (points, spawns, `TEAM_SIZE`). |
| `scripts/map_layout.gd`, `map_builder.gd`, `map_graph.gd` | The built-in map: data for the west half, mirrored across x = 0. It is built **only** through `MapBuilder`, which snaps to a 0.25 m grid and makes mesh and collider share their dimensions. `map_graph.gd` is the bot waypoint graph. |
| `scripts/blockout_importer.gd`, `map_verbs.gd` | Load blockout JSON maps (geometry, spawns, points, bot graph, verb features) and run map verbs (bounce, climb, cables, movers, events) from `Fighter.simulate_movement`. |
| `tools/blender/maps/*.py` | **Source of truth for blockout maps.** Regenerate with `python3 tools/blender/generate.py tools/blender/maps/<map>.py maps/<map>.blockout.json`. Never hand-edit the JSON. |
| `visuals.gd`, `vfx.gd`, `sfx.gd`, `hud.gd`, `minimap.gd`, `menu.gd`, `ui_style.gd` | Materials, pooled effects (capped at 220 live), synthesized sound (`Sfx.Kind`), HUD, minimap and the start/pause menu (LOADOUT and LOOK tabs). |

**Network model:**
- The host (or the offline player) is authoritative (`game.authoritative`) and simulates everything.
- Clients send inputs (`submit_input`, unreliable) and actions (`submit_actions`, reliable). They receive compressed
  world snapshots (`snapshot`, `initial_sync`) built from each `Fighter.pack()` and `Deployable.pack()`.
- Effects are broadcast as authority RPCs (`trace_visual`, `ring_visual`, `kill_feed`, ...).
- Clients predict their own movement and interpolate everyone else.
- **Any state that clients must see goes through `pack()` / `unpack()`.** Keep keys short; snapshots are size-sensitive,
  so optional fields are omitted when they hold their default.

## 3. How to add things (extend, don't overhaul)

Every system has an extension point. Use it; don't restructure the hub.

- **A gun:**
  1. Add `resources/weapons/<name>.tres` (a `WeaponSpec`: damage, pellets, falloff, interval, magazine, reload, reach,
     burst...) and append it to `Loadout.PRIMARIES` or `Loadout.SIDEARMS`.
  2. Give it a sound and tracer in `Game.WEAPON_FX` (keyed by `title`) and a model in
     `CharacterRig._primary_model` / `_sidearm_model`.
  3. Add its range to `LIVE_RANGES` in `tests/run_tests.gd`. TTK numbers are asserted by tests, so retuning a gun
     usually means updating `run_tests.gd` and the README tables.
- **A utility:**
  1. Add an entry to `Loadout.UTILITIES` and the `Utility` enum.
  2. Add a branch in `Game.use_utility` (set `success = false` when it can't be used, so it costs no cooldown).
  3. Optionally add a bot heuristic in `Game.bot_kit`, and add a case to `test_utilities`.
- **A melee weapon:** add an entry to `Loadout.MELEES` and the `Melee` enum, any special effect in `Game.use_melee`, a
  model in `CharacterRig._melee_model`, and a case to `test_melee`.
- **A cosmetic option** (hairstyle, hat, top, colour...): append it to its table in `appearance.gd`. Each field has a
  bit width in `FIELDS`, so grow the bits only if you must, and only at the end, because that changes saved codes. Then
  add a `match` case in the matching rig builder (`_hair`, `_headgear`, `_top`, `_bottoms_body` / `_leg`, `_shoe`).
  Use `ctx.add` for outlined body parts, `ctx.detail` for small face or trim parts, and `box(..., ctx.glow(...))` for
  emissive bits. `test_appearance` builds every option automatically.
- **A pickup kind:** add an entry to `Items.KINDS` (plus an `Sfx.Kind` if it needs a new sound), then place it in a map
  script with `b.pickup(x, y, z, kind="...")`.
- **A movement verb:** add a small helper in `fighter.gd` next to the others, with its constants at the top, called from
  `simulate_movement`. Add a station in `tools/blender/maps/movement.py` and a check in `tests/movement_course.gd` or
  `run_tests.gd`.
- **A map verb or map change:**
  - For a blockout map, edit `tools/blender/maps/<map>.py` with the kit (`b.block`, `b.ramp`, `b.climb`, `b.bounce`,
    `b.cable`, `b.mover`, `b.event`, `b.pickup`, `b.waypoint`), regenerate, and run the audits.
  - For the built-in map, edit `map_layout.gd`.
  - Geometry rules are in `MAP.md`. Bots walk graph links; `lad` (ladder) and `jmp` (gap jump) link tags make them
    climb or jump.
- **A new networked field:** add it to `Fighter.pack()` / `unpack()` (or `Deployable.pack()`), with a default in
  `unpack` via `data.get(key, default)`. Send player choices through the existing RPCs (`join_request`,
  `loadout_request`). Always clamp or sanitize on the server.
- **A HUD element or sound:** draw in `hud.gd` (`refresh` and its helpers), add `Sfx.Kind` entries in `sfx.gd`, and
  pool effects through `vfx.gd`. Never spawn unbounded nodes.

**House rules:**
- Match the surrounding style: tabs, typed GDScript, short comments that explain *why*, constants at the top of a file.
  `.uid` files are committed next to scripts.
- Keep data files (`loadout.gd`, `appearance.gd`, `items.gd`, `acquisition.gd`) free of scene dependencies.
- Gameplay decisions happen on the authority. Clients never decide hits, damage or pickups.
- Map collision always comes from `MapBuilder`, never from imported meshes.
- Don't break the rig bone names, the `pack()` keys (`lo` loadout, `ap` look, ...) or the RPC signatures without
  updating every caller and test (`tests/network_test.gd`).
- Add or extend a `test_*` function in `tests/run_tests.gd` for new behaviour (`check(cond, msg)`). Update `README.md`
  numbers if you change balance.
- **Git (owner's rule):** pull and push directly to `main`. No branches or PRs. Never commit conflict markers.

## 4. Testing

There is no build step. Tests are headless `SceneTree` scripts (`godot` = Godot 4.7 binary):

```
godot --headless --path . --editor --quit                          # once after adding scripts/assets (class cache, .import)
godot --headless --path . --script res://tests/run_tests.gd        # behavioural suite: must end "0 failures"
godot --headless --path . --script res://tests/map_audit.gd        # after any map change (copy a blockout to maps/blockout.json to audit it)
godot --headless --path . --script res://tests/map_walk.gd
godot --headless --fixed-fps 60 --script res://tests/match_smoke.gd
godot --headless --fixed-fps 60 --script res://tests/bot_tower.gd  # a bot climbs to the Canopy power-up
godot --headless --fixed-fps 60 --script res://tests/soak.gd -- minutes=2
python3 tools/blender/test_blockout_kit.py                          # map scripts validate
```

- The network pair (server first, then client) and the remaining suites are listed in `CLAUDE.md`.
- Renders (`tests/render_*.gd`, e.g. `render_characters.gd`) need a display:
  `xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/render_characters.gd`.
  They write to `docs/previews/`.
- Run the relevant suites before pushing, and report failures honestly.
