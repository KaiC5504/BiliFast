# The turn's log lines

1.0.0 (15) has two ways of turning (开发者 → 旋转动画, `lib/device/turn_style.dart`): 自绘, the drawn turn (the rotation
asked for with UIView animations already off, so iOS turns the window in 0 s under a still picture, cut as soon as
the page's first turned frame is drawn, and the page draws the official turn from −angle to 0), and 系统, iOS's own
rotation. Both sides log a summary of each turn. `tools/phone_report.py --turns` reads its timeline;
`tools/turn_video.py` measures what a screen recording of the same turns showed.

All lines are category `ui`. Every line has `wUs`, the wall clock in microseconds since the epoch (`Date()` natively,
`DateTime.now()` in Dart), so the two sides line up.

## Native (`TurnProbe.swift`, `TurnTakeover.swift`, `DeviceChannel.swift`): `turn native <kind>`

Each also has `turn` (the host's id for the turn, from 1 per launch; a `request` carries the last begun one, 0 before
any) and `method` (`quietRequest` for 自绘, `system` for 系统); `picture` (`cut`, `none` for 系统) may be left out.

| kind | fields |
|---|---|
| `request` | `request` (int), `mask`, `interface` (before), `animationsEnabled` (bool): Dart asked for a mask |
| `request returned` | `request`, `ms` (double): `requestGeometryUpdate` returned |
| `begin` | `angle` (rad), `seconds` (0 for 自绘), `animated` (bool), `fromW`, `fromH`, `toW`, `toH`, `animationsEnabled` (bool, before), `snapshot` (bool: a still picture is up), `snapshotMs` |
| `alongside` | the coordinator's alongside block ran |
| `completion` | `cancelled` (bool) |
| `drawn` | `action` (`cut`, or `gone` when the picture had already gone): turnDrawn arrived |
| `picture gone` | `why`: `drawn`, `fallback`, or `replaced` (the next turn's begin took it) |
| `fallback` | the 0.5 s timeout fired before turnDrawn |

A 系统 turn logs only `request`, `request returned`, `begin` (`snapshot` false) and `completion`. Any native line can
carry `lost` (int, only when above 0): sends to Dart that failed since the last line that got through.

## Dart (`lib/video/turn_recorder.dart`): `turn <kind>`

| kind | fields besides `wUs` |
|---|---|
| `presentation` | `from`, `to` (Presentation names), `wide`, `waiting` (bool), `style` (`自绘` or `系统`) |
| `started` | `turn`, `angle` (rad), `ms`, `outcome`: `pending` (the turn the page waits for), `stale` (the other way, or overtaken) or `unasked` |
| `sized` | `w`, `h`, `layout`: the first build at the new shape |
| `began` | `turn`, `spinFrom` (rad), `ms`, `grow`: the page started drawing the turn |
| `drawn sent` | `turn` |
| `late` | `missed` (bool): the wait for a turn ran out (`missed`: none came) |

iOS's own turns are never sent to Dart: a 系统 turn has only `presentation` and `sized` on this side. A turn back's
`presentation` comes a few ms after its native `begin`, a turn to landscape's before it.

## `phone_report.py --turns`

Lines are grouped into turns by `turn` id where they have one, by time where they don't. Per turn, in ms from its
native begin: request → begin, `started` (and its outcome), `began`, `drawn`, the picture going (and why), and the
first move, from the request to when the turn starts to show (系统: the begin; 自绘: once the page has begun and the
picture is gone, since the picture hides the page's first frames). Failures: the fallback, `late`, a `stale` or
`unasked` outcome, a picture up over 100 ms, lost sends, and a native begin that ran another style than the page's
label. Lines a turn should have and doesn't are listed, not failed. Then per style (自绘, 系统): turns, turns with no
failure, each failure's count, and the timing medians (picture and first move also their worst). Presentation changes
no turn followed, requests no turn followed, and lines that fit no turn are listed after.

It doesn't grade angles: what the screen showed is `turn_video.py`'s.

## Older logs

1.0.0 (13) and (14) were turn test builds with 轮换测试: `turn cycle` lines (`index`, `of`, `label`, and `turn cycle
done` / `turn cycle off`) label each turn with the style it ran under, before the page's own `style`. (14)'s styles
were 系统 and 请求前关·(直接切 | 淡出 | 无截图)·(立即 | 等截图); (13) also had 原样 `legacy`, 移除 `remove`, 抵消
`counter`, 关动作 `noActions` and 不转 `noSpin`. Both also logged per-frame `frames` lines on each side, `began.held`,
Dart `released` and `picture gone`, and (13) native `animations` and `container`. `phone_report.py` still reads them:
the timeline shows the extra lines, a held turn moves once released, the per-frame and (13)-only lines are passed over
(their lost sends still count), and a label is checked against its native begin only for 自绘, 系统 and 请求前关.

Until 1.0.0 (15) the report also graded each turn's on-screen angle from the `frames` samples. That model (the window's
angle plus the page's drawn angle) misgraded (14)'s 请求前关 turns, which the recording showed clean: iOS turns the
window in 0 s under the picture, which the samples can't place against the page's frames, so turns back read as a 90°
ghost and 无截图 as a 180° back-and-forth sweep. It was removed with the lines it read.

## What a screen recording shows (`tools/turn_video.py`)

    uv run tools/turn_video.py local/differences/10-ours-rotate-testing-v5.MP4 --log logs/2026-10-20/<session>.jsonl

(`--ffmpeg PATH` when ffmpeg isn't on PATH or at `D:/Tools/ffmpeg/bin/ffmpeg`; `--crop TOP:BOTTOM` for another
phone's small player; `--frames` for every frame's angle, scale and inliers.) It decodes every frame at the
recording's own rate, 440 wide, into a temporary folder that is deleted when it ends: frames never go into the repo,
and neither do the recordings or logs (`local/` and `logs/` are gitignored). A turn is a run of frames that differ a
lot from the one before, whose two ends measure about 90° apart. Each frame's angle (clockwise; recordings stay
portrait-framed, so upright is 0° and landscape ±90°) comes from SIFT matches against the small player of the nearest
still upright frame, or against that whole frame while the player is out of sight.

Per turn: the first frame's jump, the sweep from there, one way or not, the settle time and the RMS error against the
official turn (90° along ease-in-out cubic(0.42, 0, 0.58, 1) over 300 ms, its start fitted up to 100 ms before the
first frame that moved). The verdict: `official-like` (a smooth 90° within 3° RMS), `system-like` (smooth but off the
curve), `spin` (a sweep of 135° or more), `cut` (a jump of 60° or more with no motion after) or `?` with the reason.
With `--log`, each turn gets its native turn id, method and style (the 轮换测试 label in (13) and (14) logs, else the
page's `presentation` style, else the native method's), the recording placed on the phone's clock by the offset that
best lines the detected turns up with the native begins of the same direction. A summary per style follows. Both
tools write UTF-8 whatever the console's code page.

09 (1.0.0 (13)): 系统 within 0.5° of the official curve (iOS's own turn on this phone is the same 300 ms ease-in-out);
the (13) methods mostly a jump to about −87° and a 180° sweep back. 10 (1.0.0 (14)) picked 请求前关·直接切·立即, the
official app's look, which became 自绘. The official app's own recording (01) turns back within 1.2° of the curve and to
landscape in about 250 ms (6°).
