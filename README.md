# Hostile Takeover

A playable Godot 4.7 graybox prototype: four fighter classes, shared parkour, server-authoritative combat, five-point Acquisition, offline 6v6 bots, and LAN host/join.

## Play

Open `project.godot` in **Godot 4.7.x** and press **F6** on the main scene or **F5** to run the project. Select a class and choose **Play offline**, or **Explore map** for a single-player free roam with no bots or objectives. No asset downloads or plugins are required.

For multiplayer, one player chooses **Host LAN**. Others enter the host's IP and choose **Join server**. Use `127.0.0.1` for a second instance on the same computer. The host uses UDP **27847**; remote connections require that port to be reachable. Joining players replace bots, keeping twelve fighters. Disconnected players are replaced by bots.

| Input | Action |
|---|---|
| WASD / mouse | Move / aim |
| Left / right mouse | Primary / alternate fire |
| Space | Jump; press again in the air to double jump (one per landing or wall kick), or against a wall to wall-kick; walk into a ledge (up to about 2.6 m) to mantle automatically |
| 1 | Air dash (about 4.5 m, independent of the double jump; 3 second cooldown) — **not sprint** |
| Shift | Slide while moving on ground |
| Q / E / F | Three class abilities |
| R | Reload |
| V | Switch camera shoulder |
| Tab | Hold for the scoreboard |
| F1 / F2 / F3 | Toggle control hints / colour-blind palette / mute |
| Escape | Class selector / resume menu |

Movement is momentum-based, in the Source tradition: ground acceleration and friction take a moment, and in the air forward/back input does almost nothing. Steer air movement by strafing (A or D) while turning the view; Skyrunner's Hot Lap widens that air control. Jumps reach about 1.9 m.

Sprint activates automatically after 1.25 seconds without weapon use. Shooting and alternate fire return you to combat speed. Damage and nonweapon abilities do not reset sprint. Changes of class are accepted only in your depot or while dead. Respawn takes five seconds. The match continues while the menu is open.

## Classes

- **Skyrunner:** precise three-round burst pistol; hold alternate fire for a charged shot. Q grapples to aimed geometry; Q again releases. E propels upward. Hold F to arrest horizontal momentum and slow descent. Hot Lap improves wall-kick momentum, steering, and reload handling after wall kicks and grapple exits. Low health: 160.
- **Field Engineer:** forgiving electric hose with line-of-sight aim assistance; alternate fire repairs friendly machinery. Q places one directional turret; E places a launch pad usable by either team; F recalls the nearest owned installation and refunds half its deployment cooldown. Owned machinery condition is visible through walls and nearby idle machinery slowly repairs. Health: 200.
- **Enforcer:** minigun with a 0.6-second spin-up; alternate fire swings a heavy melee attack. Q rushes forward; E places destructible cover; F slams a forward cone and pushes enemies. Melee hits improve spin-up; sustained gun hits improve melee recovery. Firing slows movement; frontal knockback is reduced while spun up. Health: 280.
- **Mirage Agent:** accurate six-shot revolver that bounces once off geometry; alternate fire previews the bounce. Q places one physical double; Q again exchanges positions once, within 25 metres. The double lasts eight seconds, can be destroyed, cannot block fighters or capture points, and echoes harmless firing effects. E throws an arcing capsule (35 direct damage / 15 splash). F creates departure smoke and grants 2.5 seconds of concealment; attacks end it, damage briefly reveals the agent, and close opponents can see them. Swapping preserves velocity and facing, reloads one round, and enables sprint. Health: 180.

Aim placement abilities at a visible location; invalid placements do not consume cooldown. Failed or obstructed swaps do not consume the double's exchange. Friendly damage is disabled. Depot interiors protect spawning fighters from enemy damage.

## Acquisition

Points form A–B–C–D–E. Helix starts with A/B and Monarch with D/E. Only neutral C starts unlocked. After capture, only the two points on the ownership boundary unlock. Take the opposing final point to win.

Single-player capture times are 18 seconds for C, 14 for B/D, and 10 for A/E. Additional attackers accelerate capture up to three fighters. Opponents contest progress; abandoned partial captures decay after a three-second grace period. Exact simultaneous opposing captures on one frontier cancel both attempts to preserve contiguous territory.

At twelve minutes, an active capture enters overtime. A contested partial capture also sustains overtime. Three seconds without active capture ends it. The territory leader wins; equal ownership draws. The host or offline player can start a fresh round using **Escape → Restart round**.

## Balance and validation

Against a 200-HP body-shot target, measured authoritative firing times are:

| Class | Time to kill |
|---|---:|
| Skyrunner | 2.083 s |
| Mirage Agent | 2.250 s |
| Field Engineer | 2.800 s |
| Enforcer, already spun up | 2.600 s |

All measurements include firing cadence and any required reload. Enforcer spin-up adds approximately 0.6 seconds from rest. Headshots multiply damage by 1.35 except for the electric hose. A capsule plus one revolver headshot cannot eliminate even the lowest-health class.

Class tuning lives in `resources/*.tres`; movement in `scripts/fighter.gd`; combat and authority in `scripts/game.gd`; map in `scripts/map_layout.gd` (built through `scripts/map_builder.gd`, see `MAP.md`); objective rules in `scripts/acquisition.gd`; HUD in `scripts/hud.gd`; visuals in `scripts/visuals.gd`, `scripts/character_rig.gd` and `scripts/vfx.gd`. Blender exports drop into `assets/` (see `assets/README.md`).

Run behavioral checks:

```powershell
& 'path\to\godot_console.exe' --headless --path . --script res://tests/run_tests.gd
```

Run the map audits (geometry, traversal, sightlines) and the walker test:

```powershell
& 'path\to\godot_console.exe' --headless --path . --script res://tests/map_audit.gd
& 'path\to\godot_console.exe' --headless --path . --script res://tests/map_walk.gd
```

Run network checks in two terminals, starting the server first:

```powershell
& 'path\to\godot_console.exe' --headless --path . --script res://tests/network_test.gd -- --server --latency-ms=80 --drop-every=5
& 'path\to\godot_console.exe' --headless --path . --script res://tests/network_test.gd -- --latency-ms=80 --drop-every=5
```

The development flags delay outgoing movement/actions/snapshots by 80 milliseconds and drop every fifth unreliable movement or snapshot packet. Reliable ability actions are retained. These flags are off in ordinary play.

## Prototype limits

Art is generated primitive geometry (class rigs, effects and the map are code-built, with drop-in slots for authored Blender meshes and textures); dialogue is contextual text, and sound is synthesized per-class cues generated at runtime (`scripts/sfx.gd`; F3 mutes). Bots provide live targets and objective pressure, with simple routing rather than advanced navigation or human-level kit use. Local movement prediction uses snapshot correction, and remote fighters interpolate; this is not a production rollback or lag-compensation implementation. No matchmaking, dedicated-server deployment, cosmetics, progression, or persistence is included.

## Performance notes

`tests/perf_probe.gd` reports draw calls, primitives and node counts for a simulated 12-fighter match; `tests/soak.gd` runs a long bot match and fails on node or orphan growth. Character meshes are low-poly (about 10x fewer triangles than the first pass), the sun uses a single shadow cascade, small character details do not cast shadows, and combat effects are pooled and capped at 220 live nodes. Software-rendered numbers are only comparable run to run.

Automated checks establish rules and basic runtime behavior. Human balance sessions and a documented 1080p reference-PC performance test are still required before claiming the gameplay or 60-fps acceptance targets are met.
