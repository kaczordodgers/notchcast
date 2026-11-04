#!/usr/bin/env python3
"""Fixtures for check-kit.py: what it refuses, what passes, and how the baseline holds known findings."""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("check_kit", ROOT / "notchcast/check-kit.py")
KIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(KIT)

VIEW = "Tinycast/Features/Notchcast/Pages/SampleView.swift"
THEME = "Tinycast/Features/Notchcast/Island/NotchcastTheme.swift"


def rules(source, path=VIEW):
    return [(line, rule, value) for line, rule, value in KIT.findings(path, source)]


class Refuses(unittest.TestCase):
    def test_layout_literals(self):
        for call in (".padding(12)", ".padding(.horizontal, 12)", ".frame(width: 3, height: 3)", ".offset(y: 3)",
                     ".opacity(0.45)", "HStack(spacing: 10)", "RoundedRectangle(cornerRadius: 8)",
                     ".shadow(radius: 4)", ".animation(.easeOut(duration: 0.2), value: x)",
                     ".animation(.spring(response: 0.3, dampingFraction: 0.8), value: x)", "CGSize(width: 180, height: 28)",
                     "Spacer(minLength: 20)", ".delay(0.3)"):
            with self.subTest(call=call):
                found = rules(f"let a = Text(verbatim: \"\")\n    {call}\n")
                self.assertTrue(found and all(rule == "literal" and line == 2 for line, rule, _ in found), found)

    def test_literal_on_a_later_line_of_a_call(self):
        source = ".frame(height: min(NotchcastTheme.maximumHeight,\n    CGFloat(count) * 56))\n"
        self.assertEqual(rules(source), [(2, "literal", "56")])

    def test_raw_colours(self):
        for colour in ("Color(red: 0.5, green: 0.2, blue: 1)", ".foregroundStyle(.white)", ".fill(.black)",
                       "Color.gray", "Color.white.opacity(0.1)", "layer.backgroundColor = NSColor.black.cgColor",
                       "NSColor.windowBackgroundColor", ".foregroundStyle(.orange)", ".fill(.red.opacity(0.4))",
                       "NSColor(calibratedWhite: 0.2, alpha: 1)", "NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)",
                       "CGColor(gray: 0.5, alpha: 1)"):
            with self.subTest(colour=colour):
                self.assertIn("colour", {rule for _, rule, _ in rules(colour + "\n")})

    def test_fixed_font_outside_the_theme(self):
        self.assertEqual(rules(".font(.system(size: Theme.Typography.searchFieldSize))\n"),
                         [(1, "font", ".system(size:")])
        self.assertEqual([rule for _, rule, _ in rules("NSFont.systemFont(ofSize: x)\n")], ["font"])

    def test_waiver_needs_a_reason(self):
        self.assertEqual(len(rules(".padding(12) // kit: ok\n")), 1)


class Passes(unittest.TestCase):
    def test_zero_one_and_tokens(self):
        source = (".padding(0)\n.opacity(open ? 1 : 0)\n.frame(width: 1.0)\n.padding(Theme.Spacing.xl)\n"
                  "HStack(spacing: metrics.spacing.md)\n.strokeBorder(Theme.Colors.border, lineWidth: 1)\n")
        self.assertEqual(rules(source), [])

    def test_halving_and_doubling_a_token(self):
        self.assertEqual(rules(".frame(width: max(NotchcastTheme.minimumWing * 2, w))\n.offset(x: width / 2)\n"), [])
        self.assertEqual(len(rules(".offset(x: 2)\n")), 1)

    def test_strings_and_comments(self):
        source = 'Text("Take 12 photos").padding(Theme.Spacing.xl) // was .padding(12)\n/* .opacity(0.5) */\n'
        self.assertEqual(rules(source), [])

    def test_semantic_colours(self):
        source = (".foregroundStyle(Color.primary)\n.background(.clear)\nbackgroundColor = .clear\n"
                  "NSColor.clear\n.foregroundStyle(Theme.Colors.textSecondary)\n")
        self.assertEqual(rules(source), [])

    def test_waived_line(self):
        self.assertEqual(rules(".padding(12) // kit: ok matches the hardware notch\n"), [])

    def test_kit_files_hold_values(self):
        source = "static let pill = CGSize(width: 180, height: 28)\nstatic let surface = Color.black\n"
        self.assertEqual(rules(source, THEME), [])
        self.assertEqual(rules("static let x = Font.system(size: 13)\n", THEME), [])
        motion = "Tinycast/Features/Notchcast/Island/IslandMotion.swift"
        self.assertEqual([rule for _, rule, _ in rules("Font.system(size: 13)\n", motion)], ["font"])


class Tree(unittest.TestCase):
    def write(self, root, path, text):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def run_check(self, root, baseline):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = KIT.check(root, baseline)
        return code, output.getvalue()

    def test_scans_island_pages_and_island_folders_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.write(root, VIEW, ".padding(12)\n")
            self.write(root, "Tinycast/Features/Music/IslandStrip/Strip.swift", ".opacity(0.5)\n")
            self.write(root, "Tinycast/Features/Music/UI/Other.swift", ".padding(12)\n")
            code, output = self.run_check(root, {})
            self.assertEqual(code, 1)
            self.assertIn("SampleView.swift:1: FAIL literal: 12", output)
            self.assertIn("IslandStrip/Strip.swift:1: FAIL literal: 0.5", output)
            self.assertNotIn("Other.swift", output)

    def test_baseline_holds_known_findings_and_fails_new_ones(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = "Tinycast/Features/Notchcast/Island/IslandSurfaceView.swift"
            self.write(root, path, "layer?.backgroundColor = NSColor.black.cgColor\n")
            code, output = self.run_check(root, {path: {"colour": 1}})
            self.assertEqual(code, 0, output)
            self.assertIn("known colour", output)
            self.write(root, path, "NSColor.black\n.fill(.white)\n")
            code, output = self.run_check(root, {path: {"colour": 1}})
            self.assertEqual(code, 1, output)
            self.write(root, path, "\n")
            code, output = self.run_check(root, {path: {"colour": 1}})
            self.assertEqual(code, 0, output)
            self.assertIn("lower it", output)

    def test_repository_baseline_is_valid_json(self):
        baseline = json.loads((ROOT / "notchcast/check-kit-baseline.json").read_text())
        self.assertTrue(all(isinstance(rules, dict) for rules in baseline.values()))


if __name__ == "__main__":
    unittest.main(verbosity=1)
