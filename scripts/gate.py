#!/usr/bin/env python3
"""The local gate: everything that can be checked on this PC, in parallel lanes.

    python scripts/gate.py           # all lanes; a pass on a clean tree is recorded for testflight.py
    python scripts/gate.py --quick   # without the Windows build, for the edit loop; records nothing

Lanes: bili_core (analyze, tests), the app (analyze, widget tests), the workflow tests, the PC tools'
tests (log server, phone report), a Swift syntax check of ios/Runner (the PC has no iOS SDK, so only
syntax), and the Windows release build plus the Windows integration tests (real mpv). A pass on a
clean tree is recorded in .git/gate-passed (the commit), so testflight.py can tell the commit it ships
passed without running anything again.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "packages" / "bili_core"
STAMP = ROOT / ".git" / "gate-passed"

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")

Step = tuple[list[str], Path]


def tool(name: str) -> str:
    found = shutil.which(name)
    if not found:
        raise SystemExit(f"{name} is not on PATH")
    return found


def lanes(quick: bool) -> dict[str, list[Step]]:
    fvm = tool("fvm")
    flutter, dart = [fvm, "flutter"], [fvm, "dart"]
    python = [tool("uv"), "run", "--no-project", "--with", "pyyaml==6.0.3", "python"]
    swift_files = sorted(str(path) for path in (ROOT / "ios" / "Runner").rglob("*.swift"))
    result: dict[str, list[Step]] = {
        "bili_core": [(dart + ["analyze", "--fatal-infos"], CORE),
                      (dart + ["test", "--reporter", "failures-only"], CORE)],
        "app": [(flutter + ["analyze", "--fatal-infos"], ROOT),
                (flutter + ["test", "--reporter", "failures-only"], ROOT)],
        "workflows": [(python + ["-m", "unittest", "discover", "-s", "test_ci"], ROOT)],
        # screen_diff measures with numpy and draws its test pairs with Pillow.
        "tools": [(python[:-1] + ["--with", "numpy==2.5.4", "--with", "pillow==13.0.0", "python", "-m", "unittest",
                                  "discover", "-s", "tools", "-p", "test_*.py"], ROOT)],
        "swift": [([tool("swiftc"), "-parse"] + swift_files, ROOT)],
    }
    if not quick:
        windows: list[Step] = [(flutter + ["build", "windows", "--release"], ROOT)]
        if any((ROOT / "integration_test").glob("*_test.dart")):
            windows.append((flutter + ["test", "integration_test", "-d", "windows",
                                       "--reporter", "failures-only"], ROOT))
        result["windows"] = windows
    return result


def run(command: list[str], cwd: Path) -> tuple[bool, str]:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def run_lane(name: str, steps: list[Step]) -> tuple[str, bool, float, str]:
    start = time.monotonic()
    for command, cwd in steps:
        ok, output = run(command, cwd)
        if not ok:
            return name, False, time.monotonic() - start, "\n".join(output.splitlines()[-40:])
    return name, True, time.monotonic() - start, ""


def head_if_clean() -> str | None:
    status = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True)
    if status.returncode != 0 or status.stdout.strip():
        return None
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                          text=True).stdout.strip() or None


def main() -> int:
    quick = "--quick" in sys.argv[1:]
    head = None if quick else head_if_clean()
    start = time.monotonic()
    # One resolve before the lanes: parallel `pub get`s in one project race on package_config.json.
    for command, cwd in (([tool("fvm"), "flutter", "pub", "get"], ROOT), ([tool("fvm"), "dart", "pub", "get"], CORE)):
        ok, output = run(command, cwd)
        if not ok:
            print(f"FAIL  pub get in {cwd.name}\n" + "\n".join(output.splitlines()[-20:]))
            STAMP.unlink(missing_ok=True)
            return 1
    with ThreadPoolExecutor() as pool:
        results = list(pool.map(lambda item: run_lane(*item), lanes(quick).items()))
    ok = all(passed for _, passed, _, _ in results)
    for name, passed, seconds, output in results:
        print(f"{'pass' if passed else 'FAIL'}  {name}  {seconds:.0f}s")
        if output:
            print(output)
    print(f"gate {'passed' if ok else 'failed'} in {time.monotonic() - start:.0f}s")
    if quick:
        return 0 if ok else 1
    if ok and head:
        STAMP.write_text(head + "\n", encoding="utf-8")
    else:
        STAMP.unlink(missing_ok=True)
        if ok:
            print("(uncommitted changes: commit, then run the gate again to record the pass)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
