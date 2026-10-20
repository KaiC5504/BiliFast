#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["opencv-python==5.0.0.93", "numpy==2.5.4"]
# ///
"""How the picture turned on screen in a screen recording of the phone, frame by frame.

    uv run tools/turn_video.py local/differences/09-ours-rotate-testing-v4.MP4
    uv run tools/turn_video.py VIDEO --log logs/<date>/<session>.jsonl
    uv run tools/turn_video.py VIDEO --frames --crop 70:300 --ffmpeg D:/Tools/ffmpeg/bin/ffmpeg

phone_report.py --turns can't see iOS's own rotation (it happens outside the app); the recording can. Every frame is
decoded at the recording's own rate, scaled to 440 wide, into a temporary folder that is deleted afterwards. A turn is
a run of frames that differ a lot from the one before whose two ends measure about 90° apart. Each frame's angle comes
from SIFT matches against the small player (--crop, rows at 440 wide) of the nearest still upright frame, else against
that whole frame, and estimateAffinePartial2D. iPhone recordings stay portrait-framed, so upright content is at 0° and
landscape at ±90°.

Each turn is graded on its sweep, whether it moves one way, its first frame's jump, the time to settle and the RMS
error against the official turn (90° along ease-in-out cubic(0.42, 0, 0.58, 1) over 300 ms). With --log, each turn
gets the native turn it ran as and its style (the 轮换测试 label of 1.0.0 (13) and (14), else the page's: 自绘 or 系统),
the video placed on the log's clock by the offset that best lines the detected turns up with the native begins. Needs
ffmpeg (and ffprobe beside it).
"""
from __future__ import annotations

import argparse
import bisect
import datetime as dt
import json
import math
import os
import pathlib
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

import phone_report

WIDTH = 440
# The small player on the iPhone 17 Pro Max, rows at 440 wide.
CROP = (70, 300)
# Frames are compared at a quarter of WIDTH: enough to see a turn, cheap for a whole recording.
THUMB = 4
# Mean absolute difference (0–255) from the frame before. A turn moves the whole screen; a playing video changes
# the small player, or a landscape picture, far less from one frame to the next.
MOVING_DIFF = 12.0
STILL_DIFF = 2.0
# Gaps inside one turn: a still picture held before the drawn turn starts (about 0.3 s in 1.0.0 (13)'s 抵消).
MERGE_S = 0.4
# Frames measured after a turn comes to rest, for its settle.
TAIL_S = 0.25
# How long a rest is looked for after a run of moving frames.
REST_SEARCH_S = 1.0
STILL_RUN = 3

OFFICIAL_S = 0.3
OFFICIAL_CURVE = (0.42, 0.0, 0.58, 1.0)
# How far before the first frame that moved the official turn can have started: eased out of rest, it is still under
# MOVE_DEG some 40 ms in.
FIT_LEAD_S = 0.1
# SIFT on a still frame wanders by about a degree.
MOVE_DEG = 3.0
SETTLE_DEG = 3.0
BACKSTEP_DEG = 2.0
TURN_DEG = 90.0
TURN_SLACK_DEG = 20.0
SPIN_SWEEP_DEG = 135.0
CUT_JUMP_DEG = 60.0
CUT_SWEEP_DEG = 20.0
SMOOTH_JUMP_DEG = 30.0
# Measured on KaiC's phone: iOS's own turn (系统) is within 0.5° of the official curve, the official app's turn back
# 1.2° and its turn to landscape (about 250 ms) 6° (local/differences/09 and 01).
OFFICIAL_RMS_DEG = 3.0
MIN_MEASURED = 3
# A landscape picture is the small player grown to the screen's height: about 1.8×.
LANDSCAPE_SCALE = 1.3
MIN_INLIERS = 10
# The whole screen matches some of its many features wrongly while it turns; the player's few are cleaner.
SCREEN_INLIERS = 20
# A fit outside this is a degenerate one (a handful of points on a line), not the picture.
SCALES = (0.25, 4.0)
RATIO = 0.7
# Native begins and the first frame that differs, after the offset: one frame or two apart.
MATCH_S = 0.15
COARSE_MATCH_S = 0.3
# The recording's creation time is a first guess at the offset, about a second off.
GUESS_WINDOW_S = 30.0
VERDICTS = ("official-like", "system-like", "spin", "cut", "?")
STRIP_AFTER_MS = 50


def wrap180(angle: float) -> float:
    return (angle + 180) % 360 - 180


def unwrap(angles: list[float]) -> list[float]:
    """Angles made continuous, so a step across ±180° counts as the short way round."""
    result = []
    for angle in angles:
        result.append(angle if not result else result[-1] + wrap180(angle - result[-1]))
    return result


def bezier_ease(x: float, curve=OFFICIAL_CURVE) -> float:
    """CSS's cubic-bezier timing function: the progress at time fraction x."""
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    x1, y1, x2, y2 = curve

    def at(s, p1, p2):
        return 3 * (1 - s) ** 2 * s * p1 + 3 * (1 - s) * s * s * p2 + s ** 3

    lo, hi = 0.0, 1.0
    for _ in range(40):
        middle = (lo + hi) / 2
        if at(middle, x1, x2) < x:
            lo = middle
        else:
            hi = middle
    return at((lo + hi) / 2, y1, y2)


def official(t: float, t0: float, total: float) -> float:
    return total * bezier_ease((t - t0) / OFFICIAL_S)


def fit_official(points: list[tuple[float, float]], total: float, earliest: float, latest: float,
                 settled: float) -> tuple[float, float]:
    """The official turn's start in [earliest, latest] (seconds) that fits `points` (t, angle from rest) best, and its
    RMS error. Only frames while either one moves count: frames at rest on both sides would water it down."""
    best = (earliest, math.inf)
    steps = max(1, round((latest - earliest) * 1000))
    for step in range(steps + 1):
        t0 = earliest + (latest - earliest) * step / steps
        until = max(settled, t0 + OFFICIAL_S)
        errors = [angle - official(t, t0, total) for t, angle in points
                  if t0 <= t <= until or (t < t0 and abs(angle) > MOVE_DEG)]
        if not errors:
            continue
        rms = math.sqrt(sum(error * error for error in errors) / len(errors))
        if rms < best[1]:
            best = (t0, rms)
    return best


def moving_runs(times: list[float], diffs: list[float], moving=MOVING_DIFF, merge=MERGE_S) -> list[tuple[int, int]]:
    """Runs of frames that differ a lot from the one before, as (first, last) indices; runs less than `merge` seconds
    apart are one."""
    runs = []
    for index, diff in enumerate(diffs):
        if diff < moving:
            continue
        if runs and times[index] - times[runs[-1][1]] <= merge:
            runs[-1][1] = index
        else:
            runs.append([index, index])
    return [(first, last) for first, last in runs]


def rest_after(times: list[float], diffs: list[float], last: int, still=STILL_DIFF, run=STILL_RUN,
               search=REST_SEARCH_S) -> int:
    """The first frame after `last` that starts STILL_RUN still frames; without one, the last frame within `search`
    (a playing landscape picture never stands still)."""
    end = len(diffs)
    for index in range(last + 1, end):
        if times[index] - times[last] > search:
            break
        if index + run <= end and all(diff < still for diff in diffs[index:index + run]):
            return index
    return max(last + 1, min(end - 1, bisect.bisect_right(times, times[last] + search) - 1))


def turn_direction(angle: float | None, scale: float | None) -> str | None:
    """From the frame after a change measured against the small player of the frame before it: "to L" when the
    picture turned a quarter and grew to the screen, "back" when it turned and shrank (the frame before was the
    landscape one), None when it didn't turn."""
    if angle is None or scale is None or abs(abs(wrap180(angle)) - TURN_DEG) > TURN_SLACK_DEG:
        return None
    if scale >= LANDSCAPE_SCALE:
        return "to L"
    if scale <= 1 / LANDSCAPE_SCALE:
        return "back"
    return None


def grade(samples: list[tuple[float, float | None]]) -> dict:
    """A turn from its frames, (t seconds, angle or None when unmatched): the first at rest before the turn, the last
    ones at rest after it. Angles are made continuous and counted from the first frame's."""
    g = {"frames": len(samples), "unmatched": sum(angle is None for _, angle in samples), "total": None,
         "jump": None, "sweep": None, "monotonic": None, "settle": None, "rms": None, "t0": None, "moved": None,
         "hidden": 0, "gaps": 0, "verdict": "?", "why": None}
    measured = [(t, angle) for t, angle in samples if angle is not None]
    if len(measured) < 2 or samples[0][1] is None:
        g["why"] = "the rest before is unmatched" if samples and samples[0][1] is None else "too few frames matched"
        return g
    angles = unwrap([angle for _, angle in measured])
    rel = [(t, angle - angles[0]) for (t, _), angle in zip(measured, angles)]
    end = statistics.median(angle for _, angle in rel[-3:])
    g["total"] = end
    moved = next((index for index, (_, angle) in enumerate(rel) if abs(angle) > MOVE_DEG), None)
    if moved is None:
        g["why"] = "never moves"
        return g
    g["moved"] = rel[moved][0]
    g["hidden"] = sum(1 for t, angle in samples if angle is None and rel[moved - 1][0] < t < rel[moved][0])
    g["jump"] = rel[moved][1]
    after = [angle for _, angle in rel[moved:]]
    steps = [b - a for a, b in zip(after, after[1:])]
    g["sweep"] = sum(abs(step) for step in steps)
    toward = end - after[0]
    g["monotonic"] = abs(toward) <= BACKSTEP_DEG or all(step * math.copysign(1, toward) >= -BACKSTEP_DEG
                                                         for step in steps)
    settled = len(rel) - 1
    while settled > moved and abs(rel[settled - 1][1] - end) <= SETTLE_DEG:
        settled -= 1
    g["settle"] = (rel[settled][0] - rel[moved][0]) * 1000
    g["gaps"] = sum(1 for t, angle in samples if angle is None and rel[moved - 1][0] < t < rel[settled][0])
    earliest = max(rel[0][0], rel[moved][0] - FIT_LEAD_S)
    t0, rms = fit_official([point for point in rel if point[0] >= earliest], end, earliest, rel[moved][0],
                           rel[settled][0])
    g["t0"], g["rms"] = t0, rms
    g["verdict"], g["why"] = verdict(g)
    return g


def verdict(g) -> tuple[str, str | None]:
    if abs(abs(g["total"]) - TURN_DEG) > TURN_SLACK_DEG:
        return "?", f"ends {g['total']:+.0f}° from where it started"
    jump, sweep = abs(g["jump"]), g["sweep"]
    if g["frames"] - g["unmatched"] < MIN_MEASURED:
        return "?", "too few frames matched"
    if sweep >= SPIN_SWEEP_DEG:
        return "spin", None
    if g["hidden"] and jump >= SMOOTH_JUMP_DEG:
        # Whatever moved the picture there was out of sight: a spin can look like a jump.
        return "?", f"{g['hidden']} frames unmatched before it moved"
    if jump >= CUT_JUMP_DEG and sweep <= CUT_SWEEP_DEG:
        return "cut", None
    if jump < SMOOTH_JUMP_DEG and abs(jump + sweep - TURN_DEG) <= TURN_SLACK_DEG and g["monotonic"]:
        if g["rms"] > OFFICIAL_RMS_DEG:
            return "system-like", None
        if g["gaps"]:
            return "?", f"fits the official turn, but {g['gaps']} frames unmatched while it moved"
        return "official-like", None
    if not g["monotonic"]:
        return "?", "back and forth"
    return "?", f"jumps {jump:.0f}° then sweeps {sweep:.0f}°"


def align(starts: list[tuple[float, str]], begins: list[tuple[float, str]], guess: float | None = None
          ) -> tuple[float | None, dict[int, int]]:
    """The offset (log seconds = video seconds + offset) that lines the most detected turn starts up with native
    begins of the same direction, and which begin each start got. Only offsets within GUESS_WINDOW_S of `guess` are
    tried when any is; ties go to the smaller residuals."""
    candidates = sorted({b - s for s, sd in starts for b, bd in begins if sd == bd})
    near = [offset for offset in candidates if guess is not None and abs(offset - guess) <= GUESS_WINDOW_S]
    best, best_key = None, None
    for offset in near or candidates:
        matches = match(starts, begins, offset, COARSE_MATCH_S)
        residuals = sum(abs(begins[j][0] - starts[i][0] - offset) for i, j in matches.items())
        key = (-len(matches), residuals)
        if best_key is None or key < best_key:
            best, best_key = offset, key
    if best is None:
        return None, {}
    matches = match(starts, begins, best, COARSE_MATCH_S)
    if matches:
        best += statistics.median(begins[j][0] - starts[i][0] - best for i, j in matches.items())
    return best, match(starts, begins, best, MATCH_S)


def match(starts, begins, offset: float, tolerance: float) -> dict[int, int]:
    """Each start's nearest unused begin of its direction within `tolerance`, closest pairs first."""
    pairs = sorted((abs(b - s - offset), i, j) for i, (s, sd) in enumerate(starts) for j, (b, bd) in enumerate(begins)
                   if sd == bd and abs(b - s - offset) <= tolerance)
    found, used = {}, set()
    for _, i, j in pairs:
        if i not in found and j not in used:
            found[i] = j
            used.add(j)
    return found


def log_turns(path) -> list[dict]:
    """The native begins of a phone log as phone_report reads them: wall seconds, direction, id, style, method."""
    grouped = phone_report.group_turns(phone_report.load(path))
    found = []
    for turn in grouped["turns"]:
        if turn["begin"] is None:
            continue
        begin = turn["begin"]
        found.append({"s": turn["us"] / 1_000_000, "dir": phone_report.direction_of(turn), "id": turn["id"],
                      "style": phone_report.style_of(turn)[0], "cycle": turn["cycle"],
                      "native": str(begin.get("method", "?"))
                      + ("" if begin.get("picture") is None else f"/{begin.get('picture')}")})
    return found


def summary(turns: list[dict]) -> list[dict]:
    """Per style, in the order first seen: its verdicts and the medians of what was measured."""
    styles = {}
    for turn in turns:
        styles.setdefault(turn.get("style") or "?", []).append(turn["grade"])
    rows = []
    for style, grades in styles.items():
        def mid(key, absolute=False):
            values = [abs(g[key]) if absolute else g[key] for g in grades if g[key] is not None]
            return statistics.median(values) if values else None

        rows.append({"style": style, "turns": len(grades), "verdicts": Counter(g["verdict"] for g in grades),
                     "jump": mid("jump", True), "sweep": mid("sweep"), "settle": mid("settle"), "rms": mid("rms")})
    return rows


fmt = phone_report.fmt


def verdict_cell(g) -> str:
    return g["verdict"] + (f": {g['why']}" if g["why"] else "")


def render(turns: list[dict], alignment: dict | None, skipped: int, frames: bool = False) -> str:
    lines = []
    if alignment is not None:
        lines.append(alignment["text"])
    if not turns:
        lines.append("no turns found in the recording")
        return phone_report.clean("\n".join(lines)) + "\n"
    rows = [["#", "video s", "dir", "turn", "style", "native", "frames", "?", "jump", "sweep", "1-way", "settle", "rms",
             "verdict"]]
    for index, turn in enumerate(turns, 1):
        g = turn["grade"]
        rows.append([str(index), f"{turn['start']:.2f}", turn["dir"], fmt(turn.get("id")), turn.get("style") or "–",
                     turn.get("native") or "–", str(g["frames"]), str(g["unmatched"]), fmt(g["jump"], "{:+.0f}"),
                     fmt(g["sweep"]), "–" if g["monotonic"] is None else ("yes" if g["monotonic"] else "no"),
                     fmt(g["settle"]), fmt(g["rms"], "{:.1f}"), verdict_cell(g)])
    lines.append(f"== Turns in the recording: {len(turns)} ==")
    lines += phone_report.table(rows)
    lines.append("(degrees on screen, positive clockwise, counted from the rest before the turn. jump: the first "
                 "frame that moved; sweep: from there to the end; settle: ms from the first frame that moved to within "
                 f"{SETTLE_DEG:.0f}° of the end; rms: against the official {OFFICIAL_S * 1000:.0f} ms ease-in-out "
                 f"started at most {FIT_LEAD_S * 1000:.0f} ms before the first frame that moved, over the frames "
                 "where either moves. ?: frames left unmatched)")
    for index, turn in enumerate(turns, 1):
        g = turn["grade"]
        origin = g["moved"] if g["moved"] is not None else turn["frames"][0][0]
        if frames:
            lines.append(f"-- {index} · {turn['dir']} · {turn.get('style') or '?'} --")
            lines += [f"  {(t - origin) * 1000:+7.0f} ms  " + ("?" if angle is None else
                                                               f"{angle:+7.1f}°  ×{scale:.2f}  {inliers} inliers"
                                                               + ("" if source == "player" else f"  ({source})"))
                      for t, angle, scale, inliers, source in turn["frames"]]
        else:
            until = origin + ((g["settle"] or 0) + STRIP_AFTER_MS) / 1000
            strip = " ".join(f"{(t - origin) * 1000:+.0f}:" + ("?" if angle is None else f"{angle:+.0f}")
                             for t, angle, *_ in turn["frames"] if t <= until)
            lines.append(f"  {index}: {strip}")
    lines.append("(per turn, ms from the first frame that moved: the angle against the upright player, up to "
                 f"{STRIP_AFTER_MS} ms after it settled; --frames for every frame)")
    lines.append("")
    lines.append("== Per style ==")
    rows = [["style", "turns", "verdicts", "jump", "sweep", "settle", "rms"]]
    for row in summary(turns):
        rows.append([row["style"], str(row["turns"]),
                     ", ".join(f"{name} ×{row['verdicts'][name]}" for name in VERDICTS if row["verdicts"][name]),
                     fmt(row["jump"]), fmt(row["sweep"]), fmt(row["settle"]), fmt(row["rms"], "{:.1f}")])
    lines += phone_report.table(rows)
    lines.append(f"(medians. official-like: a smooth {TURN_DEG:.0f}° within {OFFICIAL_RMS_DEG:.0f}° RMS of the official "
                 f"turn; system-like: smooth but off it; spin: a sweep of {SPIN_SWEEP_DEG:.0f}° or more; cut: a jump "
                 f"of {CUT_JUMP_DEG:.0f}° or more with no motion after)")
    if skipped:
        lines.append(f"changes that weren't turns: {skipped}")
    return phone_report.clean("\n".join(lines)) + "\n"


def label(turns: list[dict], logged: list[dict], guess: float | None,
          span: tuple[float, float] | None = None) -> dict:
    """Gives each turn its log entry (id, style, native) and describes the alignment. `span`: the recording's first
    and last frame times, for the log's turns it should have shown."""
    starts = [(turn["start"], turn["dir"]) for turn in turns]
    begins = [(entry["s"], entry["dir"]) for entry in logged]
    offset, matches = align(starts, begins, guess)
    for i, j in matches.items():
        entry = logged[j]
        turns[i].update(id=entry["id"], style=entry["style"], native=entry["native"])
    if offset is None:
        return {"offset": None, "text": "log: no native begin lines up with the recording"}
    residuals = [(logged[j]["s"] - turns[i]["start"] - offset) * 1000 for i, j in matches.items()]
    first, last = span or (turns[0]["start"] - 1, turns[-1]["start"] + 1)
    missed = [entry["id"] for j, entry in enumerate(logged) if j not in matches.values()
              and first + offset <= entry["s"] <= last + offset]
    try:
        zero = dt.datetime.fromtimestamp(offset).strftime("%H:%M:%S.%f")[:-3]
    except (OverflowError, OSError, ValueError):
        zero = f"{offset:.3f} s"
    text = (f"log: the recording's 0 s is {zero} on the phone's clock"
            + (f" ({offset - guess:+.3f} s from its creation time)" if guess is not None else "")
            + f"; {len(matches)} of {len(turns)} turns matched a native begin"
            + (f", within {max(abs(r) for r in residuals):.0f} ms" if residuals else ""))
    if missed:
        text += f"\nlog turns inside the recording that weren't found in it: {', '.join(map(str, missed))}"
    return {"offset": offset, "matches": matches, "text": text}


# Decoding and measuring: opencv and numpy are imported here only, so the pure parts above load without them.

def find_ffmpeg(given: str | None) -> str:
    for candidate in ([given] if given else []) + [shutil.which("ffmpeg"), "D:/Tools/ffmpeg/bin/ffmpeg"]:
        if candidate and (shutil.which(candidate) or pathlib.Path(candidate).is_file()):
            return shutil.which(candidate) or candidate
    raise SystemExit("ffmpeg not found: put it on PATH or pass --ffmpeg")


def probe(video: pathlib.Path, ffmpeg: str) -> tuple[int, int, float | None]:
    """The recording's displayed size and its creation time (epoch seconds) if it has one."""
    ffprobe = pathlib.Path(ffmpeg).with_name("ffprobe" + pathlib.Path(ffmpeg).suffix)
    command = [str(ffprobe) if ffprobe.is_file() else (shutil.which("ffprobe") or "ffprobe"), "-v", "error",
               "-select_streams", "v:0", "-show_entries",
               "stream=width,height:stream_side_data=rotation:format_tags=creation_time", "-of", "json", str(video)]
    info = json.loads(subprocess.run(command, capture_output=True, text=True, check=True).stdout)
    stream = info["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    rotation = next((side.get("rotation") for side in stream.get("side_data_list", []) if "rotation" in side), 0)
    if abs(int(rotation or 0)) % 180 == 90:
        width, height = height, width
    created = info.get("format", {}).get("tags", {}).get("creation_time")
    try:
        created_s = dt.datetime.fromisoformat(created.replace("Z", "+00:00")).timestamp() if created else None
    except ValueError:
        created_s = None
    return width, height, created_s


SHOWINFO = re.compile(r"\bn:\s*(\d+)\s+pts:\s*-?\d+\s+pts_time:(-?[\d.]+)")


def decode(video: pathlib.Path, ffmpeg: str, folder: pathlib.Path) -> tuple[list[float], list[float], int, int]:
    """Every frame at the recording's own rate into `folder` as 440-wide grey PNGs (%06d.png from 1), and each frame's
    time and difference from the one before."""
    import numpy as np

    width, height, _ = probe(video, ffmpeg)
    height = round(height * WIDTH / width)
    small_w, small_h = WIDTH // THUMB, round(height / THUMB)
    graph = (f"[0:v]scale={WIDTH}:{height}:flags=area,format=gray,showinfo,split[full][small];"
             f"[small]scale={small_w}:{small_h}:flags=area[thumb]")
    command = [ffmpeg, "-hide_banner", "-nostats", "-loglevel", "info", "-i", str(video), "-filter_complex", graph,
               "-map", "[full]", "-fps_mode", "passthrough", str(folder / "%06d.png"),
               "-map", "[thumb]", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"]
    diffs = []
    size = small_w * small_h
    with open(folder / "ffmpeg.log", "wb") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=log)
        previous = None
        while True:
            chunk = process.stdout.read(size)
            if len(chunk) < size:
                break
            frame = np.frombuffer(chunk, np.uint8).astype(np.int16)
            diffs.append(0.0 if previous is None else float(np.abs(frame - previous).mean()))
            previous = frame
        process.stdout.close()
        if process.wait() != 0:
            raise SystemExit(f"ffmpeg failed; its log: {(folder / 'ffmpeg.log').read_text(errors='replace')[-2000:]}")
    times = {int(n): float(t) for n, t in SHOWINFO.findall((folder / "ffmpeg.log").read_text(errors="replace"))}
    if not diffs:
        raise SystemExit(f"ffmpeg decoded no frames from {video.name}")
    if len(times) != len(diffs) or sorted(times) != list(range(len(diffs))):
        raise SystemExit(f"ffmpeg gave {len(diffs)} frames but {len(times)} times")
    return [times[n] for n in range(len(diffs))], diffs, WIDTH, height


class Frames:
    """The decoded frames, their SIFT features kept once computed."""

    def __init__(self, folder: pathlib.Path, crop: tuple[int, int]):
        import cv2

        self.cv2 = cv2
        self.folder = folder
        self.crop = crop
        self.local = threading.local()
        self.features = {}

    def detect(self, image):
        if not hasattr(self.local, "sift"):
            self.local.sift = self.cv2.SIFT_create(nfeatures=3000)
        return self.local.sift.detectAndCompute(image, None)

    def image(self, index: int):
        return self.cv2.imread(str(self.folder / f"{index + 1:06d}.png"), self.cv2.IMREAD_GRAYSCALE)

    def feature(self, index: int):
        if index not in self.features:
            self.features[index] = self.detect(self.image(index))
        return self.features[index]

    def prepare(self, indices):
        missing = [index for index in indices if index not in self.features]
        with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            for index, found in zip(missing, pool.map(lambda i: self.detect(self.image(i)), missing)):
                self.features[index] = found

    def reference(self, index: int):
        top, bottom = self.crop
        return self.detect(self.image(index)[top:bottom, :])

    def measure(self, reference, index: int, least: int = MIN_INLIERS) -> tuple[float, float, int] | None:
        """The frame's angle (degrees, clockwise), scale and inliers against the reference."""
        import numpy as np

        cv2 = self.cv2
        ref_points, ref_desc = reference
        points, desc = self.feature(index)
        if ref_desc is None or desc is None or len(points) < 8 or len(ref_points) < 8:
            return None
        pairs = cv2.BFMatcher().knnMatch(ref_desc, desc, k=2)
        good = [m for m, n in (pair for pair in pairs if len(pair) == 2) if m.distance < RATIO * n.distance]
        if len(good) < 8:
            return None
        source = np.float32([ref_points[m.queryIdx].pt for m in good])
        target = np.float32([points[m.trainIdx].pt for m in good])
        matrix, inliers = cv2.estimateAffinePartial2D(source, target, method=cv2.RANSAC, ransacReprojThreshold=4.0)
        if matrix is None or inliers is None or int(inliers.sum()) < least:
            return None
        scale = math.hypot(matrix[0, 0], matrix[1, 0])
        if not SCALES[0] <= scale <= SCALES[1]:
            return None
        return math.degrees(math.atan2(matrix[1, 0], matrix[0, 0])), scale, int(inliers.sum())


def find_turns(times: list[float], diffs: list[float], frames: Frames) -> tuple[list[dict], int]:
    """Every turn in the recording with its frames measured and graded, and how many changes weren't turns."""
    turns = []
    skipped = 0
    for first, last in moving_runs(times, diffs):
        before = max(0, first - 1)
        after = rest_after(times, diffs, last)
        frames.prepare([before, after])
        forward = frames.measure(frames.reference(before), after)
        direction = turn_direction(*(forward[:2] if forward else (None, None)))
        if direction is None and forward is None:
            backward = frames.measure(frames.reference(after), before)
            if backward is not None:
                direction = turn_direction(-backward[0], 1 / backward[1])
        if direction is None:
            skipped += 1
            continue
        upright = before if direction == "to L" else after
        end = bisect.bisect_right(times, times[after] + TAIL_S)
        indices = list(range(before, min(end, len(times))))
        frames.prepare(indices)
        player, screen = frames.reference(upright), frames.feature(upright)
        measured = []
        for index in indices:
            # Some turns move the page without its player for a while: then the whole upright screen.
            found, source = frames.measure(player, index), "player"
            if found is None:
                found, source = frames.measure(screen, index, SCREEN_INLIERS), "screen"
            measured.append((times[index],) + (found + (source,) if found else (None, None, None, None)))
        turns.append({"start": times[first], "dir": direction, "frames": measured,
                      "grade": grade([(t, angle) for t, angle, *_ in measured])})
    return turns, skipped


def parse_crop(text: str) -> tuple[int, int]:
    top, _, bottom = text.partition(":")
    try:
        crop = int(top), int(bottom)
    except ValueError:
        raise argparse.ArgumentTypeError("rows as TOP:BOTTOM, e.g. 70:300") from None
    if not 0 <= crop[0] < crop[1]:
        raise argparse.ArgumentTypeError("TOP must be below BOTTOM")
    return crop


def main(argv=None) -> int:
    phone_report.utf8_console()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("video", type=pathlib.Path, help="the screen recording")
    parser.add_argument("--log", type=pathlib.Path, help="the session's .jsonl, to label turns with styles")
    parser.add_argument("--ffmpeg", help="ffmpeg's path (default: on PATH, else D:/Tools/ffmpeg/bin/ffmpeg)")
    parser.add_argument("--crop", type=parse_crop, default=CROP,
                        help=f"the small player's rows at {WIDTH} wide (default {CROP[0]}:{CROP[1]})")
    parser.add_argument("--frames", action="store_true", help="every measured frame with its scale and inliers")
    args = parser.parse_args(argv)
    ffmpeg = find_ffmpeg(args.ffmpeg)
    with tempfile.TemporaryDirectory(prefix="turn_video_") as folder:
        times, diffs, _, _ = decode(args.video, ffmpeg, pathlib.Path(folder))
        turns, skipped = find_turns(times, diffs, Frames(pathlib.Path(folder), args.crop))
    alignment = None
    if args.log:
        _, _, created = probe(args.video, ffmpeg)
        guess = None if created is None else created - times[0]
        alignment = label(turns, log_turns(args.log), guess, (times[0], times[-1]))
    print(f"{args.video.name}: {len(times)} frames over {times[-1] - times[0]:.1f} s\n")
    sys.stdout.write(render(turns, alignment, skipped, args.frames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
