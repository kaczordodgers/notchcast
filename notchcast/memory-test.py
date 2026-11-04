#!/usr/bin/env python3
"""Exercise sampling units, failures, absent app and report-only thresholds."""

import contextlib
import importlib.util
import io
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("memory", pathlib.Path(__file__).with_name("memory.py"))
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


class MemoryTest(unittest.TestCase):
    def test_sample_and_trend(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            executable = root / "Applications/Notchcast.app/Contents/MacOS/Notchcast"
            executable.parent.mkdir(parents=True)
            with (executable.parents[1] / "Info.plist").open("wb") as destination:
                plistlib.dump({"CFBundleShortVersionString": "1.2", "CFBundleVersion": "3"}, destination)
            log = root / "memory.csv"
            replies = [f"42 {executable}", "phys_footprint: 123456789 B\nphys_footprint_peak: 234567890 B", "01:02 100000"]
            with patch.object(memory, "LOG", log), patch.object(memory, "command", side_effect=replies):
                memory.sample()
            self.assertIn("123.457,234.568,102.400", log.read_text())
            output = io.StringIO()
            with patch.object(memory, "LOG", log), contextlib.redirect_stdout(output):
                memory.trend()
            self.assertIn("1.2 (3) | 1 | 123.5 -> 123.5 / 123.5 | 234.6 | 102.4 | 1/1", output.getvalue())

    def test_absent_app_does_not_write(self):
        with patch.object(memory, "command", return_value="1 /sbin/launchd"), patch.object(pathlib.Path, "open") as opened:
            memory.sample()
            opened.assert_not_called()

    def test_ambiguous_app_fails(self):
        with patch.object(memory, "command", return_value="1 /Applications/Notchcast.app/Contents/MacOS/Notchcast\n2 /Applications/Notchcast.app/Contents/MacOS/Notchcast"):
            with self.assertRaisesRegex(RuntimeError, "Expected one"):
                memory.sample()


if __name__ == "__main__":
    unittest.main()
