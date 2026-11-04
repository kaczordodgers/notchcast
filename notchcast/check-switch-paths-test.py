#!/usr/bin/env python3
"""Mutation proofs against a copy of production sources; no Swift build required."""

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("paths", Path(__file__).with_name("check-switch-paths.py"))
paths = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paths)


def main():
    with tempfile.TemporaryDirectory(dir=sys.argv[1]) as temporary:
        root = Path(temporary)
        shutil.copytree(paths.ROOT / "Tinycast", root / "Tinycast")
        (root / "notchcast").mkdir()
        for path in (paths.ALLOWLIST, paths.PATHS):
            shutil.copy(paths.ROOT / path, root / path)
        assert not paths.check(root), paths.check(root)
        print("PASS: source baseline with allowlist")
        allowlist = json.loads((root / paths.ALLOWLIST).read_text())
        allowlist.pop("clearNotifications", None)
        (root / paths.ALLOWLIST).write_text(json.dumps(allowlist))
        catalog = root / paths.CATALOG
        catalog.write_text(catalog.read_text().replace("        ClearNotificationsModule.launcherCommand,\n", ""))
        assert "smallCommands" in paths.command_paths(root), "command after a nested type was missed"
        print("PASS: commands declared after a nested type count for their switch")
        errors = paths.check(root)
        assert any("clearNotifications: no user path" in error for error in errors), errors
        print("PASS: clearNotifications without exception fails: clearNotifications: no user path")
        fixture = root / "Tinycast/Fixture.swift"
        catalog = root / paths.CATALOG
        original = catalog.read_text()
        command = 'extension Fixture { static let clear = NotchcastCommand(slug: "clear", GATE run: { NotchcastCore.clearNotifications.run() }) }'
        fixture.write_text(command.replace("GATE", "isEnabled: { prefs.isOn(.clearNotifications) },"))
        assert paths.check(root), "uncataloged command must not count"
        catalog.write_text(original.replace("static let all: [NotchcastCommand] = [", "static let all: [NotchcastCommand] = [\nFixture.clear,"))
        for gate in ("isEnabled: { prefs.isOn(.clearNotifications) },", "isEnabled: { prefs.isEnabled(.clearNotifications) },", "feature: .clearNotifications,"):
            fixture.write_text(command.replace("GATE", gate))
            assert not paths.check(root), paths.check(root)
            print(f"PASS: catalog command with {gate} supplies clearNotifications path")
        allowlist["clearNotifications"] = "Missing launcher command"
        (root / paths.ALLOWLIST).write_text(json.dumps(allowlist))
        assert any("clearNotifications: remove from allowlist" in error for error in paths.check(root))
        print("PASS: stale exception fails: clearNotifications: remove from allowlist")
        del allowlist["clearNotifications"]
        (root / paths.ALLOWLIST).write_text(json.dumps(allowlist))
        feature = root / paths.CORE
        feature.write_text(feature.read_text().replace("case tasks", "case fakeNewSwitch\n    case tasks", 1))
        assert any("fakeNewSwitch: no user path" in error for error in paths.check(root))
        print("PASS: fakeNewSwitch fails: fakeNewSwitch: no user path")
    return 0


if __name__ == "__main__":
    sys.exit(main())
