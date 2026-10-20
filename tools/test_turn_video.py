import argparse
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "testdata"))
import turn_logs  # noqa: E402
import turn_video  # noqa: E402

FRAME_S = 1 / 60


def frames(curve, *, before=4, after_s=0.6, start=0.0):
    """Samples at 60 fps: `before` frames at rest, then curve(t) for t from 0 (the turn's start) to after_s."""
    samples = [(start + (index - before) * FRAME_S, curve(-1.0)) for index in range(before)]
    index = 0
    while index * FRAME_S <= after_s:
        samples.append((start + index * FRAME_S, curve(index * FRAME_S)))
        index += 1
    return samples


def official_turn(rest=0.0, total=90.0, t0=-0.006):
    return lambda t: rest + turn_video.official(t, t0, total)


def slow_turn(rest=0.0, total=90.0, seconds=0.4):
    # Done in 400 ms, smoothstep: smooth, but not the official turn.
    def angle(t):
        x = min(max(t / seconds, 0.0), 1.0)
        return rest + total * x * x * (3 - 2 * x)
    return angle


class CurveTests(unittest.TestCase):
    def test_the_official_curve_is_ease_in_out(self):
        ease = turn_video.bezier_ease
        self.assertEqual((ease(-1), ease(0), ease(1), ease(2)), (0.0, 0.0, 1.0, 1.0))
        self.assertAlmostEqual(ease(0.5), 0.5, places=4)
        for x in (0.1, 0.2, 0.3, 0.4):
            self.assertAlmostEqual(ease(x) + ease(1 - x), 1.0, places=4, msg="symmetric")
        self.assertLess(ease(0.2), 0.1, "slow out of rest")
        values = [ease(step / 100) for step in range(101)]
        self.assertEqual(values, sorted(values))

    def test_the_fit_finds_the_start_and_scores_the_shape(self):
        points = [(t, turn_video.official(t, 0.0123, 90)) for t in (index * FRAME_S for index in range(1, 25))]
        t0, rms = turn_video.fit_official([(0.0, 0.0)] + points, 90, 0.0, FRAME_S, 0.3)
        self.assertAlmostEqual(t0, 0.0123, delta=0.0011)
        self.assertLess(rms, 0.3)
        slow = [(t, slow_turn()(t)) for t, _ in points]
        _, off = turn_video.fit_official([(0.0, 0.0)] + slow, 90, 0.0, FRAME_S, 0.4)
        self.assertGreater(off, turn_video.OFFICIAL_RMS_DEG)


class SegmentTests(unittest.TestCase):
    def test_moving_frames_are_runs_merged_across_short_holds(self):
        times = [index * FRAME_S for index in range(200)]
        diffs = [0.0] * 200
        for index in list(range(10, 28)) + [60] + list(range(78, 95)) + list(range(150, 160)):
            diffs[index] = 40.0
        diffs[120] = turn_video.MOVING_DIFF - 0.5
        self.assertEqual(turn_video.moving_runs(times, diffs), [(10, 27), (60, 94), (150, 159)],
                         "a cut held 0.3 s before the page turns is one turn; a small change is none")
        self.assertEqual(turn_video.moving_runs(times, diffs, merge=0.1), [(10, 27), (60, 60), (78, 94), (150, 159)])

    def test_the_rest_after_a_run_is_the_first_still_stretch(self):
        times = [index * FRAME_S for index in range(120)]
        diffs = [0.0] * 120
        diffs[30:40] = [30.0] * 10
        diffs[40:44] = [5.0, 1.0, 9.0, 3.0]
        self.assertEqual(turn_video.rest_after(times, diffs, 39), 44)
        playing = [0.0] * 30 + [30.0] * 10 + [6.0] * 80
        found = turn_video.rest_after(times, playing, 39)
        self.assertAlmostEqual(times[found] - times[39], turn_video.REST_SEARCH_S, delta=FRAME_S,
                               msg="a picture that never stands still: the end of the search")
        self.assertEqual(turn_video.rest_after(times[:42], playing[:42], 39), 41, "the recording ends first")

    def test_the_direction_comes_from_the_turn_and_the_size(self):
        direction = turn_video.turn_direction
        self.assertEqual(direction(89.0, 1.78), "to L")
        self.assertEqual(direction(-91.0, 1.78), "to L")
        self.assertEqual(direction(90.0, 0.56), "back")
        self.assertEqual(direction(-450.0 + 360, 0.56), "back")
        self.assertIsNone(direction(1.0, 1.0), "the controls came up")
        self.assertIsNone(direction(90.0, 1.0))
        self.assertIsNone(direction(45.0, 1.78))
        self.assertIsNone(direction(None, None))


class GradeTests(unittest.TestCase):
    def assertVerdict(self, samples, verdict, why=None):
        g = turn_video.grade(samples)
        self.assertEqual((g["verdict"], g["why"]), (verdict, why), g)
        return g

    def test_the_official_turn_either_way(self):
        for rest, total in ((0.0, 90.0), (90.0, -90.0), (-90.0, 90.0)):
            g = self.assertVerdict(frames(official_turn(rest, total)), "official-like")
            self.assertAlmostEqual(g["total"], total, delta=0.5)
            self.assertLess(abs(g["jump"]), turn_video.SMOOTH_JUMP_DEG)
            self.assertAlmostEqual(abs(g["jump"]) + g["sweep"], 90, delta=1)
            self.assertTrue(g["monotonic"])
            self.assertLess(g["rms"], 1)
            self.assertAlmostEqual(g["settle"], 250, delta=40)

    def test_a_slower_smooth_turn_is_system_like(self):
        for rest, total in ((0.0, 90.0), (90.0, -90.0)):
            g = self.assertVerdict(frames(slow_turn(rest, total)), "system-like")
            self.assertGreater(g["rms"], turn_video.OFFICIAL_RMS_DEG)
            self.assertAlmostEqual(g["sweep"] + abs(g["jump"]), 90, delta=1)

    def test_a_spin_jumps_the_wrong_way_then_sweeps_180(self):
        def angle(t):
            return 0.0 if t < 0 else -87 + 177 * turn_video.bezier_ease(t / 0.3)

        g = self.assertVerdict(frames(angle), "spin")
        self.assertAlmostEqual(g["jump"], -87, delta=0.5)
        self.assertAlmostEqual(g["sweep"], 177, delta=1)
        self.assertTrue(g["monotonic"])
        g = self.assertVerdict(frames(lambda t: 90.0 if t < 0 else 177 - 177 * turn_video.bezier_ease(t / 0.3)),
                               "spin")
        self.assertAlmostEqual(g["total"], -90, delta=0.5)

    def test_a_cut_jumps_and_stays(self):
        g = self.assertVerdict(frames(lambda t: 0.0 if t < 0 else 90.0), "cut")
        self.assertEqual((g["jump"], g["sweep"], g["settle"]), (90.0, 0.0, 0.0))
        self.assertVerdict(frames(lambda t: 90.0 if t < 0 else 0.0), "cut")

    def test_a_jump_whose_frames_before_were_out_of_sight_is_not_called(self):
        samples = frames(lambda t: 0.0 if t < 0.1 else 90.0)
        hidden = [(t, None if 0 <= t < 0.1 else angle) for t, angle in samples]
        self.assertVerdict(hidden, "?", "6 frames unmatched before it moved")

    def test_a_smooth_turn_with_unmatched_frames_is_not_official(self):
        samples = frames(official_turn())
        gappy = [(t, None if 0.1 < t < 0.17 else angle) for t, angle in samples]
        self.assertVerdict(gappy, "?", "fits the official turn, but 4 frames unmatched while it moved")
        slow = [(t, None if 0.1 < t < 0.17 else angle) for t, angle in frames(slow_turn())]
        self.assertVerdict(slow, "system-like")

    def test_what_cannot_be_graded_says_why(self):
        self.assertVerdict([(0.0, None)] + frames(official_turn())[1:], "?", "the rest before is unmatched")
        self.assertVerdict([(0.0, 0.0), (0.1, None)], "?", "too few frames matched")
        self.assertVerdict(frames(lambda t: 0.5), "?", "never moves")
        self.assertVerdict(frames(lambda t: 0.0 if t < 0 else 45.0 * min(t / 0.2, 1)), "?",
                           "ends +45° from where it started")
        wobble = frames(lambda t: 0.0 if t < 0 else 90 * min(t / 0.25, 1) + (20 if 0.1 < t < 0.15 else 0))
        self.assertVerdict(wobble, "?", "back and forth")
        self.assertVerdict(frames(lambda t: 0.0 if t < 0 else 45 + 45 * min(t / 0.2, 1)), "?",
                           "jumps 45° then sweeps 45°")

    def test_angles_are_continuous_across_180(self):
        # A turn back that spins: +90 to about +180, then down to 0, with the measurement wrapping at ±180.
        def angle(t):
            raw = 90.0 if t < 0 else 178 - 178 * turn_video.bezier_ease(t / 0.3)
            return raw if raw <= 180 else raw - 360

        samples = [(t, (a + 180) % 360 - 180) for t, a in frames(angle)]
        g = self.assertVerdict(samples, "spin")
        self.assertAlmostEqual(g["sweep"], 178, delta=1)


class AlignTests(unittest.TestCase):
    def setUp(self):
        self.offset = 1_760_000_000.7
        jitter = [0.01, -0.02, 0.0, 0.016, -0.008, 0.02]
        self.video = [(2.0 + 3.1 * index, "to L" if index % 2 == 0 else "back") for index in range(6)]
        # The log holds one more turn before the recording and two after, and nothing of what the recording missed.
        self.log = ([(self.offset - 5.0, "back")]
                    + [(t + self.offset + 0.03 + jitter[index], d) for index, (t, d) in enumerate(self.video)]
                    + [(self.offset + 40.0, "to L"), (self.offset + 41.0, "back")])

    def test_the_offset_lines_up_every_turn(self):
        for guess in (self.offset - 0.7, None):
            offset, matches = turn_video.align(self.video, self.log, guess)
            self.assertAlmostEqual(offset, self.offset + 0.03, delta=0.01)
            self.assertEqual(matches, {index: index + 1 for index in range(6)})

    def test_directions_must_agree(self):
        flipped = [(t, "back" if d == "to L" else "to L") for t, d in self.log]
        offset, matches = turn_video.align(self.video, flipped, self.offset)
        self.assertNotEqual(len(matches), 6)
        self.assertEqual(turn_video.align(self.video, [], None), (None, {}))

    def test_the_guess_keeps_far_offsets_out(self):
        # The same pattern 100 s later lines up as well; the creation time picks the right one.
        twice = self.log + [(t + 100.0, d) for t, d in self.log]
        offset, _ = turn_video.align(self.video, twice, self.offset + 100.5)
        self.assertAlmostEqual(offset, self.offset + 100.03, delta=0.01)

    def read(self, log):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "session.jsonl"
            log.write(path)
            return turn_video.log_turns(path)

    def test_log_turns_read_the_phone_log_through_phone_report(self):
        log = turn_logs.Log()
        log.cycle(1, 7, "系统")
        log.turn("系统", build=14, method="system")
        log.cycle(2, 7, "请求前关·直接切·立即")
        log.turn("请求前关·直接切·立即", build=14, to_landscape=False)
        log.dart(log.now, "presentation", **{"from": "inline", "to": "landscape"}, wide=False, waiting=True,
                 style="请求前关·直接切·立即")
        log.now += 400_000
        log.turn("请求前关·直接切·立即", build=14, to_landscape=False)
        found = self.read(log)
        self.assertEqual([(entry["id"], entry["dir"], entry["style"], entry["native"]) for entry in found],
                         [(1, "to L", "系统", "system/none"), (2, "back", "请求前关·直接切·立即", "quietRequest/cut"),
                          (3, "back", "请求前关·直接切·立即", "quietRequest/cut")],
                         "the direction is what the window did, not a presentation change that never turned")
        self.assertAlmostEqual(found[1]["s"] - found[0]["s"], 3.5, delta=0.001)

    def test_without_a_cycle_turns_take_the_pages_style(self):
        # 1.0.0 (15): no 轮换测试; a turn back's presentation change comes just after its native begin.
        log = turn_logs.Log()
        log.turn("系统", method="system")
        log.turn("系统", method="system", to_landscape=False)
        log.turn("自绘", picture=None)
        log.turn("自绘", picture=None, to_landscape=False)
        log.turn("自绘", dart=False)
        log.turn("系统", to_landscape=False)  # the host still drew it
        found = self.read(log)
        self.assertEqual([(entry["dir"], entry["style"], entry["native"]) for entry in found],
                         [("to L", "系统", "system/none"), ("back", "系统", "system/none"),
                          ("to L", "自绘", "quietRequest"), ("back", "自绘", "quietRequest"),
                          ("to L", "自绘", "quietRequest/cut"), ("back", "系统", "quietRequest/cut")])


def measured(samples):
    return [(t, angle, None if angle is None else 1.0, None if angle is None else 50, "player") for t, angle in samples]


class RenderTests(unittest.TestCase):
    def turns(self):
        made = []
        for start, direction, curve in ((1.0, "to L", official_turn()), (4.0, "back", slow_turn(90, -90)),
                                        (7.0, "to L", lambda t: 0.0 if t < 0 else 90.0)):
            samples = [(start + t, angle) for t, angle in frames(curve)]
            made.append({"start": start, "dir": direction, "frames": measured(samples),
                         "grade": turn_video.grade(samples)})
        return made

    def test_the_report_labels_turns_from_the_log_and_sums_up_each_style(self):
        turns = self.turns()
        logged = [{"s": 1000.0 + t, "dir": d, "id": n, "style": style, "cycle": None, "native": native}
                  for n, (t, d, style, native) in enumerate(
                      ((1.0, "to L", "请求前关·直接切·立即", "quietRequest/cut"), (4.0, "back", "系统", "system/none"),
                       (7.0, "to L", "请求前关·直接切·立即", "quietRequest/cut"),
                       (8.5, "back", "请求前关·直接切·立即", "quietRequest/cut")), 1)]
        alignment = turn_video.label(turns, logged, 999.4, (0.0, 9.0))
        self.assertEqual([turn["id"] for turn in turns], [1, 2, 3])
        self.assertIn("+0.600 s from its creation time", alignment["text"])
        self.assertIn("3 of 3 turns matched a native begin", alignment["text"])
        self.assertIn("weren't found in it: 4", alignment["text"])
        text = turn_video.render(turns, alignment, 2)
        self.assertRegex(text, r"\n1\s+1\.00\s+to L\s+1\s+请求前关·直接切·立即\s+quietRequest/cut\s+.*official-like\n")
        self.assertRegex(text, r"\n2\s+4\.00\s+back\s+2\s+系统\s+system/none\s+.*system-like\n")
        self.assertRegex(text, r"\n3\s+7\.00\s+to L\s+3\s+.*\s+\+90\s+0\s+yes\s+0\s+.*cut\n")
        summary = text.split("== Per style ==")[1].splitlines()
        self.assertRegex(summary[2], r"^请求前关·直接切·立即\s+2\s+official-like ×1, cut ×1\s")
        self.assertRegex(summary[3], r"^系统\s+1\s+system-like ×1\s")
        self.assertIn("changes that weren't turns: 2", text)
        self.assertIn("  3: -67:+0 -50:+0 -33:+0 -17:+0 +0:+90 +17:+90 +33:+90 +50:+90\n", text,
                      "the strip stops after the settle")
        every = turn_video.render(turns, None, 0, frames=True)
        self.assertIn("     +0 ms    +90.0°  ×1.00  50 inliers\n", every)
        self.assertNotIn("log:", every)

    def test_unlabelled_and_empty_recordings(self):
        text = turn_video.render(self.turns(), None, 0)
        self.assertRegex(text.split("== Per style ==")[1].splitlines()[2], r"^\?\s+3\s+official-like ×1")
        self.assertEqual(turn_video.render([], None, 0), "no turns found in the recording\n")
        empty = turn_video.label([], [{"s": 5.0, "dir": "to L", "id": 1, "style": "系统", "cycle": None,
                                       "native": "system/none"}], None)
        self.assertEqual(empty["text"], "log: no native begin lines up with the recording")


class CommandLineTests(unittest.TestCase):
    def test_crop_rows(self):
        self.assertEqual(turn_video.parse_crop("70:300"), (70, 300))
        for bad in ("300:70", "x:1", "70"):
            with self.assertRaises(argparse.ArgumentTypeError):
                turn_video.parse_crop(bad)

    def test_help_survives_a_cp1252_console(self):
        tool = pathlib.Path(turn_video.__file__)
        done = subprocess.run([sys.executable, str(tool), "--help"], capture_output=True, timeout=60,
                              env={**os.environ, "PYTHONIOENCODING": "cp1252"})
        self.assertEqual(done.returncode, 0, done.stderr.decode("utf-8", "replace"))
        self.assertIn("轮换测试", done.stdout.decode("utf-8"))

    def test_angles_wrap_the_short_way_round(self):
        self.assertEqual(turn_video.wrap180(270.0), -90.0)
        self.assertEqual(turn_video.unwrap([170.0, -170.0, -90.0]), [170.0, 190.0, 270.0])

    def test_the_pure_parts_load_without_opencv(self):
        # In a fresh interpreter: other tools' tests in the same run load numpy themselves.
        check = ("import sys; sys.path.insert(0, sys.argv[1]); import turn_video; "
                 "print(sorted({'cv2', 'numpy'} & set(sys.modules)))")
        loaded = subprocess.run([sys.executable, "-c", check, str(pathlib.Path(turn_video.__file__).parent)],
                                capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(loaded, "[]")


if __name__ == "__main__":
    unittest.main()
