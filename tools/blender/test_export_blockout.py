"""Tests for the pure conversion logic (no Blender needed):  python3 -I tools/blender/test_export_blockout.py"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_blockout as ex  # noqa: E402


def box_corners(lo, hi):
    """Blender world-space corners for a box given in Godot coordinates (x, y, z) -> Blender (x, -z, y)."""
    pts = []
    for x in (lo[0], hi[0]):
        for y in (lo[1], hi[1]):
            for z in (lo[2], hi[2]):
                pts.append((x, -z, y))
    return pts


class ConvertTests(unittest.TestCase):
    def test_yacht_settings(self):
        settings = {"goal_order": ["A", "B", "C", "D", "E"],
                    "team_spawns": [[[0, 0.2, 0]] * 5, [[10, 0.2, 0]] * 5],
                    "spawn_zones": [{"min": [0, 0, 0], "max": [4, 4, 4]}] * 2,
                    "kill_floor": -8}
        scene = {"ht_" + key: json.dumps(value) for key, value in settings.items()}
        self.assertEqual(ex.scene_settings(scene), settings)

    def test_axis_conversion(self):
        self.assertEqual(ex.to_godot((1.0, 2.0, 3.0)), (1.0, 3.0, -2.0))

    def test_block_round_trip(self):
        rec, warns = ex.convert_object("wall.001", box_corners((-30, 0, 45), (-29, 4, 59)), {"mirror": True}, ["Wall"])
        self.assertEqual(warns, [])
        self.assertEqual(rec["tag"], "wall")
        self.assertEqual(rec["role"], "wall")
        self.assertEqual(rec["min"], [-30, 0, 45])
        self.assertEqual(rec["max"], [-29, 4, 59])
        self.assertTrue(rec["mirror"])

    def test_role_from_property_beats_collection(self):
        rec, _ = ex.convert_object("a", box_corners((0, 0, 0), (1, 1, 1)), {"role": "cover"}, ["Walk"])
        self.assertEqual(rec["role"], "cover")

    def test_missing_role_warns(self):
        rec, warns = ex.convert_object("a", box_corners((0, 0, 0), (1, 1, 1)), {}, ["Stuff"])
        self.assertEqual(rec["role"], "wall")
        self.assertEqual(len(warns), 1)

    def test_ramp_defaults_and_validation(self):
        corners = box_corners((-28, 0, 47), (-22, 3, 53))
        rec, _ = ex.convert_object("r", corners, {"kind": "ramp", "ramp_dir": "+x", "role": "walk"}, [])
        self.assertEqual((rec["y_floor"], rec["y_start"], rec["y_end"]), (0.0, 0.0, 3.0))
        bad, warns = ex.convert_object("r", corners, {"kind": "ramp", "role": "walk"}, [])
        self.assertIsNone(bad)
        self.assertTrue(warns)

    def test_thin_and_off_grid(self):
        thin, _ = ex.convert_object("t", box_corners((0, 0, 0), (0.1, 1, 1)), {"role": "wall"}, [])
        self.assertIsNone(thin)
        _, warns = ex.convert_object("g", box_corners((0.1, 0, 0), (1.1, 1, 1)), {"role": "wall"}, [])
        self.assertTrue(any("grid" in w for w in warns))

    def test_links_and_document(self):
        self.assertEqual(ex.parse_links("B:blv, C:roof,D"), [["B", "blv"], ["C", "roof"], ["D", "blv"]])
        doc = ex.build_document([], [{"name": "p1", "pos": [0, 0, 0], "links": [["p2", "blv"]]}, {"name": "p2", "pos": [1, 0, 0], "links": []}])
        self.assertEqual(doc["format"], ex.FORMAT)
        self.assertEqual(doc["links"], [["p1", "p2", "blv"]])
        json.dumps(doc)


if __name__ == "__main__":
    unittest.main()
