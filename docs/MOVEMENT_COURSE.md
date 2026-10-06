# Movement Course

A sandbox for feeling every movement verb in isolation. In the start menu pick **Map: Movement Course**, then **Explore map**
(free roam, no bots, no objective). Spawn is the west depot; every station is on the open street, laid out west to east.
Regenerate with `python3 tools/blender/generate.py tools/blender/maps/movement.py maps/movement.blockout.json`
(it is a replace-mode blockout, so edit the generator, not the JSON). Coordinates are x, z in metres.

| Station | Where | What to try |
|---|---|---|
| **Slide hill** | x -46..-28, z -16..-10 | Run up the 14 degree ramp to the 3 m platform, turn round and slide down: slope adds speed so the slide goes much farther than on the flat (4-5 m). Steer with A/D while sliding |
| **Slide-jump gaps** | x -48..3, z -27..-21 | 1 m platforms with 5, 7 and 9 m gaps. A run-jump (8 m/s) covers about 6.2 m, so only the 5 m gap is plain. Jump out of a slide at the edge for 11 m/s and clear the 7 m gap. The 9 m gap needs a slide-jump plus the double jump or dash |
| **Ledge ladder** | x 6..34, z 8..12 | Blocks 0.6, 1.2, 1.8, 2.4 and 3.0 m high. 0.6 and 1.2 m are vaulted. 1.8 and 2.4 m are popped up from the ground, or grabbed for a moment if you reach them in the air (Space kicks off, S/Shift drops). 3.0 m is beyond mantle reach: use a wall kick or double jump |
| **Vault hurdles** | x 10..43, z -18..-10 | Five 1.1 m hurdles 8 m apart: run through them without slowing down |
| **Wall-run corridor** | x 4..34, z 19..26 | Two 8 m walls, 7 m apart. Run along one in the air, kick across, run the other. The 124 m north and south boundary walls are long wall-run strips too |

Automated check: `godot --headless --path . --script res://tests/movement_course.gd` rebuilds the course 300 m away and walks real
fighters through each station (slide hill length, 5 m and 7 m gaps with and without a slide-jump, hurdle vaults for Engineer and
Enforcer, the ledge ladder, and a wall-to-wall run). `tests/blockout_import.gd` also checks the map file and that the ledge
heights bracket the vault and mantle limits.
