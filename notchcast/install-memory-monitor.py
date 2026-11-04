#!/usr/bin/env python3
"""Install a user LaunchAgent; no app changes and no network."""

import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

home = pathlib.Path.home()
label = "notchcast.memory"
target = home / "Library/Application Support/notchcast/memory"
logs = home / "Library/Logs/notchcast"
agent = home / f"Library/LaunchAgents/{label}.plist"
target.mkdir(parents=True, exist_ok=True)
logs.mkdir(parents=True, exist_ok=True)
agent.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["/bin/launchctl", "bootout", f"gui/{os.getuid()}/{label}"],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
shutil.copyfile(pathlib.Path(__file__).with_name("memory.py"), target / "memory.py")
with agent.open("wb") as destination:
    plistlib.dump({"Label": label, "ProgramArguments": [sys.argv[1], str(target / "memory.py"), "sample"],
                  "StartInterval": 900, "RunAtLoad": True,
                  "StandardOutPath": str(logs / "memory-monitor.log"),
                  "StandardErrorPath": str(logs / "memory-monitor.log")}, destination)
subprocess.run(["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", str(agent)], check=True)
print(f"Installed {agent}; samples every 900 seconds while the app is running.")
