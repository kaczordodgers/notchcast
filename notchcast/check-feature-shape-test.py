#!/usr/bin/env python3
"""Reject unsafe registrations and typecheck three concurrent feature appends."""

import contextlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
CHECKER = ROOT / "notchcast/check-feature-shape.py"
SPEC = importlib.util.spec_from_file_location("feature_shape", CHECKER)
SHAPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHAPE)
SCHEMA, MODULES, SEARCH, DESCRIPTORS, REGISTRANTS, CATALOG = SHAPE.LISTS
PREFS = SHAPE.PREFERENCES
DESCRIBED = sorted(path.relative_to(ROOT) for path in ROOT.glob("Tinycast/Features/**/*Descriptor.swift")
                   if path.relative_to(ROOT).parent != SHAPE.DESCRIPTORS.parent)
HIDE = Path("Tinycast/Features/HideCommandM/HideCommandMDescriptor.swift")
# A capture-module arm: it stays on the switches, so planted edits keep an anchor.
ARM = "case .colorPicker: .captureAndDictation"
AI_COMMAND = "Tinycast/Features/Tweaks/TweakProfileCommands.swift"
SCREEN_TEXT = ".feature(.screenText, settings: [.captureScreenTextLineBreaks])"
PASTE_ENTRY = ".init(requires: [.pastePlain], module: plainPasteModule)"
ARCHIVES_HOOK = "        if NotchcastCore.archives.open(url) { return }\n"
DEEP_LINK_HOOK = "        if deepLinkCoordinator.handles(url) {"
ARCHIVE_ENTRIES = "Tinycast/Features/Archives/NotchcastArchiveModules.swift"
GLOBE = "Tinycast/Features/DictationTrigger/GlobeDictationDescriptor.swift"
# A fact the checker finds nowhere must fail, not pass: the error, the file, then the text every copy of which is replaced.
UNREAD = (
    (".startupItems wired is None; the spec pins true", SHAPE.FEATURE, "static let unwired", "static let notWired"),
    ("found no Descriptor field", DESCRIPTORS, "        let ", "        var "),
    ("found no module static", MODULES, "    static let ", "    static var "),
    ("found no setting", SHAPE.SETTINGS, "    case ", "  case "),
    ("found no backup anchor", SEARCH, "static let notchcastBackup", "static let backup"),
    (".screenText has no place in the settings tree", SHAPE.TREE, "case .", "case  ."),
)
# One planted break of the shipped tree per spec fact: its rule, the error it must raise, the file, then old and new text.
BREAKS = (
    ("feature-pins", ".archivesInPlace defaultEnabled is true; the spec pins false",
     "Tinycast/Features/Archives/ArchivesInPlaceDescriptor.swift", "defaultEnabled: false", "defaultEnabled: true"),
    ("feature-pins", ".captureEditor defaultEnabled is true; the spec pins false",
     SHAPE.FEATURE, "case .captureEditor: false", "case .captureEditor: true"),
    ("feature-pins", ".startupItems wired is false; the spec pins true", SHAPE.FEATURE, "        .todoIsland,\n", "        .todoIsland,\n        .startupItems,\n"),
    ("feature-pins", ".screenText settings is []; the spec pins [.captureScreenTextLineBreaks]",
     SHAPE.TREE, SCREEN_TEXT, ".feature(.screenText, settings: [])"),
    ("feature-pins", ".sudoTouchID needsIsland is true; a feature whose isSystemTweak is true keeps false",
     "Tinycast/Features/SystemTools/SudoTouchIDDescriptor.swift", "dependencies: []", "dependencies: [.island]"),
    ("feature-text", ".screenshot needs a localized, non-empty title",
     SHAPE.FEATURE, 'case .screenshot: String(localized: "Screenshots", table: "Notchcast")', 'case .screenshot: ""'),
    ("settings-item-once", ".scrollingCapture is already in the settings tree",
     SHAPE.TREE, SCREEN_TEXT, ".feature(.scrollingCapture, settings: [])"),
    ("settings-item-once", ".screenText has no place in the settings tree",
     SHAPE.TREE, SCREEN_TEXT, ".feature(.scrollingCapture, settings: [])"),
    ("command-owner", "a command states slug: first and names its owner",
     AI_COMMAND, 'sfSymbol: "brain", feature: .aiFeaturesOff,', 'sfSymbol: "brain",'),
    ("command-slugs", "add the line `ai-off aiFeaturesOff`", AI_COMMAND, 'slug: "ai-features-off"', 'slug: "ai-off"'),
    ("command-slugs", "`ai-features-off aiFeaturesOff` matches no command", AI_COMMAND, 'slug: "ai-features-off"', 'slug: "ai-off"'),
    ("command-slugs", "add the line `ai-features-off privacyChoices`",
     AI_COMMAND, 'sfSymbol: "brain", feature: .aiFeaturesOff,', 'sfSymbol: "brain", feature: .privacyChoices,'),
    ("command-slugs", "repeated command slug privacy-choices", AI_COMMAND, 'slug: "ai-features-off"', 'slug: "privacy-choices"'),
    ("command-slugs", 'hook missing or out of order: "command:nc-" + slug', SHAPE.COMMAND, '"command:nc-" + slug', '"command:" + slug'),
    ("command-listed", "list SmallCommandsModule.airDropCommand, in", CATALOG, "        SmallCommandsModule.airDropCommand,\n", ""),
    ("module-entry-requires", "the entry that runs plainPasteModule requires .pastePlain",
     MODULES, PASTE_ENTRY, ".init(requires: [], module: plainPasteModule)"),
    ("module-built-once", "build PlainPasteModule once", MODULES, "        self.pastePlain = plainPasteModule\n", ""),
    ("module-built-once", "build PlainPasteModule once",
     MODULES, "self.pastePlain = plainPasteModule", "self.pastePlain = PlainPasteModule(clipboard: core.clipboardManager)"),
    ("module-built-once", "build PlainPasteModule once", MODULES, PASTE_ENTRY, ".init(requires: [.pastePlain], module: chatTools)"),
    ("module-entry-once", "run cleaning in exactly one entry", MODULES, "            .init(requires: [.cleaningMode], module: cleaning),\n", ""),
    ("module-entry-once", "run appUpdates in exactly one entry",
     MODULES, "            .init(requires: [.appUpdates], module: appUpdates),\n", ""),
    ("module-entry-once", "run machineBackup in exactly one entry", MODULES,
     "            .init(requires: [], requiresAny: [.backupRunNow, .backupBrowseRestore], module: machineBackup),\n", ""),
    ("module-entry-once", "run module in one entry", ARCHIVE_ENTRIES, "module: module)]",
     "module: module), .init(requires: [.archivesInPlace], module: module)]"),
    ("module-entry-requires", "the entry that runs tasks requires .tasks", SHAPE.MODULES.with_name("NotchcastServicesModules.swift"),
     ".init(requires: [.tasks], module: tasks)", ".init(requires: [.island], module: tasks)"),
    ("source-hooks", "hook missing or out of order: [.init(requires: [.archives], module: module)]",
     ARCHIVE_ENTRIES, "requires: [.archives]", "requires: []"),
    ("feature-pins", ".globeDictation needsIsland is true; the spec pins false",
     GLOBE, "dependencies: [],", "dependencies: [\n            .island\n        ],"),
    ("feature-pins", "open the descriptor with `static let <feature> = Self(`", GLOBE, "= Self(", "= NotchcastFeature.Descriptor("),
    ("feature-pins", ".captureEditor defaultEnabled reads `[`; state the whole value on one line",
     SHAPE.FEATURE, "case .captureEditor: false", "case .captureEditor: ["),
    ("setting-one-case", "declare only one enum case per line", SHAPE.SETTINGS, "    case islandHoverDelay\n", "    case islandHoverDelay, islandRowless\n"),
    ("setting-row", ".probeNoRow needs exactly one arm", SHAPE.SETTINGS, "    case islandHoverDelay\n", "    case islandHoverDelay\n    case probeNoRow // new\n"),
    ("setting-row-arm", ".captureScreenTextLineBreaks needs exactly one arm that shows a row",
     SHAPE.TREE.with_name("NotchcastSettingRows+C.swift"),
     "ScreenTextLineBreaksSettingRow(module: ScreenTextModule.shared)", "EmptyView()"),
    ("backup-anchor-header", "give .notchcastBackupExport a SettingsSectionHeader",
     SHAPE.BACKUPS, "SettingsSectionHeader(.notchcastBackupExport)", "SettingsSectionHeader(.notchcastBackupImport)"),
    ("source-hooks", "hook missing or out of order: await NotchcastCore.archives.prepareForTermination()",
     "Tinycast/App/AppCore.swift", "await NotchcastCore.archives.prepareForTermination()", ""),
    ("source-hooks", "hook missing or out of order: if deepLinkCoordinator.handles(url)",
     "Tinycast/App/AppCore.swift", ARCHIVES_HOOK, "", DEEP_LINK_HOOK, ARCHIVES_HOOK + "        do {"),
    ("source-hooks", "hook missing or out of order: var extensionsEnabled: Bool { get { false } set { } }",
     SHAPE.APP_SETTINGS, "var extensionsEnabled: Bool {\n        get { false }", "var extensionsEnabled: Bool {\n        get { true }"),
    ("source-hooks", "keep showSupport out of this file",
     "Tinycast/App/MenuBarItem.swift", "showAbout() }", "showAbout() }\n            Button(\"Support\") { showSupport() }"),
    ("plist", "declare one Archives document type", SHAPE.PLIST, "<string>Alternate</string>", "<string>Owner</string>"),
    ("plist", "declare one Archives document type", SHAPE.ARCHIVE_FORMATS, '"public.zip-archive", ', ""),
    ("plist", "imported type com.example.zoo-archive is neither app.notchcast.* nor in FOREIGN_TYPES", SHAPE.PLIST,
     "<key>UTTypeIdentifier</key>\n\t\t\t<string>app.notchcast.zoo-archive<", "<key>UTTypeIdentifier</key>\n\t\t\t<string>com.example.zoo-archive<"),
    ("plist", "an imported type carries the split-archive extension 001", SHAPE.PLIST, "<string>001</string>", "<string>002</string>"),
    ("plist", "NSBonjourServices lists exactly MachLinkManager.serviceType",
     SHAPE.PLIST, "<string>_notchcast-link._tcp</string>", "<string>_other-link._tcp</string>"),
    ("plist", "NSLocalNetworkUsageDescription reads", SHAPE.PLIST, SHAPE.LOCAL_NETWORK, "Uses the network."),
)


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
            "[.island, .systemNotices], module: systemNotices),", "[.island, .systemNotices],\n                module: systemNotices),"),
            "keep each list entry on one line")

    def test_repeated_module_entry(self):
        source = (self.root / MODULES).read_text()
        self.rejected(MODULES, source.replace(
            ".init(requires: [.island, .systemNotices], module: systemNotices),",
            ".init(requires: [.island, .systemNotices], module: systemNotices),\n            .init(requires: [.systemNotices], module: systemNotices),"),
            "repeated entry systemNotices")

    def test_repeated_registrant(self):
        source = (self.root / REGISTRANTS).read_text()
        line = "        LowDiskModule.self,\n"
        self.assertEqual(source.count(line), 1)
        self.rejected(REGISTRANTS, source.replace(line, line + line), "repeated entry LowDiskModule")

    def test_two_registrants_on_one_line(self):
        source = (self.root / REGISTRANTS).read_text()
        self.rejected(REGISTRANTS, source.replace("LowDiskModule.self,", "LowDiskModule.self, LowDiskModule.self,"),
                      "list one registrant per line")

    def test_registrant_still_in_the_hub(self):
        source = (self.root / MODULES).read_text()
        anchor = "            .init(requires: [.island, .dayMarkets], module: markets),\n"
        for case, edited in enumerate((source.replace("    static let battery", "    static let lowDisk = LowDiskModule()\n    static let battery"),
                       source.replace("    static let battery", "    static private(set) var lowDisk: LowDiskModule?\n    static let battery"),
                       source.replace(anchor, anchor + "            .init(requires: [.lowDiskWarning], module: LowDiskModule.shared),\n"))):
            with self.subTest(case=case):
                self.rejected(MODULES, edited, "LowDiskModule registers itself")
        (self.root / MODULES).write_text(source)
        self.assertEqual(SHAPE.check(self.root), [])

    def test_register_outside_its_registration_file(self):
        source = ("extension LowDiskModule: NotchcastRegistrant {\n"
                  "    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] { [] }\n}\n")
        home = Path("Tinycast/Features/LowDisk/LowDiskModule+Registration.swift")
        (self.root / home).parent.mkdir(parents=True, exist_ok=True)
        (self.root / home).write_text(source)
        self.assertEqual(SHAPE.check(self.root), [])
        (self.root / home).unlink()
        brace_below = source.replace("Entry] { [] }", "Entry]\n    {\n        []\n    }")
        arrow_below = source.replace("AppCore) ->", "AppCore)\n        ->")
        for path, code in ((Path("Tinycast/Features/LowDisk/LowDiskCommands.swift"), source),
                           (Path("Tinycast/Features/LowDisk/LowDiskCommands.swift"), brace_below),
                           (Path("Tinycast/Features/LowDisk/LowDiskCommands.swift"), arrow_below),
                           (Path("Tinycast/Features/LowDisk/Service/LowDiskModule+Registration.swift"), source),
                           (Path("Tinycast/Features/Notchcast/Core/LowDiskModule+Registration.swift"), source),
                           (Path("Tinycast/Features/Notchcast/LowDiskModule+Registration.swift"), source)):
            with self.subTest(path=path, brace_below=code is brace_below):
                (self.root / path).parent.mkdir(parents=True, exist_ok=True)
                self.rejected(path, code, "implement register(_: AppCore) in")
                (self.root / path).unlink()
        protocol = Path("Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift")
        (self.root / protocol).write_text((ROOT / protocol).read_text())
        self.assertEqual(SHAPE.check(self.root), [])

    def test_registration_missing_from_registrants(self):
        home = Path("Tinycast/Features/LowDisk/LowDiskModule+Registration.swift")
        (self.root / home).parent.mkdir(parents=True, exist_ok=True)
        (self.root / home).write_text((ROOT / home).read_text())
        source = (self.root / REGISTRANTS).read_text()
        (self.root / REGISTRANTS).write_text(source.replace("        LowDiskModule.self,\n", ""))
        self.rejected(home, (ROOT / home).read_text(), f"list LowDiskModule.self, in {REGISTRANTS}")

    def test_register_in_an_upstream_folder(self):
        shipped = Path("Tinycast/Features/Launcher/LauncherScreen.swift")
        (self.root / shipped).parent.mkdir(parents=True, exist_ok=True)
        (self.root / shipped).write_text("struct LauncherScreen {}\n")
        run(self.root, "git", "init", "-q", "-b", "main")
        run(self.root, "git", "add", str(shipped))
        run(self.root, "git", "-c", "user.name=Upstream", "-c", "user.email=upstream@example.invalid",
            "commit", "-qm", "Upstream")
        run(self.root, "git", "update-ref", "refs/remotes/upstream/main", "HEAD")
        self.rejected(Path("Tinycast/Features/Launcher/CopyPathModule+Registration.swift"),
                      "extension CopyPathModule {\n    static func register(_ core: AppCore) -> [Entry] { [] }\n}\n",
                      "upstream ships Features/Launcher/")

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


class FeatureFactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="notchcast-feature-facts-")
        cls.addClassCleanup(temporary.cleanup)
        cls.root = Path(temporary.name)
        for path in (*ROOT.glob("Tinycast/**/*.swift"), ROOT / SHAPE.PLIST, ROOT / SHAPE.SLUGS):
            copy = cls.root / path.relative_to(ROOT)
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, copy)

    def test_shipped_tree_holds_every_fact(self):
        self.assertEqual(SHAPE.fact_errors(self.root), [])

    def test_a_comment_above_a_descriptor_field_passes(self):
        path = self.root / GLOBE
        shipped = path.read_text()
        self.assertIn("        dependencies: [],\n", shipped)
        path.write_text(shipped.replace("        dependencies: [],\n", "        // note: kept off the island\n        dependencies: [],\n", 1))
        try:
            self.assertEqual(SHAPE.fact_errors(self.root), [])
        finally:
            path.write_text(shipped)

    def test_each_planted_break_is_caught(self):
        for rule, message, path, *swaps in BREAKS:
            with self.subTest(rule=rule, message=message):
                shipped = broken = (self.root / path).read_text()
                for old, new in zip(swaps[::2], swaps[1::2]):
                    self.assertIn(old, broken)
                    broken = broken.replace(old, new, 1)
                (self.root / path).write_text(broken)
                try:
                    errors = SHAPE.fact_errors(self.root)
                finally:
                    (self.root / path).write_text(shipped)
                self.assertIn(message, "\n".join(errors))
                for error in errors:
                    self.assertRegex(error, r"^[\w/+.-]+:\d+: ")

    def test_a_fact_found_nowhere_fails(self):
        for message, path, old, new in UNREAD:
            with self.subTest(message=message):
                shipped = (self.root / path).read_text()
                self.assertIn(old, shipped)
                (self.root / path).write_text(shipped.replace(old, new))
                try:
                    errors = SHAPE.fact_errors(self.root)
                finally:
                    (self.root / path).write_text(shipped)
                self.assertIn(message, "\n".join(errors))
        with unittest.mock.patch.object(SHAPE, "CLASS_PINS", (("group", ".nowhere", "needsIsland", "false"),)):
            self.assertIn("no feature's group is .nowhere", "\n".join(SHAPE.fact_errors(self.root)))
        with unittest.mock.patch.object(SHAPE, "ABSENT", (("Tinycast/App/Gone.swift", "showSupport"),)):
            self.assertIn("found no file to keep showSupport out of", "\n".join(SHAPE.fact_errors(self.root)))

    def test_unreadable_tree_fails_every_rule(self):
        with tempfile.TemporaryDirectory() as empty:
            errors = SHAPE.fact_errors(Path(empty))
        self.assertEqual([error.split(":")[0] for error in errors],
                         ["feature_errors", "command_errors", "module_errors", "source_errors", "plist_errors"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
