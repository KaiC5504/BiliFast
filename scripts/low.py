#!/usr/bin/env python3
"""Runs a command at below-normal priority on Windows, so a long test run gives way to whatever else the PC is doing.

    python scripts/low.py fvm flutter test --concurrency=4 test/live

The processes it starts inherit the priority. Elsewhere it just runs the command. Exits with the command's code.
"""

from __future__ import annotations

import shutil
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    command = sys.argv[1:]
    command[0] = shutil.which(command[0]) or command[0]
    flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
    return subprocess.run(command, creationflags=flags).returncode


if __name__ == "__main__":
    sys.exit(main())
