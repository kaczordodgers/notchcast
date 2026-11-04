#!/usr/bin/env python3
"""Report-only memory sampling for the installed Notchcast process."""

import argparse
import csv
import datetime
import pathlib
import plistlib
import re
import subprocess
import sys

LOG = pathlib.Path.home() / "Library/Logs/notchcast/memory.csv"
FIELDS = ("timestamp", "version", "uptime", "footprint_mb", "footprint_peak_mb", "rss_mb")


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def sample():
    processes = command("/bin/ps", "-axo", "pid=,comm=")
    matches = [line.split(None, 1) for line in processes.splitlines()
               if line.strip().endswith("/Applications/Notchcast.app/Contents/MacOS/Notchcast")]
    if not matches:
        return
    if len(matches) != 1:
        raise RuntimeError("Expected one installed Notchcast process")
    pid, executable = matches[0]
    info = pathlib.Path(executable).parents[1] / "Info.plist"
    with info.open("rb") as source:
        metadata = plistlib.load(source)
    footprint = command("/usr/bin/footprint", "-p", pid, "--noCategories", "-f", "bytes")
    values = []
    for key in ("phys_footprint", "phys_footprint_peak"):
        match = re.search(rf"^\s*{key}:\s*([\d,]+)\s*(?:B|bytes)?\s*$", footprint, re.MULTILINE)
        if match is None:
            raise RuntimeError(f"Missing {key} in footprint output: {footprint}")
        values.append(int(match[1].replace(",", "")) / 1_000_000)
    uptime, rss = command("/bin/ps", "-p", pid, "-o", "etime=,rss=").split()
    version = f"{metadata['CFBundleShortVersionString']} ({metadata['CFBundleVersion']})"
    row = (datetime.datetime.now(datetime.timezone.utc).isoformat(), version, uptime,
           *(f"{value:.3f}" for value in values), f"{int(rss) * 1024 / 1_000_000:.3f}")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", newline="") as destination:
        writer = csv.writer(destination)
        if destination.tell() == 0:
            writer.writerow(FIELDS)
        writer.writerow(row)


def trend():
    groups = {}
    with LOG.open(newline="") as source:
        for row in csv.DictReader(source):
            groups.setdefault(row["version"], []).append(row)
    print("Report only; decimal MB; reference line 100 MB (resident budget).")
    print("build | samples | footprint first -> last / max | peak max | RSS max | RSS >100")
    for version, rows in groups.items():
        footprint = [float(row["footprint_mb"]) for row in rows]
        rss = [float(row["rss_mb"]) for row in rows]
        peak = max(float(row["footprint_peak_mb"]) for row in rows)
        print(f"{version} | {len(rows)} | {footprint[0]:.1f} -> {footprint[-1]:.1f} / "
              f"{max(footprint):.1f} | {peak:.1f} | {max(rss):.1f} | "
              f"{sum(value > 100 for value in rss)}/{len(rows)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("sample", "trend"))
    args = parser.parse_args()
    try:
        sample() if args.action == "sample" else trend()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"memory: {error}", file=sys.stderr)
        sys.exit(1)
