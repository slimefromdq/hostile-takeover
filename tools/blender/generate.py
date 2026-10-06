"""Run a blockout generator script and write the JSON (and optionally a .blend to look at).

    python3 tools/blender/generate.py tools/blender/maps/yard.py maps/blockout.json
    python3 tools/blender/generate.py tools/blender/maps/yard.py maps/blockout.json --blend yard.blend

The generator script defines build(b) and receives a blockout_kit.Blockout. Validation warnings are printed
and, with --strict, make the command fail. --blend needs Blender: it uses the `bpy` module if installed,
otherwise a `blender` executable on PATH.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from blockout_kit import Blockout  # noqa: E402


def load_generator(path):
    spec = importlib.util.spec_from_file_location("blockout_generator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "build"):
        raise SystemExit("%s must define build(b)" % path)
    return module


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("script")
    ap.add_argument("out", nargs="?", default="maps/blockout.json")
    ap.add_argument("--blend", help="also write a .blend you can open and edit in Blender")
    ap.add_argument("--strict", action="store_true", help="fail on validation warnings")
    args = ap.parse_args(argv)
    module = load_generator(args.script)
    b = Blockout(mode=getattr(module, "MODE", "add"), title=getattr(module, "TITLE", None))
    module.build(b)
    warnings = b.validate()
    for w in warnings:
        print("WARNING:", w)
    b.save(args.out, source=os.path.basename(args.script))
    print("Wrote %s: %d objects, %d waypoints, mode %s" % (args.out, len(b.objects), len(b.waypoints), b.mode))
    if args.blend:
        write_blend(args.out, args.blend)
    return 1 if (warnings and args.strict) else 0


def write_blend(json_path, blend_path):
    try:
        import bpy  # noqa: F401
        import import_blockout
        import_blockout.import_file(json_path, blend_path)
    except ImportError:
        exe = shutil.which("blender")
        if not exe:
            raise SystemExit("--blend needs Blender: `pip install bpy` or put `blender` on PATH")
        subprocess.check_call([exe, "-b", "-P", os.path.join(HERE, "import_blockout.py"), "--", json_path, blend_path])
    print("Wrote", blend_path)


if __name__ == "__main__":
    sys.exit(main())
