#!/usr/bin/env python3
"""What a phone session measured, from its log (logs/<date>/<session>.jsonl as tools/logserver.py writes it).

    python tools/phone_report.py logs/2026-10-18/0123456789abcdef.jsonl
    python tools/phone_report.py --latest
    python tools/phone_report.py --turns --latest

For each speed test run: results per variant and played quality with the differences from the first variant,
then per pass the engine's nodes (pieces won, first byte, speed, losses before the first byte, failures) and its
seek reads. Then memory warnings and the player's error log. A session without a speed test gets the same over
the whole session.

--turns grades the drawn turn (开发者 → 旋转动画) instead, from the lines docs/reference/turn-log.md describes: a
row per turn, what each turn did in detail, then each style's results, best first.

Standard library only; anything that looks like a URL is cut down to its host.
"""
from __future__ import annotations

import argparse
import bisect
import datetime as dt
import json
import math
import pathlib
import re
import sys
import textwrap
import unicodedata
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
URL = re.compile(r'https?://([^/\s?#]+)[^\s,)"]*')
# Smaller pieces are mostly first byte; their speed says little about the node.
SPEED_MIN_BYTES = 60 * 1024
QUALITY_NAMES = {127: "8K", 126: "杜比", 125: "HDR", 120: "4K", 116: "1080P60", 112: "1080P+", 80: "1080P",
                 74: "720P60", 64: "720P", 32: "480P", 16: "360P"}


def clean(value) -> str:
    return URL.sub(lambda match: match.group(1), str(value))


def load(path) -> list[dict]:
    events = []
    for line in pathlib.Path(path).read_text(encoding="utf-8", errors="replace").split("\n"):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            events.append(event)
    if all(isinstance(event.get("seq"), int) for event in events):
        events.sort(key=lambda event: event["seq"])
    return events


def latest_log(logs: pathlib.Path) -> pathlib.Path | None:
    files = list(logs.rglob("*.jsonl")) if logs.is_dir() else []
    return max(files, key=lambda path: path.stat().st_mtime) if files else None


def fields(event) -> dict:
    found = event.get("f")
    return found if isinstance(found, dict) else {}


def number(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return float(value)


def median(values) -> float | None:
    values = sorted(values)
    if not values:
        return None
    middle = len(values) // 2
    return values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2


def p90(values) -> float | None:
    values = sorted(values)
    return values[math.ceil(len(values) * 0.9) - 1] if values else None


def seconds(ms) -> str:
    return "–" if ms is None else f"{ms / 1000:.2f}"


def millis(ms) -> str:
    return "–" if ms is None else f"{ms:.0f}"


def signed_seconds(ms) -> str:
    return "–" if ms is None else f"{'-' if ms < 0 else '+'}{abs(ms) / 1000:.2f}"


def signed(count) -> str:
    return f"{'-' if count < 0 else '+'}{abs(count)}"


def quality_name(qn) -> str:
    return f"{QUALITY_NAMES.get(qn, '')}({qn})" if qn in QUALITY_NAMES else str(qn)


def clock(t) -> str:
    try:
        return dt.datetime.fromtimestamp(float(t)).strftime("%H:%M:%S")
    except (TypeError, ValueError, OverflowError, OSError):
        return "--:--:--"


def runs(events) -> list[dict]:
    """Each speed test run: its start fields, its passes (marker, steps, done, engine events) and whether it ended."""
    found = []
    run = None
    current = None
    for event in events:
        msg = event.get("msg")
        f = fields(event)
        if msg == "speedtest start":
            run = {"start": f, "passes": [], "done": None}
            found.append(run)
            current = None
        elif run is None and msg == "speedtest pass":
            # Logging turned on mid-run: the buffer that held the start has already been dropped.
            run = {"start": {}, "passes": [], "done": None}
            found.append(run)
            current = {"marker": f, "steps": [], "done": None, "events": []}
            run["passes"].append(current)
        elif run is None:
            continue
        elif msg == "speedtest pass":
            current = {"marker": f, "steps": [], "done": None, "events": []}
            run["passes"].append(current)
        elif msg == "speedtest step" and current is not None:
            current["steps"].append(f)
        elif msg == "speedtest pass done" and current is not None:
            current["done"] = f
            current = None
        elif msg == "speedtest done":
            run["done"] = f
            run = None
            current = None
        elif current is not None:
            current["events"].append(event)
    return found


def counted(passes) -> list[dict]:
    return [p for p in passes if p["done"] and not p["done"].get("skipped") and not p["done"].get("failed")]


def step_ms(passes, kind) -> list[float]:
    return [ms for p in passes for step in p["steps"] if step.get("kind") == kind
            for ms in [number(step.get("ms"))] if ms is not None]


def phase(p) -> str | None:
    """"cold" for the first pass on a video at its quality (the CDN has not cached that file), "warm" after it; None
    in logs from before builds marked it."""
    cold = p["marker"].get("cold")
    return None if cold is None else ("cold" if cold else "warm")


def groups(run) -> list[dict]:
    """Counted passes pooled per variant, played quality and phase; variants in the order they first ran, cold first."""
    order = []
    pooled = defaultdict(list)
    for p in counted(run["passes"]):
        variant = str(p["done"].get("variant", p["marker"].get("variant", "?")))
        quality = p["done"].get("quality")
        if variant not in order:
            order.append(variant)
        pooled[(variant, quality, phase(p))].append(p)
    keys = sorted(pooled, key=lambda key: (order.index(key[0]), -(key[1] or 0), key[2] != "cold"))
    result = []
    for variant, quality, when in keys:
        passes = pooled[(variant, quality, when)]
        taps = step_ms(passes, "tap")

        def total(name):
            return int(sum(number(p["done"].get(name)) or 0 for p in passes))

        result.append({
            "variant": variant,
            "quality": quality,
            "phase": when,
            "passes": len(passes),
            "first": median([ms for p in passes for ms in [number(p["done"].get("firstFrameMs"))] if ms is not None]),
            "tapMedian": median(taps),
            "tapP90": p90(taps),
            "tapMax": max(taps) if taps else None,
            "hint": median(step_ms(passes, "hint")),
            "back": median(step_ms(passes, "back")),
            "stalls": total("stalls"),
            "fastStalls": total("fastStalls"),
            "timeouts": total("timeouts"),
            "memoryWarnings": total("memoryWarnings"),
            "rssMB": int(max((number(p["done"].get("rssMaxMB")) or 0 for p in passes), default=0)),
        })
    return result


def deltas(found_groups) -> list[dict]:
    """Every later variant minus the first one, at the same quality and phase."""
    if not found_groups:
        return []
    first = found_groups[0]["variant"]
    bases = {(g["quality"], g["phase"]): g for g in found_groups if g["variant"] == first}
    result = []
    for g in found_groups:
        base = bases.get((g["quality"], g["phase"]))
        if g["variant"] == first or base is None:
            continue
        result.append({"variant": g["variant"], "base": first, "quality": g["quality"], "phase": g["phase"],
                       **{key: None if g[key] is None or base[key] is None else g[key] - base[key]
                          for key in ("first", "tapMedian", "tapP90", "tapMax", "hint", "back")},
                       **{key: g[key] - base[key] for key in ("stalls", "fastStalls", "timeouts", "rssMB")}})
    return result


def node_table(events) -> dict[str, dict]:
    nodes = defaultdict(lambda: {"won": 0, "firstByte": [], "mbps": [], "emptyLosses": 0, "emptyWait": [],
                                 "failed": 0})
    for event in events:
        msg = event.get("msg")
        if msg not in ("piece", "attempt cancelled", "attempt failed"):
            continue
        f = fields(event)
        node = nodes[clean(f.get("node", "?"))]
        size = number(f.get("bytes")) or 0
        ms = number(f.get("ms"))
        if msg == "piece":
            node["won"] += 1
            first = number(f.get("firstByteMs"))
            if first is not None:
                node["firstByte"].append(first)
            if size >= SPEED_MIN_BYTES and ms is not None and first is not None and ms > first:
                node["mbps"].append(size * 8 / 1000 / (ms - first))
        elif msg == "attempt cancelled":
            if size == 0:
                node["emptyLosses"] += 1
                if ms is not None:
                    node["emptyWait"].append(ms)
        else:
            node["failed"] += 1
    return dict(nodes)


def seek_reads(events) -> dict[str, dict]:
    tracks = defaultdict(lambda: {"firstByte": [], "ms": []})
    for event in events:
        if event.get("msg") != "seek read":
            continue
        f = fields(event)
        track = tracks[clean(f.get("track", "?"))]
        for key, name in (("firstByte", "firstByteMs"), ("ms", "ms")):
            value = number(f.get(name))
            if value is not None:
                track[key].append(value)
    return dict(tracks)


def memory_warnings(events) -> list[tuple[str, float | None]]:
    return [(clock(event.get("t")), number(fields(event).get("rssMB")))
            for event in events if str(event.get("msg", "")).startswith("memory warning")]


def error_logs(events) -> Counter:
    return Counter(clean(fields(event).get("status", "?")) for event in events
                   if event.get("cat") == "player" and event.get("msg") == "error log")


def player_values(events, msg) -> list[float]:
    return [ms for event in events if event.get("msg") == msg and event.get("cat") == "player"
            for ms in [number(fields(event).get("ms"))] if ms is not None]


def width(text: str) -> int:
    """Columns on a terminal: Chinese characters take two."""
    return sum(2 if unicodedata.east_asian_width(char) in "WF" else 1 for char in text)


def table(rows: list[list[str]]) -> list[str]:
    widths = [max(width(row[column]) for row in rows) for column in range(len(rows[0]))]
    return ["  ".join(cell + " " * (size - width(cell)) for cell, size in zip(row, widths)).rstrip() for row in rows]


def render_nodes(events, indent="  ") -> list[str]:
    nodes = node_table(events)
    lines = []
    if nodes:
        rows = [["node", "won", "first byte ms", "Mbps", "lost empty", "wait ms", "failed"]]
        for name, node in sorted(nodes.items(), key=lambda item: (-item[1]["won"], item[0])):
            mbps = median(node["mbps"])
            rows.append([name, str(node["won"]), millis(median(node["firstByte"])),
                         "–" if mbps is None else f"{mbps:.1f}", str(node["emptyLosses"]),
                         millis(median(node["emptyWait"])), str(node["failed"])])
        lines += [indent + line for line in table(rows)]
    reads = seek_reads(events)
    for track, read in sorted(reads.items()):
        lines.append(f"{indent}seek reads {track}: first byte {millis(median(read['firstByte']))} ms, "
                     f"whole read {millis(median(read['ms']))} ms (n={len(read['ms'])})")
    return lines or [indent + "(no engine events: dev builds forward them when 发送日志到电脑 is on)"]


def label(g) -> str:
    return f"{g['variant']} {quality_name(g['quality'])}{' ' + g['phase'] if g['phase'] else ''}"


def render_run(index, run) -> list[str]:
    start = run["start"]
    source = clean(start.get("source", "?"))
    note = clean(start.get("planNote", ""))
    if start:
        lines = [f"== Speed test {index}: plan {clean(start.get('plan', '?'))} ({source}{': ' + note if note and source != 'pc' else ''}), "
                 f"{start.get('passes', '?')} passes, {start.get('videos', '?')} video(s) =="]
    else:
        lines = [f"== Speed test {index}: from pass {run['passes'][0]['marker'].get('pass', '?')} (its start is not in "
                 "the log: 发送日志到电脑 was turned on mid-run) =="]
    found = groups(run)
    if found:
        rows = [["", "passes", "first", "tap med/p90/max", "hint", "back", "stalls", "fast", "timeouts", "rssMB",
                 "memW"]]
        for g in found:
            rows.append([label(g), str(g["passes"]), seconds(g["first"]),
                         "/".join(seconds(g[key]) for key in ("tapMedian", "tapP90", "tapMax")),
                         seconds(g["hint"]), seconds(g["back"]), str(g["stalls"]), str(g["fastStalls"]),
                         str(g["timeouts"]), str(g["rssMB"]), str(g["memoryWarnings"])])
        lines += table(rows)
        lines.append("(seconds; medians over every pass of the group; a timed-out seek counts as its 15 s; cold is "
                     "each video's first pass, before the CDN has the file)")
    else:
        lines.append("no pass finished")
    differences = deltas(found)
    if differences:
        lines.append(f"differences from {differences[0]['base']} (negative is faster, fewer or smaller):")
        rows = [["", "first", "tap med/p90/max", "hint", "back", "stalls", "fast", "timeouts", "rssMB"]]
        for d in differences:
            rows.append([f"{d['variant']}-{d['base']} {quality_name(d['quality'])}{' ' + d['phase'] if d['phase'] else ''}",
                         signed_seconds(d["first"]),
                         "/".join(signed_seconds(d[key]) for key in ("tapMedian", "tapP90", "tapMax")),
                         signed_seconds(d["hint"]), signed_seconds(d["back"]), signed(d["stalls"]),
                         signed(d["fastStalls"]), signed(d["timeouts"]), signed(d["rssMB"])])
        lines += table(rows)
    for p in run["passes"]:
        done = p["done"] or {}
        marker = p["marker"]
        if done.get("skipped"):
            lines.append(f"skipped: pass {marker.get('pass')} ({clean(marker.get('variant'))}, asked "
                         f"{quality_name(done.get('askedQuality'))}, played {quality_name(done.get('quality'))})")
        elif done.get("failed"):
            lines.append(f"failed: pass {marker.get('pass')} ({clean(marker.get('variant'))}): "
                         f"{clean(done.get('failure', '?'))}")
        elif not p["done"]:
            lines.append(f"unfinished: pass {marker.get('pass')} ({clean(marker.get('variant'))})")
    if run["done"] is None:
        lines.append("(the run has no 'speedtest done': stopped by the app closing, or the log is cut short)")
    elif run["done"].get("cancelled"):
        lines.append("(stopped with 停止)")
    for p in run["passes"]:
        marker = p["marker"]
        done = p["done"] or {}
        played = done.get("quality", marker.get("quality"))
        lines.append("")
        when = phase(p)
        lines.append(f"-- pass {marker.get('pass')}: {clean(marker.get('variant'))} {quality_name(played)}"
                     f"{' ' + when if when else ''} "
                     f"{clean(done.get('codecs', ''))} {clean(marker.get('bvid', ''))} seed {marker.get('seed')} "
                     f"per host {marker.get('connectionsPerHost')} overrides {clean(marker.get('overrides', ''))} --")
        lines += render_nodes(p["events"])
    return lines


def render_general(events) -> list[str]:
    lines = ["== Session (no speed test) =="]
    firsts = player_values(events, "first frame")
    seeks = player_values(events, "seek resumed")
    lines.append(f"first frames: {len(firsts)}, median {seconds(median(firsts))} s, "
                 f"each {', '.join(seconds(ms) for ms in firsts) or '–'}")
    lines.append(f"seeks resumed: {len(seeks)}, median {seconds(median(seeks))} s, p90 {seconds(p90(seeks))} s, "
                 f"slowest {seconds(max(seeks) if seeks else None)} s")
    stalls = sum(1 for event in events if event.get("cat") == "player" and event.get("msg") == "stall")
    lines.append(f"stalls: {stalls}")
    lines += render_nodes(events)
    return lines


def render(events) -> str:
    found = runs(events)
    lines = []
    if found:
        for index, run in enumerate(found, 1):
            if lines:
                lines.append("")
            lines += render_run(index, run)
    else:
        lines += render_general(events)
    lines.append("")
    warnings = memory_warnings(events)
    lines.append(f"memory warnings: {len(warnings)}")
    lines += [f"  {at} rss {'?' if rss is None else int(rss)} MB" for at, rss in warnings]
    errors = error_logs(events)
    lines.append("player error log: " + (", ".join(f"{status} x{count}" for status, count in errors.most_common())
                                          or "none"))
    return clean("\n".join(lines)) + "\n"


# The drawn turn's lines (docs/reference/turn-log.md).

# A frame Flutter builds reaches the screen a vsync later.
TICK_US = 1_000_000 / 60
SWEEP_DEG = 90
SWEEP_SLACK_DEG = 6
GHOST_MAX_DEG = 3
GAP_MAX_MS = 50
FIRST_MOVE_MAX_MS = 120
MOVE_DEG = 1
# Steps back smaller than this are the layers' rounding, not a wobble anyone sees.
BACKSTEP_DEG = 0.5
# Below this the still picture no longer hides what is under it.
COVERING_OPACITY = 0.5
# How long before its native begin a turn's presentation change and rotation request can come.
LEAD_US = 3_000_000
# How long after a begin the Dart side's lines without a turn id still belong to it.
TRAIL_US = 1_500_000
DART_KINDS = ("presentation", "started", "sized", "began", "released", "drawn sent", "picture gone", "late", "frames")
DART_WITH_ID = ("started", "began", "released", "drawn sent", "picture gone")
UNDRAWN_STYLES = ("系统", "不转")
FAIL_KEYS = ("sweep", "back and forth", "ghost", "gap", "first move")


def parse_number(text) -> float | None:
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None


def wrap180(angle: float) -> float:
    return (angle + 180) % 360 - 180


def wall_us(event) -> float | None:
    us = number(fields(event).get("wUs"))
    if us is not None:
        return us
    t = number(event.get("t"))
    return None if t is None else t * 1_000_000


def turn_id(f) -> int | None:
    value = number(f.get("turn"))
    return None if value is None else int(value)


def turn_lines(events) -> tuple[list[dict], int]:
    """The turn log's lines in wall-clock order, each {us, side (native, dart or cycle), kind, f}; and how many
    turn lines had no time at all."""
    lines = []
    undated = 0
    for order, event in enumerate(events):
        msg = event.get("msg")
        if not isinstance(msg, str) or not msg.startswith("turn "):
            continue
        rest = msg[len("turn "):]
        if rest.startswith("native "):
            side, kind = "native", rest[len("native "):]
        elif rest in ("cycle", "cycle done"):
            side, kind = "cycle", rest
        elif rest in DART_KINDS:
            side, kind = "dart", rest
        else:
            continue
        us = wall_us(event)
        if us is None:
            undated += 1
            continue
        lines.append({"us": us, "side": side, "kind": kind, "f": fields(event), "order": order})
    lines.sort(key=lambda line: (line["us"], line["order"]))
    return lines, undated


def native_ticks(frames: list[dict]) -> tuple[list[dict], int]:
    """The display-link samples of a turn's native `frames` lines, and how many samples could not be read."""
    ticks = []
    bad = 0
    for f in frames:
        samples = f.get("samples")
        if not isinstance(samples, str):
            bad += 1
            continue
        for sample in samples.split(";"):
            if not sample.strip():
                continue
            parts = sample.split(",")
            if len(parts) < 8:
                bad += 1
                continue
            parts += [""] * (10 - len(parts))
            t, gap, scene, window = (parse_number(part) for part in parts[:4])
            container = parse_number(parts[6]) if parts[6].strip() else 0.0
            root = parse_number(parts[7])
            picture = parse_number(parts[8]) if parts[8].strip() else None
            opacity = parse_number(parts[9]) if parts[9].strip() else None
            if None in (t, scene, window, root, container) or (parts[8].strip() and picture is None):
                bad += 1
                continue
            ticks.append({"t": t, "gap": gap, "scene": scene, "window": window, "container": container, "root": root,
                          "picture": picture, "opacity": opacity})
    ticks.sort(key=lambda tick: tick["t"])
    return ticks, bad


def dart_frames(f) -> dict:
    """A Dart `frames` line: its samples as (wall µs, drawn angle), its span and its worst frames."""
    t0 = number(f.get("t0Us"))
    samples = []
    bad = 0
    raw = f.get("samples")
    for sample in raw.split(";") if isinstance(raw, str) else []:
        if not sample.strip():
            continue
        parts = sample.split(",")
        t = parse_number(parts[0])
        angle = parse_number(parts[1]) if len(parts) > 1 else None
        if t is None or angle is None or t0 is None:
            bad += 1
            continue
        samples.append((t0 + t * 1000, angle))
    samples.sort()
    timings = []
    raw = f.get("timings")
    for timing in raw.split(";") if isinstance(raw, str) else []:
        parts = [parse_number(part) for part in timing.split(",")]
        if len(parts) >= 3 and None not in parts[:3]:
            timings.append(parts[:3])
    build = number(f.get("worstBuildMs"))
    raster = number(f.get("worstRasterMs"))
    slow = number(f.get("slow"))
    return {
        "t0": t0,
        "samples": samples,
        "bad": bad,
        "span": (samples[0][0], samples[-1][0]) if samples else None,
        "build": build if build is not None else max((timing[0] for timing in timings), default=None),
        "raster": raster if raster is not None else max((timing[1] for timing in timings), default=None),
        "slow": int(slow) if slow is not None else
        (sum(1 for timing in timings if timing[2] > TICK_US / 1000) if timings else None),
    }


def new_turn(ident, us, anchor) -> dict:
    return {"id": ident, "us": us, "anchor": anchor, "begin": None, "native": defaultdict(list),
            "dart": defaultdict(list), "request": None, "returned": None, "presentation": None, "cycle": None,
            "dartFrames": [], "end": None}


def group_turns(events) -> dict:
    """Every turn with its native and Dart lines: by turn id where a line has one, by time where it doesn't."""
    lines, undated = turn_lines(events)
    turns = []
    for line in lines:
        if line["side"] == "native" and line["kind"] == "begin":
            turn = new_turn(turn_id(line["f"]), line["us"], "native begin")
            turn["begin"] = line["f"]
            turns.append(turn)

    def by_id(ident, us, slack):
        found = [turn for turn in turns if turn["id"] == ident and turn["us"] <= us + slack]
        return max(found, key=lambda turn: turn["us"]) if found else None

    unplaced = Counter()
    for line in lines:
        side, kind, f = line["side"], line["kind"], line["f"]
        if side == "native" and kind not in ("begin", "request", "request returned"):
            ident = turn_id(f)
            turn = by_id(ident, line["us"], 100_000)
            if turn is None and ident and kind != "container":
                # A turn whose begin never reached the log.
                turn = new_turn(ident, line["us"], f"native {kind}")
                turns.append(turn)
            if turn is None:
                unplaced[f"native {kind}"] += 1
            else:
                turn["native"][kind].append({**f, "us": line["us"]})
        elif side == "dart" and kind in DART_WITH_ID:
            ident = turn_id(f)
            turn = by_id(ident, line["us"], 500_000)
            if turn is None and ident is not None:
                turn = new_turn(ident, line["us"], f"Dart {kind}")
                turns.append(turn)
            if turn is None:
                unplaced[f"Dart {kind}"] += 1
            else:
                turn["dart"][kind].append({**f, "us": line["us"]})
    turns.sort(key=lambda turn: turn["us"])
    for turn, after in zip(turns, turns[1:] + [None]):
        turn["end"] = None if after is None else after["us"]

    def next_turn(us):
        for turn in turns:
            if turn["us"] >= us:
                return turn if turn["us"] - us <= LEAD_US else None
        return None

    def last_turn(us):
        found = [turn for turn in turns if turn["us"] <= us + 50_000]
        return found[-1] if found and us - found[-1]["us"] <= TRAIL_US else None

    orphans = []
    requests_without = 0
    cycles = []
    all_frames = []
    for line in lines:
        side, kind, f, us = line["side"], line["kind"], line["f"], line["us"]
        if side == "cycle":
            cycles.append((us, kind, f))
        elif side == "native" and kind == "request":
            turn = next_turn(us)
            if turn is None:
                requests_without += 1
            else:
                if turn["request"] is not None:
                    requests_without += 1
                turn["request"] = {**f, "us": us}
        elif side == "native" and kind == "request returned":
            asked = [t for t in turns if t["request"] is not None and t["request"]["us"] <= us
                     and number(t["request"].get("request")) == number(f.get("request"))]
            turn = asked[-1] if asked else next_turn(us)
            if turn is not None:
                turn["returned"] = {**f, "us": us}
        elif side == "dart" and kind == "presentation":
            turn = next_turn(us)
            if turn is None:
                orphans.append({"us": us, "f": f, "late": []})
            else:
                if turn["presentation"] is not None:
                    orphans.append({"us": turn["presentation"]["us"], "f": turn["presentation"], "late": []})
                turn["presentation"] = {**f, "us": us}
        elif side == "dart" and kind == "late":
            waiting = [orphan for orphan in orphans if orphan["us"] <= us]
            turn = last_turn(us)
            if f.get("missed") is True and waiting:
                waiting[-1]["late"].append(f)
            elif turn is not None:
                turn["dart"]["late"].append({**f, "us": us})
            elif waiting:
                waiting[-1]["late"].append(f)
            else:
                unplaced["Dart late"] += 1
        elif side == "dart" and kind == "sized":
            turn = last_turn(us)
            if turn is None:
                unplaced["Dart sized"] += 1
            else:
                turn["dart"]["sized"].append({**f, "us": us})
        elif side == "dart" and kind == "frames":
            frames = dart_frames(f)
            all_frames.append(frames)
            span = frames["span"] or ((frames["t0"],) * 2 if frames["t0"] is not None else None)
            placed = False
            for turn in turns:
                window_end = turn["end"] if turn["end"] is not None else turn["us"] + TRAIL_US
                if span is not None and span[0] <= window_end and span[1] >= turn["us"]:
                    turn["dartFrames"].append(frames)
                    placed = True
            if not placed:
                unplaced["Dart frames"] += 1

    for turn in turns:
        marks = [mark for mark in cycles if mark[0] <= turn["us"]]
        if marks and marks[-1][1] == "cycle":
            turn["cycle"] = marks[-1][2]
    # Pooled across turns: a frame drawn before this turn's first one is what the page still shows.
    pool = sorted(sample for frames in all_frames for sample in frames["samples"])
    return {"turns": turns, "orphans": orphans, "requestsWithout": requests_without, "undated": undated,
            "unplaced": unplaced, "pool": ([us for us, _ in pool], [angle for _, angle in pool]),
            "dartBad": sum(frames["bad"] for frames in all_frames)}


def style_of(turn) -> tuple[str, str | None]:
    """The turn's style: the 轮换测试 label it ran under, else the page's; and the page's when the two disagree."""
    page = (turn["presentation"] or {}).get("style")
    page = None if page is None else str(page)
    label = (turn["cycle"] or {}).get("label")
    if label is not None:
        label = str(label)
        return label, page if page is not None and page != label else None
    if page is not None:
        return page, None
    for f in [turn["begin"]] + [f for lines in turn["native"].values() for f in lines]:
        if f and f.get("method") is not None:
            return f"{f.get('method')}/{f.get('picture', '?')}", None
    return "?", None


def direction_of(turn) -> str:
    presentation = turn["presentation"] or {}
    source, target = presentation.get("from"), presentation.get("to")
    if target == "landscape":
        return "to L"
    if source == "landscape":
        return "back"
    if source is not None or target is not None:
        return f"{source}→{target}"
    begin = turn["begin"] or {}
    for w, h in [(begin.get("toW"), begin.get("toH"))] + [(f.get("w"), f.get("h")) for f in turn["dart"]["sized"]]:
        w, h = number(w), number(h)
        if w is not None and h is not None:
            return "to L" if w > h else "back"
    return "?"


def unwrap(angles: list[float]) -> list[float]:
    """Angles made continuous, so a step across ±180° counts as the short way round."""
    result = []
    for angle in angles:
        result.append(angle if not result else result[-1] + wrap180(angle - result[-1]))
    return result


def analyse_turn(turn, pool) -> dict:
    """What was on screen at each display-link tick, and the turn's grades from it.

    What is seen is the still picture while it covers the screen (opacity at least a half), the content otherwise:
    `scene + window + container + root` plus the angle of the latest Dart frame built a tick or more before. Until the
    turn's first frame is on screen that is the page's last frame from before, upright (0) when there is none."""
    walls, angles = pool
    ticks, malformed = native_ticks(turn["native"]["frames"])
    anchor = turn["us"]
    cut = None
    if turn["end"] is not None:
        kept = [tick for tick in ticks if anchor + tick["t"] * 1000 < turn["end"]]
        if len(kept) < len(ticks):
            cut = (turn["end"] - anchor) / 1000
        ticks = kept
    style, _ = style_of(turn)
    window_end = anchor + (ticks[-1]["t"] * 1000 if ticks else TRAIL_US)
    dart_samples = bisect.bisect_right(walls, window_end) - bisect.bisect_left(walls, anchor)
    has_native = turn["begin"] is not None or any(turn["native"].values())
    has_dart = any(turn["dart"].values()) or bool(turn["dartFrames"]) or turn["presentation"] is not None
    method = (turn["begin"] or {}).get("method")
    spins = bool(turn["dart"]["began"]) or (not has_dart and style not in UNDRAWN_STYLES
                                             and method not in (None, "noSpin"))
    a = {"ticks": len(ticks), "malformed": malformed, "cut": cut, "dartSamples": dart_samples, "spins": spins,
         "fails": [], "unknown": [], "gap": None, "ghost": None, "pictureUntil": None, "pictureAtEnd": False,
         "start": None, "sweep": None, "monotonic": None, "step": None, "moved": None, "settled": None,
         "overshoot": None, "ios": None, "iosPeak": None}

    previous = None
    gaps = []
    for tick in ticks:
        gap = tick["gap"] if tick["gap"] is not None else (None if previous is None else tick["t"] - previous)
        if gap is not None:
            gaps.append(gap)
        previous = tick["t"]
    a["gap"] = max(gaps, default=None)

    samples = []
    for tick in ticks:
        index = bisect.bisect_right(walls, anchor + tick["t"] * 1000 - TICK_US) - 1
        drawn = angles[index] if index >= 0 else 0.0
        turned = tick["scene"] + tick["window"]
        content = turned + tick["container"] + tick["root"] + drawn
        opacity = 1.0 if tick["opacity"] is None else tick["opacity"]
        picture = None if tick["picture"] is None or opacity <= 0.01 else turned + tick["picture"]
        samples.append({"t": tick["t"], "turned": turned, "content": content, "picture": picture, "opacity": opacity,
                        "seen": picture if picture is not None and opacity >= COVERING_OPACITY else content})

    ghosts = []
    for index, sample in enumerate(samples):
        if sample["picture"] is None:
            continue
        a["pictureUntil"] = sample["t"]
        leaving = index + 1 < len(samples) and samples[index + 1]["picture"] is None
        if sample["opacity"] < 0.99 or leaving:
            ghosts.append((abs(wrap180(sample["picture"] - sample["content"])), sample["t"]))
    a["ghost"] = max(ghosts, default=None)
    a["pictureAtEnd"] = bool(samples) and samples[-1]["picture"] is not None

    if len(samples) >= 2:
        seen = unwrap([sample["seen"] for sample in samples])
        norm = [angle - seen[-1] for angle in seen]
        steps = [after - before for before, after in zip(norm, norm[1:])]
        start = norm[0]
        a["start"] = start
        a["sweep"] = sum(abs(step) for step in steps)
        a["step"] = max(abs(step) for step in steps)
        if abs(start) >= MOVE_DEG:
            toward = -1 if start > 0 else 1
            a["monotonic"] = all(step * toward >= -BACKSTEP_DEG for step in steps)
            a["overshoot"] = max(0.0, max(-angle if start > 0 else angle for angle in norm))
        else:
            a["monotonic"] = a["sweep"] < MOVE_DEG
            a["overshoot"] = 0.0
        a["moved"] = next((sample["t"] for sample, angle in zip(samples, norm) if abs(angle - start) > MOVE_DEG), None)
        settle = len(norm) - 1
        while settle > 0 and abs(norm[settle - 1]) <= MOVE_DEG:
            settle -= 1
        a["settled"] = samples[settle]["t"]
        ios = unwrap([sample["turned"] for sample in samples])
        a["ios"] = ios[-1] - ios[0]
        a["iosPeak"] = max(ios) - min(ios)

    if not has_native:
        a["unknown"].append("no native lines")
    elif len(samples) < 2:
        a["unknown"].append("no native frames" if not turn["native"]["frames"] else "native frames unreadable")
    if spins and dart_samples == 0:
        a["unknown"].append("no Dart frames, so the page's spin is left out")
    if not a["unknown"]:
        if abs(a["sweep"] - SWEEP_DEG) > SWEEP_SLACK_DEG:
            a["fails"].append(("sweep", f"sweep {a['sweep']:.0f}°"))
        if not a["monotonic"]:
            a["fails"].append(("back and forth", "back and forth"))
        if a["ghost"] is not None and a["ghost"][0] >= GHOST_MAX_DEG:
            a["fails"].append(("ghost", f"ghost {a['ghost'][0]:.1f}°"))
        if a["gap"] is not None and a["gap"] >= GAP_MAX_MS:
            a["fails"].append(("gap", f"gap {a['gap']:.0f} ms"))
        if a["moved"] is None:
            a["fails"].append(("first move", "never moves"))
        elif a["moved"] >= FIRST_MOVE_MAX_MS:
            a["fails"].append(("first move", f"first move {a['moved']:.0f} ms"))
    a["verdict"] = "?" if a["unknown"] else ("bad" if a["fails"] else "good")

    frames = turn["dartFrames"]
    a["build"] = max((fr["build"] for fr in frames if fr["build"] is not None), default=None)
    a["raster"] = max((fr["raster"] for fr in frames if fr["raster"] is not None), default=None)
    slow = [fr["slow"] for fr in frames if fr["slow"] is not None]
    a["slow"] = sum(slow) if slow else None
    a["dartFrames"] = sum(len(fr["samples"]) for fr in frames)
    request = turn["request"]
    a["requestToBegin"] = (anchor - request["us"]) / 1000 if request and turn["begin"] is not None else None
    return a


def fmt(value, spec="{:.0f}") -> str:
    return "–" if value is None else spec.format(value)


def verdict_text(a) -> str:
    if a["verdict"] == "?":
        return "?: " + "; ".join(a["unknown"])
    if a["verdict"] == "bad":
        return "bad: " + ", ".join(text for _, text in a["fails"])
    return "good"


def turn_times(turn) -> str:
    anchor = turn["us"]
    marks = []

    def mark(f, name, detail=""):
        if f is not None and f.get("us") is not None:
            marks.append((f["us"], f"{name} {(f['us'] - anchor) / 1000:+.0f}" + (f" ({detail})" if detail else "")))

    presentation = turn["presentation"]
    if presentation is not None:
        mark(presentation, "presentation", f"{presentation.get('from', '?')}→{presentation.get('to', '?')}"
             + (", waiting" if presentation.get("waiting") is True else ""))
    request = turn["request"]
    if request is not None:
        mark(request, "request", f"#{request.get('request', '?')} {request.get('mask', '?')}"
             + (", animations off" if request.get("animationsEnabled") is False else ""))
        if presentation is not None:
            marks.append((request["us"], f"presentation→request {(request['us'] - presentation['us']) / 1000:.0f}"))
    returned = turn["returned"]
    if returned is not None:
        mark(returned, "returned", f"{fmt(number(returned.get('ms')), '{:.1f}')} ms")
    begin = turn["begin"]
    if begin is not None:
        angle = number(begin.get("angle"))
        snapshot = number(begin.get("snapshotMs"))
        marks.append((anchor, "begin 0 (" + ", ".join(
            [f"{math.degrees(angle):+.0f}°" if angle is not None else "angle ?",
             f"{fmt(number(begin.get('seconds')), '{:.2f}')} s"]
            + ([f"snapshot {snapshot:.1f} ms"] if snapshot else [])
            + (["not animated"] if begin.get("animated") is False else [])) + ")"))
    for f in turn["native"]["alongside"]:
        mark(f, "alongside")
    for f in turn["native"]["completion"]:
        mark(f, "completion", "cancelled" if f.get("cancelled") is True else "")
    for f in turn["native"]["drawn"]:
        mark(f, "drawn", str(f.get("action", "")))
    for f in turn["native"]["picture gone"]:
        mark(f, "picture gone", str(f.get("why", "")))
    for f in turn["native"]["fallback"]:
        mark(f, "fallback")
    for f in turn["native"]["container"]:
        mark(f, "container", str(f.get("event", "")))
    for f in turn["dart"]["started"]:
        mark(f, "started", str(f.get("outcome", "")))
    for f in turn["dart"]["sized"]:
        mark(f, "sized", f"{fmt(number(f.get('w')))}×{fmt(number(f.get('h')))} {f.get('layout', '')}".strip())
    for f in turn["dart"]["began"]:
        spin = number(f.get("spinFrom"))
        mark(f, "began", (f"from {math.degrees(spin):+.0f}°" if spin is not None else "")
             + (", held" if f.get("held") is True else ""))
    for f in turn["dart"]["released"]:
        mark(f, "released", str(f.get("why", "")))
    for f in turn["dart"]["drawn sent"]:
        mark(f, "drawn sent")
    for f in turn["dart"]["picture gone"]:
        mark(f, "Dart picture gone")
    for f in turn["dart"]["late"]:
        mark(f, "late", "missed" if f.get("missed") is True else "")
    marks.sort(key=lambda item: item[0])
    origin = "the native begin" if begin is not None else turn["anchor"]
    return f"times (ms from {origin}): " + " · ".join(text for _, text in marks)


def animations_text(lines) -> str | None:
    parts = []
    for f in lines:
        found = f.get("found")
        layers = defaultdict(list)
        for entry in found.split(";") if isinstance(found, str) else []:
            if entry.strip():
                bits = entry.split("|")
                layers[bits[0] or "?"].append(bits[1] if len(bits) > 1 and bits[1] else "?")
        listed = ", ".join(f"{layer}×{len(keys)} [{', '.join(sorted(set(keys)))}]" for layer, keys in layers.items())
        parts.append(f"{f.get('phase', '?')} found {listed or 'none'}, removed {fmt(number(f.get('removed')))}")
    return "; ".join(parts) if parts else None


def angles_text(a) -> str:
    if a["start"] is None:
        return "angles: –"
    text = (f"angles: seen {a['start']:+.0f}° → 0, sweep {a['sweep']:.0f}°, "
            f"{'one way' if a['monotonic'] else 'back and forth'}, biggest step {a['step']:.1f}°, "
            f"first move {fmt(a['moved'])} ms, settled {fmt(a['settled'])} ms, "
            + (f"overshoot {a['overshoot']:.1f}°" if a["overshoot"] > MOVE_DEG else "no overshoot")
            + f"; iOS turned {a['ios']:+.0f}°" + (f" (peak {a['iosPeak']:.0f}°)" if a["iosPeak"] - abs(a["ios"]) > MOVE_DEG
                                                 else ""))
    if a["pictureUntil"] is None:
        text += "; no picture"
    else:
        text += f"; picture up to {a['pictureUntil']:.0f} ms"
        if a["ghost"] is not None:
            text += f", ghost {a['ghost'][0]:.1f}° at {a['ghost'][1]:.0f} ms"
        if a["pictureAtEnd"]:
            text += ", still up when the samples end"
    return text


def turn_detail(number_, turn, a) -> list[str]:
    style, page = style_of(turn)
    cycle = turn["cycle"]
    where = f" (轮换 {cycle.get('index', '?')}/{cycle.get('of', '?')})" if cycle else ""
    try:
        when = dt.datetime.fromtimestamp(turn["us"] / 1_000_000).strftime("%H:%M:%S.%f")[:-3]
    except (OverflowError, OSError, ValueError):
        when = "--:--:--.---"
    lines = [f"-- {number_} · turn {fmt(turn['id'])} · {style}{where} · {direction_of(turn)} · {when} --"]
    wrap = textwrap.TextWrapper(width=118, initial_indent="  ", subsequent_indent="    ", break_long_words=False)
    lines += wrap.wrap(turn_times(turn))
    animations = animations_text(turn["native"]["animations"])
    if animations:
        lines += wrap.wrap("animations: " + animations)
    lines += wrap.wrap(angles_text(a))
    lines += wrap.wrap(f"stalls: native longest gap {fmt(a['gap'])} ms over {a['ticks']} ticks; Dart worst build "
                       f"{fmt(a['build'], '{:.1f}')} ms, raster {fmt(a['raster'], '{:.1f}')} ms, {fmt(a['slow'])} "
                       f"slow over {a['dartFrames']} frames")
    notes = []
    if page is not None:
        notes.append(f"the page logged style {page}")
    if a["cut"] is not None:
        notes.append(f"the next turn began at {a['cut']:.0f} ms")
    if a["malformed"]:
        notes.append(f"{a['malformed']} native samples unreadable")
    if turn["native"]["fallback"]:
        notes.append("the 0.5 s fallback fired")
    if notes:
        lines += wrap.wrap("notes: " + "; ".join(notes))
    missing = [name for name, there in (
        ("native request", turn["request"] is not None),
        ("native begin", turn["begin"] is not None),
        ("native frames", bool(turn["native"]["frames"])),
        ("Dart presentation", turn["presentation"] is not None),
        ("Dart started", bool(turn["dart"]["started"])),
        ("Dart began", bool(turn["dart"]["began"]) or style in UNDRAWN_STYLES),
        ("Dart frames", a["dartSamples"] > 0 or bool(turn["dartFrames"])),
    ) if not there]
    if missing:
        lines += wrap.wrap("not in the log: " + ", ".join(missing))
    lines.append(f"  verdict: {verdict_text(a)}")
    return lines


def style_summary(analysed) -> list[dict]:
    """Per style, best first: the most good turns, then the smallest worst gap, then the quickest first move."""
    styles = {}
    for turn, a in analysed:
        style, _ = style_of(turn)
        entry = styles.setdefault(style, {"style": style, "cycle": turn["cycle"], "turns": []})
        entry["turns"].append(a)
    rows = []
    for entry in styles.values():
        graded = [a for a in entry["turns"] if a["verdict"] != "?"]
        good = sum(a["verdict"] == "good" for a in graded)
        rows.append({
            "style": entry["style"],
            "cycle": entry["cycle"],
            "turns": len(entry["turns"]),
            "good": good,
            "bad": len(graded) - good,
            "unknown": len(entry["turns"]) - len(graded),
            "sweep": median([a["sweep"] for a in graded if a["sweep"] is not None]),
            "ghost": median([a["ghost"][0] for a in graded if a["ghost"] is not None]),
            "move": median([a["moved"] for a in graded if a["moved"] is not None]),
            "gap": max((a["gap"] for a in graded if a["gap"] is not None), default=None),
            "request": max((a["requestToBegin"] for a in entry["turns"] if a["requestToBegin"] is not None),
                           default=None),
            "fails": Counter(key for a in graded for key, _ in a["fails"]),
            "graded": len(graded),
        })
    rows.sort(key=lambda row: (row["graded"] == 0, -row["good"] / row["graded"] if row["graded"] else 0,
                               math.inf if row["gap"] is None else row["gap"],
                               math.inf if row["move"] is None else row["move"]))
    return rows


def render_turns(events) -> str:
    grouped = group_turns(events)
    turns = grouped["turns"]
    lines = []
    if not turns:
        lines.append("no turns in this log (the 旋转动画 test build logs them while 发送日志到电脑 is on)")
    else:
        analysed = [(turn, analyse_turn(turn, grouped["pool"])) for turn in turns]
        directions = Counter(direction_of(turn) for turn in turns)
        lines.append(f"== Turns: {len(turns)} ("
                     + ", ".join(f"{name} {count}" for name, count in sorted(directions.items())) + ") ==")
        rows = [["#", "at", "turn", "style", "dir", "req→beg", "iOS", "start", "sweep", "1-way", "step", "move",
                 "settle", "over", "ghost", "gap", "Dart b/r/slow", "verdict"]]
        for index, (turn, a) in enumerate(analysed, 1):
            rows.append([
                str(index), clock(turn["us"] / 1_000_000), fmt(turn["id"]), style_of(turn)[0], direction_of(turn),
                fmt(a["requestToBegin"]), fmt(a["ios"], "{:+.0f}"), fmt(a["start"], "{:+.0f}"), fmt(a["sweep"]),
                "–" if a["monotonic"] is None else ("yes" if a["monotonic"] else "no"), fmt(a["step"], "{:.1f}"),
                fmt(a["moved"]), fmt(a["settled"]), fmt(a["overshoot"], "{:.1f}"),
                fmt(None if a["ghost"] is None else a["ghost"][0], "{:.1f}"), fmt(a["gap"]),
                f"{fmt(a['build'])}/{fmt(a['raster'])}/{fmt(a['slow'])}", verdict_text(a)])
        lines += table(rows)
        lines.append("(ms from the native begin; degrees on screen, positive clockwise, the final angle 0. iOS: what "
                     "the scene and window turned. start, sweep, 1-way, step, settle, over: what was seen, the still "
                     "picture while it covered, the content otherwise. ghost: picture against content as the picture "
                     "went. gap: the longest native frame)")
        for index, (turn, a) in enumerate(analysed, 1):
            lines.append("")
            lines += turn_detail(index, turn, a)
        lines.append("")
        lines.append("== Styles, best first ==")
        rows = [["rank", "style", "轮换", "turns", "good", "bad", "?", "sweep", "ghost", "move", "worst gap",
                 "req→beg max", "fails"]]
        for rank, row in enumerate(style_summary(analysed), 1):
            cycle = row["cycle"]
            rows.append([str(rank), row["style"], f"{cycle.get('index', '?')}/{cycle.get('of', '?')}" if cycle else "–",
                         str(row["turns"]), str(row["good"]), str(row["bad"]), str(row["unknown"]),
                         fmt(row["sweep"]), fmt(row["ghost"], "{:.1f}"), fmt(row["move"]), fmt(row["gap"]),
                         fmt(row["request"]),
                         ", ".join(f"{key} ×{row['fails'][key]}" for key in FAIL_KEYS if row["fails"][key]) or "–"])
        lines += table(rows)
        lines.append(f"(good: sweep {SWEEP_DEG}±{SWEEP_SLACK_DEG}°, one way, ghost under {GHOST_MAX_DEG}°, native gaps "
                     f"under {GAP_MAX_MS} ms, first move under {FIRST_MOVE_MAX_MS} ms. sweep, ghost and move are medians "
                     "of the graded turns)")
    extras = []
    for orphan in grouped["orphans"]:
        f = orphan["f"]
        late = orphan["late"]
        extras.append(f"  {clock(orphan['us'] / 1_000_000)} {f.get('style', '?')} {f.get('from', '?')}→"
                      f"{f.get('to', '?')}" + (" (late, missed)" if any(l.get("missed") is True for l in late)
                                               else " (late)" if late else ""))
    if extras:
        lines += ["", f"presentation changes no turn followed: {len(extras)}"] + extras
    if grouped["requestsWithout"]:
        lines.append(f"rotation requests no turn followed: {grouped['requestsWithout']}")
    if grouped["unplaced"]:
        lines.append("lines that fit no turn: " + ", ".join(
            f"{name} ×{count}" for name, count in sorted(grouped["unplaced"].items())))
    if grouped["undated"]:
        lines.append(f"turn lines without a time: {grouped['undated']}")
    if grouped["dartBad"]:
        lines.append(f"Dart frame samples unreadable: {grouped['dartBad']}")
    return clean("\n".join(lines)) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?", type=pathlib.Path, help="a session's .jsonl")
    parser.add_argument("--latest", action="store_true", help="the newest .jsonl under logs/")
    parser.add_argument("--turns", action="store_true", help="grade the drawn turns instead")
    args = parser.parse_args(argv)
    path = latest_log(ROOT / "logs") if args.latest else args.session
    if path is None:
        parser.error("give a session file, or --latest with logs under logs/")
    if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(f"{path.name}\n")
    events = load(path)
    sys.stdout.write(render_turns(events) if args.turns else render(events))
    return 0


if __name__ == "__main__":
    sys.exit(main())
