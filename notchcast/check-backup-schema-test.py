#!/usr/bin/env python3
"""Exercise the backup classification checker against isolated source fixtures."""

import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-backup-schema.py")
KEYS = Path("Tinycast/Features/First/FirstBackupKeys.swift")
OWN_KEY = 'extension NotchcastFeature.BackupKeys {\n    static let first = Self(allowed: [\n        "first.size": .integer(1...9),\n    ], excluded: [\n        "first.cache",\n    ])\n}\n'
CASES = (
    # label, allowed, excluded, featureKeys, key files, status, diagnostic
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
     "list .first, in featureKeys"),
    ("listed feature without a key file", '"first": .bool,', '"stored",', '.first,', {}, 1,
     ".first has no FirstBackupKeys.swift"),
    ("key file in a layer folder", '"first": .bool,', '"stored",', '', {Path("Tinycast/Features/First/Model/FirstBackupKeys.swift"): OWN_KEY}, 1,
     "declare backup keys in Tinycast/Features/<its folder>/<Name>BackupKeys.swift"),
    ("key file for an undescribed feature", '"first": .bool,', '"stored",', '.renamed,',
     {Path("Tinycast/Features/Renamed/RenamedBackupKeys.swift"): OWN_KEY.replace("static let first", "static let renamed")}, 1,
     ".renamed has no descriptor"),
    ("key file with two declarations", '"first": .bool,', '"stored",', '.first,',
     {KEYS: OWN_KEY.replace("}\n", "    static let second = first\n}\n")}, 1, "declare exactly one .first"),
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
    for label, allowed, excluded, listed, files, status, diagnostic in CASES:
        schema.write_text("enum ForkSettingsBackupSchema {\n"
                          f"private static let featureKeys: [NotchcastFeature.BackupKeys] = [\n{listed}\n]\n"
                          f"private static let listedAllowed: [String: NotchcastFeature.BackupValue] = [\n{allowed}\n]\n"
                          f"private static let listedExcluded: Set<String> = [\n{excluded}\n]\n}}\n")
        for path, source in files.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(source)
        result = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)], text=True, capture_output=True)
        for path in files:
            (root / path).unlink()
        assert result.returncode == status, f"{label}: {result.stdout}{result.stderr}"
        assert diagnostic in result.stdout, f"{label}: {result.stdout}"
        print(f"PASS {label}: {result.stdout.strip().splitlines()[0]}")
print(f"backup schema tests: PASS ({len(CASES)} fixtures)")
