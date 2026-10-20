"""Synthetic phone logs of drawn turns, in docs/reference/turn-log.md's formats, for test_phone_report.py.

    python tools/testdata/turn_logs.py

rewrites turn_session.jsonl: a 轮换测试 over five styles switched off by hand, a turn after it with only the Dart side,
one at 60 Hz, and a presentation change no turn followed; the sample `phone_report.py --turns` is tried on.
"""
from __future__ import annotations

import json
import math
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SAMPLE = HERE / "turn_session.jsonl"
# The phone's display; a turn can run at another rate.
HZ = 120
START_US = 1_760_000_000_000_000
# A frame's build and raster, well inside one 120 Hz tick.
BUILD_MS = 4.2
RASTER_MS = 3.1


def ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def number_text(value: float) -> str:
    return f"{value:.2f}".rstrip("0").rstrip(".") if value != 0 else "0"


class Log:
    def __init__(self, start_us: int = START_US):
        self.lines: list[tuple[float, str, dict]] = []
        self.now = float(start_us)
        self.ids = 0
        self.requests = 0

    def line(self, us: float, msg: str, **f):
        self.lines.append((us, msg, {"wUs": int(round(us)), **f}))

    def native(self, us: float, kind: str, turn: int, method: str, picture: str, **f):
        self.line(us, f"turn native {kind}", turn=turn, method=method, picture=picture, **f)

    def dart(self, us: float, kind: str, **f):
        self.line(us, f"turn {kind}", **f)

    def cycle(self, index: int, of: int, label: str):
        self.line(self.now, "turn cycle", index=index, of=of, label=label)
        self.now += 500_000

    def cycle_done(self, of: int = 13, label: str = "移除·直接切·立即"):
        self.line(self.now, "turn cycle done", of=of, label=label)
        self.now += 500_000

    def cycle_off(self, index: int, of: int = 13, label: str = "移除·直接切·立即"):
        self.line(self.now, "turn cycle off", index=index, of=of, label=label)
        self.now += 500_000

    def events(self, session: str = "turns01") -> list[dict]:
        ordered = sorted(self.lines, key=lambda line: line[0])
        return [{"t": us / 1_000_000, "seq": seq, "session": session, "level": "info", "cat": "ui", "msg": msg, "f": f}
                for seq, (us, msg, f) in enumerate(ordered, 1)]

    def write(self, path: pathlib.Path):
        path.write_text("".join(json.dumps(event, ensure_ascii=False) + "\n" for event in self.events()),
                        encoding="utf-8", newline="\n")

    def presentation_only(self, style: str):
        """A change of presentation whose turn never came."""
        self.dart(self.now, "presentation", **{"from": "inline", "to": "landscape"}, wide=False, waiting=True,
                  style=style)
        self.dart(self.now + 600_000, "late", missed=True)
        self.now += 3_000_000

    def turn(self, style: str, *, method: str = "remove", picture: str = "cut", to_landscape: bool = True,
             ios_turns: bool = False, counter: bool = False, spin: bool = True, hold: bool = False,
             first_frame_ms: float = 20.0, drawn_ms: float = 55.0, fade_ms: float = 0.0, spin_ms: float = 400.0,
             seconds: float = 0.4, stall_at_ms: float | None = None, stall_ms: float = 0.0,
             native: bool = True, dart: bool = True, native_frames: bool = True, dart_frames: bool = True,
             frames_after_ms: float = 300.0, hz: float = HZ, totals: dict[int, float] | None = None,
             shown: bool = True, raster_end: bool = True, snapshot: bool | None = None, lost: int = 0) -> int:
        """One turn with `now` as its native begin; moves `now` on 3 s. iOS's own rotation shows as the window's angle
        going from the turn's start to 0; the page's as the Dart frames' angle doing the same. The Dart `frames` line
        comes `frames_after_ms` after the last frame (up to ~1.5 s in release builds, waiting for FrameTimings).

        The display ticks at `hz`, and the page builds a frame on every tick from `first_frame_ms`, each done
        BUILD_MS + RASTER_MS after it starts unless `totals` gives a frame (by index) another span. `shown` and
        `raster_end` leave out the frames' raster finish, as a log without FrameTimings has it; `snapshot` False is a
        still picture that failed; `lost` rides on the begin."""
        tick_ms = 1000 / hz
        totals = totals or {}
        self.ids += 1
        self.requests += 1
        ident = self.ids
        begin = self.now
        angle = 90.0 if to_landscape else -90.0
        start = -angle
        at = lambda ms: begin + ms * 1000  # noqa: E731
        common = {"method": method, "picture": picture}
        snapped = picture != "none" if snapshot is None else snapshot
        if dart:
            self.dart(at(-40), "presentation", **({"from": "inline", "to": "landscape"} if to_landscape
                                                   else {"from": "landscape", "to": "inline"}),
                      wide=not to_landscape, waiting=True, style=style)
        if native:
            self.native(at(-25), "request", ident - 1, **common, request=self.requests,
                        mask="landscape" if to_landscape else "portrait",
                        interface="portrait" if to_landscape else "landscapeRight", animationsEnabled=True)
            self.native(at(-24), "request returned", ident - 1, **common, request=self.requests, ms=0.8)
            size = (440, 956, 956, 440) if to_landscape else (956, 440, 440, 956)
            self.native(at(0), "begin", ident, **common, angle=math.radians(angle), seconds=seconds, animated=True,
                        fromW=size[0], fromH=size[1], toW=size[2], toH=size[3], animationsEnabled=True,
                        snapshot=snapped, snapshotMs=6.5 if snapped else 0.0, **({"lost": lost} if lost else {}))
            found = "window|transform|CABasicAnimation|0.4|easeInEaseOut|false|0;root|bounds|CABasicAnimation|0.4|easeInEaseOut|false|0"
            self.native(at(1), "animations", ident, **common, phase="after super", found=found,
                        removed=0 if ios_turns else 2)
            self.native(at(2), "alongside", ident, **common)
            if counter:
                self.native(at(2), "container", ident, **common, event="installed")
            if snapped:
                self.native(at(drawn_ms), "drawn", ident, **common, action=picture)
                self.native(at(drawn_ms), "picture gone", ident, **common, why="drawn")
            self.native(at(seconds * 1000), "completion", ident, **common, cancelled=False)

        spin_start = drawn_ms + 2 + tick_ms if hold else first_frame_ms
        if dart:
            self.dart(at(4), "started", turn=ident, angle=math.radians(angle), ms=seconds * 1000, outcome="pending")
            self.dart(at(first_frame_ms - 2), "sized", w=956 if to_landscape else 440, h=440 if to_landscape else 956,
                      layout="landscape" if to_landscape else "inline")
            if spin:
                self.dart(at(first_frame_ms), "began", turn=ident, spinFrom=math.radians(start), ms=spin_ms,
                          grow=0.0 if to_landscape else 1.0, held=hold)
                self.dart(at(drawn_ms - 3), "drawn sent", turn=ident)
                if snapped:
                    self.dart(at(drawn_ms + 2), "picture gone", turn=ident)
                if hold:
                    self.dart(at(drawn_ms + 2), "released", turn=ident, why="picture")

        def drawn_angle(ms: float) -> float:
            return start * (1 - ease((ms - spin_start) / spin_ms)) if spin else 0.0

        if dart and dart_frames:
            samples, timings = [], []
            ms = first_frame_ms
            last = ms
            slow = 0
            shown_ms = 0.0
            while ms <= spin_start + spin_ms + 2 * tick_ms:
                index = len(samples)
                total = totals.get(index, BUILD_MS + RASTER_MS)
                slow += total > tick_ms
                # Rasters run in order: a frame is never on screen before the one before it.
                shown_ms = max(shown_ms, ms - first_frame_ms + total)
                progress = ease((ms - first_frame_ms) / spin_ms)
                grow = progress if to_landscape else 1 - progress
                since = ms - first_frame_ms
                # The player box is empty at rest, once the turn is done.
                box = ["", "", "", ""] if ms > spin_start + spin_ms else ["0", "0", "956", "440"]
                samples.append(",".join([number_text(since), number_text(drawn_angle(ms)), f"{grow:.3f}", *box,
                                         "956", "440", number_text(shown_ms) if shown else ""]))
                timing = [number_text(BUILD_MS), number_text(total - BUILD_MS), number_text(total)]
                timings.append(",".join(timing + ([number_text(shown_ms)] if raster_end else [])))
                last = ms
                ms += tick_ms
            self.dart(at(last + frames_after_ms), "frames", t0Us=int(round(at(first_frame_ms))), count=len(samples),
                      samples=";".join(samples), timings=";".join(timings), worstBuildMs=BUILD_MS,
                      worstRasterMs=max(total - BUILD_MS for total in [BUILD_MS + RASTER_MS, *totals.values()]),
                      refreshHz=hz, slow=slow)

        if native and native_frames:
            ticks = []
            ms, previous = 0.0, None
            while ms <= 1200:
                if stall_at_ms is not None and stall_at_ms < ms < stall_at_ms + stall_ms:
                    ms = stall_at_ms + stall_ms
                gap = tick_ms if previous is None else ms - previous
                window = start * (1 - ease(ms / (seconds * 1000))) if ios_turns else 0.0
                container = -window if counter else None
                up = snapped and ms < drawn_ms + fade_ms
                opacity = None if not up else 1.0 if ms < drawn_ms else 1 - (ms - drawn_ms) / fade_ms
                # The still picture is turned back so it stays where it was on the phone.
                picture_angle = (start - window if counter else start) if up else None
                ticks.append(",".join([
                    number_text(ms), number_text(gap), "0", number_text(window), "956", "440",
                    "" if container is None else number_text(container), "0",
                    "" if picture_angle is None else number_text(picture_angle),
                    "" if opacity is None else number_text(opacity)]))
                previous = ms
                ms += tick_ms
            self.native(at(1210), "frames", ident, **common, count=len(ticks), samples=";".join(ticks))
        self.now += 3_000_000
        return ident


def sample() -> Log:
    log = Log()
    styles = [
        ("系统", {"method": "legacy", "picture": "none", "ios_turns": True, "spin": False}),
        ("原样·淡出·立即", {"method": "legacy", "picture": "fade", "fade_ms": 120, "ios_turns": True}),
        ("移除·直接切·立即", {"method": "remove"}),
        ("移除·淡出·立即", {"method": "remove", "picture": "fade", "fade_ms": 120}),
        ("抵消·直接切·等截图", {"method": "counter", "ios_turns": True, "counter": True, "hold": True,
                         "stall_at_ms": 150, "stall_ms": 300}),
    ]
    for index, (label, options) in enumerate(styles, 1):
        log.cycle(index, 13, label)
        log.turn(label, **options)
        log.turn(label, to_landscape=False, **{**options, "stall_at_ms": None})
    log.cycle_off(len(styles), 13, "移除·直接切·立即")
    log.turn("移除·直接切·立即", native=False)
    log.turn("移除·直接切·立即", to_landscape=False, hz=60, lost=2)
    log.presentation_only("移除·直接切·立即")
    return log


if __name__ == "__main__":
    sample().write(SAMPLE)
