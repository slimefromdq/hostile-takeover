# Loadouts

Hostile Takeover has no heroes or classes. Every fighter has the same body: 200 HP (`Fighter.MAX_HEALTH`), one capsule
size (`Fighter.BODY_RADIUS`), the full movement set and no abilities of their own. What sets players apart is the
**loadout**, Splatoon-style: four items picked in the start menu and carried at all times.

| Slot | Key | Rule |
|---|---|---|
| Primary | LMB / RMB | Shotgun, Rifle, SMG, Rocket Launcher, Grenade Launcher, Plasma Gun, Lightning Gun, Railgun or Double-Barrel Shotgun. RMB detonates launcher grenades or fires a double-barrel recoil blast; other guns aim down sights. |
| Sidearm | 2 / mouse wheel | A second gun with its own magazine (Pistol, Burst Pistol, Revolver, Nail Pistol, Disc Launcher). Swapping takes `Fighter.SWAP_TIME` (0.25 s), at least four times faster than any primary reload, so swapping is the answer to an empty magazine mid-fight. A swap drops a reload in progress. |
| Utility | Q | One tool on a cooldown: Grapple, Frag Grenade, Smoke Grenade, Launch Pad, Sentry Turret, Barricade, Breach Charge. A use that fails costs nothing. |
| Melee | F | Knife, Sledgehammer or Sword. The recovery also holds the gun. |

Numbers are in the README (Loadouts). Item names are plain descriptions of what the item is.

## Design rules

- **The body never changes.** Health, size and movement are the same for everyone, so the map audit, the walker and
  the movement course test one fighter. Item effects include the gun in hand's `move_speed_mult` (0.95 to 1.05),
  the Grapple's Hot Lap window, explosive jumps and double-barrel recoil. Weapon impulses interrupt constrained
  traversal, keep existing air resources, cap horizontal/upward velocity at 24 m/s and briefly allow boosted air speed.
- **Sidearms are a fallback, not a second primary.** Each primary out-trades every sidearm in that primary's own range
  (asserted in `test_weapon_specs`). A sidearm's job is to cover the reload and the range a primary is bad at.
- **Utilities replace abilities, one at a time.** They are the old hero abilities that work on any body: the Grapple
  (was the Skyrunner's Sling Line), the Frag Grenade (the Mirage capsule), the Smoke Grenade, the Launch Pad and Sentry
  Turret (the Engineer's machinery), the Barricade (Enforcer cover) and the Breach Charge (Reave's Breach).
- **No single melee hit kills** a full-health fighter, backstab included.
- **No ordinary gun one-shots either**, including rail headshots and alternate double blasts. Triple damage is an exception.
- **Projectiles invite prediction and movement.** Rockets pressure feet, grenades bounce and detonate remotely,
  plasma/nails reward leading, lightning rewards tracking, rails reward peeks, and discs bank around cover.
  Reduced explosive self-damage (25% of unboosted splash) gives jumps a modest health cost; recoil jumps spend two rounds.
- **No ultimates.** Power-ups and light armor are the big swings.

## How a loadout travels

`Loadout.encode(primary, sidearm, utility, melee)` packs the four ids into one int (4 bits each); `Loadout.decode` clamps
every slot into its table, so any int from the network is safe. The int rides in `join_request` / `loadout_request` and
in the snapshot (`"lo"`). The gun in hand (`"slot"`), the holstered magazine (`"ammo2"`), the swap timer and the two
cooldowns (`"ucd"`, `"mcd"`) are only sent while they differ from the default.

The optional world `"pr"` list carries projectile id, owner/team, gun id (primary index or 16 + sidearm index), position,
velocity, age and bounce count. Launch damage multipliers stay on the authority. Clients reconcile ids and extrapolate
motion without collision/damage decisions. Fighter `"wi"` identifies a new weapon impulse; `"wl"` and `"wb"` carry its
launch grace and boosted air-speed time. Defaults preserve older snapshots. Existing gun/loadout indices are unchanged.

## Adding an item

- **A gun:** add `resources/weapons/<name>.tres` (a `WeaponSpec`) and append it to `Loadout.PRIMARIES` or
  `Loadout.SIDEARMS`. Give it a sound and tracer in `Game.WEAPON_FX` (keyed by `title`) and a model in
  `CharacterRig._primary_model` / `_sidearm_model`. Add its range to `LIVE_RANGES` in `tests/run_tests.gd`, which then
  checks its live cadence against `body_ttk`.
- **A utility:** add an entry to `Loadout.UTILITIES` and the `Utility` enum, a branch in `Game.use_utility` (set
  `success = false` when it cannot be used), and a heuristic in `Game.bot_kit` if bots should use it. Add a case to
  `test_utilities`.
- **A melee weapon:** add an entry to `Loadout.MELEES` (damage, reach, arc as the minimum dot with the facing,
  recovery, push, backstab multiplier) and the `Melee` enum, any special effect in `Game.use_melee`, a model in
  `CharacterRig._melee_model`, and a case to `test_melee`.

Each slot holds at most 16 items (4 bits).

## Look

How a fighter looks is separate from the loadout and purely cosmetic: `scripts/appearance.gd` holds the option tables
(build, skin, eyes, hairstyle, hair colour, headgear, top, bottoms, shoes and a colour for each garment) and packs a look
into one int (`Appearance.encode` / `decode`, every field clamped, so any int from the network is safe). It travels in
`join_request` / `loadout_request` and in snapshots as `"ap"`; `Game.apply_look` applies it anywhere (no return-to-spawn
rule) and `Game.bot_look` gives each bot id a fixed random look. The build only scales the drawn body, never the collider.

`CharacterRig` draws the look as a cute low-poly person with a sculpted cheek/chin profile, polygon eyes, pointed hair
locks, longer tapered limbs, fitted tops, flared skirts and chunky shoes. Faceted profiles, flat face patches, boxes and
prisms are baked into one vertex-coloured mesh per bone. The shared 1.9 m capsule and 1.55 m headshot line are unchanged.
Team trim (collar or stripe, upper-arm bands, shoe stripes, chest badge) is the team colour; the outline is a crack-free
inverted hull pushed back in depth so it only draws around the silhouette. See [character design notes](CHARACTERS.md).

- **A new option:** append to its table in `appearance.gd` (mind the field's bit width in `FIELDS`) and add a `match`
  case to the matching builder in `character_rig.gd` (`_hair`, `_headgear`, `_top`, `_bottoms_body` / `_leg`, `_shoe`).
  `test_appearance` builds every option of every field and fails on a missing bone.
