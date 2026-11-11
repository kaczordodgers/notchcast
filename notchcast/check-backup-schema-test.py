#!/usr/bin/env python3
"""Exercise the backup classification checker against isolated source fixtures."""

import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-backup-schema.py")
KEYS = Path("Tinycast/Features/First/FirstBackupKeys.swift")
OWN_KEY = 'extension NotchcastFeature.BackupKeys {\n    static let first = Self(allowed: [\n        "first.size": .integer(1...9),\n    ], excluded: [\n        "first.cache",\n    ])\n}\n'
STORE = Path("Tinycast/Features/First/Service/FirstStore.swift")
OWNER = 'final class FirstStore {\n    static let sizeKey = "first.size"\n}\n'
LIVE = ('extension NotchcastFeature.BackupKeys {\n    static let first = Self(allowed: [\n'
        '        FirstStore.sizeKey: .integer(1...9),\n        "first.name": .json(.object(["title": .string(9)])),\n'
        '    ], excluded: [\n        "first.cache",\n    ], snapshot: {\n        let store = FirstStore.shared\n'
        '        return [FirstStore.sizeKey: store.size, "first.name": store.name]\n    }, apply: { values in\n'
        '        if let value = values[FirstStore.sizeKey] as? Int { FirstStore.shared.size = value }\n'
        '        if let value = values["first.name"] as? String { FirstStore.shared.name = value }\n    })\n}\n')
LIST = "Tinycast/Features/Notchcast/Core/NotchcastBackupKeys.swift"
CASES = (
    # label, allowed, excluded, listed features, key files, status, diagnostic
    ("unclassified", '"first": .bool,', '', '', {}, 1, "renamed (stored): unclassified"),
    ("good raw value", '"first": .bool,', '"stored",', '', {}, 0, "PASS"),
    ("double classification", '"first": .bool,\n"stored": .bool,', '"stored",', '', {}, 1, "stored declared twice"),
    ("comments ignored", '"first": .bool,\n// "stored": .bool,', '"stored",', '', {}, 0, "PASS"),
    ("feature key in its own folder", '"first": .bool,', '"stored",', '.first,', {KEYS: OWN_KEY}, 0, "PASS"),
    ("feature key typed in the schema", '"first": .bool,\n"first.size": .integer(1...9),', '"stored",', '', {}, 1,
     "first.size is a feature's own key"),
    ("feature key in both places", '"first": .bool,', '"stored",\n"first.cache",', '.first,', {KEYS: OWN_KEY}, 1,
     "first.cache declared twice"),
    ("key file the schema does not list", '"first": .bool,', '"stored",', '', {KEYS: OWN_KEY}, 1,
     f"list .first, in {LIST}"),
    ("listed feature without a key file", '"first": .bool,', '"stored",', '.first,', {}, 1,
     ".first has no FirstBackupKeys.swift"),
    ("key file in a layer folder", '"first": .bool,', '"stored",', '', {Path("Tinycast/Features/First/Model/FirstBackupKeys.swift"): OWN_KEY}, 1,
     "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("key file for an undescribed feature", '"first": .bool,', '"stored",', '.renamed,',
     {Path("Tinycast/Features/Renamed/RenamedBackupKeys.swift"): OWN_KEY.replace("static let first", "static let renamed")}, 1,
     ".renamed has no descriptor"),
    ("key file with two declarations", '"first": .bool,', '"stored",', '.first,',
     {KEYS: OWN_KEY.replace("}\n", "    static let second = first\n}\n")}, 1, "declare exactly one .first"),
    ("keys typed on a stray static", '"first": .bool,', '"stored",', '',
     {Path("Tinycast/Features/First/FirstStray.swift"): "enum Stray {\n    static let keys: NotchcastFeature.BackupKeys = .first\n}\n"},
     1, "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("keys returned from a func", '"first": .bool,', '"stored",', '',
     {Path("Tinycast/Features/First/FirstStray.swift"): "func strayKeys() -> BackupKeys {\n    .first\n}\n"},
     1, "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("two names on one list line", '"first": .bool,', '"stored",', '.first, .first,', {KEYS: OWN_KEY}, 1,
     f"{LIST}:4: list one feature per line"),
    ("feature listed twice", '"first": .bool,', '"stored",', '.first,\n.first,', {KEYS: OWN_KEY}, 1,
     ".first listed twice (first at line 4)"),
    ("key file away from its descriptor", '"first": .bool,', '"stored",', '.first,',
     {Path("Tinycast/Features/Elsewhere/FirstBackupKeys.swift"): OWN_KEY}, 1, "put it beside FirstDescriptor.swift"),
    ("live values match the allowed keys", '"first": .bool,', '"stored",', '.first,', {KEYS: LIVE, STORE: OWNER}, 0, "PASS"),
    ("snapshot writes a key not allowed", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE.replace('"first.name": store.name', '"first.title": store.name'), STORE: OWNER}, 1,
     "snapshot writes first.title, which the file does not allow"),
    ("snapshot writes an excluded key", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE.replace('"first.name": store.name', '"first.name": store.name, "first.cache": 1'), STORE: OWNER}, 1,
     "snapshot writes first.cache, which the file does not allow"),
    ("allowed key the snapshot drops", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE.replace(', "first.name": store.name', ''), STORE: OWNER}, 1,
     "FirstBackupKeys.swift:4: first.name is allowed, but snapshot never writes it"),
    ("apply reads a key not allowed", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE.replace('values["first.name"]', 'values["first.title"]'), STORE: OWNER}, 1,
     "apply reads first.title, which the file does not allow"),
    ("allowed key apply never reads", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE.replace('values[FirstStore.sizeKey]', 'values.first?.value'), STORE: OWNER}, 1,
     "FirstBackupKeys.swift:3: first.size is allowed, but apply never reads it"),
    ("owner constant retyped as a literal elsewhere", '"first": .bool,', '"stored",\n"first.size",', '.first,',
     {KEYS: LIVE, STORE: OWNER}, 1, "first.size declared twice"),
    ("owner renamed its constant", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE, STORE: OWNER.replace("sizeKey", "widthKey")}, 1, "FirstStore.sizeKey: no string constant sizeKey under First/"),
    ("constant on another type", '"first": .bool,', '"stored",', '.first,',
     {KEYS: LIVE, STORE: OWNER.replace("class FirstStore", "class OtherStore")}, 1, "no string constant sizeKey under First/"),
)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    core = root / "Tinycast/Features/Notchcast/Core"
    schema = root / "Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift"
    core.mkdir(parents=True)
    schema.parent.mkdir(parents=True)
    (core / "NotchcastFeature.swift").write_text('enum NotchcastFeature: String {\n case first\n case renamed = "stored"\n}\n')
    (core / "NotchcastFeature+Descriptor.swift").write_text(
        "extension NotchcastFeature {\n    static let descriptors: [Self: Descriptor] = [\n        .first: .first,\n    ]\n}\n")
    (root / KEYS).parent.mkdir(parents=True)
    (root / KEYS).with_name("FirstDescriptor.swift").write_text("")
    for label, allowed, excluded, listed, files, status, diagnostic in CASES:
        (root / LIST).write_text(f"extension NotchcastFeature.BackupKeys {{\n    /// One per line.\n    static let all: [Self] = [\n{listed}\n]\n}}\n")
        schema.write_text("enum ForkSettingsBackupSchema {\n"
                          f"private static let listedAllowed: [String: NotchcastFeature.BackupValue] = [\n{allowed}\n]\n"
                          f"private static let listedExcluded: Set<String> = [\n{excluded}\n]\n}}\n")
        for path, source in files.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(source)
        result = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)], text=True, capture_output=True)
        for path in files:
            (root / path).unlink()
        assert result.returncode == status, f"{label}: {result.stdout}{result.stderr}"
        output = result.stdout + result.stderr
        assert diagnostic in output, f"{label}: {output}"
        print(f"PASS {label}: {output.strip().splitlines()[0]}")
print(f"backup schema tests: PASS ({len(CASES)} fixtures)")
