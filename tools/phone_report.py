#!/usr/bin/env python3
"""What a phone session measured, from its log (logs/<date>/<session>.jsonl as tools/logserver.py writes it).

    python tools/phone_report.py logs/2026-10-18/0123456789abcdef.jsonl
    python tools/phone_report.py --latest

For each speed test run: results per variant and played quality with the differences from the first variant,
then per pass the engine's nodes (pieces won, first byte, speed, losses before the first byte, failures) and its
seek reads. Then memory warnings and the player's error log. A session without a speed test gets the same over
the whole session. Standard library only; anything that looks like a URL is cut down to its host.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import pathlib
import re
import sys
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


def groups(run) -> list[dict]:
    """Counted passes pooled per variant and played quality, variants in the order they first ran."""
    order = []
    pooled = defaultdict(list)
    for p in counted(run["passes"]):
        variant = str(p["done"].get("variant", p["marker"].get("variant", "?")))
        quality = p["done"].get("quality")
        if variant not in order:
            order.append(variant)
        pooled[(variant, quality)].append(p)
    keys = sorted(pooled, key=lambda key: (order.index(key[0]), -(key[1] or 0)))
    result = []
    for variant, quality in keys:
        passes = pooled[(variant, quality)]
        taps = step_ms(passes, "tap")

        def total(name):
            return int(sum(number(p["done"].get(name)) or 0 for p in passes))

        result.append({
            "variant": variant,
            "quality": quality,
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
    """Every later variant minus the first one, at the same quality."""
    if not found_groups:
        return []
    first = found_groups[0]["variant"]
    bases = {g["quality"]: g for g in found_groups if g["variant"] == first}
    result = []
    for g in found_groups:
        base = bases.get(g["quality"])
        if g["variant"] == first or base is None:
            continue
        result.append({"variant": g["variant"], "base": first, "quality": g["quality"],
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


def table(rows: list[list[str]]) -> list[str]:
    widths = [max(len(row[column]) for row in rows) for column in range(len(rows[0]))]
    return ["  ".join(cell.ljust(width) for cell, width in zip(row, widths)).rstrip() for row in rows]


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


def render_run(index, run) -> list[str]:
    start = run["start"]
    source = clean(start.get("source", "?"))
    note = clean(start.get("planNote", ""))
    lines = [f"== Speed test {index}: plan {clean(start.get('plan', '?'))} ({source}{': ' + note if note and source != 'pc' else ''}), "
             f"{start.get('passes', '?')} passes, {start.get('videos', '?')} video(s) =="]
    found = groups(run)
    if found:
        rows = [["", "passes", "first", "tap med/p90/max", "hint", "back", "stalls", "fast", "timeouts", "rssMB",
                 "memW"]]
        for g in found:
            rows.append([f"{g['variant']} {quality_name(g['quality'])}", str(g["passes"]), seconds(g["first"]),
                         "/".join(seconds(g[key]) for key in ("tapMedian", "tapP90", "tapMax")),
                         seconds(g["hint"]), seconds(g["back"]), str(g["stalls"]), str(g["fastStalls"]),
                         str(g["timeouts"]), str(g["rssMB"]), str(g["memoryWarnings"])])
        lines += table(rows)
        lines.append("(seconds; medians over every pass of the group; a timed-out seek counts as its 15 s)")
    else:
        lines.append("no pass finished")
    differences = deltas(found)
    if differences:
        lines.append(f"differences from {differences[0]['base']} (negative is faster, fewer or smaller):")
        rows = [["", "first", "tap med/p90/max", "hint", "back", "stalls", "fast", "timeouts", "rssMB"]]
        for d in differences:
            rows.append([f"{d['variant']}-{d['base']} {quality_name(d['quality'])}", signed_seconds(d["first"]),
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
        lines.append(f"-- pass {marker.get('pass')}: {clean(marker.get('variant'))} {quality_name(played)} "
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


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?", type=pathlib.Path, help="a session's .jsonl")
    parser.add_argument("--latest", action="store_true", help="the newest .jsonl under logs/")
    args = parser.parse_args(argv)
    path = latest_log(ROOT / "logs") if args.latest else args.session
    if path is None:
        parser.error("give a session file, or --latest with logs under logs/")
    if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(f"{path.name}\n")
    sys.stdout.write(render(load(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
