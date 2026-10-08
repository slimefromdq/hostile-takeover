# Hostile Takeover

A playable Godot 4.7 graybox prototype: one shared fighter body with Splatoon-style loadouts (primary, sidearm, utility, melee), shared parkour, server-authoritative combat, five-point Acquisition, offline 5v5 bots, and LAN host/join.

AI agents (ChatGPT, Codex, Claude...): start with [`AGENTS.md`](AGENTS.md) for the code map and how to extend each system.

## Play

Open `project.godot` in **Godot 4.7.x** and press **F6** on the main scene or **F5** to run the project. Pick a loadout and choose **Play offline**, or **Explore map** for a single-player free roam with no bots or objectives. No asset downloads or plugins are required.

For multiplayer, one player chooses **Host LAN**. Others enter the host's IP and choose **Join server**. Use `127.0.0.1` for a second instance on the same computer. The host uses UDP **27847**; remote connections require that port to be reachable. Joining players replace bots, keeping a full ten-fighter (5v5) roster. Disconnected players are replaced by bots.

Choose **Yacht Club** under **Map** for the Z-shaped marina: A/E are beside the yachts, B/D are inside the lighthouse
ground floors, and C is inside the central shack. The ocean kills below y = -8, including in Explore and while
invulnerable; a recent enemy knockback earns the elimination. Yacht cabins protect spawns and permit loadout changes.
Both LAN instances must select the same map. See [coordinates, routes and previews](docs/YACHT_CLUB.md).

| Input | Action |
|---|---|
| WASD / mouse | Move / aim |
| Left / right mouse | Fire / aim down sights. Grenade Launcher RMB detonates armed grenades; Double-Barrel RMB spends two rounds for a recoil blast. Other guns zoom over the shoulder; Revolver ADS previews its bounce. |
| Space | Jump; press again in the air to double jump (one per landing), or against a wall to wall-kick; walk into a ledge to mantle (see Movement verbs) |
| 1 | Air dash (about 3.5 m, independent of the double jump; 2.5 second cooldown, holds vertical speed so you hover through it) — **not sprint** |
| Shift | Slide while moving on the ground (see Movement verbs) |
| Q | Utility (see Loadouts) |
| F | Melee |
| 2 / mouse wheel | Swap primary / sidearm (0.25 s) |
| R | Reload |
| V | Switch camera shoulder |
| Tab | Hold for the scoreboard |
| F1 / F2 / F3 | Toggle control hints / colour-blind palette / mute |
| Escape | Loadout picker / resume menu |

Movement is momentum-based, in the Source tradition: ground acceleration and friction take a moment, and in the air forward/back input does almost nothing. Steer air movement by strafing (A or D) while turning the view; the Grapple's Hot Lap widens that air control. Jumps reach about 1.9 m.

### Movement verbs

| Verb | How | Numbers |
|---|---|---|
| Slide | Hold Shift while moving on the ground at 5+ m/s | Short boosted burst: entry boost up to 9.5 m/s, then 8 m/s² of friction, so about 4-5 m on the flat (slopes extend it). Turn with A/D or the view: input rotates your velocity without costing speed. Ends on release or below 4.5 m/s; 0.6 s cooldown between slides |
| Slide-jump | Jump out of a slide, or within 0.15 s after | Keeps your speed and adds up to 1.5 m/s (3 m/s with Hot Lap), capped at 12 m/s (14 with Hot Lap), so slide-hops cannot snowball |
| Wall run | In the air, hold W moving along a wall at 5+ m/s (at most about 45 degrees into it) | Attaches automatically for 0.9 s (1.4 s with Hot Lap), keeps speed (cap 12/14 m/s), gravity drops to 15% and returns over the last 0.3 s. Space kicks off at full wall-kick strength. Restores neither double jump nor dash; 0.35 s cooldown |
| Vault | Walk or run into a ledge under 1.3 m | Carries you over at your current speed (at least 4.5 m/s, cap 12) |
| Ledge grab | Reach a ledge 1.3 to 2.6 m up while airborne | Hangs 0.2 s, then pulls up. Space kicks off, S or Shift drops (0.5 s before you can grab again). The same ledge from the ground pops up as a plain mantle |
| Input forgiveness | Automatic | Jump presses are buffered 0.12 s (a press just before landing or touching a wall still counts, but only a fresh press spends the double jump), and a ground jump still works 0.12 s after walking off an edge. Wall-kick reach is 1.1 m |

Try each verb in isolation on the Movement Course (`docs/MOVEMENT_COURSE.md`): choose it under **Map** in the start menu, then **Explore map**.

Sprint activates automatically after 1.25 seconds without weapon use. Shooting and aiming down sights return you to combat speed. Damage and utilities do not reset sprint. Loadout changes are accepted only in your depot or while dead. Respawn takes five seconds. The match continues while the menu is open.

## Loadouts

There are no heroes or classes. Every fighter has the same body: **200 HP**, the same size and the full movement set, and no abilities of their own. What sets players apart is the **loadout**, four items picked in the start menu (Splatoon-style). Like the old class choice, the loadout can be changed only in your depot or while dead. Bots cycle through the primaries and roll the other three slots.

**Look (character creator):** the start menu's **LOOK** tab dresses your fighter, a cute low-poly person with a sculpted face, bright polygon eyes, pointed hair locks, tapered limbs and chunky shoes: build (Slim / Standard / Sturdy), skin tone, eye colour, hairstyle (Bob, Twin Tails, Ponytail, Buzz, Long, Spiky) and hair colour, headgear (Cap, Goggle Helmet, Headset, Beanie, Sunglasses), top (Tee, Hoodie, Crop Jacket, Tactical Vest, Jersey), bottoms (Shorts, Cargo Pants, Skirt, Cutoffs) and shoes (Sneakers, Boots, High-tops), each garment with its own colour, plus **Randomize**. Your colours stay yours; team identity is trim in the team colour (collar or stripe, a band on each upper arm, shoe stripes, a small chest badge) and the ally/enemy outline. Looks are cosmetic only (every build shares the same collider and hitbox), can be changed anywhere with **Apply loadout / Resume**, are saved between sessions (`user://settings.cfg`) and replicate to everyone. Every bot wears its own random look. Data in `scripts/appearance.gd`, drawing in `scripts/character_rig.gd`; `tests/render_characters.gd` renders a lineup, face detail and movement poses to `docs/previews/`. See [the character design notes](docs/CHARACTERS.md).

| Slot | Key | What it is |
|---|---|---|
| Primary | LMB | Your main gun. |
| Sidearm | **2** / mouse wheel to swap | A second gun with its own magazine. Swapping takes **0.25 s**, much faster than any primary reload (1.4 to 2.2 s), so swapping beats reloading mid-fight. Swapping drops a reload in progress; the holstered gun keeps whatever it had left. |
| Utility | **Q** | A tool on a cooldown. A use that fails (nothing to hook, no ground to place on) costs nothing. |
| Melee | **F** | A quick close-range attack. Its recovery also holds your gun. |

**Primaries**

| Weapon | Role | Damage | Rate | Magazine / reload | Reach | Falloff | Spread | Headshot |
|---|---|---|---|---|---|---|---|---|
| Shotgun | Close range pump shotgun | 10 pellets x 12 | 0.70 s | 6 / 2.2 s | 22 m | full to 6 m, 20% at 20 m | 5.5 deg | 1.2x |
| Rifle | Mid to long range rifle | 55 | 0.32 s | 8 / 1.8 s | 80 m | full to 35 m, 70% at 80 m | none | 1.6x |
| SMG | Rapid-fire SMG | 8 | 0.05 s | 40 / 1.6 s | 30 m | full to 10 m, 55% at 30 m | 1.8 deg | 1.25x |
| Rocket Launcher | Splash pressure, rocket jumps | 100 direct | 0.85 s | 4 / 1.8 s | 60 m | none | none | none |
| Grenade Launcher | Bank shots, remote detonation | 110 direct | 0.90 s | 4 / 1.9 s | 40 m aiming | none | none | none |
| Plasma Gun | Lead and track targets | 14 | 0.06 s | 40 / 1.5 s | 36 m | none | none | none |
| Lightning Gun | Close sustained tracking beam | 10 | 0.05 s | 50 / 1.6 s | 18 m | none | none | none |
| Railgun | Long-range peeks | 105 | 1.15 s | 4 / 2.0 s | 100 m | none | none | 1.65x |
| Double-Barrel Shotgun | Close burst, recoil jumps | 9 pellets x 12; RMB 14 x 12 | 0.65 s | 2 / 1.4 s | 20 m | full to 5 m, 20% at 18 m | 7 deg | none |

**Sidearms**

| Weapon | Role | Damage | Rate | Magazine / reload | Reach | Falloff | Headshot |
|---|---|---|---|---|---|---|---|
| Pistol | Accurate semi-auto | 28 | 0.20 s | 12 / 1.2 s | 40 m | full to 15 m, 60% at 40 m | 1.5x |
| Burst Pistol | Three-round burst | 18 x 3 | 0.55 s per burst, 0.06 s between rounds | 18 / 1.3 s | 32 m | full to 12 m, 60% at 32 m | 1.35x |
| Revolver | Heavy six-shot; a miss bounces once off geometry (ADS previews the bounce) | 48 | 0.38 s | 6 / 1.5 s | 45 m | none | 1.35x |
| Nail Pistol | Accurate projectile follow-ups | 18 | 0.14 s | 18 / 1.2 s | 40 m | none | none |
| Disc Launcher | Visible projectiles, two geometry bounces | 50 | 0.55 s | 6 / 1.4 s | 40 m total travel | none | none |

Ideal time to kill a 200-HP body-shot target, from first impact with every pellet landing: Shotgun 0.70 s at 3 m; Rifle 0.96 s out to 35 m; SMG 1.20 s up to 10 m; Rocket Launcher 0.85 s direct; Grenade Launcher 0.90 s direct; Plasma Gun 0.84 s; Lightning Gun 0.95 s; Railgun 1.15 s; Double-Barrel 0.65 s inside 5 m. Sidearms at 10 m: Pistol 1.40 s, Burst Pistol 1.77 s, Revolver 1.52 s, Nail Pistol 1.54 s and Disc Launcher 1.65 s. Projectile travel adds time before first impact. No ordinary single shot, headshot or alternate blast kills at full health; triple damage remains an exception. A shotgun blast against one target counts as one hit. Movement multipliers: Shotgun/Rifle 0.95, SMG 1.05, every other gun 1.0.

Rockets fly at 28 m/s and burst on contact, with splash falling linearly from 80 to 15 damage across 3.5 m. Launcher grenades fly at 24 m/s plus 3 m/s upward, fall under 15 m/s² gravity, bounce with 65% velocity retention and burst on fighter/deployable contact or after 2.5 s. Their splash falls from 85 to 15 across 3.5 m. RMB remotely detonates your grenades after 0.25 s arming; four can be active. Direct victims take direct damage once, without extra splash. Cover blocks splash; allies take neither damage nor impulse.

Fire explosives at floors or walls to jump: self-damage is 25% of normal splash, with armor absorbing it; triple damage does not increase this cost. Explosive impulse peaks at 16 m/s for yourself and 6 m/s for enemies, declining across the radius. Double-Barrel RMB consumes two rounds and adds 10 m/s recoil opposite the aim direction, without self-damage. Both techniques retain momentum, interrupt constrained traversal and keep your current air-jump/dash resources. Weapon impulses cap horizontal and upward speeds at 24 m/s, with 0.12 s launch grace and 0.8 s boosted air-speed allowance before normal limits return. A suicide grants no kill, armor drop or power-up streak.

Plasma bolts fly at 42 m/s, nails at 65 m/s, and discs at 24 m/s. Discs retain full speed and damage through two geometry bounces. Other guns retain RMB aiming. In-flight projectiles keep the firing weapon and damage multiplier through weapon swaps and shooter death; loadout replacement, disconnect and round restart remove owned projectiles.

**Utilities (Q)**

| Utility | Cooldown | Effect |
|---|---|---|
| Grapple | 7 s | Hooks aimed geometry within 28 m and reels you in for up to 2.5 s; Q again lets go. Letting go (or arriving) grants 2 s of Hot Lap: wider air control, a bigger slide-jump boost and a longer wall run. |
| Frag Grenade | 9 s | Arcing throw that bursts on contact or after 3 s: 35 on a direct hit, 15 splash within 2.5 m. |
| Smoke Grenade | 16 s | Smoke at your feet and 2.5 s of concealment. Attacks end it, damage briefly reveals you, and close opponents can still see you. |
| Launch Pad | 10 s | Placed pad (80 HP, 90 s) that throws anyone who steps on it 14.5 m/s upward, either team. One at a time. |
| Sentry Turret | 12 s | Placed turret (100 HP, 90 s) covering a 120 degree cone out to 14 m, 6 damage per shot. One at a time; it slowly repairs while you are within 12 m and it has not been hit for 4 s. |
| Barricade | 14 s | Placed 3.5 m wall of cover with 180 HP that stands for 8 s. |
| Breach Charge | 8 s | Close blast in front of you: 20 damage within 5 m, launches enemies, triple damage to enemy deployables. |

**Melee (F)**

| Melee | Damage | Reach | Arc | Recovery | Notes |
|---|---|---|---|---|---|
| Knife | 35 | 2.2 m | 120 deg | 0.5 s | Double damage from behind |
| Sledgehammer | 75 | 3 m | 140 deg | 0.9 s | Knocks the target back |
| Sword | 50 | 3.5 m | 180 deg | 0.75 s | A hit refills your current magazine |

No single melee hit can kill a full-health fighter. Item data is `scripts/loadout.gd` (utility and melee tables) plus `resources/weapons/*.tres` (guns); a loadout rides in the `join_request` / `loadout_request` RPCs and the snapshot (`"lo"`) as one packed int. See `docs/LOADOUTS.md` for the design and how to add an item.

**Light armor:** every kill drops an armor plate where the victim died, for the killer's team to grab (walk over it; it lasts 20 s). A plate gives 15 armor, plus 10 for each objective point the killer's team is behind on (up to +20). Armor soaks damage 1:1 before health, caps at 100 and is lost on death.

Aim placement utilities at a visible location; invalid placements do not consume cooldown. Friendly damage is disabled. Depot interiors protect spawning fighters from enemy damage.

## Health packs

Concrete Canopy has 19 health packs, deliberately hard to find: rooftops and docks, tucked corners inside buildings, and underground dead ends (foundation pit, pump hall, market vault). The minimap marks every pack with a green plus (grey while taken, with an arrow when it is on another tier). Walking over one while hurt heals 60 HP at once, then regenerates another 150 HP over the next 5 seconds. Damage from an enemy cancels the regeneration. A taken pack comes back after 25 seconds. They are `pickup` features in the blockout (`tools/blender/maps/canopy.py`, `stage_healpacks`).

**Timed items (Concrete Canopy):** besides the hidden health packs, the Canopy has visible items on fixed timers, taken by whichever team touches them first (and only when they would help): **health bubbles** (green, +15 HP at once, no regen, back after 10 s; 8 on movement lines), **armor tier 1** (blue square, +50 armor, 30 s; 4 on the A/B approaches and in the tunnel) and **armor tier 2** (gold, +100 armor, 45 s; one in the cistern under point C). Armor stacks with kill-drop armor up to 100 and soaks damage 1:1 before health. The minimap shows every item (grey while taken). **Power-up:** one for the whole map, on the control booth of the gatehouse over point C (the central tower, 12 m up; reach it by the span ladders to the deck, then the booth ladder on either gatehouse wall or the launch pad beside it), first available 30 s into the match, then every 90 s after it is taken. Bots go for it too: the Canopy graph has a route up the gatehouse (ladder links the bot climbs by walking into them), so a bot within 60 m will make the climb when no enemy is in sight. Each time it comes up it is randomly either **invincibility** (cyan: nothing damages you for 12 s, except the out-of-bounds kill) or **triple damage** (red: everything you deal is tripled for 12 s). Only one at a time per fighter; it is lost on death. It is announced to everyone when it appears and when someone takes it, the holder pulses a ring every second, and the HUD shows the name and time left. In the last 15 s before it comes back, the minimap shows a pulsing purple ring closing in on its spot with the seconds left (the type is only rolled when it spawns, so the ring does not say which). Taking it plays a map-wide pickup cue, a different one for invincibility (rising shimmer) and triple damage (falling growl), so every team knows it is gone and which one. Everyone hears a rising warning cue when a taken power-up enters its last 15 s, a tick at 3, 2 and 1 s, and a chime when it spawns. Kills scored while holding one build a streak that is announced to everyone from the second kill ("HELIX DOUBLE KILL · 2 kills on TRIPLE DAMAGE", then triple, quad, rampage); the count restarts with the next pickup. The scoreboard (hold Tab) has a **PWR** column counting the power-ups each player has taken. Numbers live in `scripts/items.gd`; placement is `stage_items` in `tools/blender/maps/canopy.py`. Bots detour for them when they need them (a bubble once below 75% health, armor tier 1 or 2 when under 50 or 60 armor), within 30 m, only while no enemy is in sight and not while holding a point, and give up after 10 s (`choose_bot_item` in `scripts/game.gd`).

## Acquisition

Points form A–B–C–D–E. Helix starts with A/B and Monarch with D/E. Only neutral C starts unlocked. After capture, only the two points on the ownership boundary unlock. Take the opposing final point to win.

Single-player capture times are 18 seconds for C, 14 for B/D, and 10 for A/E. Additional attackers accelerate capture up to three fighters. Opponents contest progress; abandoned partial captures decay after a three-second grace period. Exact simultaneous opposing captures on one frontier cancel both attempts to preserve contiguous territory.

At twelve minutes, an active capture enters overtime. A contested partial capture also sustains overtime. Three seconds without active capture ends it. The territory leader wins; equal ownership draws. The host or offline player can start a fresh round using **Escape → Restart round**.

## Balance and validation

Every fighter has 200 HP. `tests/run_tests.gd` fires every primary and sidearm on the authoritative path and checks the live time to kill against the model in the Loadouts section (cadence and any required reload included), and checks the role ordering: each primary beats every sidearm in its own range, and swapping is at least four times faster than any primary reload.

Item tuning lives in `scripts/loadout.gd` and `resources/weapons/*.tres`; movement in `scripts/fighter.gd`; combat and authority in `scripts/game.gd`; map in `scripts/map_layout.gd` (built through `scripts/map_builder.gd`, see `MAP.md`); objective rules in `scripts/acquisition.gd`; HUD in `scripts/hud.gd`; visuals in `scripts/visuals.gd`, `scripts/character_rig.gd` and `scripts/vfx.gd`. Blender exports drop into `assets/` (see `assets/README.md`).

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

The development flags delay outgoing movement/actions/snapshots by 80 milliseconds and drop every fifth unreliable movement or snapshot packet. Reliable actions (utility, melee, swap, reload) are retained. These flags are off in ordinary play.

## Prototype limits

Art is generated primitive geometry (the fighter rig, effects and the map are code-built, with drop-in slots for authored Blender meshes and textures); dialogue is contextual text, and sound is synthesized per-weapon and per-item cues generated at runtime (`scripts/sfx.gd`; F3 mutes). Bots provide live targets and objective pressure, with simple routing rather than advanced navigation or human-level item use. Local movement prediction uses snapshot correction, and remote fighters interpolate; this is not a production rollback or lag-compensation implementation. No matchmaking, dedicated-server deployment, progression, or persistence beyond local settings and your character look is included.

## Performance notes

`tests/perf_probe.gd` reports draw calls, primitives and node counts for a simulated 10-fighter (5v5) match; `tests/soak.gd` runs a long bot match and fails on node or orphan growth. Characters are boxes baked into one vertex-coloured mesh per bone (about a dozen draw calls per fighter whatever the outfit), the sun uses a single shadow cascade, only a fighter's head, torso and legs cast shadows, and combat effects are pooled and capped at 220 live nodes. Software-rendered numbers are only comparable run to run.

Automated checks establish rules and basic runtime behavior. Human balance sessions and a documented 1080p reference-PC performance test are still required before claiming the gameplay or 60-fps acceptance targets are met.

## Test cheats (offline or host only)

F6 toggles disabled cooldowns (utility, melee, dash, slide), F8 toggles taking damage, F9 fully heals you.
