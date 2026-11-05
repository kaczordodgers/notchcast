#!/usr/bin/env python3
"""Source discovery and coverage fixtures keep new UI visible as inventory gaps."""

import importlib.util
import json
import re
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("inventory", Path(__file__).with_name("inventory.py"))
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class InventoryTests(unittest.TestCase):
    def test_closed_state_registry(self):
        source = (Path(__file__).resolve().parents[2] / "Tinycast/Features/Notchcast/Gallery/GalleryPages+Island.swift").read_text()
        registry = re.search(r'let closed = \[(.*?)\]\.map', source, re.S).group(1)
        for state in ("idle", "volume", "brightness", "airpods", "low-battery", "wifi", "tailscale", "low-disk", "meeting-reminder", "dictation", "walk", "message", "danger-message"):
            self.assertIn('"' + state + '"', registry, state)
        self.assertIn('[true, false].flatMap', source)
        self.assertIn('mba ? "mba" : "ext"', source)

    def test_declarations(self):
        source = """
        // struct Comment: View {}
        struct Example<Content: View>: View { }
        final class Panel: NSPanel { }
        struct Model: Sendable { }
        """
        declarations = inventory.declarations(source)
        self.assertEqual([item[0] for item in declarations], ["Example", "Panel", "Model"])
        self.assertEqual(declarations[0][1], 3)

    def test_generated_gap_and_inheritance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / "Tinycast/Features/Settings"
            settings.mkdir(parents=True)
            (settings / "SettingsDetailView.swift").write_text("struct SettingsDetailView: View {}")
            (settings / "SettingsTab.swift").write_text("")
            source = root / "Tinycast/Feature.swift"
            source.write_text("struct Covered: View {}\nstruct NewView: View {}\n"
                              "class Parent: NSPanel {}\nclass Child: Parent {}\n")
            output = root / "shots"
            output.mkdir()
            (output / "manifest.txt").write_text("sample.png\n")
            (output / "coverage.json").write_text(json.dumps([{"page": "sample", "types": ["Covered"]}]))
            (output / "sample-layout.json").write_text(json.dumps({"accessibilityComplete": False,
                                                                  "accessibilityGap": "fixture AX gap"}))
            inventory.generate(root, output)
            data = json.loads((output / "inventory.json").read_text())
            records = {item["type"]: item for item in data["views"]}
            self.assertEqual(records["Covered"]["pages"], ["sample"])
            self.assertEqual(records["NewView"]["pages"], [])
            self.assertTrue(records["NewView"]["reason"].startswith("Gap:"))
            self.assertIn("Child", records)
            self.assertEqual(data["incomplete_exports"], [{"page": "sample", "reason": "fixture AX gap"}])
            self.assertIn("NewView", (output / "inventory.md").read_text())


if __name__ == "__main__":
    unittest.main()
