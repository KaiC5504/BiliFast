import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "testdata"))
import phone_report  # noqa: E402
import turn_logs  # noqa: E402

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


def analysed(log):
    grouped = phone_report.group_turns(log.events())
    return [(turn, phone_report.analyse_turn(turn, grouped["pool"])) for turn in grouped["turns"]]


def only(log):
    found = analysed(log)
    assert len(found) == 1, found
    return found[0]


class TurnReportTests(unittest.TestCase):
    def assertGrades(self, a, *, start, sweep, verdict, fails=()):
        self.assertAlmostEqual(a["start"], start, delta=1)
        self.assertAlmostEqual(a["sweep"], sweep, delta=1)
        self.assertEqual(a["verdict"], verdict, phone_report.verdict_text(a))
        self.assertEqual([key for key, _ in a["fails"]], list(fails))

    def test_ios_still_turning_under_the_drawn_spin_sweeps_180(self):
        for to_landscape, start, ios in ((True, -180, 90), (False, 180, -90)):
            log = turn_logs.Log()
            log.turn("原样·直接切·立即", method="legacy", ios_turns=True, to_landscape=to_landscape)
            turn, a = only(log)
            self.assertGrades(a, start=start, sweep=180, verdict="bad", fails=["sweep"])
            self.assertTrue(a["monotonic"])
            self.assertAlmostEqual(a["ios"], ios, delta=1)
            self.assertEqual(phone_report.direction_of(turn), "to L" if to_landscape else "back")

    def test_a_clean_drawn_turn_is_good(self):
        for to_landscape, start in ((True, -90), (False, 90)):
            log = turn_logs.Log()
            log.turn("移除·直接切·立即", to_landscape=to_landscape)
            _, a = only(log)
            self.assertGrades(a, start=start, sweep=90, verdict="good")
            self.assertAlmostEqual(a["ios"], 0, delta=0.1)
            self.assertLess(a["ghost"][0], 1)
            self.assertLess(a["moved"], phone_report.FIRST_MOVE_MAX_MS)
            self.assertAlmostEqual(a["gap"], 1000 / 120, delta=0.1)
            self.assertAlmostEqual(a["tick"], 1000 / 120, delta=0.1)
            self.assertEqual(a["slow"], 0)
            self.assertLessEqual(a["overshoot"], 1)
            self.assertIsNone(a["mismatch"])

    def test_a_60_hz_turn_measures_its_own_tick(self):
        log = turn_logs.Log()
        log.turn("移除·直接切·立即", hz=60, totals={3: 12, 4: 12, 5: 12})
        _, a = only(log)
        self.assertGrades(a, start=-90, sweep=90, verdict="good")
        self.assertAlmostEqual(a["tick"], 1000 / 60, delta=0.1)
        self.assertAlmostEqual(a["gap"], 1000 / 60, delta=0.1)
        self.assertEqual(a["slow"], 0, "12 ms is inside a 60 Hz tick")

    def test_the_system_turn_is_seen_through_the_window_alone(self):
        log = turn_logs.Log()
        log.turn("系统", method="system", ios_turns=True)
        events = log.events()
        self.assertEqual({event["f"]["method"] for event in events if event["msg"].startswith("turn native ")},
                         {"system"})
        self.assertEqual({event["msg"] for event in events},
                         {"turn presentation", "turn native request", "turn native request returned",
                          "turn native begin", "turn native completion", "turn native frames", "turn sized",
                          "turn frames"}, "what Swift and the page log for 系统")
        # Whatever angle the page's frames say, 系统's is iOS's turn alone.
        frames = next(event for event in events if event["msg"] == "turn frames")
        frames["f"]["samples"] = ";".join(
            ",".join([parts[0], "45", *parts[2:]]) for parts in
            (sample.split(",") for sample in frames["f"]["samples"].split(";")))
        grouped = phone_report.group_turns(events)
        turn = grouped["turns"][0]
        a = phone_report.analyse_turn(turn, grouped["pool"])
        self.assertGrades(a, start=-90, sweep=90, verdict="good")
        self.assertIsNone(a["mismatch"])
        self.assertAlmostEqual(a["ios"], 90, delta=1)
        text = "\n".join(phone_report.turn_detail(1, turn, a))
        self.assertNotIn("not in the log", text, "nothing is missing: 系统 is never sent to Dart")
        self.assertIsNone(a["ghost"])
        self.assertIsNone(a["pictureUntil"])

    def test_a_picture_fading_over_a_moving_page_is_a_ghost(self):
        log = turn_logs.Log()
        log.turn("移除·淡出·立即", picture="fade", fade_ms=120)
        _, a = only(log)
        self.assertGrades(a, start=-90, sweep=90, verdict="bad", fails=["ghost"])
        self.assertGreater(a["ghost"][0], 10)
        self.assertGreater(a["pictureUntil"], 150)

    def test_a_picture_cut_before_the_first_frame_is_on_screen_shows_the_old_frame(self):
        # The page's first frame (built at 20 ms, its raster done at 27) is on screen at the 33 ms tick; the picture
        # went at 24 ms, before it.
        log = turn_logs.Log()
        log.turn("移除·直接切·立即", drawn_ms=24)
        _, a = only(log)
        self.assertAlmostEqual(a["ghost"][0], 90, delta=1)
        self.assertGreater(a["sweep"], 250)
        self.assertFalse(a["monotonic"])
        self.assertEqual([key for key, _ in a["fails"]], ["sweep", "back and forth", "ghost"])

    def test_a_300_ms_gap_is_a_stall(self):
        log = turn_logs.Log()
        log.turn("移除·直接切·立即", stall_at_ms=150, stall_ms=300)
        _, a = only(log)
        self.assertAlmostEqual(a["gap"], 300, delta=0.1)
        self.assertEqual(a["verdict"], "bad")
        self.assertEqual([key for key, _ in a["fails"]], ["gap"])
        self.assertGreater(a["step"], 40)

    def test_turns_take_the_style_of_the_cycle_they_ran_in(self):
        log = turn_logs.Log()
        log.cycle(1, 13, "原样·直接切·立即")
        log.turn("原样·直接切·立即", method="legacy", ios_turns=True)
        log.turn("别的", method="legacy", ios_turns=True, to_landscape=False)
        log.cycle(2, 13, "移除·直接切·立即")
        log.turn("移除·直接切·立即")
        log.cycle_done()
        log.turn("抵消·淡出·立即", method="counter", picture="fade", fade_ms=120, ios_turns=True, counter=True)
        found = analysed(log)
        self.assertEqual([phone_report.style_of(turn) for turn, _ in found],
                         [("原样·直接切·立即", None), ("原样·直接切·立即", "别的"), ("移除·直接切·立即", None),
                          ("抵消·淡出·立即", None)])
        rows = phone_report.style_summary(found)
        self.assertEqual([(row["style"], row["turns"], row["good"], row["bad"]) for row in rows],
                         [("移除·直接切·立即", 1, 1, 0), ("原样·直接切·立即", 2, 0, 2), ("抵消·淡出·立即", 1, 0, 1)])
        text = phone_report.render_turns(log.events())
        self.assertIn("(轮换 1/13)", text)
        self.assertIn("the page logged style 别的", text)

    def test_lines_are_placed_by_turn_id_and_time_not_by_arrival(self):
        log = turn_logs.Log()
        log.turn("移除·直接切·立即")
        log.now -= 2_400_000  # the turn back starts 600 ms after the first
        log.turn("移除·直接切·立即", to_landscape=False)
        events = log.events()
        # The phone may log the two sides in any order; only the wall clock counts.
        shuffled = [{**event, "seq": len(events) - index} for index, event in enumerate(events)]
        for given in (events, shuffled):
            grouped = phone_report.group_turns(given)
            first, second = grouped["turns"]
            self.assertEqual((first["id"], second["id"]), (1, 2))
            self.assertEqual((first["presentation"]["to"], second["presentation"]["to"]), ("landscape", "inline"))
            self.assertEqual((first["request"]["request"], second["request"]["request"]), (1, 2))
            self.assertEqual((first["returned"]["request"], second["returned"]["request"]), (1, 2))
            self.assertEqual([f["w"] for f in first["dart"]["sized"]], [956])
            self.assertEqual([f["w"] for f in second["dart"]["sized"]], [440])
            self.assertEqual((len(first["dartFrames"]), len(second["dartFrames"])), (1, 1))
            a = phone_report.analyse_turn(first, grouped["pool"])
            self.assertAlmostEqual(a["cut"], 600, delta=1)
            self.assertLessEqual(a["ticks"], 72)
            self.assertEqual(a["verdict"], "good")

    def test_each_turn_holds_only_its_own_frames_line(self):
        # The page's line starts at the presentation change, before the native begin, inside the last turn's trail.
        for apart_ms in (600, 1000, 3000):
            log = turn_logs.Log()
            log.turn("移除·直接切·立即")
            log.now += (apart_ms - 3000) * 1000
            log.turn("移除·直接切·立即", to_landscape=False)
            log.now += (apart_ms - 3000) * 1000
            log.turn("系统", method="system", ios_turns=True)
            events = log.events()
            counts = [event["f"]["count"] for event in events if event["msg"] == "turn frames"]
            starts = [event["f"]["t0Us"] for event in events if event["msg"] == "turn frames"]
            grouped = phone_report.group_turns(events)
            turns = grouped["turns"]
            self.assertTrue(all(start < turn["us"] for start, turn in zip(starts, turns)), "a waiting frame first")
            self.assertEqual([len(turn["dartFrames"]) for turn in turns], [1, 1, 1], f"{apart_ms} ms apart")
            self.assertEqual([phone_report.analyse_turn(turn, grouped["pool"])["dartFrames"] for turn in turns],
                             counts)
            self.assertEqual(grouped["unplaced"], {})

    def test_a_frames_line_logged_after_the_next_turn_began_still_belongs_to_its_own(self):
        # Release builds wait for FrameTimings: the page's frames line can come ~1.5 s after the turn's last frame.
        log = turn_logs.Log()
        log.turn("移除·直接切·立即", frames_after_ms=1500)
        log.now -= 2_000_000  # the turn back begins 1 s after the first, before the first's frames line
        log.turn("移除·直接切·立即", to_landscape=False, frames_after_ms=1500)
        events = log.events()
        order = [event["msg"] for event in events]
        self.assertLess(order.index("turn presentation", order.index("turn native begin") + 1),
                        order.index("turn frames"))
        grouped = phone_report.group_turns(events)
        first, second = grouped["turns"]
        self.assertEqual([len(turn["dartFrames"]) for turn in (first, second)], [1, 1])
        self.assertLess(first["dartFrames"][0]["span"][1], second["us"])
        self.assertLess(second["dartFrames"][0]["span"][0], second["us"], "its waiting frame, in the first's trail")
        for turn, start in ((first, -90), (second, 90)):
            a = phone_report.analyse_turn(turn, grouped["pool"])
            self.assertGrades(a, start=start, sweep=90, verdict="good")

    def test_missing_pieces_are_named_not_fatal(self):
        log = turn_logs.Log()
        log.cycle(0, 13, "系统")
        log.turn("系统", method="system", ios_turns=True, dart=False)
        log.cycle(1, 13, "移除·直接切·立即")
        log.turn("移除·直接切·立即", native=False)
        log.turn("移除·直接切·立即", dart=False)
        log.turn("移除·直接切·立即", native_frames=False)
        log.turn("移除·直接切·立即", dart_frames=False)
        log.presentation_only("移除·直接切·立即")
        found = analysed(log)
        self.assertEqual([a["verdict"] for _, a in found], ["good", "?", "?", "?", "?"])
        self.assertEqual([a["unknown"] for _, a in found[1:]],
                         [["no native lines"], ["no Dart frames, so the page's spin is left out"],
                          ["no native frames"], ["no Dart frames, so the page's spin is left out"]])
        text = phone_report.render_turns(log.events())
        self.assertIn("not in the log: native request, native begin, native frames", text)
        self.assertIn("not in the log: Dart presentation, Dart started, Dart began, Dart frames", text)
        self.assertIn("presentation changes no turn followed: 1", text)
        self.assertIn("(late, missed)", text)
        self.assertIn("?: no native frames", text)

    def test_malformed_lines_and_samples_never_crash(self):
        log = turn_logs.Log()
        log.turn("移除·直接切·立即")
        events = log.events()
        native = next(event for event in events if event["msg"] == "turn native frames")
        native["f"]["samples"] = "rubbish;1,2;;" + native["f"]["samples"] + ";5,16.7,0,x,956,440,,0,,"
        dart = next(event for event in events if event["msg"] == "turn frames")
        dart["f"]["samples"] = dart["f"]["samples"] + ";oops;3"
        dart["f"]["timings"] = "a,b;1"
        events += [
            {"seq": 900, "msg": "turn native begin", "f": "not fields"},
            {"seq": 901, "msg": "turn started", "f": {"turn": "two"}},
            {"seq": 902, "msg": 5},
            {"seq": 903, "msg": "turn frames", "t": 1_760_000_100.0, "f": {"wUs": "soon", "samples": 7}},
            {"seq": 904, "msg": "turn native frames", "t": 1_760_000_000.5, "f": {"turn": 1, "samples": None}},
            {"seq": 905, "msg": "turn cycle", "f": {"wUs": 1.5e15, "label": None}},
            {"seq": 906, "msg": "turn presentation", "f": {"wUs": float("inf")}},
            {"seq": 907, "msg": "turn native drawn", "f": {"wUs": 1e30, "turn": 99}},
        ]
        grouped = phone_report.group_turns(events)
        first = grouped["turns"][0]
        a = phone_report.analyse_turn(first, grouped["pool"])
        self.assertEqual(a["malformed"], 4)
        self.assertEqual(a["verdict"], "good")
        self.assertEqual(grouped["dartBad"], 2)
        text = phone_report.render_turns(events)
        self.assertIn("4 native samples unreadable", text)
        self.assertIn("turn lines without a time: 3", text)
        self.assertIn("Dart frame samples unreadable: 2", text)
        self.assertEqual(phone_report.render_turns([]).strip(),
                         "no turns in this log (the 旋转动画 test build logs them while 发送日志到电脑 is on)")

    def test_styles_rank_good_first_then_by_worst_gap_and_first_move(self):
        log = turn_logs.Log()
        for label, options in (("坏", {"method": "legacy", "ios_turns": True}),
                               ("慢", {"stall_at_ms": 150, "stall_ms": 40}),
                               ("好", {}),
                               ("晚", {"hold": True, "first_frame_ms": 10, "drawn_ms": 40}),
                               ("缺", {"native_frames": False})):
            log.turn(label, **options)
            log.turn(label, to_landscape=False, **options)
        rows = phone_report.style_summary(analysed(log))
        self.assertEqual([row["style"] for row in rows], ["好", "晚", "慢", "坏", "缺"])
        self.assertEqual([(row["good"], row["bad"], row["unknown"]) for row in rows],
                         [(2, 0, 0), (2, 0, 0), (2, 0, 0), (0, 2, 0), (0, 0, 2)])
        self.assertAlmostEqual(rows[2]["gap"], 40, delta=0.1)
        self.assertGreater(rows[1]["move"], rows[0]["move"])
        self.assertEqual(rows[3]["fails"], {"sweep": 2})
        self.assertAlmostEqual(rows[0]["sweep"], 90, delta=1)

    def test_the_turn_report_never_prints_a_url(self):
        log = turn_logs.Log()
        log.cycle(0, 13, "see https://evil.example.com/x?token=SECRET")
        log.turn("移除·直接切·立即")
        text = phone_report.render_turns(log.events())
        self.assertIn("evil.example.com", text)
        self.assertNotIn("http", text)
        self.assertNotIn("SECRET", text)

    def test_the_sample_session_is_what_turn_logs_writes(self):
        self.assertEqual(phone_report.load(turn_logs.SAMPLE), turn_logs.sample().events())

    def test_main_grades_the_sample_session(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(phone_report.main(["--turns", str(turn_logs.SAMPLE)]), 0)
        text = out.getvalue()
        self.assertIn("== Turns: 12 (back 6, to L 6) ==", text)
        self.assertIn("== Styles, best first ==", text)
        summary = text[text.index("== Styles, best first =="):].splitlines()
        self.assertRegex(summary[2], r"^1\s+系统\s+1/13\s+2\s+2\s+0\s+0\s+0\s+90\s.*under 4 turns$")
        self.assertRegex(summary[3], r"^2\s+移除·直接切·立即\s+3/13\s+4\s+3\s+0\s+1\s+0\s+90\s")
        self.assertRegex(text, r"原样·淡出·立即\s+to L .* bad: sweep 180°, ghost 23.3°")
        self.assertIn("bad: ghost 23.3°", text)
        self.assertIn("bad: gap 300 ms", text)
        self.assertRegex(text, r"\n12 .* back +25 +16\.7 .* good\n", "the 60 Hz turn")
        self.assertIn("native sends to Dart lost: 2", text)

    def test_a_cycle_switched_off_labels_nothing_after_it(self):
        log = turn_logs.Log()
        log.cycle(1, 13, "移除·淡出·立即")
        log.turn("移除·淡出·立即", picture="fade")
        log.cycle_off(1, 13, "抵消·直接切·立即")
        log.turn("抵消·直接切·立即", method="counter", ios_turns=True, counter=True)
        log.cycle(1, 13, "系统")
        log.cycle_done(13, "移除·直接切·立即")
        log.turn("移除·直接切·立即")
        found = analysed(log)
        self.assertEqual([phone_report.style_of(turn) for turn, _ in found],
                         [("移除·淡出·立即", None), ("抵消·直接切·立即", None), ("移除·直接切·立即", None)])
        self.assertEqual([turn["cycle"] is not None for turn, _ in found], [True, False, False])
        self.assertEqual([a["mismatch"] for _, a in found], [None, None, None])
        text = phone_report.render_turns(log.events())
        self.assertIn("移除·淡出·立即 (轮换 1/13)", text)
        self.assertNotIn("抵消·直接切·立即 (轮换", text)

    def test_a_turn_whose_native_begin_disagrees_with_its_label_is_flagged(self):
        log = turn_logs.Log()
        log.cycle(4, 13, "移除·淡出·立即")
        log.turn("移除·淡出·立即", picture="fade")
        log.turn("移除·淡出·立即", to_landscape=False)  # the style hadn't reached the host
        log.cycle_off(4)
        log.turn("抵消·直接切·立即", method="remove", to_landscape=True)
        log.turn("系统", method="system", ios_turns=True, to_landscape=False)
        log.turn("系统", method="legacy", picture="none", ios_turns=True, spin=False)  # the takeover still on
        log.turn("不转", method="noSpin", picture="cut", spin=False, ios_turns=True)
        log.turn("自定", method="remove")
        found = analysed(log)
        self.assertEqual([a["mismatch"] for _, a in found],
                         [None, "remove/cut", "remove/cut", None, "legacy/none", "noSpin/cut", None])
        text = phone_report.render_turns(log.events())
        self.assertIn("移除·淡出·立即 ≠ remove/cut", text)
        self.assertIn("the native begin ran remove/cut, not 移除·淡出·立即", text)
        self.assertIn("the native begin ran remove/cut, not 抵消·直接切·立即", text)
        rows = {row["style"]: row for row in phone_report.style_summary(found)}
        self.assertEqual(rows["移除·淡出·立即"]["mismatched"], 1)
        self.assertEqual(rows["系统"]["mismatched"], 1)

    def test_styles_rank_by_good_out_of_all_their_turns_a_question_mark_counting_as_not_good(self):
        log = turn_logs.Log()
        for _ in range(2):
            log.turn("半", native_frames=False)
            log.turn("半", to_landscape=False)
        for to_landscape in (True, False, True):
            log.turn("多", to_landscape=to_landscape)
        log.turn("多", method="legacy", ios_turns=True)
        log.turn("一", to_landscape=False)
        rows = phone_report.style_summary(analysed(log))
        self.assertEqual([(row["style"], row["good"], row["bad"], row["unknown"]) for row in rows],
                         [("一", 1, 0, 0), ("多", 3, 1, 0), ("半", 2, 0, 2)])
        self.assertEqual([row["few"] for row in rows], [True, False, False])
        summary = phone_report.render_turns(log.events()).split("== Styles, best first ==")[1].splitlines()
        self.assertRegex(summary[2], r"^1\s+一\s.*under 4 turns$")
        self.assertNotIn("under 4 turns", summary[3] + summary[4])

    def test_a_dart_frame_is_on_screen_from_the_first_tick_after_its_raster_finished(self):
        self.assertEqual(phone_report.on_screen([(0, None, 10.0), (8_000, 30_000, 20.0), (16_000, 25_000, 30.0)],
                                                8_333), ([8_333, 25_000, 30_000], [10.0, 30.0, 20.0]))
        # The first frame is built at 20 ms and its raster is done at 48: on screen at the 50 ms tick, after the
        # picture went at 35. Placed a tick after it was built instead, it would be under the picture by 33.
        graded = {}
        for shown in (True, False):
            log = turn_logs.Log()
            log.turn("移除·直接切·立即", drawn_ms=35, totals={0: 28}, shown=shown)
            graded[shown] = only(log)[1]
        self.assertAlmostEqual(graded[True]["ghost"][0], 90, delta=1)
        self.assertFalse(graded[True]["monotonic"])
        self.assertEqual(graded[True]["verdict"], "bad")
        self.assertLess(graded[False]["ghost"][0], 1)
        self.assertEqual(graded[False]["verdict"], "good")
        self.assertEqual(graded[False]["slow"], 1)

    def test_more_than_two_slow_dart_frames_inside_the_turn_fail_it(self):
        def turn(slow_frames, **options):
            log = turn_logs.Log()
            log.turn("移除·直接切·立即", totals={index: 12 for index in range(5, 5 + slow_frames)}, **options)
            return log

        _, two = only(turn(2))
        self.assertEqual((two["slow"], two["verdict"]), (2, "good"))
        _, three = only(turn(3))
        self.assertEqual(three["slow"], 3)
        self.assertGrades(three, start=-90, sweep=90, verdict="bad", fails=["slow"])
        self.assertIn("bad: 3 slow frames", phone_report.verdict_text(three))
        _, sixty = only(turn(3, hz=60))
        self.assertEqual((sixty["slow"], sixty["verdict"]), (0, "good"), "against the turn's own tick")

        # A slow frame placed after the turn is not the turn's.
        events = turn(2).events()
        frames = next(event for event in events if event["msg"] == "turn frames")
        frames["f"]["timings"] += ";4.2,20,24.2,5000"
        grouped = phone_report.group_turns(events)
        self.assertEqual(phone_report.analyse_turn(grouped["turns"][0], grouped["pool"])["slow"], 2)
        # Without timings, the line's own count.
        frames["f"]["timings"] = ""
        frames["f"]["slow"] = 3
        grouped = phone_report.group_turns(events)
        a = phone_report.analyse_turn(grouped["turns"][0], grouped["pool"])
        self.assertEqual((a["slow"], a["verdict"]), (3, "bad"))
        # Without a raster finish, every frame of the line.
        _, unplaced = only(turn(3, raster_end=False, shown=False))
        self.assertEqual((unplaced["slow"], unplaced["verdict"]), (3, "bad"))

    def test_a_picture_style_whose_snapshot_failed_is_not_graded(self):
        for picture in ("cut", "fade"):
            log = turn_logs.Log()
            log.turn("移除·直接切·立即", picture=picture, snapshot=False)
            _, a = only(log)
            self.assertEqual(a["verdict"], "?")
            self.assertEqual(a["unknown"], ["no picture"])
            text = phone_report.render_turns(log.events())
            self.assertIn("?: no picture", text)
            self.assertIn("snapshot failed", text)
        log = turn_logs.Log()
        log.turn("移除·无截图·立即", picture="none")
        _, a = only(log)
        self.assertEqual(a["unknown"], [], "no picture is what 无截图 asks for")

    def test_lost_sends_are_totalled(self):
        log = turn_logs.Log()
        log.turn("移除·直接切·立即", lost=3)
        log.turn("移除·直接切·立即", to_landscape=False, lost=2)
        log.native(log.now, "container", 0, "counter", "cut", event="lost", lost=1)
        grouped = phone_report.group_turns(log.events())
        self.assertEqual(grouped["lost"], 6)
        self.assertEqual([turn["lost"] for turn in grouped["turns"]], [3, 2])
        text = phone_report.render_turns(log.events())
        self.assertIn("native sends to Dart lost: 6", text)
        self.assertIn("notes: 3 native sends lost before its lines", text)
        self.assertNotIn("lost", phone_report.render_turns([]))

if __name__ == "__main__":
    unittest.main()
