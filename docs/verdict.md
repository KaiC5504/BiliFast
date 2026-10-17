# Verdict: should BiliFast move to Flutter?

2026-10-17. Spike: this repo (`D:\Repos\Apps\BiliFlutterSpike`), Flutter 3.47.7 (latest stable), media_kit 1.2.6 /
media_kit_video 2.0.1 (latest on pub.dev), measured on KaiC's Windows PC, overseas, home network.

## Answer: go, as Flutter UI with the native player kept on iOS

Updated the same day. KaiC: what made him drop PiliPlus was its design, not Flutter's feel. If Flutter can look like
the official app, Flutter is fine. It can: the official app's look is custom-drawn (pink tabs, cards, its own player
controls and panels), which is what Flutter does well. The spike's 推荐 feed came close to reference section 01 in an
hour.

That leaves picture quality as the one real problem, and it has a fix:

- Flutter itself cannot show HDR video. Every Flutter video plugin, Flutter's own AVPlayer-based `video_player`
  included, copies frames into an 8-bit texture (flutter/flutter#91241 for `video_player`, #127520 for HDR output).
  So switching or patching the Flutter player does not help.
- What does: on iOS, embed a real UIKit view with an `AVPlayerLayer` in the Flutter page (a platform view). That view
  is Apple's player, so HDR, Dolby Vision, AV1 hardware decoding, PiP and AirPlay all keep working as in the Swift app.
  Flutter draws everything around and on top of it.

Recommended shape:

| Part | iPhone | Windows (development) |
|---|---|---|
| Screens, gestures, controls, danmaku layer, comments, panels | Flutter | Flutter, same code |
| Video view | BiliNative's Swift player (AVPlayer, PiP, the HLS bridge) wrapped as a Flutter plugin | media_kit, direct links |
| Download engine | BiliNative's Swift BTR engine (BiliCore), unchanged | not needed to test screens |

The Dart engine port from this spike is then not needed in the app; it proved that Flutter is not the speed problem.

Risks to check on the phone first, before porting screens:

1. Flutter widgets drawn over a native view on iOS cost extra compositing. Danmaku moving at 120 Hz over the
   AVPlayer view is the case to try.
2. HDR shows through the platform view (it should: the layer is AVPlayer's own).
3. Gestures over the player (seek drag, swipe back, hold to speed up) and rotation to full screen, with Flutter
   receiving the touches above a native view.

The rest of this file is the original analysis: the measurements, and why media_kit alone is not enough on iOS.

## Measured: BTR in Dart vs one connection (Windows, media_kit/mpv)

Each video was played once in each mode: open, play 25 s, jump to the middle, play 15 s. The order alternated per
video, so the second run met warmer CDN nodes. KaiC was streaming video elsewhere during part of this run, which
adds noise to both modes. Same stream in both modes (mpv plays `hev1` HEVC directly, unlike AVPlayer's 直连 in M1).

| Video | Stream | | Starts playing | Stalls | Jump → playing again |
|---|---|---|---|---|---|
| BV1jt421t7XH | 4K HEVC 19 Mbps | **BTR** | **1.12 s** | **0** | **1.3 s** |
| | | 直连 | 2.33 s | 3, 26.9 s in all | 23.8 s |
| BV198S7B8E6C | 4K HEVC 10 Mbps | **BTR** | **1.09 s** | **0** | **3.1 s** |
| | | 直连 | 2.06 s | 1, 1.7 s | 20.5 s |
| BV1NKszezErg | 4K HEVC 2.9 Mbps | **BTR** | **1.68 s** | **0** | **1.0 s** |
| | | 直连 | 1.87 s | 2, 4.3 s | 2.6 s |
| BV1bMdEY1E2r | 1080P+ HEVC 1.3 Mbps | **BTR** | **1.47 s** | **0** | **0.5 s** |
| | | 直连 | 2.24 s | 1, 4.1 s | 1.4 s |

- On the 19 Mbps video, one connection delivered 1.6 MB/s, below the stream's 2.4 MB/s, so mpv's buffer never
  rose above 0 s. BTR peaked at 21 MB/s, held a 19-20 s buffer, and spread the bytes over Akamai (96 MB), aliov
  (139 MB), cosov (7 MB) and the two HK nodes (2 MB each).
- Bytes thrown away from losing backup copies and failed requests: 3-8% of what BTR downloaded.
- Logged out (480P, 4 feed videos): BTR started in 1.17-1.25 s vs 1.37-1.91 s; no stalls in either mode at that
  bitrate.
- Same pattern as the Swift app on the phone (`BiliNative/docs/m1-results.md`): BTR starts faster, does not stall,
  and plays again 0.5-3 s after a jump where 直连 took up to 24 s here (9-13 s on the phone in M1). The absolute
  numbers are PC numbers, not phone numbers.

## Picture quality on the iPhone with media_kit

Not run on the phone (no repo or TestFlight was set up, see below). These come from the code media_kit ships for
iOS, which leaves little doubt:

| | media_kit on iOS | Swift app (AVPlayer) |
|---|---|---|
| HEVC 8-bit (most 1080P/4K) | Hardware (VideoToolbox) | Hardware |
| HDR (真彩 HDR, 125) | Decoded in hardware, then forced to **8-bit** and shown as SDR | Real HDR on the XDR screen |
| Dolby Vision (杜比视界, 126) | Same as HDR: the HEVC Main10 base layer only, as SDR | Dolby Vision |
| AV1 | **Software** (dav1d). The A19 Pro's AV1 hardware is not used | Hardware |
| Picture in Picture | **None** | Yes, and it survives leaving the page |
| PC (this spike, for reference) | HEVC on the GPU (`d3d11va`) | — |

Why:

- media_kit's iOS libraries (`media_kit_libs_ios_video` 1.1.4, the latest on pub.dev) download libmpv build
  v0.6.0 from 2023: mpv 0.36, FFmpeg 6.0, dav1d 1.2.1. Upstream's unreleased `main` uses build v0.7.2, which pins
  the same mpv and FFmpeg. PiliPlus ships a fork whose build has FFmpeg 7.0.2.
- Every one of those builds carries the patch `ffmpeg-fix-ios-hdr-texture.patch`: on iOS, any video deeper than
  8 bits is converted to 8-bit BGRA ("iOS doesn't support 10 bit textures in GLES"). The plugin then renders
  through OpenGL ES into an 8-bit pixel buffer (`media_kit_video/ios/Classes/plugin/TextureHW.swift`). There is
  no path to an HDR display. media_kit issue #615 ("Video Player HDR Problem", open since 2023) shows the result
  next to the native player.
- VideoToolbox AV1 decoding entered FFmpeg in 8.0 (`libavcodec/videotoolbox_av1.c` is absent at tag n7.1).
- iOS Picture in Picture is an open, unmerged pull request (#1410).
- On these videos Bilibili labels the 杜比视界 track `hvc1.2.4` (plain HEVC Main10), so it plays, just as SDR.

## What moving would gain and lose

Gained:
- Screens run on the PC in a phone-sized window, with hot reload. Gesture and layout logic is testable on Windows:
  the five swipe-back widget tests here (`test/swipe_back_test.dart`) run in about one second.
- One codebase could also become an Android or desktop app.

Lost:
- HDR, Dolby Vision, AV1 hardware decoding and Picture in Picture (above).
- AVPlayer's own integration: AirPlay, lock-screen controls, and system playback behaviour would need plugins.
- UIKit's own behaviour. Flutter's Cupertino route gives the edge swipe back; the swipe from anywhere in the content
  (iOS 26) had to be written by hand here (`lib/ui/swipe_back_route.dart`). Rotation, sheets and system controls are
  Flutter's versions, not UIKit's. KaiC's call: the design matters, not this.
- A stable player library. media_kit's last pub.dev release was December 2025, and its iOS libraries are still the
  2023 build. PiliPlus depends on a community fork.
- The engine needs more work in Dart than it looks: dart:io speaks HTTP/1.1 only, so every request in flight holds
  its own connection. The spike already had to port BiliNative's fix for Akamai's per-host limit, and Akamai
  closing idle keep-alive connections shows up as failed requests (up to 7 per run). On iOS it would want
  `cupertino_http` (URLSession, HTTP/2) instead.

What still holds on Windows today, without Flutter: BiliCore (the engine, API, danmaku) already builds and tests on
the PC with `swift test`, and `tools/check-app.sh` compiles the app locally. The part only a Mac can test is UIKit
behaviour, and a Flutter app on the phone would need the phone for its own iOS-specific checks too (rotation, PiP,
safe areas, the player).

## Rough cost to redo milestones 1-2 in Flutter

BiliNative today: about 7,900 lines of engine and API code, 19,400 lines of SwiftUI app and 14,100 lines of tests,
built in two days.

| Piece | Estimate (agent time) |
|---|---|
| Finish the engine port (hurry mode, damaged spans, automatic connection count, node stats, network changes) | 0.5-1 day |
| API, danmaku, comments, history, favourites, coin and like calls and their models | 1 day |
| Screens: video page, player gestures, full screen and rotation, panels, danmaku layer, comments, 推荐, 历史记录 | 2 days |
| HDR, Dolby Vision, PiP: a native AVPlayer view embedded in Flutter on iOS, fed by the Dart engine | 2-4 days, uncertain |
| Phone test rounds and fixes | as many as the Swift app needed |

That comes to about 5-8 days to reach where the Swift app already is with the Dart engine. With the recommended shape
(the Swift player and engine wrapped as a plugin instead), the engine rows drop out: about 2-3 days for the plugin
and the phone checks above, then 2-3 days of screens. The player stays outside what Windows can test, but every
screen around it moves onto the PC.

## Not checked

- Nothing ran on the iPhone. A TestFlight build needs a new public repo and an App Store Connect record (about
  15 minutes of KaiC's clicks). The no-go rests on facts from media_kit's own code, so that test would confirm,
  not decide.
- Battery and heat of media_kit's OpenGL ES path vs AVPlayer.
- Dart's networking on iOS (the PC numbers use Windows' network stack).

## Account safety

KaiC logged in once, in the ghosthand test Chrome. The logged-in session made 8 API calls (`view` and `playurl` for
4 videos), the same as opening 4 video pages on bilibili.com. The app never held a cookie: it played those saved
playurl responses (gitignored `local/playurl/`, now deleted). Video bytes came from the CDN through signed links,
as the BiliFast build on the phone already fetches them.

## How to look at it yourself

1. `D:\Repos\Apps\BiliFlutterSpike\build\windows\x64\runner\Release\bili_flutter_spike.exe` (logged out, 480P).
2. The 推荐 feed shows two columns of cards. Tap one: the video plays with the stats panel underneath.
3. Switch between `BTR 多节点` and `直连`: the video restarts in that mode and the panel shows start time, stalls,
   download speed and the nodes in use. `跳到中间` measures a jump.
4. Drag the page right with the mouse, from the left edge or from the middle: it slides back to the feed.
5. `flutter test` runs the swipe-back tests.
