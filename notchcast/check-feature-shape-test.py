#!/usr/bin/env python3
"""Reject unsafe registrations and typecheck three concurrent feature appends."""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
CHECKER = ROOT / "notchcast/check-feature-shape.py"
SPEC = importlib.util.spec_from_file_location("feature_shape", CHECKER)
SHAPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHAPE)


def run(root, *args):
    environment = os.environ.copy()
    environment.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull})
    result = subprocess.run(args, cwd=root, env=environment, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"{' '.join(args)}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def append_feature(source, name):
    boundary = source.index("    var settingsGroup:")
    last_case = list(re.finditer(r"^    case \w+\n", source[:boundary], re.M))[-1]
    source = source[:last_case.end()] + f"    case {name}\n" + source[last_case.end():]
    values = {
        "settingsGroup": f".{name}Group",
        "title": f'String(localized: "{name}")',
        "subtitle": f'String(localized: "{name} subtitle")',
        "requiredGrants": "[.accessibility]",
    }
    if "var startsOff:" in source:
        values["startsOff"] = "true"
    for member, value in values.items():
        start = source.index(f"    var {member}:")
        end = source.index("\n        }", start)
        default = source.find("        default:", start, end)
        insertion = default if default != -1 else end + 1
        source = source[:insertion] + f"        case .{name}: {value}\n" + source[insertion:]
    return source


class FeatureShapeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="notchcast-feature-union-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for path in (SHAPE.FEATURE, SHAPE.GROUPS):
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text((ROOT / path).read_text())

    def rejected(self, path, source, message):
        (self.root / path).write_text(source)
        result = subprocess.run(
            ["python3", str(CHECKER), str(self.root)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertRegex(result.stderr, rf"{re.escape(str(path))}:\d+:")

    def test_shared_multi_case_arm(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            "case .island: .island", "case .island, .islandExternalDisplays: .island"),
            "multi-case arm")

    def test_shared_group_line(self):
        source = (self.root / SHAPE.GROUPS).read_text()
        self.rejected(SHAPE.GROUPS, source.replace(
            "case island\n", "case island, islandOptions\n"), "one enum case per line")

    def test_two_declarations_on_one_line(self):
        source = (self.root / SHAPE.GROUPS).read_text()
        self.rejected(SHAPE.GROUPS, source.replace(
            "case island\n", "case island; case islandOptions\n"), "own line")

    def test_union_duplicated_group_header(self):
        source = (self.root / SHAPE.GROUPS).read_text()
        self.rejected(SHAPE.GROUPS, source + source, "expected one SettingsGroup enum, found 2")

    def test_multiline_arm_and_starts_off(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        source += "\nextension NotchcastFeature {\n    var startsOff: Bool {\n        switch self {\n"
        source += "        case .island,\n             .systemMonitor: true\n        default: false\n"
        source += "        }\n    }\n}\n"
        self.rejected(SHAPE.FEATURE, source, "multi-case arm")

    def test_three_branch_union_merge(self):
        (self.root / ".gitattributes").write_text((ROOT / ".gitattributes").read_text())
        run(self.root, "git", "init", "-q", "-b", "base")
        run(self.root, "git", "config", "user.name", "Feature shape test")
        run(self.root, "git", "config", "user.email", "feature-shape@example.invalid")
        run(self.root, "git", "config", "core.hooksPath", os.devnull)
        run(self.root, "git", "config", "commit.gpgSign", "false")
        run(self.root, "git", "config", "merge.gpgSign", "false")
        for path in (SHAPE.FEATURE, SHAPE.GROUPS):
            self.assertTrue(run(self.root, "git", "check-attr", "merge", "--", str(path)).endswith(": union"))
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Base feature shape")
        for name in ("unionAlpha", "unionBeta", "unionGamma"):
            run(self.root, "git", "switch", "-qc", name, "base")
            feature = self.root / SHAPE.FEATURE
            feature.write_text(append_feature(feature.read_text(), name))
            groups = self.root / SHAPE.GROUPS
            source = groups.read_text()
            last_case = list(re.finditer(r"^        case \w+\n", source, re.M))[-1]
            groups.write_text(source[:last_case.end()] + f"        case {name}Group\n" + source[last_case.end():])
            self.assertEqual(SHAPE.check(self.root), [])
            run(self.root, "git", "add", ".")
            run(self.root, "git", "commit", "-qm", f"Append {name}")
        run(self.root, "git", "switch", "-q", "base")
        for name in ("unionAlpha", "unionBeta", "unionGamma"):
            run(self.root, "git", "merge", "--no-ff", "--no-edit", name)
            self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
            self.assertEqual(SHAPE.check(self.root), [])
            run(self.root, "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-typecheck", str(SHAPE.FEATURE), str(SHAPE.GROUPS))
            print(f"PASS: {name} merge clean; feature, group and all switch appends typecheck", flush=True)
        features = (self.root / SHAPE.FEATURE).read_text()
        groups = (self.root / SHAPE.GROUPS).read_text()
        for name in ("unionAlpha", "unionBeta", "unionGamma"):
            self.assertEqual(features.count(f"    case {name}\n"), 1)
            self.assertEqual(groups.count(f"        case {name}Group\n"), 1)
            expected_arms = 5 if "var startsOff:" in features else 4
            self.assertEqual(features.count(f"case .{name}:"), expected_arms)


if __name__ == "__main__":
    unittest.main(verbosity=2)
