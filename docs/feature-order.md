# BiliFast in Flutter: which features move first

Short version for KaiC. The full spec, with sources and checks for each slice, is [flutter-move-spec.md](flutter-move-spec.md).

Draft for KaiC, 2026-10-17. Scope: everything on BiliNative `main` today (milestone 1 and milestone 2 builds A and B).
Shape: Flutter screens, Dart BTR engine, AVPlayer in a native view on iOS (verdict.md). The Flutter app lives in the
BiliNative repo (`app/`) and ships as the same BiliFast app, reusing the existing login from the keychain. The Swift
app stays installable from TestFlight until slice 9 passes both phone checklists.

Order rule: the riskiest unknown first, then the path a user walks (home → video page → player → page body), each
slice usable on its own and checked on the phone before the next one builds on it.

## Slice 0: foundations (Windows only, no phone)

- API client and models: WBI, feed, view, playurl, history, comments, actions, danmaku (port `BiliAPI` with its tests
  and JSON fixtures).
- Pure logic from `AppLogic`: quality rules, count and time formats, resume point, autoplay, gesture math, history
  grouping, heartbeat schedule (port with tests).
- Login: read BiliFast's cookies from the keychain (`com.kaichuan.bilinative.cookies`), so no new login.
- Settings storage, the developer log sink to the PC (`tools/logserver.py` unchanged), crash reports.
- Done when: the ported tests pass on Windows; the app shows the logged-in name from the reused cookies.

## Slice 1: player core on the phone (the kill switch)

- AVPlayer in a native view; Dart engine and the HLS bridge (`DashHLS` + `LocalHTTP`, with the `hev1` rewrite) in a
  background isolate; direct mode with backup addresses; quality and codec choice; the stats overlay; PiP.
- Flutter drawn on top: play/pause, progress bar with seek drag, a test danmaku stream.
- Done when, on the phone: HDR and 杜比视界 look the same as the Swift app, PiP works, danmaku stays smooth at 120 Hz
  over the video, the seek drag works. If it fails here, stop and keep Swift.

## Slice 2: engine parity (Windows, simulated CDN)

- Port `RipperTests` (with `SimCDN`), then the rest of the engine: hurry mode, full-node rule, ban healing, damaged
  spans, kept prefetches, network changes, automatic connection count. URLSession transport on iOS.
- Done when: the tests pass, and the Dart bench matches Swift's `ripper-bench` on the same saved playurl.

## Slice 3: home and the video page shell

- 推荐 feed (two columns, pull to refresh, endless scroll), tab bar, opening a video page, swipe back from the edge
  and from the middle, the portrait player at the top of the page, autoplay and resume point.
- Done when: matches reference screens 01 and 03 side by side; swipe back works on the phone over every part of the
  page.

## Slice 4: player interaction

- Portrait, landscape and vertical-video chrome; tap, double tap, seek drag, brightness and volume drags, hold to
  speed up; full screen by rotation and by button, rotation lock; panels: 清晰度, 倍速, ⋮ more, 选集; end screens;
  screenshot.
- Done when: matches reference screens 04-06, 09, 15, 20-21, 25-27, and `m2-phone-checklist.md` build A's player
  items pass.

## Slice 5: danmaku

- Display layer (lanes, scroll/top/bottom), 弹幕设置 panel, block words, sending from portrait and landscape with the
  style panel.
- Done when: matches reference screens 07-08, 22-24; build A's danmaku items pass.

## Slice 6: page body

- 简介: uploader row with 关注, title with expand, meta line, 分P, 合集 sheet, related list.
- Actions: like, coin with the coin dialog, favourite with the folder sheet, 三连 (long press), 不喜欢 with the TV-login
  token, watch later.
- Done when: matches reference screens 03, 15-19; build B's 简介 and action items pass.

## Slice 7: comments

- 评论 tab, sorting, threads (评论详情 sliding over the page), the composer with emotes, likes on comments, the player
  shrinking and collapsing to the 继续播放 bar while scrolling.
- Done when: matches reference screens 10-14; build B's comment items pass.

## Slice 8: the rest of the app

- 历史记录, 我的 (what M2 has of it), settings, the web login screen for a fresh install, logout.

## Slice 9: page lifecycle and cutover

- Pages stacked on pages, a covered page pausing, PiP keeping a closed page alive and restoring it, one player per
  page, closed pages releasing memory, background and network-change behaviour.
- Done when: `m1-phone-checklist.md` and `m2-phone-checklist.md` pass in full on the Flutter build. Then the Swift
  app is retired and milestone 3 continues in Flutter.

## Android (any time after slice 2)

ExoPlayer in a native view reading DASH from the Dart engine, PiP through Android's own mode, sideloaded APK.
