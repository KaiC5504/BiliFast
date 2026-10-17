"""scripts/testflight.py against a fake gh: what it refuses, and how many GitHub calls a round costs."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("testflight", ROOT / "scripts" / "testflight.py")
testflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(testflight)

SHA = "a" * 40


class FakeGitHub:
    def __init__(self, compile_conclusion="success", busy=False):
        self.calls = []
        self.compile_conclusion = compile_conclusion
        self.busy = busy

    def __call__(self, *args):
        if args[0] == "git":
            return SHA if args[1] == "rev-parse" else ""
        self.calls.append(args)
        joined = " ".join(args)
        if "--workflow app-compile.yml" in joined:
            return json.dumps([{"status": "completed", "conclusion": self.compile_conclusion, "url": "u"}])
        if args[1:3] == ("run", "list"):
            status = "in_progress" if self.busy else "completed"
            return json.dumps([{"databaseId": 1, "displayTitle": f"TestFlight upload {'b' * 40}", "status": status,
                                "conclusion": "success", "headSha": "b" * 40, "headBranch": "main",
                                "event": "workflow_dispatch", "url": "u1"}])
        if args[1] == "api" and args[2].endswith("deployment-branch-policies"):
            return json.dumps({"branch_policies": [{"name": "main"}]})
        if args[1] == "api":
            return json.dumps({"deployment_branch_policy": {"custom_branch_policies": True,
                                                            "protected_branches": False}})
        if args[1:3] == ("secret", "list"):
            return json.dumps([{"name": n} for n in testflight.SECRETS])
        if args[1:3] == ("workflow", "run"):
            return "https://github.com/KaiC5504/BiliFast/actions/runs/2\n"
        if args[1:3] == ("run", "view"):
            return json.dumps({"databaseId": 2, "displayTitle": f"TestFlight dry run {SHA}", "status": "queued",
                               "conclusion": "", "headSha": SHA, "headBranch": "main",
                               "event": "workflow_dispatch", "url": "u2", "jobs": []})
        raise AssertionError(f"unexpected call {args}")


class StartTest(unittest.TestCase):
    def setUp(self):
        folder = Path(tempfile.mkdtemp())
        self.stamp = folder / "gate-passed"
        self.last = folder / "last-run"
        for name, value in (("GATE_STAMP", self.stamp), ("LAST_RUN", self.last)):
            patcher = mock.patch.object(testflight, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        sleep = mock.patch.object(testflight.time, "sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def start(self, fake, *argv):
        with mock.patch.object(testflight, "run", fake), mock.patch("builtins.print"):
            return testflight.cmd_start(list(argv))

    def test_without_the_local_gate_nothing_touches_github(self):
        fake = FakeGitHub()
        self.assertEqual(1, self.start(fake, "--dry-run"))
        self.assertEqual([], fake.calls)

    def test_a_red_compile_check_stops_it_after_one_call(self):
        self.stamp.write_text(SHA)
        fake = FakeGitHub(compile_conclusion="failure")
        self.assertEqual(1, self.start(fake, "--dry-run"))
        self.assertEqual(1, len(fake.calls))

    def test_a_busy_run_stops_it(self):
        self.stamp.write_text(SHA)
        fake = FakeGitHub(busy=True)
        self.assertEqual(1, self.start(fake, "--dry-run"))
        self.assertFalse(any(c[1:3] == ("workflow", "run") for c in fake.calls))

    def test_a_dry_run_costs_seven_calls_and_remembers_the_run(self):
        self.stamp.write_text(SHA)
        fake = FakeGitHub()
        self.assertEqual(0, self.start(fake, "--dry-run"))
        # compile check, run list, environment x3, dispatch, one look at the new run
        self.assertEqual(7, len(fake.calls))
        self.assertEqual("2", self.last.read_text().strip())
        dispatch = next(c for c in fake.calls if c[1:3] == ("workflow", "run"))
        self.assertIn("upload=false", dispatch)
        self.assertIn(f"sha={SHA}", dispatch)

    def test_status_is_one_call(self):
        self.last.write_text("2")
        fake = FakeGitHub()
        with mock.patch.object(testflight, "run", fake), mock.patch("builtins.print"):
            testflight.cmd_status(None)
        self.assertEqual(1, len(fake.calls))


if __name__ == "__main__":
    unittest.main()
