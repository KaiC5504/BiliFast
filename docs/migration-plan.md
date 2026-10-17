# Moving BiliFast to Flutter: what to change first

Draft for KaiC's approval, 2026-10-17. Target shape (verdict.md, option B): Flutter for every screen, one Dart BTR
engine for iPhone, Android and Windows, and each phone's own player in a native view (AVPlayer on iOS, ExoPlayer on
Android) so HDR, Dolby Vision and PiP survive.

## Rules for the whole move

- BiliNative `main` stays as it is and keeps shipping to the phone until the Flutter app passes both phone
  checklists. No new Swift features; fix only what blocks daily use.
- BiliNative becomes the reference: its BiliCore tests, fixtures, docs and phone logs are the spec the Dart code must
  meet. Nothing gets rediscovered on the phone that a log already told us.
- The riskiest unknown goes first, so the plan can stop early and cheaply.
- One Bilibili login for the Flutter app, done in the app that becomes the final one (same repo and bundle id from
  the first phone build), so it is never repeated.
- Light testing on KaiC's account: engine work runs against the simulated CDN; live benches use one saved playurl.

## Step 0: finish what is pending on the Swift app (KaiC, phone)

Run the build A and B checklists (`docs/m2-phone-checklist.md`). Whatever they find is behaviour the Flutter version
must get right, so it is cheaper to learn it now. Fix only blockers in Swift.

## Step 1: phone proof of the hybrid player (kill switch, about 2 days + 1 TestFlight round)

The one thing that could still sink the plan is Flutter drawing over a native video view on the iPhone.

- New public repo for the Flutter app (from this spike), TestFlight pipeline copied from Kazumi
  (`flutter build ipa`, same signing and secrets pattern). KaiC: App Store Connect record and secrets, about 15 min.
- iOS plugin: an `AVPlayerLayer` in a native view. Its Swift side reuses BiliNative's player code where it fits
  (`Playback/PlaybackBuilder`, `Player/PlayerSurface`, `VideoPage/PiPKeeper`, `Player/OrientationController`) with its
  hard-won rules (never parent a hosting controller to a system controller).
- Feed it from the Dart engine through a Dart port of the HLS bridge (`DashHLS` + `LocalHTTP/PlaybackRouter`, about
  600 lines, with their tests ported first).
- Flutter on top: the portrait controls, a seek drag, swipe back, and danmaku from a saved segment.
- In-app QR login, the one login.
- Pass: HDR and 杜比视界 look like the Swift app; PiP works; danmaku stays smooth at 120 Hz over the video; drags and
  rotation to full screen work. Fail on danmaku: draw danmaku natively inside the plugin instead. Fail on HDR or
  gestures: stop, keep Swift.

## Step 2: engine parity on the PC (about 2-3 days, no phone, no account traffic)

- Port BiliCore's tests to Dart first: `RipperTests` (with `SimCDN`), `BiliAPITests` (same JSON fixtures),
  `DanmakuTests`, `AppLogicTests`, `DevLogTests`. They are the acceptance suite.
- Port the engine until they pass: hurry mode, full-node rule, ban healing, damaged spans, kept prefetches, network
  changes, automatic connection count. It runs in a background isolate from the start.
- Transport per platform behind one interface: `cupertino_http` (URLSession, HTTP/2) on iOS, `cronet_http` on Android,
  dart:io on Windows. Tests that assumed URLSession's per-host limit get a transport parameter.
- Port DevLog and the log sink to Dart, so phone bugs come with logs from day one (`tools/logserver.py` stays).
- Gate: Swift `ripper-bench` and the Dart bench on the same saved playurl; Dart equal or better on first MiB, jumps
  and node spread before it goes to the phone.

## Step 3: screens, in the order the app is used (about 3-4 days)

Each with Windows widget tests, and screenshots compared against `official-app-reference.md`.

1. Shell, 推荐 home, login, settings and developer page (log sink on/off, test crash).
2. Video page player: portrait and landscape chrome, gestures (`GestureMath` ported in step 2), full screen and
   rotation, quality, speed and danmaku panels, the danmaku layer, end screens.
3. Video page body: 简介, actions (三连, coin dialog, favourites, 不喜欢 via the TV token), comments with threads and
   the composer, related videos, 合集 and 分P.
4. 历史记录.

BiliNative sizes for scale: VideoPage 4.8k lines, Player 3.5k, Comments 2.1k, Danmaku 2.0k, Home 0.8k.

## Step 4: Android (about 1-2 days, can run beside step 3)

ExoPlayer (Media3) in a native view, reading DASH straight from the Dart engine's local server (no HLS bridge), PiP
through Android's own mode. APK sideloaded; no store needed.

## Step 5: cutover

The Flutter app passes `m1-phone-checklist.md` and `m2-phone-checklist.md` on the phone. Then BiliFast's TestFlight
moves to the Flutter build, BiliNative is archived as the reference, and milestone 3 continues in Flutter.

## Totals

About 8-11 days of agent time plus phone rounds. Step 1 alone decides whether the rest happens.
