#!/usr/bin/env python3
"""Exercise conflict resolution checks using real commits in a temporary repository."""

import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-entry-lists.py").resolve()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.STDOUT).strip()

    def commit(message, entries):
        (root / "entries.swift").write_text("enum Sample {\n" + "\n".join(entries) + "\n}\n")
        git("add", "entries.swift")
        git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", message)
        return git("rev-parse", "HEAD")

    git("init", "-q")
    base = commit("base", ["case kept", "case deletedByOurs", "case deletedByTheirs"])
    ours = commit("ours", ["case kept", "case deletedByTheirs", "case ours"])
    git("checkout", "-q", "--detach", base)
    theirs = commit("theirs", ["case kept", "case deletedByOurs", "case theirs"])
    for label, lines, status, diagnostic in (
        ("dropped case", ["case kept", "case ours"], 1, "dropped from theirs: case theirs"),
        ("good resolution", ["case kept", "case ours", "case theirs", "case extra", "// ignored"], 0, "result-only: case extra"),
        ("dropped shared case", ["case ours", "case theirs"], 1, "dropped from ours and theirs: case kept"),
    ):
        commit(label, lines)
        result = subprocess.run([sys.executable, str(SCRIPT), "--ours", ours, "--theirs", theirs, "--file", "entries.swift"], cwd=root, text=True, capture_output=True)
        assert result.returncode == status, result.stdout + result.stderr
        assert diagnostic in result.stdout, result.stdout
        assert "dropped from ours: case deletedByTheirs" not in result.stdout
        assert "dropped from theirs: case deletedByOurs" not in result.stdout
        print(f"PASS {label}: {result.stdout.strip()}")
print("entry lists tests: PASS (3 resolutions)")
