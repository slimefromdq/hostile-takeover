# Heroes

Fighters are **heroes**, not classes. The model is a fighting-game roster (or a Valorant / Deadlock one): every hero
shares a movement language and a resource, and is free to differ in everything else.

## What every hero shares

- **Movement.** The full verb set in `scripts/fighter.gd` (jump, double jump, air dash, wall kick, slide, wall run,
  vault, ledge grab, sprint) and the map verbs in `scripts/map_verbs.gd`. Heroes do not get movement kits of their own
  unless that *is* their gimmick (Skyrunner). Reave has none.
- **The Tension meter.** 0 to 100, charges over time and faster in combat, kept through death, reset by swapping hero.
  Ultimates cost 50% of the bar (`Tension.ULTIMATE_COST`), so they can be chained when fights run hot; they are tuned a
  little weaker to compensate. Rules and numbers are in `scripts/tension.gd` (pure, no scene dependencies). Gains are
  applied in `Game.damage_fighter` (dealt, taken, kills, assists), `combat_tick` (passive) and `objectives_tick`
  (contesting a point). `Game.activate_ultimate` is the single place a hero's ultimate is paid for.
  The meter is deliberately a general resource: only ultimates spend it so far, and other spends are open design space.
- **The ultimate key (X)**, the three ability keys (Q / E / F), primary and alternate fire, reload.

## What a hero chooses

A hero is a `ClassSpec` resource (`resources/*.tres`) plus whatever `class_id` branches it needs in `game.gd`.

| Dimension | Notes |
|---|---|
| Identity | `hero_name`, `epithet`, `tagline`, `quips`. The corporate setting (Helix, Monarch, Civic Dividend) is background lore, not the voice of the roster. |
| Weapon | Signature gun from the spec: damage, pellets, spread, falloff, magazine. Some heroes lock out the shared weapons (Reave). |
| Ability count | 0 to 3 abilities (Q / E / F) plus an optional ultimate. Skyrunner, Engineer, Enforcer and Mirage have three; Reave has one. HUD, menu and `activate` all cope with fewer. |
| Alternate fire | Free for the hero to define (charge shot, repair beam, melee, guard). Primary is suppressed while alternate fire is held. |
| Resource and win condition | Charge on Reave's blade, spin on the Enforcer, a placed double for the Mirage. Anything that needs replicating goes in `Fighter.pack` / `unpack`, and should only be sent while it matters because snapshots are already larger than the MTU. |

## Adding a hero

1. `resources/<hero>.tres` and `scenes/<hero>.tscn` (copy `scenes/reave.tscn`, set `class_id`).
2. Register in `Fighter.SPECS`, `Game.CLASS_SCENES` and `CharacterRig.SLUGS`, in the same index order, and add a
   `_hero()` rig plus its `match` branch in `character_rig.gd`.
3. Branch on `class_id` in `game.gd`: `activate` (abilities), `activate_ultimate`, the alternate-fire block in
   `combat_tick`, and bots (`bot_input`).
4. Any per-hero state: `Fighter` var, reset in `change_class`, replicate in `pack` / `unpack`.
5. Tests: add the hero's TTK to `test_specs` in `tests/run_tests.gd` and write its own checks (see `test_reave`).

## Reave, the Gunblade

Tank-leaning, short range, no movement hook. The gun builds damage, the blade spends it. Full numbers are in the
README; the design problems worth watching in playtests:

- **The guard is front-only.** Hits from behind or steeply above and below go through, and the turn-rate cap
  (`Fighter.GUARD_TURN_RATE`, applied in `Game.limit_guard_turn` on the owner and again on the server) must stay real,
  or the counterplay disappears.
- **Stalling.** Guard stamina drains while held and per point absorbed; an empty bar breaks the guard, stuns and loses
  the Charge.
- **Chip farming.** Charge is capped at 100 and small hits (under 10) count half, so poke cannot feed a one-shot Slash.
- **Range.** Everything she has is short range. Breach and Pyre Edge are her only answers to kiting; tune them
  carefully. The shotgun model TTK (2.1 s) is point blank with every pellet landing; at distance spread and falloff
  make it much slower.
- **Netcode.** Guard and Slash are server-evaluated from the held-button state, so a Slash is timed by the release
  edge the server sees. Under heavy packet loss a very short guard tap can be missed.
