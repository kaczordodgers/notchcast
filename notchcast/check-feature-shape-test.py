#!/usr/bin/env python3
"""Reject unsafe registrations and typecheck three concurrent feature appends."""

import contextlib
import importlib.util
import io
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
SCHEMA, MODULES, SEARCH, DESCRIPTORS = SHAPE.LISTS
PREFS = SHAPE.PREFERENCES
DESCRIBED = sorted(path.relative_to(ROOT) for path in ROOT.glob("Tinycast/Features/**/*Descriptor.swift")
                   if path.relative_to(ROOT).parent != SHAPE.DESCRIPTORS.parent)
HIDE = Path("Tinycast/Features/HideCommandM/HideCommandMDescriptor.swift")
# A capture-module arm: it stays on the switches, so planted edits keep an anchor.
ARM = "case .colorPicker: .captureAndDictation"


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
    def test_repeated_backup_key(self):
        source = (ROOT / SCHEMA).read_text()
        self.rejected(SCHEMA, source.replace('"island": .bool,',
            '"island": .bool,\n        "island": .string(10),'), "repeated entry island")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="notchcast-feature-union-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for path in (SHAPE.FEATURE, SHAPE.GROUPS, *SHAPE.LISTS, SHAPE.PREFERENCES, *DESCRIBED):
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
            ARM, "case .colorPicker, .screenshot: .captureAndDictation"),
            "multi-case arm")

    def test_single_line_string_values(self):
        for value in ('"Other"', 'String(localized: "Other")'):
            with self.subTest(value=value):
                source = (ROOT / SHAPE.FEATURE).read_text()
                self.assertEqual(source.count(ARM), 1)
                (self.root / SHAPE.FEATURE).write_text(source.replace(ARM, f"case .colorPicker: {value}"))
                self.assertEqual(SHAPE.check(self.root), [])

    def test_two_switch_cases_on_one_line(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            ARM, 'case .colorPicker: "Other"; case .extra: "Extra"'),
            "own line")

    def test_multiline_string_value(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            ARM, 'case .colorPicker:\n            "Other"'),
            "keep each feature arm on one line")

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
            ARM, "case\n            .colorPicker, .screenshot: .captureAndDictation"),
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
            "case .treadmillWalk: .activities", "case .treadmillWalk: .activities\n        case .treadmillWalk: .system"),
            "repeated case .treadmillWalk in switch")

    def test_default_enabled_multi_case_arm(self):
        source = (self.root / SHAPE.FEATURE).read_text()
        self.rejected(SHAPE.FEATURE, source.replace(
            "case .captureEditor: false", "case .captureEditor, .treadmillWalk: false"),
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

    def test_list_entry_split_over_lines(self):
        source = (self.root / MODULES).read_text()
        self.rejected(MODULES, source.replace(
            "[.island, .lowDiskWarning], module: lowDisk),", "[.island, .lowDiskWarning],\n                module: lowDisk),"),
            "keep each list entry on one line")

    def test_repeated_module_entry(self):
        source = (self.root / MODULES).read_text()
        self.rejected(MODULES, source.replace(
            ".init(requires: [.island, .lowDiskWarning], module: lowDisk),",
            ".init(requires: [.island, .lowDiskWarning], module: lowDisk),\n            .init(requires: [.lowDiskWarning], module: lowDisk),"),
            "repeated entry lowDisk")

    def test_repeated_static(self):
        source = (self.root / MODULES).read_text()
        self.rejected(MODULES, source.replace(
            "    static let timers = LiveTimerModule()\n",
            "    static let timers = LiveTimerModule()\n    static let timers = LiveTimerModule(sound: true)\n"),
            "repeated static timers")

    def test_repeated_search_entry_with_new_keywords(self):
        source = (self.root / SEARCH).read_text()
        line = ('        .init(group: .notchcast(feature: .liveTimers), LocalizedStringResource("Timers", table: "Notchcast"),'
                ' keywords: ["duration", "alarm", "sound"]),\n')
        self.rejected(SEARCH, source.replace(line, line + line.replace('"sound"', '"sound", "ring"')),
                      'repeated entry .init(group: .notchcast(feature: .liveTimers), LocalizedStringResource("Timers"')

    def test_setting_split_over_lines(self):
        source = (self.root / PREFS).read_text()
        line = '    var fanMode: String { didSet { defaults.set(fanMode, forKey: "fanMode") } }'
        self.rejected(PREFS, source.replace(line, line.replace("{ didSet", "{\n        didSet")),
                      "keep each setting on one line")

    def test_repeated_setting(self):
        source = (self.root / PREFS).read_text()
        line = '    var fanMode: String { didSet { defaults.set(fanMode, forKey: "fanMode") } }\n'
        self.rejected(PREFS, source.replace(line, line + line.replace("String", "String?")), "repeated setting fanMode")

    def test_repeated_assignment(self):
        source = (self.root / PREFS).read_text()
        line = '        fanMode = defaults.string(forKey: "fanMode") ?? "auto"\n'
        self.rejected(PREFS, source.replace(line, line + line.replace('"auto"', '"quiet"')), "repeated assignment fanMode")

    def test_init_statement_split_over_lines(self):
        source = (self.root / PREFS).read_text()
        self.rejected(PREFS, source.replace(
            'Self.threshold(defaults, "monitorCPU", 90, 10...100)', 'Self.threshold(defaults, "monitorCPU",\n            90, 10...100)'),
            "keep each init statement on one line")

    def test_union_duplicated_preferences_class(self):
        source = (self.root / PREFS).read_text()
        self.rejected(PREFS, source + source, "expected one NotchcastPreferences class")

    def test_arm_for_described_feature(self):
        for anchor, arm in ((ARM + "\n", "case .hideCommandM: .system\n"),
                            ("case .recording: [.screenRecording]\n", "case .linkHealth: []\n")):
            with self.subTest(arm=arm):
                source = (ROOT / SHAPE.FEATURE).read_text()
                self.assertEqual(source.count(anchor), 1)
                self.rejected(SHAPE.FEATURE, source.replace(anchor, anchor + "        " + arm), "has a descriptor")
                (self.root / SHAPE.FEATURE).write_text(source)

    def test_descriptor_outside_its_feature_folder(self):
        source = (ROOT / HIDE).read_text()
        (self.root / HIDE).unlink()
        for path in (Path("Tinycast/Features/Notchcast/Core/HideCommandMDescriptor.swift"),
                     Path("Tinycast/Features/HideCommandM/Model/HideCommandMDescriptor.swift"),
                     Path("Tinycast/Features/HideCommandM/HideCommandM.swift")):
            with self.subTest(path=path):
                (self.root / path).parent.mkdir(parents=True, exist_ok=True)
                self.rejected(path, source, "declare a descriptor in Tinycast/Features/<its folder>/")
                (self.root / path).unlink()
        hub = (ROOT / DESCRIPTORS).read_text()
        self.rejected(DESCRIPTORS, hub.rstrip() + "\n\n" + source.split("\n", 1)[1], "declare a descriptor in")

    def test_typed_and_init_descriptor_outside_its_feature_folder(self):
        ghost = ('extension NotchcastFeature {\n    static let ghost: Descriptor = .init(title: "", subtitle: "",'
                 ' group: .system, defaultEnabled: false, dependencies: [], requiredGrants: [],'
                 ' isSystemFeature: false, isSystemTweak: false)\n}\n')
        returned = ghost.replace("static let ghost: Descriptor = .init(", "static func ghost() -> Descriptor { .init(")
        for path, source in ((Path("Tinycast/Features/LowDisk/Model/SubfolderDescriptor.swift"), ghost),
                             (Path("Tinycast/Features/LowDisk/LowDiskGhost.swift"),
                              ghost.replace(": Descriptor = .init(", " = NotchcastFeature.Descriptor.init(")),
                             (Path("Tinycast/Features/LowDisk/LowDiskGhost.swift"), returned.replace(")\n}", ") }\n}"))):
            with self.subTest(path=path):
                (self.root / path).parent.mkdir(parents=True, exist_ok=True)
                self.rejected(path, source, "declare a descriptor in Tinycast/Features/<its folder>/")
                (self.root / path).unlink()

    def test_descriptor_in_a_nested_code_folder(self):
        source = (ROOT / HIDE).read_text()
        (self.root / HIDE).unlink()
        for folder in ("Notchcast/Island", "Distill/Convert", "MachRemote/Integration"):
            with self.subTest(folder=folder):
                path = self.root / "Tinycast/Features" / folder / HIDE.name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
                self.assertEqual(SHAPE.check(self.root), [])
                path.unlink()
        for folder in ("Notchcast", "Notchcast/Core", "Distill/Convert/Model", "Distill/Convert/Service",
                       "Notchcast/Island/UI", "Notchcast/Settings"):
            with self.subTest(folder=folder):
                path = Path("Tinycast/Features") / folder / HIDE.name
                (self.root / path).parent.mkdir(parents=True, exist_ok=True)
                self.rejected(path, source, "declare a descriptor in Tinycast/Features/<its folder>/")
                (self.root / path).unlink()

    def test_descriptor_cannot_restate_needs_island(self):
        source = (ROOT / HIDE).read_text()
        self.assertEqual(source.count("        isSystemTweak: false\n"), 1)
        (self.root / HIDE).write_text(source.replace("        isSystemTweak: false\n",
                                                     "        isSystemTweak: false,\n        needsIsland: false\n"))
        result = subprocess.run(["swiftc", "-swift-version", "6", "-typecheck", str(SHAPE.FEATURE), str(SHAPE.GROUPS),
                                 str(DESCRIPTORS), *(str(self.root / path) for path in DESCRIBED)],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0, "needsIsland is derived from dependencies, never stated")
        self.assertIn("needsIsland", result.stderr)

    def test_descriptor_file_names_its_one_feature(self):
        source = (ROOT / HIDE).read_text()
        (self.root / HIDE).unlink()
        self.rejected(HIDE.with_name("HideDescriptor.swift"), source, "declare exactly one descriptor, .hide")
        (self.root / HIDE.with_name("HideDescriptor.swift")).unlink()
        self.rejected(HIDE, source.replace("    static let hideCommandM", "    static let hideCommandK = hideCommandM\n"
                                           "    static let hideCommandM"), "declare exactly one descriptor")

    def test_descriptor_file_the_hub_does_not_list(self):
        path = Path("Tinycast/Features/Treadmill/TreadmillWalkDescriptor.swift")
        (self.root / path).parent.mkdir(parents=True, exist_ok=True)
        self.rejected(path, (ROOT / HIDE).read_text().replace("static let hideCommandM", "static let treadmillWalk"),
                      f"list .treadmillWalk: .treadmillWalk, in {DESCRIPTORS}")

    def test_descriptor_in_an_upstream_folder(self):
        shipped = Path("Tinycast/Features/Launcher/LauncherScreen.swift")
        (self.root / shipped).parent.mkdir(parents=True, exist_ok=True)
        (self.root / shipped).write_text("struct LauncherScreen {}\n")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(SHAPE.upstream_folders(self.root), set())
        self.assertIn("no upstream/main ref", stderr.getvalue())
        run(self.root, "git", "init", "-q", "-b", "main")
        run(self.root, "git", "add", str(shipped))
        run(self.root, "git", "-c", "user.name=Upstream", "-c", "user.email=upstream@example.invalid",
            "commit", "-qm", "Upstream")
        run(self.root, "git", "update-ref", "refs/remotes/upstream/main", "HEAD")
        self.assertEqual(SHAPE.check(self.root), [])
        source = (ROOT / HIDE).read_text()
        (self.root / HIDE).unlink()
        for folder in ("Launcher", "Launcher/Keys"):
            with self.subTest(folder=folder):
                path = Path("Tinycast/Features") / folder / HIDE.name
                (self.root / path).parent.mkdir(parents=True, exist_ok=True)
                self.rejected(path, source, "upstream ships Features/Launcher/")
                (self.root / path).unlink()

    def test_hub_entry_maps_another_descriptor(self):
        source = (ROOT / DESCRIPTORS).read_text()
        self.rejected(DESCRIPTORS, source.replace(".linkHealth: .linkHealth,", ".linkHealth: .lowDiskWarning,"),
                      ".linkHealth must map to its own descriptor")

    def test_undescribed_feature_without_exhaustive_arm(self):
        source = (ROOT / SHAPE.FEATURE).read_text()
        arm = '        case .colorPicker: String(localized: "Color Picker", table: "Notchcast")\n'
        self.assertEqual(source.count(arm), 1)
        self.rejected(SHAPE.FEATURE, source.replace(arm, ""),
                      ".colorPicker needs a descriptor or a title arm")

    def init_repository(self):
        (self.root / ".gitattributes").write_text((ROOT / ".gitattributes").read_text())
        run(self.root, "git", "init", "-q", "-b", "base")
        run(self.root, "git", "config", "user.name", "Feature shape test")
        run(self.root, "git", "config", "user.email", "feature-shape@example.invalid")
        run(self.root, "git", "config", "core.hooksPath", os.devnull)
        run(self.root, "git", "config", "commit.gpgSign", "false")
        run(self.root, "git", "config", "merge.gpgSign", "false")
        for path in (SHAPE.FEATURE, SHAPE.GROUPS, *SHAPE.LISTS, SHAPE.PREFERENCES):
            self.assertTrue(run(self.root, "git", "check-attr", "merge", "--", str(path)).endswith(": union"))
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Base feature shape")

    def test_union_append_beside_edited_arm(self):
        self.init_repository()
        feature = self.root / SHAPE.FEATURE
        run(self.root, "git", "switch", "-qc", "append", "base")
        source = feature.read_text().replace("    case treadmillWalk\n", "    case treadmillWalk\n    case captureArea\n")
        for member, value in (("settingsGroup", ".activities"),
                              ("title", 'String(localized: "Capture Area")'),
                              ("subtitle", 'String(localized: "Capture an area.")')):
            start = source.index(f"    var {member}:")
            end = source.index("\n        }", start)
            arm = re.search(r"^        case \.treadmillWalk:[^\n]*", source[start:end], re.M)
            insertion = start + arm.end() + 1
            source = source[:insertion] + f"        case .captureArea: {value}\n" + source[insertion:]
        feature.write_text(source)
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Append captureArea beside treadmillWalk")
        run(self.root, "git", "switch", "-qc", "edit", "base")
        feature.write_text(feature.read_text().replace("case .treadmillWalk: .activities", "case .treadmillWalk: .system"))
        run(self.root, "git", "add", ".")
        run(self.root, "git", "commit", "-qm", "Change treadmillWalk group")
        run(self.root, "git", "switch", "-q", "append")
        run(self.root, "git", "merge", "--no-ff", "--no-edit", "edit")
        self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        merged = feature.read_text()
        self.assertIn("case .treadmillWalk: .activities", merged)
        self.assertIn("case .treadmillWalk: .system", merged)
        self.assertIn("case .captureArea: .activities", merged)
        self.rejected(SHAPE.FEATURE, merged, "repeated case .treadmillWalk in switch")
        print("PASS: captureArea append plus treadmillWalk edit merges clean; checker rejects retained old arm", flush=True)

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
                "-warnings-as-errors", "-typecheck", str(SHAPE.FEATURE), str(SHAPE.GROUPS),
                str(DESCRIPTORS), *map(str, DESCRIBED))
            print(f"PASS: {name} merge clean; feature, group and all switch appends typecheck", flush=True)
        features = (self.root / SHAPE.FEATURE).read_text()
        groups = (self.root / SHAPE.GROUPS).read_text()
        for name in ("unionAlpha", "unionBeta", "unionGamma"):
            self.assertEqual(features.count(f"    case {name}\n"), 1)
            self.assertEqual(groups.count(f"        case {name}Group\n"), 1)
            expected_arms = 5 if "var startsOff:" in features else 4
            self.assertEqual(features.count(f"case .{name}:"), expected_arms)

    def test_list_appends_merge_and_edit_is_caught(self):
        self.init_repository()
        modules, search = self.root / MODULES, self.root / SEARCH
        base = (modules.read_text(), search.read_text())
        anchor = "            .init(requires: [.island, .dayMarkets], module: markets),\n"
        row = '        .init(group: .notchcast(feature: .dayCalendar), "Calendar", keywords: ["events", "day", "schedule"]),\n'
        for name in ("alpha", "beta"):
            run(self.root, "git", "switch", "-qc", name, "base")
            modules.write_text(base[0].replace(
                "    static let battery", f"    static let {name} = LiveTimerModule()\n    static let battery").replace(
                anchor, anchor + f"            .init(requires: [.island], module: {name}),\n"))
            search.write_text(base[1].replace(row, row + f'        .init(group: .notchcast(feature: .dayCalendar), "{name}"),\n'))
            self.assertEqual(SHAPE.check(self.root), [])
            run(self.root, "git", "commit", "-qam", f"Append {name}")
        run(self.root, "git", "switch", "-q", "base")
        for name in ("alpha", "beta"):
            run(self.root, "git", "merge", "--no-ff", "--no-edit", name)
            self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        self.assertEqual(SHAPE.check(self.root), [])
        for name in ("alpha", "beta"):
            self.assertEqual(modules.read_text().count(f"module: {name})"), 1)
            self.assertEqual(search.read_text().count(f'"{name}"'), 1)
        run(self.root, "git", "switch", "-qc", "edit", "base~2")
        modules.write_text(base[0].replace("module: markets)", "module: markets, order: 1)"))
        run(self.root, "git", "commit", "-qam", "Edit markets entry")
        run(self.root, "git", "switch", "-q", "base")
        run(self.root, "git", "merge", "--no-ff", "--no-edit", "edit")
        self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        self.assertIn(f"{MODULES}", "\n".join(SHAPE.check(self.root)))
        self.assertIn("repeated entry markets", "\n".join(SHAPE.check(self.root)))
        print("PASS: module and search appends merge clean; checker rejects an edited entry kept twice", flush=True)

    def test_setting_appends_merge_and_edit_is_caught(self):
        self.init_repository()
        prefs = self.root / PREFS
        base = prefs.read_text()
        setting = '    var fanMode: String { didSet { defaults.set(fanMode, forKey: "fanMode") } }\n'
        assignment = '        fanMode = defaults.string(forKey: "fanMode") ?? "auto"\n'
        for name in ("alpha", "beta"):
            run(self.root, "git", "switch", "-qc", name, "base")
            prefs.write_text(base.replace(setting, setting + f'    var {name}: Bool {{ didSet {{ defaults.set({name}, forKey: "{name}") }} }}\n').replace(
                assignment, assignment + f'        {name} = defaults.bool(forKey: "{name}")\n'))
            self.assertEqual(SHAPE.check(self.root), [])
            run(self.root, "git", "commit", "-qam", f"Add {name} setting")
        run(self.root, "git", "switch", "-q", "base")
        for name in ("alpha", "beta"):
            run(self.root, "git", "merge", "--no-ff", "--no-edit", name)
            self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        self.assertEqual(SHAPE.check(self.root), [])
        run(self.root, "swiftc", "-swift-version", "6", "-typecheck", str(SHAPE.FEATURE), str(SHAPE.GROUPS), str(PREFS),
            str(DESCRIPTORS), *map(str, DESCRIBED),
            str(ROOT / "Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift"), str(ROOT / "Tinycast/Platform/AppPaths.swift"))
        run(self.root, "git", "switch", "-qc", "edit", "base~2")
        prefs.write_text(base.replace('?? "auto"', '?? "quiet"'))
        run(self.root, "git", "commit", "-qam", "Change fan mode default")
        run(self.root, "git", "switch", "-q", "base")
        run(self.root, "git", "merge", "--no-ff", "--no-edit", "edit")
        self.assertEqual(run(self.root, "git", "diff", "--name-only", "--diff-filter=U"), "")
        self.assertIn("repeated assignment fanMode", "\n".join(SHAPE.check(self.root)))
        print("PASS: setting appends merge clean and typecheck; checker rejects an edited assignment kept twice", flush=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
