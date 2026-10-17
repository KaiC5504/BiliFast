#!/usr/bin/env python3
"""Start and check the signed TestFlight build (.github/workflows/testflight.yml).

    python scripts/testflight.py start [--dry-run] [--create-signing] [--again]
    python scripts/testflight.py status [RUN_ID]     # one GitHub call; default: the last run started here

start builds origin/main's head. It refuses unless the local gate passed on that commit
(scripts/gate.py), the compile check passed on it, nothing else is building, and the `testflight`
environment is locked to main with its secrets in place. --dry-run signs and checks the IPA without
uploading. --create-signing registers the bundle id and creates the profile or renews an expired
certificate. --again rebuilds a commit that already shipped.

There is no watch command: polling GitHub tripped its rate limit on 2026-10-17. Start, then run
`status` once, about 10 minutes later for a dry run and 20 for an upload. An upload is green once
Apple has finished processing it.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = "KaiC5504/BiliFast"
WORKFLOW = "testflight.yml"
COMPILE_WORKFLOW = "app-compile.yml"
ENVIRONMENT = "testflight"
SECRETS = {
    "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_KEY_IDENTIFIER",
    "APP_STORE_CONNECT_PRIVATE_KEY",
    "CERT_KEY_B64",
    "SIGNING_NAME",
}
# The workflow's run-name starts with one of these.
UPLOAD = "TestFlight upload"
DRY_RUN = "TestFlight dry run"
FIELDS = "databaseId,displayTitle,status,conclusion,headSha,headBranch,event,url"
ROOT = Path(__file__).resolve().parents[1]
GATE_STAMP = ROOT / ".git" / "gate-passed"
LAST_RUN = ROOT / ".git" / "testflight-last-run"

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")


def run(*args: str) -> str:
    result = subprocess.run(list(args), capture_output=True, text=True, encoding="utf-8",
                            errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"{' '.join(args[:3])} failed: {result.stderr.strip()}")
    return result.stdout


def git(*args: str) -> str:
    return run("git", *args).strip()


def runs(limit: int = 20) -> list[dict]:
    return json.loads(run("gh", "run", "list", "-R", REPO, "--workflow", WORKFLOW,
                          "--limit", str(limit), "--json", FIELDS))


def view(run_id: int | str, fields: str = FIELDS) -> dict:
    return json.loads(run("gh", "run", "view", str(run_id), "-R", REPO, "--json", fields))


def last_shipped(recent: list[dict]) -> dict | None:
    """The newest upload run on main that passed, i.e. a build Apple accepted."""
    return next((r for r in recent if r["displayTitle"].startswith(UPLOAD)
                 and r["headBranch"] == "main" and r.get("event") == "workflow_dispatch"
                 and r["conclusion"] == "success"), None)


def report(run_: dict) -> None:
    """Prints a run fetched with its jobs; fetches the log only when something failed."""
    state = run_["conclusion"] or run_["status"]
    print(f"run     {run_['databaseId']}  {state}")
    print(f"title   {run_['displayTitle']}")
    print(f"url     {run_['url']}")
    for job in run_.get("jobs", []):
        print(f"\n{job['name']}: {job['conclusion'] or job['status']}")
        for step in job["steps"]:
            step_state = step["conclusion"] or step["status"]
            marker = ("x" if step_state in {"failure", "cancelled", "timed_out"}
                      else "-" if step_state in {"skipped", "pending", "queued"} else "+")
            print(f"  {marker} {step['name']}: {step_state}")
    if run_["status"] == "completed" and run_["conclusion"] != "success":
        log = subprocess.run(["gh", "run", "view", str(run_["databaseId"]), "-R", REPO,
                              "--log-failed"], capture_output=True, text=True,
                             encoding="utf-8", errors="replace").stdout
        lines = [line for line in log.splitlines() if line.strip()]
        if lines:
            print(f"\n--- failed steps: last {min(len(lines), 60)} lines ---")
            print("\n".join(lines[-60:]))


def environment_problems() -> list[str]:
    """The secrets are only as safe as this environment's lock to main."""
    env = json.loads(run("gh", "api", f"repos/{REPO}/environments/{ENVIRONMENT}"))
    policy = env.get("deployment_branch_policy") or {}
    problems = []
    if not policy.get("custom_branch_policies") or policy.get("protected_branches"):
        problems.append(f"environment {ENVIRONMENT} isn't limited to chosen branches")
    else:
        branches = json.loads(run("gh", "api",
                                  f"repos/{REPO}/environments/{ENVIRONMENT}/deployment-branch-policies"))
        names = sorted(p["name"] for p in branches.get("branch_policies", []))
        if names != ["main"]:
            problems.append(f"environment {ENVIRONMENT} allows {names}, not just main")
    names = {s["name"] for s in json.loads(run("gh", "secret", "list", "--env", ENVIRONMENT,
                                                "-R", REPO, "--json", "name"))}
    problems += [f"environment {ENVIRONMENT} has no secret {n}" for n in sorted(SECRETS - names)]
    return problems


def compile_check_problem(sha: str) -> str | None:
    found = json.loads(run("gh", "run", "list", "-R", REPO, "--workflow", COMPILE_WORKFLOW,
                           "--commit", sha, "--limit", "1", "--json", "status,conclusion,url"))
    if not found:
        return f"no compile check ran on {sha[:8]}"
    if found[0]["conclusion"] != "success":
        return f"the compile check on {sha[:8]} is {found[0]['conclusion'] or found[0]['status']}: {found[0]['url']}"
    return None


def dispatched_run(output: str, known: set[int], sha: str) -> dict | None:
    """The run `gh workflow run` just made. Its title is the bare workflow name until
    GitHub evaluates run-name, so the first look waits a few seconds."""
    match = re.search(r"/actions/runs/(\d+)", output)
    for _ in range(5):
        time.sleep(4)
        try:
            if match:
                found = view(match.group(1))
                if sha in found["displayTitle"]:
                    return found
            else:
                new = [r for r in runs(5) if r["databaseId"] not in known and sha in r["displayTitle"]]
                if new:
                    return new[0]
        except SystemExit:
            pass
    return None


def cmd_status(run_id: str | None) -> int:
    if run_id is None and LAST_RUN.exists():
        run_id = LAST_RUN.read_text(encoding="utf-8").strip()
    if run_id is None:
        latest = runs(1)
        if not latest:
            print("No TestFlight runs yet.")
            return 0
        run_id = str(latest[0]["databaseId"])
    current = view(run_id, FIELDS + ",jobs")
    report(current)
    if current["status"] != "completed":
        return 2
    return 0 if current["conclusion"] == "success" else 1


def cmd_start(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="testflight.py start")
    parser.add_argument("--dry-run", action="store_true", help="sign and check, upload nothing")
    parser.add_argument("--create-signing", action="store_true",
                        help="register the bundle id / create the profile or certificate")
    parser.add_argument("--again", action="store_true", help="rebuild a commit that already shipped")
    args = parser.parse_args(argv)

    git("fetch", "-q", "origin", "main")
    sha = git("rev-parse", "origin/main")
    # Local checks first: they cost no GitHub calls.
    gated = GATE_STAMP.read_text(encoding="utf-8").strip() if GATE_STAMP.exists() else ""
    if gated != sha:
        print(f"The local gate hasn't passed on {sha[:8]}: run `python scripts/gate.py` on that commit.")
        return 1

    problem = compile_check_problem(sha)
    if problem:
        print(f"Not starting: {problem}")
        return 1
    recent = runs()
    busy = [r for r in recent if r["status"] != "completed"]
    if busy:
        print(f"run {busy[0]['databaseId']} is still {busy[0]['status']}: {busy[0]['url']}")
        return 1
    if not args.dry_run and not args.again:
        shipped = last_shipped(recent)
        if shipped and shipped["headSha"] == sha:
            print(f"{sha[:8]} already shipped in run {shipped['databaseId']}. "
                  "Use --again to build it under a new number.")
            return 1
    problems = environment_problems()
    if problems:
        print("Not starting:\n" + "\n".join(f"  - {p}" for p in problems))
        return 1

    output = run("gh", "workflow", "run", WORKFLOW, "-R", REPO, "--ref", "main",
                 "-f", f"sha={sha}",
                 "-f", f"upload={'false' if args.dry_run else 'true'}",
                 "-f", f"create_signing={'true' if args.create_signing else 'false'}")
    new = dispatched_run(output, {r["databaseId"] for r in recent}, sha)
    if not new:
        print("Dispatched, but the run hasn't appeared yet; see `testflight.py status`.")
        LAST_RUN.unlink(missing_ok=True)
        return 0
    want = DRY_RUN if args.dry_run else UPLOAD
    if not new["displayTitle"].startswith(want):
        run("gh", "run", "cancel", str(new["databaseId"]), "-R", REPO)
        print(f"run {new['databaseId']} came up as {new['displayTitle']!r}, not {want!r}; "
              "cancelled it.")
        return 1
    LAST_RUN.write_text(f"{new['databaseId']}\n", encoding="utf-8")
    print(f"started run {new['databaseId']} on {sha[:8]}"
          + (" (dry run, no upload)" if args.dry_run else ""))
    print(new["url"])
    return 0


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    rest = sys.argv[2:]
    if command == "status":
        return cmd_status(rest[0] if rest else None)
    if command == "start":
        return cmd_start(rest)
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
