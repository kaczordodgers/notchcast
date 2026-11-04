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

    def test_bare_case_before_multiline_arm(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            "case .island: .island", "case\n            .island, .islandExternalDisplays: .island"),
            "multi-case arm")

    def test_enum_comma_on_next_line(self):
        source = (self.root / SHAPE.GROUPS).read_text()
        self.rejected(SHAPE.GROUPS, source.replace(
            "case launcher\n", "case launcher\n        , launcher2\n"), "one enum case per line")

    def test_repeated_enum_cases(self):
        for path, name in ((SHAPE.FEATURE, "island"), (SHAPE.FEATURE, "accessibility"),
                           (SHAPE.GROUPS, "launcher")):
            with self.subTest(path=path, name=name):
                source = (ROOT / path).read_text()
                self.rejected(path, source.replace(
                    f"case {name}\n", f"case {name}\n    case {name}\n"), f"repeated case {name}")
                (self.root / path).write_text(source)

    def test_repeated_switch_arm(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            "case .dayMarkets: .activities", "case .dayMarkets: .activities\n        case .dayMarkets: .system"),
            "repeated case .dayMarkets in switch")

    def test_needs_island_multi_case_arm(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            "case .displayBrightness: false", "case .displayBrightness, .quitProtection: false"),
            "multi-case arm")

    def test_union_duplicated_group_header(self):
        source = (self.root / SHAPE.GROUPS).read_text()
        self.rejected(SHAPE.GROUPS, source + source, "expected one SettingsGroup enum, found 2")

    def test_multiline_arm_and_starts_off(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        source += "\nextension NotchcastFeature {\n    var startsOff: Bool {\n        switch self {\n"
        source += "        case .island,\n             .systemMonitor: true\n        default: false\n"
        source += "        }\n    }\n}\n"
        self.rejected(SHAPE.FEATURE, source, "multi-case arm")

    def init_repository(self):
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

    def test_union_append_beside_edited_arm(self):
        self.init_repository()
        feature = self.root / SHAPE.FEATURE
        run(self.root, "git", "switch", "-qc", "append", "base")
        source = feature.read_text().replace("    case dayMarkets\n", "    case dayMarkets\n    case captureArea\n")
        for member, value in (("settingsGroup", ".activities"),
                              ("title", 'String(localized: "Capture Area")'),
                              ("subtitle", 'String(localized: "Capture an area.")')):
            start = source.index(f"    var {member}:")
            end = source.index("\n        }", start)
            arm = re.search(r"^        case \.dayMarkets:[^\n]*", source[start:end], re.M)
            insertion = start + arm.end() + 1
            source = source[:insertion] + f"        case .captureArea: {value}\n" + source[insertion:]
        feature.write_text(source)
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Append captureArea beside dayMarkets")
        run(self.root, "git", "switch", "-qc", "edit", "base")
        feature.write_text(feature.read_text().replace("case .dayMarkets: .activities", "case .dayMarkets: .system"))
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Change dayMarkets group")
        run(self.root, "git", "switch", "-q", "append")
        run(self.root, "git", "merge", "--no-ff", "--no-edit", "edit")
        self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        merged = feature.read_text()
        self.assertIn("case .dayMarkets: .activities", merged)
        self.assertIn("case .dayMarkets: .system", merged)
        self.assertIn("case .captureArea: .activities", merged)
        self.rejected(SHAPE.FEATURE, merged, "repeated case .dayMarkets in switch")
        print("PASS: captureArea append plus dayMarkets edit merges clean; checker rejects retained old arm", flush=True)

    def test_three_branch_union_merge(self):
        self.init_repository()
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
