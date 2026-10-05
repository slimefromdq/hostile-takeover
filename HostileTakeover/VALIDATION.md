# Validation — October 5, 2026

Tested with Godot **4.7.2 stable**, Windows, compatibility renderer.

| Check | Result |
|---|---|
| Behavioral suite | **82 checks passed**, zero failures or runtime errors |
| Host/client integration | Both processes passed with 80 ms outgoing delay on each side and every fifth unreliable motion/state packet dropped |
| Network behaviors | Human replaces bot; twelve-player roster; class assignment; reliable double deployment; one-use swap; authoritative relocation and teleport correction; predicted movement |
| Packet size | Compressed twelve-fighter snapshot measured **897 bytes** in the final network test |
| Two-minute simulated match | Passed: twelve valid fighters, ten bots advanced out of spawn, center acquired, valid frontier |
| Render verification | OpenGL 3.3 on Intel Arc; gameplay screenshot saved and inspected; no rendering errors |

Live authoritative body-shot measurements against 200 HP:

- Skyrunner: **2.083 seconds**.
- Mirage Agent: **2.250 seconds**.
- Field Engineer: **2.800 seconds**.
- Enforcer: **2.600 seconds**, excluding its initial spin-up.

The behavioral suite covers capture progression and counterpushes, locks, both final-point victories, contested capture, decay, overtime, simultaneous opposing captures, reload-aware damage timing, primary hits, friendly-fire exclusion, automatic sprint, air dash, all-class wall kicks, sliding, mantling, double exchange and obstruction, double destruction and expiry, objective exclusion, concealment, turret arcs and repair, shared launch pads, Enforcer passive triggers, server authority, respawn, class changes, stale-snapshot rejection, and round restart.

Run the bot-match check with:

```powershell
& 'path\to\godot_console.exe' --headless --fixed-fps 60 --path . --script res://tests/match_smoke.gd
```

`--fixed-fps` accelerates the simulation without establishing real rendered performance. **Human playtests, final balance, production networking, and the 1080p/60-fps target remain unverified.**
