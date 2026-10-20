# The drawn turn's log lines

1.0.0 (13) carries every way of drawing the turn (开发者 → 旋转动画, `lib/device/turn_style.dart`) and logs each
turn on both sides. `tools/phone_report.py --turns` merges the two and grades each style. Once the phone has picked
one, the losing styles and the per-frame lines go, and the summary stays.

All lines are category `ui`. Every line has `wUs`, the wall clock in microseconds since the epoch (`Date()` natively,
`DateTime.now()` in Dart), so the two sides line up. Native lines also have `turn` (the host's id for the turn, from 1
per launch; 0 when there is no turn yet), `method` and `picture` (the `NativeTurnMethod` and `NativeTurnPicture`
names). Angles in the `frames` samples are in degrees, positive clockwise on screen. Fields hold strings, ints,
doubles and bools only; per-frame data is packed into strings.

## Native (`TurnProbe.swift`, `TurnTakeover.swift`, `DeviceChannel.swift`): `turn native <kind>`

| kind | fields besides the common ones |
|---|---|
| `request` | `request` (int), `mask`, `interface` (before), `animationsEnabled` (bool): Dart asked for a mask |
| `request returned` | `request`, `ms` (double): `requestGeometryUpdate` returned |
| `begin` | `angle` (rad), `seconds`, `animated` (bool), `fromW`, `fromH`, `toW`, `toH`, `animationsEnabled` (bool, before), `snapshotMs` (double, 0 with no picture) |
| `animations` | `phase` (`after super` or `next tick`), `found` (string, below), `removed` (int) |
| `alongside` | the coordinator's alongside block ran |
| `completion` | `cancelled` (bool) |
| `drawn` | `action` (`cut`, `fade`, `none` or `gone`): Flutter's turnDrawn arrived |
| `picture gone` | `why` (`drawn` or `fallback`) |
| `fallback` | the 0.5 s timeout fired before turnDrawn |
| `container` | `event` (`installed`, `lost` or `restored`): the counter method's container around the Flutter view |
| `frames` | `count` (int), `samples` (string, below) |

`found`: `;`-separated animations, each `layer|keyPath|class|duration|timing|additive|beginOffsetMs`. Layer names:
`window`, `window^1`, `window^2` (its superlayers, nearest first), `root` (the Flutter view), `container`,
`picture`.

`frames.samples`: one per CADisplayLink tick for 1.2 s from `begin`, `;`-separated, each `,`-separated:
`tMs` (since `begin`'s `wUs`), `gapMs` (since the last tick), `scene` (the summed angle of the window's superlayers),
`window`, `windowW`, `windowH`, `container` (empty when none), `root`, `picture` (empty when none), `pictureOpacity`
(empty when none). Angles and sizes are the presentation layers', so they show what was on screen.

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
| `frames` | `t0Us` (wall µs the samples count from), `count`, `samples`, `timings`, `worstBuildMs`, `worstRasterMs`, `slow` (frames over 16.7 ms) |

`frames.samples`: one per frame built while a turn runs, `;`-separated, each `,`-separated:
`tMs` (since `t0Us`), `angle` (deg, the page's drawn turn), `grow`, `boxL`, `boxT`, `boxW`, `boxH` (empty at rest),
`w`, `h` (the size laid out at). `frames.timings`: the engine's FrameTiming for the same window, `;`-separated
`buildMs,rasterMs,totalMs`.

The line is written once the turn has settled (300 ms with no frame), so logging never runs inside the turn.

## What the report computes per turn

The content's angle on screen at each display-link tick is `scene + window + container + root` plus the page's drawn
angle from the Dart frame one tick earlier (a frame shows one vsync after it is built). From that: where it starts
relative to the end (should be ±90°), the total sweep (90°, not 180°), whether it moves one way only, the biggest
step, the time to settle, how far the picture and the content disagreed when the picture went (the ghost), the
longest gap on each side, and the time from Dart's request to the first frame that moves.
