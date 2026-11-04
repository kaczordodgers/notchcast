#!/usr/bin/env python3
"""Launch the Debug fixture process with a disposable home and a filesystem/network fence."""

import json
import os
from pathlib import Path
import plistlib
import sys


def launch(scratch, output, bundle, executable):
    scratch, output, bundle = (Path(path).resolve() for path in (scratch, output, bundle))
    account_home = Path.home()
    home = scratch / "home"
    preferences = home / "Library/Preferences"
    preferences.mkdir(parents=True, exist_ok=True)
    (home / ".notchcast-gallery-home").touch()
    with (preferences / "app.notchcast.dev.plist").open("wb") as stream:
        plistlib.dump({"showInMenuBar": False, "calendarEnabled": False,
                      "automaticallyCheckForUpdates": False, "AppleLanguages": ["en"]}, stream)
    quote = lambda path: json.dumps(str(path), ensure_ascii=True)
    exceptions = " ".join(f"(require-not (subpath {quote(path)}))" for path in (scratch, output, bundle))
    profile = ("(version 1) (allow default) (deny network*) "
               f"(deny file-read-data file-write* (require-all (subpath {quote(account_home)}) {exceptions})) "
               '(deny mach-lookup (global-name "com.apple.securityd"))')
    environment = os.environ | {"HOME": str(home), "CFFIXED_USER_HOME": str(home),
                                "TMPDIR": str(scratch / "tmp") + "/"}
    os.execve("/usr/bin/sandbox-exec", ["sandbox-exec", "-p", profile,
                                      str(bundle / "Contents/MacOS" / executable)], environment)


if __name__ == "__main__":
    launch(*sys.argv[1:])
