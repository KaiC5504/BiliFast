import io
import json
import os
import pathlib
import subprocess
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
    return [(turn, phone_report.analyse_turn(turn)) for turn in grouped["turns"]]


def only(log):
    found = analysed(log)
    assert len(found) == 1, found
    return found[0]


def fail_keys(a):
    return [key for key, _ in a["fails"]]


class TurnReportTests(unittest.TestCase):
    def test_a_drawn_turn_reads_as_its_timeline(self):
        for to_landscape in (True, False):
            for picture in ("cut", None):
                log = turn_logs.Log()
                log.turn("自绘", to_landscape=to_landscape, picture=picture)
                turn, a = only(log)
                self.assertEqual(phone_report.style_of(turn), ("自绘", None))
                self.assertEqual(phone_report.direction_of(turn), "to L" if to_landscape else "back")
                self.assertTrue(a["drawn"])
                self.assertEqual((a["requestToBegin"], a["started"], a["began"], a["drawnAt"], a["picture"]),
                                 (20, 9, 11, 20, 20))
                self.assertEqual((a["outcome"], a["pictureWhy"]), ("pending", "drawn"))
                # The picture hides the page's first frames: the turn shows once it is gone.
                self.assertEqual(a["move"], 40)
                self.assertEqual((a["fails"], a["missing"], a["mismatch"]), ([], [], None))

    def test_the_system_turn_moves_at_its_begin_and_sends_nothing_to_dart(self):
        log = turn_logs.Log()
        log.turn("系统", method="system", to_landscape=False)
        events = log.events()
        self.assertEqual({event["msg"] for event in events},
                         {"turn presentation", "turn native request", "turn native request returned",
                          "turn native begin", "turn native completion", "turn sized"})
        turn, a = only(log)
        self.assertFalse(a["drawn"])
        self.assertEqual((a["requestToBegin"], a["move"], a["began"], a["picture"]), (20, 20, None, None))
        self.assertEqual((a["fails"], a["missing"]), ([], []))
        text = "\n".join(phone_report.turn_detail(1, turn, a))
        self.assertNotIn("not in the log", text)

    def test_a_held_turn_moves_once_released(self):
        log = turn_logs.Log()
        log.turn("请求前关·直接切·等截图", build=14, hold=True)
        turn, a = only(log)
        self.assertAlmostEqual(a["move"], 40.35, delta=0.01, msg="released just after the picture went")
        self.assertEqual(a["fails"], [])

    def test_a_turn_backs_presentation_after_its_begin_is_its_own(self):
        # The page logs a turn back's presentation change a few ms after the native begin.
        log = turn_logs.Log()
        log.turn("自绘")
        log.now -= 2_400_000
        log.turn("自绘", to_landscape=False)
        log.now -= 2_400_000
        log.turn("系统", method="system")
        grouped = phone_report.group_turns(log.events())
        turns = grouped["turns"]
        self.assertEqual([turn["presentation"]["to"] for turn in turns], ["landscape", "inline", "landscape"])
        self.assertEqual([turn["presentation"]["us"] - turn["us"] for turn in turns], [-10_000, 8_000, -10_000])
        self.assertEqual([phone_report.style_of(turn)[0] for turn in turns], ["自绘", "自绘", "系统"])
        self.assertEqual(grouped["orphans"], [])

    def test_failures_are_named(self):
        log = turn_logs.Log()
        log.turn("自绘", fallback=True)
        log.turn("自绘", late=True, to_landscape=False)
        log.turn("自绘", outcome="stale")
        log.turn("自绘", outcome="unasked", to_landscape=False)
        log.turn("请求前关·淡出·立即", build=14, picture="fade", fade_ms=130)
        log.turn("自绘", lost=3, to_landscape=False)
        log.turn("系统")  # the takeover still on
        log.turn("自绘", fallback=True, snapshot=False, to_landscape=False)
        found = analysed(log)
        self.assertEqual([fail_keys(a) for _, a in found],
                         [["fallback", "picture"], ["late"], ["stale"], ["unasked"], ["picture"], ["lost"],
                          ["≠native"], ["fallback"]])
        self.assertEqual([phone_report.verdict_text(a) for _, a in found],
                         ["fallback, picture 500 ms", "late", "stale", "unasked", "picture 150 ms", "3 lost",
                          "ran quietRequest/cut", "fallback"])
        self.assertEqual(found[0][1]["move"], 520)
        self.assertEqual(found[0][1]["missing"], [], "a fallback stands for turnDrawn")
        text = phone_report.render_turns(log.events())
        self.assertRegex(text, r"\n1 .* 自绘\s+to L\s+20\s+9\s+11\s+510\s+500 fallback\s+520\s+fallback, picture 500 ms\n")
        self.assertRegex(text, r"\n3 .* 9 stale ")
        self.assertIn("the native begin ran quietRequest/cut, not 系统", text)
        self.assertIn("notes: 3 native sends lost before its lines", text)
        self.assertIn("snapshot failed", text)

    def test_a_14_picture_the_page_doesnt_wait_for_is_not_a_failure(self):
        log = turn_logs.Log()
        log.turn("请求前关·无截图·立即", build=14, picture="none")
        _, a = only(log)
        self.assertEqual((a["picture"], a["move"], a["fails"]), (None, 31, []))

    def test_turns_take_the_style_of_the_cycle_they_ran_in(self):
        log = turn_logs.Log()
        log.cycle(1, 7, "请求前关·淡出·立即")
        log.turn("请求前关·淡出·立即", build=14, picture="fade")
        log.turn("别的", build=14, picture="fade", to_landscape=False)
        log.cycle_off(1, 7, "请求前关·直接切·等截图")
        log.turn("请求前关·直接切·等截图", build=14, hold=True)
        log.cycle(1, 7, "系统")
        log.cycle_done(7, "请求前关·直接切·立即")
        log.turn("请求前关·直接切·立即", build=14, to_landscape=False)
        found = analysed(log)
        self.assertEqual([phone_report.style_of(turn) for turn, _ in found],
                         [("请求前关·淡出·立即", None), ("请求前关·淡出·立即", "别的"),
                          ("请求前关·直接切·等截图", None), ("请求前关·直接切·立即", None)])
        self.assertEqual([turn["cycle"] is not None for turn, _ in found], [True, True, False, False])
        self.assertEqual([a["mismatch"] for _, a in found], [None, None, None, None])
        text = phone_report.render_turns(log.events())
        self.assertIn("请求前关·淡出·立即 (轮换 1/7)", text)
        self.assertIn("the page logged style 别的", text)
        self.assertNotIn("请求前关·直接切·等截图 (轮换", text)

    def test_a_turn_whose_native_begin_disagrees_with_its_label_is_flagged(self):
        log = turn_logs.Log()
        log.cycle(4, 7, "请求前关·淡出·立即")
        log.turn("请求前关·淡出·立即", build=14, picture="fade")
        log.turn("请求前关·淡出·立即", build=14, to_landscape=False)  # the style hadn't reached the host
        log.cycle_off(4)
        log.turn("请求前关·直接切·立即", build=14, method="system")
        log.turn("移除·直接切·立即", build=14, method="remove")  # 1.0.0 (13)'s, not checked
        log.turn("自绘", method="system", to_landscape=False)
        log.turn("自绘", picture="fade")
        log.turn("自定", to_landscape=False)
        found = analysed(log)
        self.assertEqual([a["mismatch"] for _, a in found],
                         [None, "quietRequest/cut", "system/none", None, "system/none", "quietRequest/fade", None])
        rows = {row["style"]: row for row in phone_report.style_summary(found)}
        self.assertEqual(rows["请求前关·淡出·立即"]["fails"]["≠native"], 1)
        self.assertEqual(rows["自绘"]["fails"]["≠native"], 2)

    def test_the_native_method_names_a_turn_the_page_left_unlabelled(self):
        log = turn_logs.Log()
        log.turn("自绘", dart=False)
        log.turn("系统", method="system", dart=False, to_landscape=False)
        log.turn("抵消", method="counter", dart=False)
        self.assertEqual([phone_report.style_of(turn)[0] for turn, _ in analysed(log)],
                         ["自绘", "系统", "counter/cut"])

    def test_missing_pieces_are_named_not_fatal(self):
        log = turn_logs.Log()
        log.turn("系统", method="system", dart=False)
        log.turn("自绘", native=False, to_landscape=False)
        log.turn("自绘", dart=False)
        log.presentation_only("自绘")
        found = analysed(log)
        self.assertEqual([a["missing"] for _, a in found],
                         [["Dart presentation"], ["native request", "native begin", "native drawn"],
                          ["Dart presentation", "Dart started", "Dart began"]])
        self.assertIsNone(found[1][1]["requestToBegin"])
        self.assertEqual((found[1][1]["move"], found[1][1]["moveFrom"]), (3, "presentation"))
        text = phone_report.render_turns(log.events())
        self.assertIn("not in the log: native request, native begin, native drawn", text)
        self.assertIn("ok (missing lines)", text)
        self.assertIn("presentation changes no turn followed: 1", text)
        self.assertIn("(late, missed)", text)

    def test_malformed_lines_never_crash(self):
        log = turn_logs.Log()
        log.turn("自绘")
        events = log.events() + [
            {"seq": 900, "msg": "turn native begin", "f": "not fields"},
            {"seq": 901, "msg": "turn started", "f": {"turn": "two"}},
            {"seq": 902, "msg": 5},
            {"seq": 903, "msg": "turn frames", "t": 1_760_000_100.0, "f": {"wUs": "soon", "samples": 7}},
            {"seq": 904, "msg": "turn native frames", "t": 1_760_000_000.5, "f": {"turn": 1, "samples": None}},
            {"seq": 905, "msg": "turn cycle", "f": {"wUs": 1.5e15, "label": None}},
            {"seq": 906, "msg": "turn presentation", "f": {"wUs": float("inf")}},
            {"seq": 907, "msg": "turn native drawn", "f": {"wUs": 1e30, "turn": 99}},
            {"seq": 908, "msg": "turn native picture gone", "f": {"wUs": 1.76e15, "turn": 1, "why": None}},
        ]
        grouped = phone_report.group_turns(events)
        self.assertEqual(phone_report.analyse_turn(grouped["turns"][0])["fails"], [])
        text = phone_report.render_turns(events)
        self.assertIn("turn lines without a time: 3", text)
        self.assertEqual(phone_report.render_turns([]).strip(),
                         "no turns in this log (dev builds log them while 发送日志到电脑 is on)")

    def test_lines_are_placed_by_turn_id_and_time_not_by_arrival(self):
        log = turn_logs.Log()
        log.turn("自绘")
        log.now -= 2_400_000  # the turn back starts 600 ms after the first
        log.turn("自绘", to_landscape=False)
        events = log.events()
        shuffled = [{**event, "seq": len(events) - index} for index, event in enumerate(events)]
        for given in (events, shuffled):
            grouped = phone_report.group_turns(given)
            first, second = grouped["turns"]
            self.assertEqual((first["id"], second["id"]), (1, 2))
            self.assertEqual((first["request"]["request"], second["request"]["request"]), (1, 2))
            self.assertEqual((first["returned"]["request"], second["returned"]["request"]), (1, 2))
            self.assertEqual([f["w"] for f in first["dart"]["sized"]], [956])
            self.assertEqual([f["w"] for f in second["dart"]["sized"]], [440])
            self.assertEqual([phone_report.analyse_turn(turn)["fails"] for turn in (first, second)], [[], []])

    def test_older_builds_per_frame_and_13_lines_are_passed_over(self):
        log = turn_logs.Log()
        log.cycle(4, 13, "抵消·直接切·立即")
        log.turn("抵消·直接切·立即", build=14, method="counter")
        log.turn("抵消·直接切·立即", build=14, method="counter", to_landscape=False)
        clean = [a for _, a in analysed(log)]
        for turn in (1, 2):
            us = turn_logs.START_US + 500_000 + (turn - 1) * 3_000_000
            log.native(us + 1000, "animations", turn, "counter", "cut", phase="after super",
                       found="window|transform|CABasicAnimation|0.4|easeInEaseOut|false|0", removed=2)
            log.native(us + 2000, "container", turn, "counter", "cut", event="installed")
        log.native(log.now, "container", 7, "counter", "cut", event="lost", lost=1)
        events = log.events()
        grouped = phone_report.group_turns(events)
        self.assertEqual([turn["id"] for turn in grouped["turns"]], [1, 2], "no turn made up from a container line")
        self.assertEqual((grouped["unplaced"], grouped["lost"], grouped["frames"]), ({}, 1, 4))
        self.assertEqual([phone_report.analyse_turn(turn) for turn in grouped["turns"]], clean)
        text = phone_report.render_turns(events)
        self.assertNotIn("animations", text)
        self.assertNotIn("container", text)
        self.assertIn("per-frame lines passed over: 4", text)

    def test_styles_are_summed_up_in_the_order_first_seen(self):
        log = turn_logs.Log()
        log.turn("系统", method="system")
        log.turn("自绘", to_landscape=False)
        log.turn("自绘", fallback=True)
        log.turn("系统", method="system", to_landscape=False, late=True)
        log.turn("自绘", to_landscape=False, dart=False)
        rows = phone_report.style_summary(analysed(log))
        self.assertEqual([(row["style"], row["turns"], row["ok"], row["missing"]) for row in rows],
                         [("系统", 2, 1, 0), ("自绘", 3, 2, 1)])
        self.assertEqual(rows[0]["fails"], {"late": 1})
        self.assertEqual(rows[1]["fails"], {"fallback": 1, "picture": 1})
        self.assertEqual((rows[1]["picture"], rows[1]["pictureMax"], rows[1]["move"], rows[1]["moveMax"]),
                         (20, 500, 280, 520))
        self.assertEqual((rows[0]["move"], rows[0]["began"]), (20, None))

    def test_the_turn_report_never_prints_a_url(self):
        log = turn_logs.Log()
        log.cycle(0, 7, "see https://evil.example.com/x?token=SECRET")
        log.turn("自绘")
        text = phone_report.render_turns(log.events())
        self.assertIn("evil.example.com", text)
        self.assertNotIn("http", text)
        self.assertNotIn("SECRET", text)

    def test_lost_sends_are_totalled(self):
        log = turn_logs.Log()
        log.turn("自绘", lost=3)
        log.turn("自绘", to_landscape=False, lost=2)
        log.native(log.now, "container", 0, "counter", "cut", event="lost", lost=1)
        grouped = phone_report.group_turns(log.events())
        self.assertEqual(grouped["lost"], 6)
        self.assertEqual([turn["lost"] for turn in grouped["turns"]], [3, 2])
        self.assertIn("native sends to Dart lost: 6", phone_report.render_turns(log.events()))
        self.assertNotIn("lost", phone_report.render_turns([]))

    def test_the_sample_sessions_are_what_turn_logs_writes(self):
        self.assertEqual(phone_report.load(turn_logs.SAMPLE_15), turn_logs.sample_15().events())
        self.assertEqual(phone_report.load(turn_logs.SAMPLE_14), turn_logs.sample_14().events())

    def run_main(self, path):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(phone_report.main(["--turns", str(path)]), 0)
        return out.getvalue()

    def test_main_reads_a_15_session(self):
        text = self.run_main(turn_logs.SAMPLE_15)
        self.assertIn("== Turns: 8 (back 4, to L 4) ==", text)
        summary = text[text.index("== Per style =="):].splitlines()
        self.assertRegex(summary[2], r"^系统\s+–\s+2\s+2\s+–\s+0\s+20\s+–\s+–\s+–/–\s+20/20$")
        self.assertRegex(summary[3], r"^自绘\s+–\s+6\s+2\s+fallback ×1, late ×1, stale ×1, picture ×1, lost ×1\s+0\s+"
                                     r"20\s+11\s+20\s+20/500\s+40/520$")
        self.assertIn("presentation changes no turn followed: 1", text)
        self.assertIn("native sends to Dart lost: 2", text)
        self.assertNotIn("passed over", text)

    def test_main_reads_a_14_session(self):
        text = self.run_main(turn_logs.SAMPLE_14)
        self.assertIn("== Turns: 12 (back 6, to L 6) ==", text)
        summary = text[text.index("== Per style =="):].splitlines()
        self.assertRegex(summary[2], r"^系统\s+1/7\s+2\s+2\s")
        self.assertRegex(summary[5], r"^请求前关·淡出·立即\s+4/7\s+2\s+0\s+picture ×2\s")
        self.assertRegex(summary[3], r"^请求前关·直接切·立即\s+2/7\s+4\s+3\s+lost ×1\s+1\s",
                         "the two turns after the cycle was switched off share the page's label")
        self.assertIn("per-frame lines passed over: 23", text)

    def test_help_and_report_survive_a_cp1252_console(self):
        tool = pathlib.Path(phone_report.__file__)
        env = {**os.environ, "PYTHONIOENCODING": "cp1252"}
        for args in (["--help"], ["--turns", str(turn_logs.SAMPLE_15)]):
            done = subprocess.run([sys.executable, str(tool), *args], capture_output=True, env=env, timeout=60)
            self.assertEqual(done.returncode, 0, done.stderr.decode("utf-8", "replace"))
            self.assertIn("旋转动画" if args == ["--help"] else "自绘", done.stdout.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
