#!/usr/bin/env python3
"""Exercise the backup classification checker against isolated source fixtures."""

import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-backup-schema.py")
KEYS = Path("Tinycast/Features/First/FirstBackupKeys.swift")
OWN_KEY = 'extension NotchcastFeature.BackupKeys {\n    static let first = Self(allowed: [\n        "first.size": .integer(1...9),\n    ], excluded: [\n        "first.cache",\n    ])\n}\n'
RENAMED_KEYS = Path("Tinycast/Features/Renamed/RenamedBackupKeys.swift")
RENAMED_KEY = OWN_KEY.replace("static let first", "static let renamed").replace("first.", "renamed.")
STORE = Path("Tinycast/Features/First/Service/FirstStore.swift")
OWNER = 'final class FirstStore {\n    static let sizeKey = "first.size"\n}\n'
HUB = Path("Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift")
LIVE = ('extension NotchcastFeature.BackupKeys {\n    static let first = Self(allowed: [\n'
        '        FirstStore.sizeKey: .integer(1...9),\n        "first.name": .json(.object(["title": .string(9)])),\n'
        '    ], excluded: [\n        "first.cache",\n    ], snapshot: {\n        let store = FirstStore.shared\n'
        '        return [FirstStore.sizeKey: store.size, "first.name": store.name]\n    }, apply: { values in\n'
        '        if let value = values[FirstStore.sizeKey] as? Int { FirstStore.shared.size = value }\n'
        '        if let value = values["first.name"] as? String { FirstStore.shared.name = value }\n    })\n}\n')
LIST = "Tinycast/Features/Notchcast/Core/NotchcastBackupKeys.swift"
FEATURE = "Tinycast/Features/Notchcast/Core/NotchcastFeature.swift"
# How the fixture's features say whether a backup carries their switch: .first in its descriptor, the others in an arm.
FLAG = "backedUp: true,"
ARMS = "case .renamed: false\ncase .secretKeeper: false"
CASES = (
    # label, descriptor flag, hub arms, listed features, key files, status, diagnostic
    ("unclassified", FLAG, "case .secretKeeper: false", '', {}, 1, "renamed (stored): unclassified"),
    ("described feature without a flag", '', ARMS, '', {}, 1, "first (first): unclassified"),
    ("good raw value", FLAG, ARMS, '', {}, 0, "PASS"),
    ("double classification", FLAG, ARMS + "\ncase .renamed: true", '', {}, 1, "stored declared twice"),
    ("flag stated and an arm kept", FLAG, ARMS + "\ncase .first: true", '', {}, 1, "first declared twice"),
    ("comments ignored", FLAG, ARMS + "\n// case .renamed: true", '', {}, 0, "PASS"),
    ("arm for no feature", FLAG, ARMS + "\ncase .ghost: true", '', {}, 1, ".ghost is no feature"),
    ("feature key in its own folder", FLAG, ARMS, '.first,', {KEYS: OWN_KEY}, 0, "PASS"),
    ("key file names a switch", FLAG, ARMS, '.first,', {KEYS: OWN_KEY.replace("first.cache", "stored")}, 1,
     "stored declared twice"),
    ("key in two key files", FLAG, ARMS, '.first,\n.renamed,',
     {KEYS: OWN_KEY, RENAMED_KEYS: RENAMED_KEY.replace("renamed.cache", "first.cache")}, 1, "first.cache declared twice"),
    ("key file the schema does not list", FLAG, ARMS, '', {KEYS: OWN_KEY}, 1, f"list .first, in {LIST}"),
    ("listed feature without a key file", FLAG, ARMS, '.first,', {}, 1, ".first has no FirstBackupKeys.swift"),
    ("key file in a layer folder", FLAG, ARMS, '', {Path("Tinycast/Features/First/Model/FirstBackupKeys.swift"): OWN_KEY}, 1,
     "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("key file for an undescribed feature", FLAG, ARMS, '.renamed,', {RENAMED_KEYS: RENAMED_KEY}, 0, "PASS"),
    ("key file with two declarations", FLAG, ARMS, '.first,',
     {KEYS: OWN_KEY.replace("}\n", "    static let second = first\n}\n")}, 1, "declare exactly one .first"),
    ("keys typed on a stray static", FLAG, ARMS, '',
     {Path("Tinycast/Features/First/FirstStray.swift"): "enum Stray {\n    static let keys: NotchcastFeature.BackupKeys = .first\n}\n"},
     1, "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("keys returned from a func", FLAG, ARMS, '',
     {Path("Tinycast/Features/First/FirstStray.swift"): "func strayKeys() -> BackupKeys {\n    .first\n}\n"},
     1, "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("two names on one list line", FLAG, ARMS, '.first, .first,', {KEYS: OWN_KEY}, 1,
     f"{LIST}:4: list one feature per line"),
    ("feature listed twice", FLAG, ARMS, '.first,\n.first,', {KEYS: OWN_KEY}, 1,
     ".first listed twice (first at line 4)"),
    ("key file away from its descriptor", FLAG, ARMS, '.first,',
     {Path("Tinycast/Features/Elsewhere/FirstBackupKeys.swift"): OWN_KEY}, 1, "put it beside FirstDescriptor.swift"),
    ("live values match the allowed keys", FLAG, ARMS, '.first,', {KEYS: LIVE, STORE: OWNER}, 0, "PASS"),
    ("snapshot writes a key not allowed", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace('"first.name": store.name', '"first.title": store.name'), STORE: OWNER}, 1,
     "snapshot writes first.title, which the file does not allow"),
    ("snapshot writes an excluded key", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace('"first.name": store.name', '"first.name": store.name, "first.cache": 1'), STORE: OWNER}, 1,
     "snapshot writes first.cache, which the file does not allow"),
    ("allowed key the snapshot drops", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace(', "first.name": store.name', ''), STORE: OWNER}, 1,
     "FirstBackupKeys.swift:4: first.name is allowed, but snapshot never writes it"),
    ("apply reads a key not allowed", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace('values["first.name"]', 'values["first.title"]'), STORE: OWNER}, 1,
     "apply reads first.title, which the file does not allow"),
    ("allowed key apply never reads", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace('values[FirstStore.sizeKey]', 'values.first?.value'), STORE: OWNER}, 1,
     "FirstBackupKeys.swift:3: first.size is allowed, but apply never reads it"),
    ("owner constant retyped as a literal elsewhere", FLAG, ARMS, '.first,\n.renamed,',
     {KEYS: LIVE, STORE: OWNER, RENAMED_KEYS: RENAMED_KEY.replace("renamed.cache", "first.size")}, 1,
     "first.size declared twice"),
    ("owner renamed its constant", FLAG, ARMS, '.first,',
     {KEYS: LIVE, STORE: OWNER.replace("sizeKey", "widthKey")}, 1, "FirstStore.sizeKey: no string constant sizeKey under First/"),
    ("constant on another type", FLAG, ARMS, '.first,',
     {KEYS: LIVE, STORE: OWNER.replace("class FirstStore", "class OtherStore")}, 1, "no string constant sizeKey under First/"),
    ("constant the hub owns", FLAG, ARMS, '.first,',
     {KEYS: LIVE.replace("FirstStore.sizeKey", "NotchcastPreferences.sizeKey"),
      HUB: OWNER.replace("FirstStore", "NotchcastPreferences")}, 0, "PASS"),
    ("secret-shaped key allowed in a key file", FLAG, ARMS, '.first,',
     {KEYS: OWN_KEY.replace("first.size", "first.apiKey")}, 1, "this allowed key is named like a secret"),
    ("secret-shaped switch backed up", FLAG, "case .renamed: false\ncase .secretKeeper: true", '', {}, 1,
     f"{FEATURE}:8: this allowed key is named like a secret"),
    ("secret-shaped key excluded", FLAG, ARMS, '.first,',
     {KEYS: OWN_KEY.replace("first.cache", "first.token")}, 0, "PASS"),
)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    core = root / "Tinycast/Features/Notchcast/Core"
    core.mkdir(parents=True)
    (core / "NotchcastFeature+Descriptor.swift").write_text(
        "extension NotchcastFeature {\n    static let descriptors: [Self: Descriptor] = [\n        .first: .first,\n    ]\n}\n")
    (root / KEYS).parent.mkdir(parents=True)
    for label, flag, arms, listed, files, status, diagnostic in CASES:
        (root / FEATURE).write_text(
            'enum NotchcastFeature: String {\n    case first\n    case renamed = "stored"\n    case secretKeeper\n\n'
            f"    var backedUp: Bool {{\n{arms}\n    }}\n}}\n")
        (root / KEYS).with_name("FirstDescriptor.swift").write_text(
            f"extension NotchcastFeature.Descriptor {{\n    static let first = Self(\n{flag}\n    )\n}}\n")
        (root / LIST).write_text(f"extension NotchcastFeature.BackupKeys {{\n    /// One per line.\n    static let all: [Self] = [\n{listed}\n]\n}}\n")
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
