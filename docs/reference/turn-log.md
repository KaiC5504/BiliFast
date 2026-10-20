# The drawn turn's log lines

1.0.0 (14) has two ways of turning (开发者 → 旋转动画, `lib/device/turn_style.dart`): 系统, iOS's own rotation, and
请求前关, which asks for the rotation with UIView animations already off so that iOS doesn't animate it and the video
page draws the official turn itself, with a still picture (直接切, 淡出 or 无截图) and a start (立即 or 等截图). Both
sides log each turn. `tools/phone_report.py --turns` merges the two and grades each style; `tools/turn_video.py`
measures what a screen recording of the same turns showed. Once the phone has picked a style, the losing ones and the
per-frame lines go, and the summary stays.

All lines are category `ui`. Every line has `wUs`, the wall clock in microseconds since the epoch (`Date()` natively,
`DateTime.now()` in Dart), so the two sides line up. Native lines also have `turn` (the host's id for the turn, from 1
per launch; 0 when there is no turn yet), `method` and `picture` (the `NativeTurnMethod` and `NativeTurnPicture`
names: `quietRequest` with `cut`, `fade` or `none` for 请求前关; `system` and `none` for 系统, the takeover off). A 系统
turn to or from landscape is only logged and sampled: `request`, `request returned`, `begin` (`snapshot` false),
`completion` and `frames`. Angles in the `frames` samples are in degrees, positive clockwise on screen. Fields hold
strings, ints, doubles and bools only; per-frame data is packed into strings.

## Native (`TurnProbe.swift`, `TurnTakeover.swift`, `DeviceChannel.swift`): `turn native <kind>`

| kind | fields besides the common ones |
|---|---|
| `request` | `request` (int), `mask`, `interface` (before), `animationsEnabled` (bool): Dart asked for a mask |
| `request returned` | `request`, `ms` (double): `requestGeometryUpdate` returned |
| `begin` | `angle` (rad), `seconds`, `animated` (bool), `fromW`, `fromH`, `toW`, `toH`, `animationsEnabled` (bool, before), `snapshot` (bool: a still picture is up for this turn), `snapshotMs` (double, 0 with no picture) |
| `alongside` | the coordinator's alongside block ran |
| `completion` | `cancelled` (bool) |
| `drawn` | `action` (`cut`, `fade`, `none` or `gone`): Flutter's turnDrawn arrived |
| `picture gone` | `why` (`drawn` or `fallback`) |
| `fallback` | the 0.5 s timeout fired before turnDrawn |
| `frames` | `count` (int), `samples` (string, below); its own `wUs` is when sampling stopped |

`request` lines carry the last begun turn's id. `picture gone` can also have
`why: replaced` (the next turn's begin took it away); a turn with no picture (`none`, a failed snapshot) has no
`picture gone` line. Any native line can carry `lost` (int, only when above 0): sends to Dart that failed since the
last line that got through. The first `frames` sample's `gapMs` counts from `begin`, so a stall before the first tick
shows there; `scene` and `window` angles include the layer's `sublayerTransform`.

`frames.samples`: one per CADisplayLink tick for 1.2 s from `begin`, `;`-separated, each `,`-separated:
`tMs` (since `begin`'s `wUs`), `gapMs` (since the last tick), `scene` (the summed angle of the window's superlayers),
`window`, `windowW`, `windowH`, `container` (always empty since 1.0.0 (14); kept so the columns stay where they were),
`root`, `picture` (empty when none), `pictureOpacity` (empty when none). Angles and sizes are the presentation
layers', so they show what was on screen.

1.0.0 (13) had five more methods (原样 `legacy`, 移除 `remove`, 抵消 `counter`, 关动作 `noActions`, 不转 `noSpin`) and
two more kinds: `animations` (the animations iOS had added, and how many were removed) and `container` (the counter
method's container around the Flutter view). `phone_report.py` still reads those logs: it passes over the two kinds
(their `lost` still counts), grades the old methods' turns on what was seen like any other, and checks a turn's label
against its native begin only for 系统 and 请求前关.

## Dart (`lib/video/turn_recorder.dart`): `turn <kind>`

| kind | fields besides `wUs` |
|---|---|
| `presentation` | `from`, `to` (Presentation names), `wide` (bool), `waiting` (bool), `style` (TurnStyle label) |
| `started` | `turn`, `angle` (rad), `ms`, `outcome` (`pending`, `stale` or `unasked`) |
| `sized` | `w`, `h`, `layout` |
| `began` | `turn`, `spinFrom` (rad), `ms`, `grow`, `held` (bool) |
| `released` | `turn`, `why` (`picture` or `timeout`) |
| `drawn sent` | `turn` |
| `picture gone` | `turn` |
| `late` | `missed` (bool) |
| `frames` | `t0Us` (wall µs the samples count from), `count`, `samples`, `timings`, `worstBuildMs`, `worstRasterMs`, `refreshHz` (the display's rate), `slow` (frames over one refresh) |

`frames.samples`: one per frame built while a turn runs, `;`-separated, each `,`-separated:
`tMs` (since `t0Us`), `angle` (deg, the page's drawn turn), `grow`, `boxL`, `boxT`, `boxW`, `boxH` (empty at rest),
`w`, `h` (the size laid out at), `shownMs` (since `t0Us`, when its raster finished, from its FrameTiming; empty when
not known). `frames.timings`: the engine's FrameTiming for the same window, `;`-separated
`buildMs,rasterMs,totalMs,rasterEndMs` (`rasterEndMs` since `t0Us`, empty when the engine gives no wall time).

`grow` has 3 decimals. `timings` holds only the frames whose build overlaps the samples, placed on the wall clock
by their raster finish; `slow` counts those whose whole span (vsync to raster end) is over one refresh at
`refreshHz` (the iPhone runs at 120 Hz). A frame built while a settled window still waits for its timings starts a
new window, so each line holds one turn.

The line is written once the turn has settled (300 to 600 ms with no frame or event), so logging never runs inside the
turn. Release builds hand FrameTimings over in batches up to 1 s apart, so it waits up to 1.2 s more for the batch
holding the last frame: it can come about 1.5 s after the turn's last frame.

## 轮换测试 (`lib/devtools/turn_cycle.dart`)

The cycle is 系统, then 请求前关 with each of its six picture and start pairs (`TurnStyle.cycle`), so `of` is 7.
`turn cycle` with `index` (from 1), `of`, `label` and `wUs` each time the style moves on (and on 重置); `turn cycle
done` after the last style and `turn cycle off` when it is switched off by hand, both with `of` and `label` (the style
put back), `off` also with `index`. A position counts only once landscape,
and then upright, have each held for 1.5 s, so a refused or quickly reversed turn doesn't move it on.

## What the report computes per turn

The content's angle on screen at each display-link tick is `scene + window + container + root` plus the page's drawn
angle from the Dart frame one tick earlier (a frame shows one vsync after it is built). From that: where it starts
relative to the end (should be ±90°), the total sweep (90°, not 180°), whether it moves one way only, the biggest
step, the time to settle, how far the picture and the content disagreed when the picture went (the ghost), the
longest gap on each side, and the time from Dart's request to the first frame that moves. A turn's direction is what
its native begin's `toW` and `toH` say, else the page's presentation change.

## What a screen recording shows (`tools/turn_video.py`)

The log can't see iOS animating the window outside the app, so a 1.0.0 (13) style could log a clean turn while the
phone showed a 180° spin. KaiC's screen recording can:

    uv run tools/turn_video.py local/differences/09-ours-rotate-testing-v4.MP4 --log logs/2026-10-20/<session>.jsonl

(`--ffmpeg PATH` when ffmpeg isn't on PATH or at `D:/Tools/ffmpeg/bin/ffmpeg`; `--crop TOP:BOTTOM` for another
phone's small player; `--frames` for every frame's angle, scale and inliers.) It decodes every frame at the
recording's own rate, 440 wide, into a temporary folder that is deleted when it ends: frames never go into the repo,
and neither do the recordings or logs (`local/` and `logs/` are gitignored). A turn is a run of frames that differ a
lot from the one before, whose two ends measure about 90° apart. Each frame's angle (clockwise; recordings stay
portrait-framed, so upright is 0° and landscape ±90°) comes from SIFT matches against the small player of the nearest
still upright frame (before a turn to landscape, after a turn back), or against that whole frame while the player is
out of sight.

Per turn: the first frame's jump, the sweep from there, one way or not, the settle time and the RMS error against the
official turn (90° along ease-in-out cubic(0.42, 0, 0.58, 1) over 300 ms, its start fitted up to 100 ms before the
first frame that moved, over the frames where either moves). The verdict: `official-like` (a smooth 90° within 3° RMS),
`system-like` (smooth but off the curve), `spin` (a sweep of 135° or more), `cut` (a jump of 60° or more with no
motion after) or `?` with the reason. With `--log`, each turn gets its native turn id and the 轮换测试 style (read
through `phone_report.py`), the recording placed on the phone's clock by the offset that best lines the detected turns
up with the native begins of the same direction; the recording's creation time is only the first guess (0.7 s off in
09). A summary per style follows.

09 (1.0.0 (13), 52 turns, all matched within 26 ms): 系统 smooth and within 0.5° of the official curve (iOS's own
turn on this phone is the same 300 ms ease-in-out, so the curve alone can't tell it from a correct drawn turn);
原样, 移除, 抵消 and 关动作 mostly a jump to about −87° and a 180° sweep back; 请求前关 a cut straight to 90°. The official
app's own recording (01) turns back within 1.2° of the curve and to landscape in about 250 ms (6°).
