#!/usr/bin/env python3
"""Exercise the backup classification checker against isolated source fixtures."""

import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-backup-schema.py")
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    feature = root / "Tinycast/Features/Notchcast/Core/NotchcastFeature.swift"
    schema = root / "Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift"
    feature.parent.mkdir(parents=True)
    schema.parent.mkdir(parents=True)
    feature.write_text('enum NotchcastFeature: String {\n case first\n case renamed = "stored"\n}\n')
    for label, allowed, excluded, status, diagnostic in (
        ("unclassified", '"first": .bool,', '', 1, "renamed (stored): unclassified"),
        ("good raw value", '"first": .bool,', '"stored",', 0, "PASS"),
        ("double classification", '"first": .bool,\n"stored": .bool,', '"stored",', 1, "doubly classified"),
        ("comments ignored", '"first": .bool,\n// "stored": .bool,', '"stored",', 0, "PASS"),
    ):
        schema.write_text(f'struct ForkSettingsBackupSchema {{\nstatic let allowed: [String: Value] = [\n{allowed}\n]\nstatic let excluded: Set<String> = [\n{excluded}\n]\n}}\n')
        result = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)], text=True, capture_output=True)
        assert result.returncode == status, result.stdout + result.stderr
        assert diagnostic in result.stdout, result.stdout
        if status:
            assert str(schema.relative_to(root)) in result.stdout
        print(f"PASS {label}: {result.stdout.strip()}")
print("backup schema tests: PASS (4 fixtures)")
