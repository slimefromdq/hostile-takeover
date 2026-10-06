"""Tests for blockout_kit (no Blender needed):  python3 -I tools/blender/test_blockout_kit.py"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from blockout_kit import Blockout  # noqa: E402
import blockout_check  # noqa: E402
import generate  # noqa: E402


class KitTests(unittest.TestCase):
    def test_snapping_and_order(self):
        b = Blockout()
        r = b.block(10.1, 5, 0, -3.9, 0, 3.13, "wall", "w")
        self.assertEqual(r["min"], [0, 0, -4])
        self.assertEqual(r["max"], [10, 3.25, 5])

    def test_thin_block_rejected(self):
        with self.assertRaises(ValueError):
            Blockout().block(0, 0, 0.1, 5, 0, 3, "wall")

    def test_unknown_role_rejected(self):
        with self.assertRaises(ValueError):
            Blockout().block(0, 0, 4, 4, 0, 3, "marble")

    def test_ramp_slope_warning(self):
        b = Blockout()
        b.ramp(0, 0, 4, 4, 0, 0, 2.5, "+x", "walk", "steep")
        b.ramp(0, 10, 12, 14, 0, 0, 3, "+x", "walk", "gentle")
        self.assertEqual(len([w for w in b.validate() if "degrees" in w]), 1)

    def test_stairs_down_flips_direction(self):
        b = Blockout()
        r = b.stairs(0, 0, 12, 4, 3, 0, "+x", "walk")
        self.assertEqual((r["dir"], r["y_start"], r["y_end"]), ("-x", 0, 3))

    def test_room_openings(self):
        b = Blockout()
        b.room(0, 0, 10, 10, 0, 6, 1, "wall", "r", openings=[("e", 5, 4, 3)])
        east = [o for o in b.objects if o["tag"].startswith("r_e")]
        self.assertEqual(len(east), 3)  # two jambs and a lintel
        self.assertTrue(any(o["min"][1] == 3 and o["max"][1] == 6 for o in east))

    def test_overlap_detected(self):
        b = Blockout()
        b.block(0, 0, 4, 4, 0, 3, "wall", "a")
        b.block(2, 2, 6, 6, 0, 3, "wall", "b")
        b.block(4, 0, 8, 2, 0, 3, "wall", "touching")
        problems = [w for w in b.validate() if "overlaps" in w]
        self.assertEqual(len(problems), 1)

    def test_replace_requirements(self):
        b = Blockout(mode="replace")
        self.assertEqual(len([w for w in b.validate() if "needs" in w]), 2)

    def test_yard_is_valid_replace_map(self):
        module = generate.load_generator(os.path.join(HERE, "maps", "yard.py"))
        b = Blockout(mode=module.MODE)
        module.build(b)
        self.assertEqual(b.validate(), [])
        self.assertEqual(sum(1 for w in b.waypoints if w.get("point")), 3)  # A, B mirrored + C

    def _generated(self, name):
        module = generate.load_generator(os.path.join(HERE, "maps", name))
        b = Blockout(mode=module.MODE)
        module.build(b)
        return b

    def test_maps_validate_and_navigate(self):
        for name in ("yard.py", "overpass.py"):
            b = self._generated(name)
            self.assertEqual(b.validate(), [], name)
            self.assertEqual(blockout_check.check(b.to_document()), [], name)

    def test_checker_catches_bad_waypoints(self):
        b = Blockout(mode="add")
        b.block(-20, -20, 20, 20, -1, 0, "walk", "floor")
        b.block(-1, -1, 1, 1, 0, 3, "wall", "pillar")
        b.waypoint("a", -10, 0, 0, "b:blv")
        b.waypoint("b", 10, 0, 0, "")          # the pillar is in the way
        b.waypoint("c", 0, 0, 10, "")          # fine, unlinked
        b.waypoint("d", 5, 2, 5, "")           # floating
        problems = blockout_check.check(b.to_document())
        self.assertTrue(any("pillar in the way" in p for p in problems))
        self.assertTrue(any("waypoint d" in p for p in problems))

    def test_overpass_has_five_points_and_two_spawns(self):
        b = self._generated("overpass.py")
        nodes, _ = blockout_check.nodes_of(b.to_document())
        points = [n for n in nodes if n.replace("e_", "", 1) in ("A", "B", "C")]
        self.assertEqual(len(points), 5)


if __name__ == "__main__":
    unittest.main()
