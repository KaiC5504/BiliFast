import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import phone_report  # noqa: E402

FIXTURE = pathlib.Path(__file__).resolve().parent / "testdata" / "phone_session.jsonl"


class PhoneReportTests(unittest.TestCase):
    def setUp(self):
        self.events = phone_report.load(FIXTURE)

    def test_load_skips_lines_that_are_not_events(self):
        self.assertEqual(len(self.events), 37)
        self.assertEqual([event["seq"] for event in self.events], list(range(1, 38)))

    def test_results_per_variant_and_played_quality_leave_out_skipped_passes(self):
        run = phone_report.runs(self.events)[0]
        self.assertEqual(len(run["passes"]), 3)
        groups = phone_report.groups(run)
        self.assertEqual([(g["variant"], g["quality"], g["passes"]) for g in groups], [("A", 127, 1), ("B", 127, 1)])
        a, b = groups
        self.assertEqual((a["first"], a["tapMedian"], a["tapP90"], a["tapMax"], a["back"]), (1500, 600, 15000, 15000, 100))
        self.assertEqual((a["stalls"], a["timeouts"], a["rssMB"], a["memoryWarnings"]), (1, 1, 812, 1))
        self.assertEqual((b["first"], b["tapMedian"], b["tapP90"], b["tapMax"], b["back"]), (1200, 500, 700, 700, 50))

    def test_differences_are_later_variants_minus_the_first(self):
        delta = phone_report.deltas(phone_report.groups(phone_report.runs(self.events)[0]))
        self.assertEqual(len(delta), 1)
        d = delta[0]
        self.assertEqual((d["variant"], d["base"], d["quality"]), ("B", "A", 127))
        self.assertEqual((d["first"], d["tapMedian"], d["tapP90"], d["back"]), (-300, -100, -14300, -50))
        self.assertEqual((d["stalls"], d["timeouts"], d["rssMB"]), (-1, -1, -112))

    def test_engine_events_belong_to_the_pass_they_ran_in(self):
        passes = phone_report.runs(self.events)[0]["passes"]
        first = phone_report.node_table(passes[0]["events"])
        self.assertEqual(sorted(first), ["cos", "hk", "upos-hz-mirrorakam.akamaized.net"])
        cos = first["cos"]
        self.assertEqual((cos["won"], phone_report.median(cos["firstByte"])), (3, 200))
        self.assertEqual(len(cos["mbps"]), 2, "the 30 KB piece is too small to time")
        self.assertAlmostEqual(phone_report.median(cos["mbps"]), 1048576 * 8 / 1000 / 400)
        self.assertEqual(cos["emptyLosses"], 0, "a loss after the first byte is not an empty one")
        hk = first["hk"]
        self.assertEqual((hk["won"], hk["emptyLosses"], phone_report.median(hk["emptyWait"]), hk["failed"]), (0, 2, 650, 1))
        reads = phone_report.seek_reads(passes[0]["events"])
        self.assertEqual((phone_report.median(reads["video"]["firstByte"]), phone_report.median(reads["video"]["ms"])), (300, 1100))
        self.assertEqual(phone_report.median(reads["audio"]["firstByte"]), 100)
        second = phone_report.node_table(passes[1]["events"])
        self.assertEqual(list(second), ["cos"])
        self.assertEqual(second["cos"]["won"], 1)

    def test_memory_warnings_and_error_log_statuses(self):
        self.assertEqual([rss for _, rss in phone_report.memory_warnings(self.events)], [812])
        self.assertEqual(phone_report.error_logs(self.events), {"-12938": 2, "403": 1})

    def test_the_report_never_prints_a_url(self):
        text = phone_report.render(self.events)
        self.assertNotIn("http", text)
        self.assertNotIn("SECRET", text)
        self.assertNotIn("upgcxcode", text)
        self.assertIn("upos-hz-mirrorakam.akamaized.net", text)
        self.assertEqual(phone_report.clean("see https://a.example.com/x/y.m4s?upsig=1, then (https://b.example.com/z)"),
                         "see a.example.com, then (b.example.com)")

    def test_the_report_reads_as_results_then_passes(self):
        text = phone_report.render(self.events)
        self.assertIn("== Speed test 1: plan builtin-1 (builtin: 电脑上没有计划), 3 passes, 1 video(s) ==", text)
        self.assertRegex(text, r"A 8K\(127\)\s+1\s+1\.50\s+0\.60/15\.00/15\.00")
        self.assertRegex(text, r"B-A 8K\(127\)\s+-0\.30\s+-0\.10/-14\.30/-14\.30")
        self.assertIn("skipped: pass 3 (A, asked 4K(120), played 4K(120))", text)
        self.assertIn("-- pass 2: B 8K(127) HEVC BV1GJ411x7h7 seed 22", text)
        self.assertIn("seek reads video: first byte 300 ms, whole read 1100 ms (n=2)", text)
        self.assertIn("memory warnings: 1", text)
        self.assertIn("player error log: -12938 x2, 403 x1", text)

    def test_a_session_without_a_speed_test_gets_the_whole_session(self):
        plain = [event for event in self.events if not str(event.get("msg", "")).startswith("speedtest")]
        self.assertEqual(phone_report.runs(plain), [])
        text = phone_report.render(plain)
        self.assertIn("== Session (no speed test) ==", text)
        self.assertIn("first frames: 1, median 1.50 s", text)
        self.assertIn("seeks resumed: 1, median 0.30 s", text)
        self.assertIn("stalls: 1", text)
        self.assertEqual(phone_report.node_table(plain)["cos"]["won"], 4)
        self.assertNotIn("http", text)

    def test_cold_and_warm_passes_are_kept_apart_and_compared_alike(self):
        def pass_events(number, variant, cold, tap):
            return [
                {"seq": number * 10, "msg": "speedtest pass",
                 "f": {"pass": number, "variant": variant, "quality": 127, "cold": cold, "seed": number}},
                {"seq": number * 10 + 1, "msg": "speedtest step", "f": {"pass": number, "kind": "tap", "ms": tap}},
                {"seq": number * 10 + 2, "msg": "speedtest pass done",
                 "f": {"pass": number, "variant": variant, "quality": 127, "firstFrameMs": 500}},
            ]

        # Logging came on after the start: the run still counts, from its first pass.
        events = (pass_events(1, "A", True, 8000) + pass_events(2, "B", False, 300) + pass_events(3, "B", True, 5000)
                  + pass_events(4, "A", False, 400) + [{"seq": 99, "msg": "speedtest done", "f": {"passes": 4}}])
        run = phone_report.runs(events)[0]
        self.assertEqual(len(run["passes"]), 4)
        self.assertEqual([(g["variant"], g["phase"], g["tapMedian"]) for g in phone_report.groups(run)],
                         [("A", "cold", 8000), ("A", "warm", 400), ("B", "cold", 5000), ("B", "warm", 300)])
        self.assertEqual([(d["phase"], d["tapMedian"]) for d in phone_report.deltas(phone_report.groups(run))],
                         [("cold", -3000), ("warm", -100)])
        text = phone_report.render(events)
        self.assertIn("from pass 1 (its start is not in the log", text)
        self.assertRegex(text, r"B-A 8K\(127\) cold\s+\+0\.00\s+-3\.00")
        self.assertIn("-- pass 3: B 8K(127) cold", text)

    def test_latest_is_the_newest_session_file(self):
        with tempfile.TemporaryDirectory() as folder:
            logs = pathlib.Path(folder)
            self.assertIsNone(phone_report.latest_log(logs / "missing"))
            older = logs / "2026-10-17" / "old.jsonl"
            newer = logs / "2026-10-18" / "new.jsonl"
            for index, path in enumerate([older, newer]):
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps({"seq": 1, "msg": "x"}) + "\n", encoding="utf-8")
                os.utime(path, (1_700_000_000 + index, 1_700_000_000 + index))
            self.assertEqual(phone_report.latest_log(logs), newer)

    def test_main_prints_the_report_for_a_file(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(phone_report.main([str(FIXTURE)]), 0)
        self.assertIn("Speed test 1", out.getvalue())


if __name__ == "__main__":
    unittest.main()
