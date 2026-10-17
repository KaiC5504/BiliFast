#!/usr/bin/env python3
"""The local gate: bili_core, the app and the workflow tests, in three parallel lanes.

    python scripts/gate.py          # on the PC, through fvm and uv
    python scripts/gate.py --ci     # in GitHub Actions, with flutter/dart/python on PATH

On the PC a pass on a clean tree is recorded in .git/gate-passed (the commit), so testflight.py
can tell the commit it ships passed without running anything again.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAMP = ROOT / ".git" / "gate-passed"


def tool(name: str) -> str:
    found = shutil.which(name)
    if not found:
        raise SystemExit(f"{name} is not on PATH")
    return found


def lanes(ci: bool) -> dict[str, list[tuple[list[str], Path]]]:
    if ci:
        flutter, dart = [tool("flutter")], [tool("dart")]
        python = [sys.executable]
    else:
        fvm = tool("fvm")
        flutter, dart = [fvm, "flutter"], [fvm, "dart"]
        python = [tool("uv"), "run", "--no-project", "--with", "pyyaml==6.0.3", "python"]
    core = ROOT / "packages" / "bili_core"
    return {
        "bili_core": [(dart + ["pub", "get"], core), (dart + ["analyze", "--fatal-infos"], core),
                      (dart + ["test", "--reporter", "failures-only"], core)],
        "app": [(flutter + ["pub", "get"], ROOT), (flutter + ["analyze", "--fatal-infos"], ROOT),
                (flutter + ["test", "--reporter", "failures-only"], ROOT)],
        "workflows": [(python + ["-m", "unittest", "discover", "-s", "test_ci"], ROOT)],
    }


def run_lane(name: str, steps: list[tuple[list[str], Path]]) -> tuple[str, bool, float, str]:
    start = time.monotonic()
    for command, cwd in steps:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                                encoding="utf-8", errors="replace")
        if result.returncode != 0:
            output = (result.stdout + result.stderr).strip().splitlines()
            return name, False, time.monotonic() - start, "\n".join(output[-40:])
    return name, True, time.monotonic() - start, ""


def head_if_clean() -> str | None:
    status = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True)
    if status.returncode != 0 or status.stdout.strip():
        return None
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                          text=True).stdout.strip() or None


def main() -> int:
    ci = "--ci" in sys.argv[1:]
    head = None if ci else head_if_clean()
    start = time.monotonic()
    with ThreadPoolExecutor() as pool:
        results = list(pool.map(lambda item: run_lane(*item), lanes(ci).items()))
    ok = all(passed for _, passed, _, _ in results)
    for name, passed, seconds, output in results:
        print(f"{'pass' if passed else 'FAIL'}  {name}  {seconds:.0f}s")
        if output:
            print(output)
    print(f"gate {'passed' if ok else 'failed'} in {time.monotonic() - start:.0f}s")
    if not ci:
        if ok and head:
            STAMP.write_text(head + "\n", encoding="utf-8")
        else:
            STAMP.unlink(missing_ok=True)
            if ok:
                print("(uncommitted changes: commit, then run the gate again to record the pass)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
