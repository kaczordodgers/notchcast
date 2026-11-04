#!/usr/bin/env python3
"""xins.py TARGET SOURCE BASE: three-way text insertion into TARGET."""
from pathlib import Path
import runpy
import sys

merge = runpy.run_path(str(Path(__file__).with_name("xcstrings-union.py")))["merge"]

if __name__ == "__main__":
    target, source, base = map(Path, sys.argv[1:4])
    try:
        target.write_text(merge(base.read_text(), target.read_text(), source.read_text()))
    except ValueError as error:
        sys.exit(str(error))
