#!/usr/bin/env python3
"""What a phone session measured, from its log (logs/<date>/<session>.jsonl as tools/logserver.py writes it).

    python tools/phone_report.py logs/2026-10-18/0123456789abcdef.jsonl
    python tools/phone_report.py --latest
    python tools/phone_report.py --turns --latest

For each speed test run: results per variant and played quality with the differences from the first variant,
then per pass the engine's nodes (pieces won, first byte, speed, losses before the first byte, failures) and its
seek reads. Then memory warnings and the player's error log. A session without a speed test gets the same over
the whole session.

--turns reads the turns (开发者 → 旋转动画) instead, from the lines docs/reference/turn-log.md describes: a row per
turn with its timeline and failures, each turn's lines in detail, then each style's failures and timing medians.

Standard library only; anything that looks like a URL is cut down to its host.
"""
from __future__ import annotations

import argparse
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

# How long before its native begin a turn's rotation request and presentation change can come.
LEAD_US = 3_000_000
# The page logs a turn back's presentation change just after the native begin.
PRESENTATION_AFTER_US = 100_000
# How long after a begin the Dart side's lines without a turn id still belong to it.
TRAIL_US = 1_500_000
# A still picture up longer than this is seen as the screen freezing.
PICTURE_MAX_MS = 100
DART_KINDS = ("presentation", "started", "sized", "began", "released", "drawn sent", "picture gone", "late", "frames")
DART_WITH_ID = ("started", "began", "released", "drawn sent", "picture gone")
CYCLE_KINDS = ("cycle", "cycle done", "cycle off")
# Native kinds besides begin and the requests. 1.0.0 (13) and (14) also logged `frames` (and (13) `animations` and
# `container`): those lines are passed over, though their lost sends still count.
NATIVE_KINDS = ("alongside", "completion", "drawn", "picture gone", "fallback")
SYSTEM_STYLE = "系统"
FAIL_KEYS = ("fallback", "late", "stale", "unasked", "picture", "lost", "≠native")
# 旋转动画's labels (lib/device/turn_style.dart) as the native lines name them: 1.0.0 (15)'s 自绘 and 系统, and (14)'s
# 请求前关 with its picture. 1.0.0 (13)'s other methods are read without this check.
NATIVE_METHODS = {"系统": "system", "自绘": "quietRequest", "请求前关": "quietRequest"}
NATIVE_PICTURES = {"直接切": "cut", "淡出": "fade", "无截图": "none"}
METHOD_STYLES = {"system": "系统", "quietRequest": "自绘"}


def wall_us(event) -> float | None:
    us = number(fields(event).get("wUs"))
    if us is not None:
        return us
    t = number(event.get("t"))
    return None if t is None else t * 1_000_000


def turn_id(f) -> int | None:
    value = number(f.get("turn"))
    return None if value is None else int(value)


def lost_of(f) -> int:
    lost = number(f.get("lost"))
    return int(lost) if lost is not None and lost > 0 else 0


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
        elif rest in CYCLE_KINDS:
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


def new_turn(ident, us, anchor) -> dict:
    return {"id": ident, "us": us, "anchor": anchor, "begin": None, "native": defaultdict(list),
            "dart": defaultdict(list), "request": None, "returned": None, "presentation": None, "cycle": None,
            "end": None, "lost": 0}


def group_turns(events) -> dict:
    """Every turn with its native and Dart lines: by turn id where a line has one, by time where it doesn't."""
    lines, undated = turn_lines(events)
    turns = []
    for line in lines:
        if line["side"] == "native" and line["kind"] == "begin":
            turn = new_turn(turn_id(line["f"]), line["us"], "native begin")
            turn["begin"] = line["f"]
            turn["lost"] += lost_of(line["f"])
            turns.append(turn)

    def by_id(ident, us, slack):
        found = [turn for turn in turns if turn["id"] == ident and turn["us"] <= us + slack]
        return max(found, key=lambda turn: turn["us"]) if found else None

    unplaced = Counter()
    for line in lines:
        side, kind, f = line["side"], line["kind"], line["f"]
        if side == "native" and kind in NATIVE_KINDS:
            ident = turn_id(f)
            turn = by_id(ident, line["us"], 100_000)
            if turn is None and ident:
                # A turn whose begin never reached the log.
                turn = new_turn(ident, line["us"], f"native {kind}")
                turns.append(turn)
            if turn is None:
                unplaced[f"native {kind}"] += 1
            else:
                turn["native"][kind].append({**f, "us": line["us"]})
                turn["lost"] += lost_of(f)
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

    def next_turn(us, after=0):
        for turn in turns:
            if turn["us"] >= us - after:
                return turn if turn["us"] - us <= LEAD_US else None
        return None

    def last_turn(us):
        found = [turn for turn in turns if turn["us"] <= us + 50_000]
        return found[-1] if found and us - found[-1]["us"] <= TRAIL_US else None

    orphans = []
    requests_without = 0
    cycles = []
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
            turn = next_turn(us, PRESENTATION_AFTER_US)
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

    for turn in turns:
        marks = [mark for mark in cycles if mark[0] <= turn["us"]]
        # A cycle that is done or was switched off labels nothing after it.
        if marks and marks[-1][1] == "cycle":
            turn["cycle"] = marks[-1][2]
    return {"turns": turns, "orphans": orphans, "requestsWithout": requests_without, "undated": undated,
            "unplaced": unplaced, "frames": sum(1 for line in lines if line["kind"] == "frames"),
            "lost": sum(lost_of(line["f"]) for line in lines if line["side"] == "native")}


def style_of(turn) -> tuple[str, str | None]:
    """The turn's style: the 轮换测试 label it ran under, else the page's, else the native method's; and the page's
    when it disagrees with the 轮换测试 label."""
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
            method = str(f.get("method"))
            return METHOD_STYLES.get(method, f"{method}/{f.get('picture', '?')}"), None
    return "?", None


def native_style(label: str) -> tuple[str, str] | None:
    """The native method and picture a 旋转动画 label runs as; None for a label that isn't one."""
    parts = label.split("·")
    method = NATIVE_METHODS.get(parts[0])
    if method is None:
        return None
    if parts[0] == SYSTEM_STYLE:
        return method, "none"
    if len(parts) == 1:
        return method, "cut"
    picture = NATIVE_PICTURES.get(parts[1])
    return None if picture is None else (method, picture)


def label_mismatch(turn) -> str | None:
    """What the native begin ran, when its method or picture isn't what the turn's label says. 1.0.0 (15) may leave
    the picture out, and then only the method is checked."""
    begin = turn["begin"]
    expected = native_style(style_of(turn)[0])
    if begin is None or expected is None:
        return None
    method, picture = begin.get("method"), begin.get("picture")
    if (method is not None and str(method) != expected[0]) or (picture is not None and str(picture) != expected[1]):
        return f"{method if method is not None else '?'}/{picture if picture is not None else '?'}"
    return None


def direction_of(turn) -> str:
    """What the window turned to, from the native begin's sizes; else what the page asked for. A presentation change
    whose turn never came can sit on the next turn."""
    begin = turn["begin"] or {}
    w, h = number(begin.get("toW")), number(begin.get("toH"))
    if w is not None and h is not None:
        return "to L" if w > h else "back"
    presentation = turn["presentation"] or {}
    source, target = presentation.get("from"), presentation.get("to")
    if target == "landscape":
        return "to L"
    if source == "landscape":
        return "back"
    if source is not None or target is not None:
        return f"{source}→{target}"
    for f in turn["dart"]["sized"]:
        w, h = number(f.get("w")), number(f.get("h"))
        if w is not None and h is not None:
            return "to L" if w > h else "back"
    return "?"


def drawn_turn(turn) -> bool:
    """Whether the page draws this turn (自绘, 1.0.0 (14)'s 请求前关, (13)'s methods) rather than iOS (系统)."""
    method = (turn["begin"] or {}).get("method")
    if method is not None:
        return method != "system"
    return style_of(turn)[0] != SYSTEM_STYLE


def first_us(lines) -> float | None:
    return min((f["us"] for f in lines if f.get("us") is not None), default=None)


def analyse_turn(turn) -> dict:
    """The turn's timeline in ms from its native begin, what went wrong and what is missing.

    The first move is when the turn starts to show: iOS's own at the native begin; a drawn one once the page has begun
    (and, held, been released) and the still picture has gone, since the picture hides the page's first frames."""
    native, dart = turn["native"], turn["dart"]
    begin = turn["begin"]
    anchor = turn["us"]
    drawn = drawn_turn(turn)

    def since(us):
        return None if us is None or begin is None else (us - anchor) / 1000

    request, presentation = turn["request"], turn["presentation"]
    asked = request["us"] if request is not None else None if presentation is None else presentation["us"]
    gone = native["picture gone"][0] if native["picture gone"] else None
    began = first_us(dart["began"])
    if not drawn:
        moved = anchor if begin is not None else None
    elif began is None:
        moved = None
    else:
        moved = max([began] + [us for us in (first_us(dart["released"]), None if gone is None else gone["us"])
                               if us is not None])
    outcomes = [str(f.get("outcome")) for f in dart["started"]]
    a = {
        "drawn": drawn,
        "requestToBegin": None if request is None or begin is None else (anchor - request["us"]) / 1000,
        "started": since(first_us(dart["started"])),
        "outcome": outcomes[0] if outcomes else None,
        "began": since(began),
        "drawnAt": since(first_us(native["drawn"])),
        "picture": since(None if gone is None else gone["us"]),
        "pictureWhy": None if gone is None else str(gone.get("why", "?")),
        "move": None if moved is None or asked is None else (moved - asked) / 1000,
        "moveFrom": "request" if request is not None else "presentation",
        "mismatch": label_mismatch(turn),
        "fails": [],
    }
    fallback = bool(native["fallback"]) or a["pictureWhy"] == "fallback" or any(
        f.get("why") == "timeout" for f in dart["released"])
    if fallback:
        a["fails"].append(("fallback", "fallback"))
    if dart["late"]:
        a["fails"].append(("late", "late" + (", missed" if any(f.get("missed") is True for f in dart["late"])
                                             else "")))
    for outcome in ("stale", "unasked"):
        if outcome in outcomes:
            a["fails"].append((outcome, outcome))
    if a["picture"] is not None and a["picture"] > PICTURE_MAX_MS:
        a["fails"].append(("picture", f"picture {a['picture']:.0f} ms"))
    if turn["lost"]:
        a["fails"].append(("lost", f"{turn['lost']} lost"))
    if a["mismatch"]:
        a["fails"].append(("≠native", f"ran {a['mismatch']}"))

    expected = [("native request", request is not None), ("native begin", begin is not None),
                ("Dart presentation", presentation is not None)]
    # iOS's own turns are never sent to Dart.
    if drawn:
        expected += [("Dart started", bool(dart["started"])), ("Dart began", bool(dart["began"])),
                     ("native drawn", bool(native["drawn"]) or fallback)]
    a["missing"] = [name for name, there in expected if not there]
    return a


def fmt(value, spec="{:.0f}") -> str:
    return "–" if value is None else spec.format(value)


def verdict_text(a) -> str:
    return ", ".join(text for _, text in a["fails"]) or "ok"


def picture_cell(a) -> str:
    if a["picture"] is None:
        return "–"
    return fmt(a["picture"]) + ("" if a["pictureWhy"] == "drawn" else f" {a['pictureWhy']}")


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
            + (["snapshot failed"] if begin.get("snapshot") is False and begin.get("method") == "quietRequest"
               and begin.get("picture", "cut") != "none" else [])
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
    notes = []
    if a["mismatch"]:
        notes.append(f"the native begin ran {a['mismatch']}, not {style}")
    if page is not None:
        notes.append(f"the page logged style {page}")
    if turn["lost"]:
        notes.append(f"{turn['lost']} native sends lost before its lines")
    if a["move"] is not None:
        notes.append(f"first move {a['move']:.0f} ms after the {a['moveFrom']}")
    if notes:
        lines += wrap.wrap("notes: " + "; ".join(notes))
    if a["missing"]:
        lines += wrap.wrap("not in the log: " + ", ".join(a["missing"]))
    lines.append(f"  verdict: {verdict_text(a)}")
    return lines


def style_summary(analysed) -> list[dict]:
    """Per style (自绘 and 系统 since 1.0.0 (15)), in the order first seen: its failures and timing medians."""
    styles = {}
    for turn, a in analysed:
        style, _ = style_of(turn)
        entry = styles.setdefault(style, {"style": style, "cycle": turn["cycle"], "turns": []})
        entry["turns"].append(a)
    rows = []
    for entry in styles.values():
        found = entry["turns"]

        def values(key):
            return [a[key] for a in found if a[key] is not None]

        rows.append({
            "style": entry["style"],
            "cycle": entry["cycle"],
            "turns": len(found),
            "ok": sum(1 for a in found if not a["fails"]),
            "missing": sum(1 for a in found if a["missing"]),
            "fails": Counter(key for a in found for key, _ in a["fails"]),
            "requestToBegin": median(values("requestToBegin")),
            "began": median(values("began")),
            "drawnAt": median(values("drawnAt")),
            "picture": median(values("picture")),
            "pictureMax": max(values("picture"), default=None),
            "move": median(values("move")),
            "moveMax": max(values("move"), default=None),
        })
    return rows


def render_turns(events) -> str:
    grouped = group_turns(events)
    turns = grouped["turns"]
    lines = []
    if not turns:
        lines.append("no turns in this log (dev builds log them while 发送日志到电脑 is on)")
    else:
        analysed = [(turn, analyse_turn(turn)) for turn in turns]
        directions = Counter(direction_of(turn) for turn in turns)
        lines.append(f"== Turns: {len(turns)} ("
                     + ", ".join(f"{name} {count}" for name, count in sorted(directions.items())) + ") ==")
        rows = [["#", "at", "turn", "style", "dir", "req→beg", "started", "began", "drawn", "picture", "move",
                 "verdict"]]
        for index, (turn, a) in enumerate(analysed, 1):
            started = fmt(a["started"]) + ("" if a["outcome"] in (None, "pending") else f" {a['outcome']}")
            rows.append([str(index), clock(turn["us"] / 1_000_000), fmt(turn["id"]), style_of(turn)[0],
                         direction_of(turn), fmt(a["requestToBegin"]), started, fmt(a["began"]), fmt(a["drawnAt"]),
                         picture_cell(a), fmt(a["move"]),
                         verdict_text(a) + (" (missing lines)" if a["missing"] else "")])
        lines += table(rows)
        lines.append("(ms. req→beg: the rotation request to the native begin. started, began: the page's lines; "
                     "drawn: turnDrawn reaching the host; picture: the still picture going (why, when not drawn); "
                     "all from the native begin. move: from the request to the turn's first move, iOS's at the begin, "
                     "a drawn one's once the page has begun and the picture is gone. Failures: the 0.5 s fallback, a "
                     f"late or stale or unasked turn, a picture up over {PICTURE_MAX_MS} ms, lost sends, a native "
                     "begin that ran another style)")
        for index, (turn, a) in enumerate(analysed, 1):
            lines.append("")
            lines += turn_detail(index, turn, a)
        lines.append("")
        lines.append("== Per style ==")
        rows = [["style", "轮换", "turns", "ok", "fails", "missing", "req→beg", "began", "drawn", "picture med/max",
                 "move med/max"]]
        for row in style_summary(analysed):
            cycle = row["cycle"]
            rows.append([row["style"], f"{cycle.get('index', '?')}/{cycle.get('of', '?')}" if cycle else "–",
                         str(row["turns"]), str(row["ok"]),
                         ", ".join(f"{key} ×{row['fails'][key]}" for key in FAIL_KEYS if row["fails"][key]) or "–",
                         str(row["missing"]), fmt(row["requestToBegin"]), fmt(row["began"]), fmt(row["drawnAt"]),
                         f"{fmt(row['picture'])}/{fmt(row['pictureMax'])}",
                         f"{fmt(row['move'])}/{fmt(row['moveMax'])}"])
        lines += table(rows)
        lines.append("(ok: turns with no failure. missing: turns with lines not in the log. Medians over the turns "
                     "that have the line; what the screen showed is turn_video.py's to grade)")
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
    if grouped["frames"]:
        lines.append(f"per-frame lines passed over: {grouped['frames']} (1.0.0 (13) and (14); turn_video.py grades "
                     "what was on screen)")
    if turns or grouped["lost"]:
        lines.append(f"native sends to Dart lost: {grouped['lost']}")
    return clean("\n".join(lines)) + "\n"


def utf8_console():
    """The reports and --help hold Chinese, which a cp1252 Windows console or pipe can't encode."""
    for stream in (sys.stdout, sys.stderr):
        if stream.encoding and stream.encoding.lower().replace("-", "") != "utf8":
            stream.reconfigure(encoding="utf-8", errors="replace")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?", type=pathlib.Path, help="a session's .jsonl")
    parser.add_argument("--latest", action="store_true", help="the newest .jsonl under logs/")
    parser.add_argument("--turns", action="store_true", help="the turns' timelines instead")
    utf8_console()
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
