#!/usr/bin/env python3
"""Plan and run checks inside an isolated Release app."""
import argparse
import fnmatch
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = json.loads((ROOT / "notchcast/app-proofs.json").read_text())


def command(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    plan = modes.add_parser("plan")
    plan.add_argument("base")
    plan.add_argument("head")
    run = modes.add_parser("run")
    run.add_argument("--app", type=Path)
    run.add_argument("checks", nargs="+")
    args = parser.parse_args()
    if args.mode == "plan":
        base = command(["git", "merge-base", args.base, args.head], capture_output=True, text=True).stdout.strip()
        paths = command(["git", "diff", "--name-only", "-z", f"{base}..{args.head}"], capture_output=True).stdout.decode().split("\0")
        for name, globs in REGISTRY.items():
            if any(fnmatch.fnmatchcase(path, glob) for path in paths for glob in globs):
                print(name)
        return
    # samefile catches /applications and the /System/Volumes/Data firmlink, which string checks miss.
    if args.app and any(parent.exists() and os.path.samefile(parent, "/Applications")
                        for path in (args.app.absolute(), args.app.resolve()) for parent in (path, *path.parents)):
        parser.error("refusing an app under /Applications")
    for name in args.checks:
        if name not in REGISTRY:
            parser.error(f"unknown check: {name}")
    with tempfile.TemporaryDirectory(prefix="notchcast-proof-") as directory:
        scratch = Path(directory)
        if args.app:
            app = scratch / args.app.name
            command(["ditto", str(args.app.resolve()), str(app)])
            plist = app / "Contents/Info.plist"
            info = plistlib.loads(plist.read_bytes())
            info["CFBundleIdentifier"] = "app.notchcast.proof"
            plist.write_bytes(plistlib.dumps(info))
            command(["codesign", "--force", "--deep", "--sign", "-", str(app)])
        else:
            build = ["xcodebuild", "-project", "Tinycast.xcodeproj", "-scheme", "Tinycast", "-configuration", "Release", "-derivedDataPath", str(scratch / "DerivedData"), "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "PRODUCT_BUNDLE_IDENTIFIER=app.notchcast.proof", "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "OTHER_CODE_SIGN_FLAGS=--timestamp=none", "build", "-quiet"]
            # NOTCHCAST_BUILD_QUEUE: an optional machine-wide build queue (notchcast/README.md, "Private hooks").
            queue = os.environ.get("NOTCHCAST_BUILD_QUEUE", "").split()
            if not os.environ.get("GITHUB_ACTIONS") and queue:
                build = [*queue, "hold", "--", *build]
            command(build)
            app = scratch / "DerivedData/Build/Products/Release/Notchcast.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != "app.notchcast.proof":
            parser.error("built app has the wrong proof identity")
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        for name in args.checks:
            result = subprocess.run([str(executable)], env={**os.environ, "NOTCHCAST_PROOF": name}, capture_output=True, text=True, timeout=60)
            print(result.stdout, end="")
            if result.returncode != 0 or f"PROOF PASS {name}" not in result.stdout.splitlines():
                raise SystemExit(f"proof {name} failed (exit {result.returncode}): {result.stderr}")


if __name__ == "__main__":
    main()
