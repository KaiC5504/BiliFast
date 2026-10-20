"""Synthetic phone logs of turns, in docs/reference/turn-log.md's formats, for test_phone_report.py and
test_turn_video.py.

    python tools/testdata/turn_logs.py

rewrites the two sample sessions `phone_report.py --turns` is tried on: turn_session_15.jsonl, 1.0.0 (15)'s 自绘 and
系统 with a fallback, a late turn, a stale one and lost sends; and turn_session_14.jsonl, 1.0.0 (14)'s 轮换测试 over
five of its seven styles switched off by hand, with its per-frame lines, a turn with only the Dart side and a
presentation change no turn followed.
"""
from __future__ import annotations

import json
import math
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SAMPLE_15 = HERE / "turn_session_15.jsonl"
SAMPLE_14 = HERE / "turn_session_14.jsonl"
START_US = 1_760_000_000_000_000
# Where each line of a drawn turn lands, ms from the native begin, as on KaiC's phone in 1.0.0 (14).
REQUEST_MS = -20.0
STARTED_MS = 9.0
BEGAN_MS = 11.0
DRAWN_MS = 20.0
FALLBACK_MS = 500.0


class Log:
    def __init__(self, start_us: int = START_US):
        self.lines: list[tuple[float, str, dict]] = []
        self.now = float(start_us)
        self.ids = 0
        self.requests = 0

    def line(self, us: float, msg: str, **f):
        self.lines.append((us, msg, {"wUs": int(round(us)), **f}))

    def native(self, us: float, kind: str, turn: int, method: str, picture: str | None, **f):
        self.line(us, f"turn native {kind}", turn=turn, method=method, **({} if picture is None else
                                                                          {"picture": picture}), **f)

    def dart(self, us: float, kind: str, **f):
        self.line(us, f"turn {kind}", **f)

    def cycle(self, index: int, of: int, label: str):
        self.line(self.now, "turn cycle", index=index, of=of, label=label)
        self.now += 500_000

    def cycle_done(self, of: int = 7, label: str = "请求前关·直接切·立即"):
        self.line(self.now, "turn cycle done", of=of, label=label)
        self.now += 500_000

    def cycle_off(self, index: int, of: int = 7, label: str = "请求前关·直接切·立即"):
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

    def turn(self, style: str, *, build: int = 15, method: str = "quietRequest", picture: str | None = "cut",
             to_landscape: bool = True, hold: bool = False, native: bool = True, dart: bool = True,
             fade_ms: float = 0.0, fallback: bool = False, snapshot: bool | None = None, outcome: str = "pending",
             late: bool = False, lost: int = 0) -> int:
        """One turn with `now` as its native begin; moves `now` on 3 s.

        Method `system` is 系统: request, request returned, begin (0.3 s, no picture) and completion natively, and
        only the presentation change and the new size from the page. Otherwise the page draws the turn (自绘, and
        1.0.0 (14)'s 请求前关 with `picture` cut, fade or none): iOS turns in 0 s under a still picture that goes once
        turnDrawn arrives (`fade_ms` later for 淡出), or at the 0.5 s fallback when it doesn't (`fallback`).
        `picture` None is a 1.0.0 (15) host that leaves the field out. A turn back's presentation change comes just
        after the begin, as on the phone.

        `build` 14 adds that build's lines: the Dart `picture gone`, `began`'s `held`, `released` for 等截图 (`hold`)
        and a per-frame line on each side."""
        self.ids += 1
        self.requests += 1
        ident = self.ids
        begin = self.now
        angle = math.pi / 2 if to_landscape else -math.pi / 2
        at = lambda ms: begin + ms * 1000  # noqa: E731
        system = method == "system"
        if system:
            picture = "none"
        common = {"method": method, "picture": picture}
        pictured = picture != "none" if snapshot is None else snapshot
        if dart:
            change = {"from": "inline", "to": "landscape"} if to_landscape else {"from": "landscape", "to": "inline"}
            self.dart(at(-10 if to_landscape else 8), "presentation", **change, wide=not to_landscape,
                      waiting=not system, style=style)
        if native:
            self.native(at(REQUEST_MS), "request", ident - 1, **common, request=self.requests,
                        mask="landscape" if to_landscape else "portrait",
                        interface="portrait" if to_landscape else "landscapeRight", animationsEnabled=True)
            self.native(at(REQUEST_MS + 0.5), "request returned", ident - 1, **common, request=self.requests, ms=0.01)
            size = (440, 956, 956, 440) if to_landscape else (956, 440, 440, 956)
            self.native(at(0), "begin", ident, **common, angle=angle, seconds=0.3 if system else 0.0,
                        animated=system, fromW=size[0], fromH=size[1], toW=size[2], toH=size[3],
                        animationsEnabled=False, snapshot=pictured, snapshotMs=3.5 if pictured else 0.0,
                        **({"lost": lost} if lost else {}))
            if system:
                self.native(at(300), "completion", ident, **common, cancelled=False)
            else:
                self.native(at(7), "alongside", ident, **common)
                self.native(at(7.1), "completion", ident, **common, cancelled=False)
                if fallback:
                    self.native(at(FALLBACK_MS), "fallback", ident, **common)
                    if pictured:
                        self.native(at(FALLBACK_MS), "picture gone", ident, **common, why="fallback")
                    self.native(at(FALLBACK_MS + 10), "drawn", ident, **common, action="gone")
                else:
                    self.native(at(DRAWN_MS), "drawn", ident, **common, action=picture or "cut")
                    if pictured:
                        self.native(at(DRAWN_MS + fade_ms), "picture gone", ident, **common, why="drawn")
            if build == 14:
                self.native(at(1200), "frames", ident, **common, count=2,
                            samples="0,8.3,0,0,956,440,,0,,;8.3,8.3,0,0,956,440,,0,,")
        if dart:
            self.dart(at(160 if system else BEGAN_MS), "sized", w=956 if to_landscape else 440,
                      h=440 if to_landscape else 956, layout="landscape" if to_landscape else "inline")
            if not system:
                self.dart(at(STARTED_MS), "started", turn=ident, angle=angle, ms=0.0, outcome=outcome)
                if build == 14 and not pictured:
                    self.dart(at(STARTED_MS + 0.1), "picture gone", turn=ident)
                self.dart(at(BEGAN_MS), "began", turn=ident, spinFrom=-angle, ms=300.0,
                          grow=0.0 if to_landscape else 1.0, **({"held": hold} if build == 14 else {}))
                sent = (FALLBACK_MS + 10 if fallback else DRAWN_MS) - 0.05
                self.dart(at(sent), "drawn sent", turn=ident)
                if build == 14 and pictured:
                    self.dart(at(sent + fade_ms + 0.3), "picture gone", turn=ident)
                if build == 14 and hold:
                    self.dart(at(sent + fade_ms + 0.4), "released", turn=ident, why="picture")
            if late:
                self.dart(at(600), "late", missed=False)
            if build == 14:
                self.dart(at(1000), "frames", t0Us=int(round(at(-10))), count=1, samples="0,0,0.000,,,,,440,956,7.3",
                          timings="4.2,3.1,7.3,7.3", worstBuildMs=4.2, worstRasterMs=3.1, refreshHz=120, slow=0)
        self.now += 3_000_000
        return ident


def sample_15() -> Log:
    log = Log()
    for to_landscape in (True, False):
        log.turn("系统", method="system", to_landscape=to_landscape)
    log.turn("自绘")
    log.turn("自绘", to_landscape=False, picture=None)
    log.turn("自绘", fallback=True)
    log.turn("自绘", to_landscape=False, late=True)
    log.turn("自绘", outcome="stale")
    log.turn("自绘", to_landscape=False, lost=2)
    log.presentation_only("自绘")
    return log


def sample_14() -> Log:
    log = Log()
    styles = [
        ("系统", {"method": "system"}),
        ("请求前关·直接切·立即", {}),
        ("请求前关·直接切·等截图", {"hold": True}),
        ("请求前关·淡出·立即", {"picture": "fade", "fade_ms": 130}),
        ("请求前关·无截图·立即", {"picture": "none"}),
    ]
    for index, (label, options) in enumerate(styles, 1):
        log.cycle(index, 7, label)
        log.turn(label, build=14, **options)
        log.turn(label, build=14, to_landscape=False, **options)
    log.cycle_off(len(styles))
    log.turn("请求前关·直接切·立即", build=14, native=False)
    log.turn("请求前关·直接切·立即", build=14, to_landscape=False, lost=2)
    log.presentation_only("请求前关·直接切·立即")
    return log


if __name__ == "__main__":
    sample_15().write(SAMPLE_15)
    sample_14().write(SAMPLE_14)
