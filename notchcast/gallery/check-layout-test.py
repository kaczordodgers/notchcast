#!/usr/bin/env python3
"""Fixtures exercise each checker rule independently, including malformed input."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("checker", Path(__file__).with_name("check-layout.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def fixture(x=4, y=4, width=20, height=12, role="AXStaticText"):
    return {"page": "island-closed-timer-mba", "scale": 2,
            "canvas": {"x": 0, "y": 0, "width": 100, "height": 40},
            "surface": {"x": 0, "y": 0, "width": 100, "height": 40},
            "hardwareNotch": {"x": 40, "y": 0, "width": 20, "height": 32},
            "elements": [{"role": role, "label": "fixture", "frame": {
                "x": x, "y": y, "width": width, "height": height}}]}


class LayoutTests(unittest.TestCase):
    def test_clean(self):
        self.assertEqual(checker.problems(fixture()), [])

    def test_surface(self):
        self.assertIn("fixture: outside surface", checker.problems(fixture(x=-1)))

    def test_hardware_notch(self):
        self.assertIn("fixture: under hardware notch", checker.problems(fixture(x=40)))

    def test_container_can_span_notch(self):
        self.assertEqual(checker.problems(fixture(x=40, role="AXGroup")), [])

    def test_each_edge(self):
        for key in ("x", "y", "width", "height"):
            with self.subTest(edge=key):
                self.assertTrue(any("between 2x pixels" in item for item in checker.problems(fixture(**{key: 4.25}))))

    def test_half_points(self):
        self.assertEqual(checker.problems(fixture(x=4.5, y=4.5)), [])

    def test_invalid_geometry(self):
        with self.assertRaises(ValueError):
            checker.problems(fixture(width=float("nan")))

    def test_missing_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(checker.check(Path(directory)), 1)


if __name__ == "__main__":
    unittest.main()
