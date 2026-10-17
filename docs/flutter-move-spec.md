# BiliFast in Flutter: the spec for the move

Written 2026-10-17 for the session that does the work. It is the handover from the spike session: everything that
was decided, where every source lives, and the order to build in.

**Update 2026-10-17, slice 0:** KaiC moved the Flutter app out of BiliNative. It lives at the root of this repo
(`D:\Repos\Apps\BiliFast`, public `KaiC5504/BiliFast`), not in `BiliNative/app/`. Wherever this spec says
`BiliNative/app/` or `app/`, read this repo's root; BiliNative stays the Swift reference. The app identity (bundle id,
App Store record, keychain items) is unchanged, so builds still replace the Swift app and keep its login. The signed
workflow is plain `testflight.yml` in this repo, with its own `testflight` environment.

Reference documents next to this one:

| File | What it holds |
|---|---|
| `docs/reference/bilicore-inventory.md` | BiliNative's Swift package `BiliCore`, module by module: every endpoint with its signing, the engine's rules with their numbers, the HLS bridge, DevLog, and all 546 tests. The port's checklist. |
| `docs/reference/app-inventory.md` | BiliNative's SwiftUI app, feature by feature: files, settings keys, keychain format, demo screens, tests, CI, docs, and every hard-won rule with `file:line`. |
| `docs/reference/piliplus-map.md` | Where PiliPlus keeps what, which of its packages are licence-safe, and what never to take from it. |
| `docs/reference/testflight-flutter.md` | How this repo ships as the next BiliFast builds (workflow, build numbers, Info.plist). |
| `docs/verdict.md` | The spike's measurements and why the iPhone keeps AVPlayer. |
| `docs/feature-order.md` | The short version of section 6, for KaiC. |
| `docs/migration-plan.md` | The earlier plan. Superseded by this file where they differ. |

## 0. If you are the new session, start here

1. Read this file to the end. Then read `D:\Repos\Apps\BiliNative\CLAUDE.md` (the Swift app's rules, most of which still
   apply) and the two BiliNative inventories above. Open the PiliPlus map only when a slice points you to it.
2. KaiC's global instructions (decision profile, ghosthand, ios-testflight skill) load by themselves. Two hard floors:
   - never commit secrets;
   - shipped products never surveil users.
3. Load the `ios-testflight` skill before touching any workflow, signing or Info.plist.
4. Work slice by slice (section 6). Before each slice, show KaiC a short plan (what you will build, how he will check
   it) and wait for his go; small fixes inside a slice need no plan. Each slice ends with:
   - what was built, how it works and numbered test steps;
   - for phone slices, the TestFlight build number.
5. Don't re-open the decisions in section 2. Push back only with new evidence. KaiC wants a collaborator who
   challenges, not one who obeys, but he also hates re-litigating.

## 1. Goal

BiliFast (KaiC's iOS Bilibili client, `D:\Repos\Apps\BiliNative`, Swift/SwiftUI) moves to Flutter:
- **Everything milestone 1 and milestone 2 do today keeps working:** BTR multi-node playback, picture quality, PiP, the
  official-style player and video page, danmaku, comments, actions, history.
- **The UI looks like the official Bilibili app.** KaiC's words: "if Flutter can make it look exactly like Official app
  why not." The visual target is `BiliNative/docs/official-app-reference.md` and KaiC's screenshots in
  `BiliNative/local/official-app-reference/` (gitignored; open them with the Read tool before building a screen).
- **One codebase can also become an Android app** later.

**Done** = the Flutter build passes `BiliNative/docs/m1-phone-checklist.md` and `m2-phone-checklist.md` on KaiC's
iPhone 17 Pro Max. Then the Swift app retires and milestone 3 continues in Flutter.

## 2. Decisions already made (2026-10-17, KaiC's calls)

| Decision | Why |
|---|---|
| **Flutter for every screen.** | KaiC dropped PiliPlus for its *design*, not for Flutter's feel. The official app's look is custom-drawn (pink tabs, cards, its own player chrome and panels), which suits Flutter. The spike's 推荐 feed came close to reference screen 01 within an hour. |
| **The iPhone keeps Apple's player.** An `AVPlayerLayer` in a native view (a platform view) shows the video. Flutter draws everything around and on top of it. | Flutter cannot show HDR video: every Flutter video path copies frames into an 8-bit texture. Flutter's own `video_player` shows HDR wrong (flutter/flutter#91241), there is no HDR texture output (#127520, open), and media_kit's iOS build forces 8-bit (`ffmpeg-fix-ios-hdr-texture.patch`, OpenGL ES) and has no PiP. A native view keeps HDR, 杜比视界, AV1 hardware decoding, PiP and AirPlay exactly as today. |
| **Option B: one Dart BTR engine for every platform**, with each platform's own player: AVPlayer on iOS, ExoPlayer (Media3) on Android, media_kit on Windows for development. | KaiC wants Android to be possible. With A (wrapping the Swift engine as a plugin), Android would need a third engine in Kotlin. With B, Windows runs the real engine too. Risks and mitigations are in section 10. |
| **Same app, its own repo.** First "Same app, BiliNative repo"; changed by KaiC at the start of slice 0 to "build slice 0 in this folder, check the history, then create the public KaiC5504/BiliFast repo and push." | Same bundle id `com.kaichuan.bilifast` and App Store record (`ASC_APP_ID` 6823476667), so builds replace the Swift app and read its keychain login: no new login. The repo needs its own `testflight` environment (the same five secrets, one manual step). BiliNative stays untouched as the Swift reference. |
| **No new Bilibili login.** | KaiC: "I would only do it once to prevent bili from suspecting multiple logins." BiliFast's cookies are already in the keychain (section 4.6). For the PC, KaiC logged in once in the ghosthand test Chrome; that session stays the only other one. |
| **Light testing on KaiC's account.** | "no need for very detailed or bad testing that could cause my acc issues." Engine work runs against the simulated CDN. Live checks use a handful of calls; the whole spike used 8 logged-in API calls. |
| **No Mac.** | "Dont install in MAC, im planning to stop using it." Don't use `tools/mac-test.sh` or `ssh macrent` for this work. iOS checks run in GitHub Actions (`macos-26`) and on the phone. |
| **Swift BiliFast stays installable until cutover.** | Flutter builds become the next BiliFast builds in TestFlight. Installing one **replaces** the Swift app on the phone (same bundle id). The Swift builds stay under TestFlight → BiliFast → Previous Builds, so KaiC can go back at any time. No new Swift features; fix Swift only if something blocks daily use. |
| **Step 0 is done.** | KaiC on the Swift app's pending phone checklists: "Step 0 tested pretty much all is good. … Just changing into Flutter." The Swift app's current behaviour is the behaviour to match. |

## 3. Where everything is

| Path | What | Use it for |
|---|---|---|
| `D:\Repos\Apps\BiliNative` | The Swift app (public repo `KaiC5504/BiliNative`, branch `main`, at `a956b99` when this was written). | The reference for every behaviour. Swift sources `ios/Sources/App/` (132 files, 19.4k lines), package `ios/Packages/BiliCore/` (7.9k lines plus 8.2k lines of tests), docs `docs/`. |
| `D:\Repos\Apps\BiliNative\docs\background.md` | Real CDN behaviour, deviations from BTR, hurry mode, environment limits. | Read before touching the engine. Summarised at the end of `bilicore-inventory.md`. |
| `D:\Repos\Apps\BiliNative\docs\superpowers\specs\` and `plans\` | M1 and M2 designs and plans. | The *why* behind each Swift screen. The M2 design (`2026-10-17-m2-video-page-design.md`) explains the player and page. |
| `D:\Repos\Apps\BiliFast` (this repo, public `KaiC5504/BiliFast`) | The Flutter app at the root; the spike in `spike/`: WBI, feed, a minimal Dart BTR engine, media_kit playback on Windows, swipe back. | The app, these docs, and spike code to carry over (section 11). |
| `D:\Repos\Apps\PiliPlus` (GPL-3.0, `bb2d86ca`) | A Flutter Bilibili client. | Endpoints and formats only, never code (`piliplus-map.md`). |
| `D:\Repos\Apps\Kazumi` | KaiC's Flutter fork, shipped to TestFlight by GitHub Actions. | The Flutter signed-build steps (`testflight-flutter.md`). |
| `D:\Repos\Apps\Bilibili-thread-ripper` | BTR, the JS engine BiliNative's Swift engine was ported from (MIT). | Read at tag `2026.10.8.1` only: `git -C D:\Repos\Apps\Bilibili-thread-ripper show 2026.10.8.1:src/idm-downloader.js`. Port from the Swift version, not from BTR: Swift carries the phone fixes. |
| `C:\Users\KaiChuan\scoop\apps\fvm\current\versions\3.47.7` | Flutter 3.47.7 (Dart 3.13.5), latest stable on 2026-10-17. | `fvm flutter …` (flutter is not on PATH). Check for a newer stable before slice 0 and pin one version in `.fvmrc`, pubspec and the workflows. |
| `D:\Tools\Swift` | Swift 6.4.1 for Windows. | Run the Swift tests and `ripper-bench` as the reference: `swift test --package-path ios/Packages/BiliCore` in BiliNative. |
| `BiliNative/tools/logserver.py` | The PC log receiver (`uv run tools/logserver.py`, port 47321, Bonjour `_bilinative-log._tcp`). | Unchanged. The Flutter app posts the same NDJSON events to it. |

## 4. Target architecture

### 4.1 Layers

| Layer | iPhone | Android (later) | Windows (development) |
|---|---|---|---|
| Screens, gestures, chrome, panels, danmaku, comments | Flutter | Flutter | Flutter (same code) |
| Video view | `AVPlayerLayer` in a native view (Swift, in `ios/Runner/`) | ExoPlayer in a native view (Kotlin) | media_kit (`Video` widget) |
| What the player reads | HLS from the Dart local server (`master.m3u8` → byte-range segments of the DASH files) | DASH (an MPD built in Dart) from the same local server | The same local server: EDL as in the spike, or the HLS playlists if mpv takes them |
| Download engine | Dart BTR engine in a background isolate | the same | the same |
| HTTP underneath the engine | `cupertino_http` (URLSession, HTTP/2) | `cronet_http` | dart:io |
| API client | Dart port of `BiliAPI` | the same | the same |

### 4.2 Folders in BiliNative

```
BiliFast/                      this repo: the Flutter app (pubspec name bilifast)
    packages/bili_core/        pure Dart, no Flutter import: runs with `fvm dart test` on Windows
      lib/src/shared/          ByteRange, ContentRange, MediaSegment, clocks
      lib/src/devlog/          LogEvent, Logger, Redactor, FileSink, NetworkSink, AckStore/Replay
      lib/src/danmaku/         ProtobufReader, DanmakuElem/Segment, Filter, Timeline, LaneLayout, MidHash
      lib/src/api/             BiliClient, WBI, AppSigner, CookieJar, all models, RichText, LinkParser, TrackSelector
      lib/src/dash_hls/        SidxParser, InitSegmentFixer (hev1→hvc1), CodecMapper, PlaylistBuilder, (MPD builder for Android)
      lib/src/engine/          the BTR port (Resolver … RipperSession) behind a RangeTransport interface
      lib/src/local_http/      PlaybackRouter, RangeRequest; the dart:io server itself
      lib/src/logic/           AppLogic: QualityRules/Names, ResumePoint, Autoplay, GestureMath, Heartbeat, History grouping, formats
      bin/ripper_bench.dart    the counterpart of Swift's ripper-bench
      test/                    ports of the Swift tests, SimCDN included
      LICENSE-BTR.txt          BTR's MIT notice (from BiliNative's Ripper folder)
    lib/                       the Flutter app: app shell, home, video_page, player (+chrome, panels, gestures), danmaku,
                               comments, history, account, settings, devtools, shared, demo (fixtures)
    ios/Runner/                Swift: player registry and view, PiP, orientation, device controls, frame capture,
                               keychain, log-server discovery, crash reports
    android/                   later: ExoPlayer view, PiP
    windows/                   runner window 440×880 ("BiliFast"), like the spike
    test/                      widget tests (Windows)
    integration_test/          simulator tests run in CI
```

A separate pure-Dart package keeps the 546 ported tests fast and Flutter-free, as `BiliCore` is today.

### 4.3 Engine, transport and the local server

- **Port the Swift engine's structure, not the spike's.** Swift's `RipperSession.read(track, range)` takes one
  byte-range per player request, which is AVPlayer's shape (whole SIDX segments). The spike's `session.dart` was
  reshaped for mpv's open-ended ranges. Keep that only as a Windows adapter.
- **`RangeTransport` interface** (Swift `Transport.swift`):
  - `fetch(url, range)` returns status, lowercased headers and a body stream once headers arrive;
  - `connectionsPerHost`;
  - cancelling, or dropping the body, cancels the request at once, so a losing hedge copy gives its connection back
    immediately.
  - Implementations: dart:io (Windows and tests), `cupertino_http` (iOS: HTTP/2 to the mirrors, URLSession's
    8-per-host limit for Akamai), `cronet_http` (Android). Licences: BSD, from the Dart team.
- **Background isolate.** The engine and its `HttpServer` (dart:io, bound to `127.0.0.1`, port 0) run in their own
  isolate from day one, so 20+ MB/s of piece handling never touches the UI thread that draws danmaku. The UI isolate
  gets stats and node states over a `SendPort`.
  - Check in slice 1 that `cupertino_http` works from a background isolate.
  - If it doesn't, keep the transport on the main isolate and stream bytes over ports, and measure the frame times.
- **The local server follows `LocalServer.swift` and `PlaybackRouter.swift`:**
  - paths `/<token>/master.m3u8`, `v.m3u8`, `a.m3u8`, `v.mp4`, `a.mp4`, with a 128-bit random token;
  - GET and HEAD only, 206 with `Content-Range`, 416 with `bytes */total`, `Connection: close`;
  - the patched init and index served from memory as a prefix;
  - a client disconnect cancels the engine read.
- **iOS can silently take a suspended app's listening socket.** Before every load and after returning from the
  background, probe the server over loopback (`answers()` in Swift); if it doesn't answer, rebind and give the player
  the new URLs. This caused build 1's "first BTR video after a long background fell back to direct".
- **直连 (direct) mode on iOS:** the playlists still come from the local server, but their segment URIs point at the
  CDN. The native side gives AVPlayer the `User-Agent` and `Referer` headers through `AVURLAssetHTTPHeaderFieldsKey`.
  This replaces Swift's custom-scheme resource loader (`DirectPlaylistLoader.swift`). If AVPlayer refuses mixed hosts,
  port the resource loader instead.
- **Signed media URLs expire.** Refresh them 300 s before their `deadline` (`PlaybackController.urlMarginSeconds`)
  through `session.replaceURLs`.

### 4.4 The player interface

One Dart interface (`BiliPlayer`), three implementations: `IosPlayer`, `AndroidPlayer` (later) and `WindowsPlayer`
(media_kit, from the spike's `lib/playback.dart`). Use **Pigeon** (Flutter team, BSD) for typed platform channels.

**Commands**
- `create() → id`;
- `load(masterUrl, headers, startSeconds, autoplay)`;
- `play`, `pause`, `seek(seconds, precise)`, `setRate`;
- `setFit(fit|fill|stretch|16:9|4:3)`, `setMirrored`;
- `startPiP`, `stopPiP`, `setAutoPiP(bool)`;
- `captureFrame() → saved|failed`;
- `dispose(id)`.

**Events** (a stream per player)
- position (about 10 Hz, with the host clock time of the reading), duration, buffered ranges;
- playing / paused / stalled (with the 0.75 s 卡顿 rule from `StallFilter`), ended, error, rate;
- presentation size;
- PiP state, and the PiP restore request;
- AVPlayer access-log and error-log entries (DevLog `player` events).

Danmaku extrapolates the position each frame from the last reading and the rate, so it moves smoothly at 120 Hz
between position events.

**Native side (iOS)**
- A `PlayerRegistry` owns each `AVPlayer`, its host view (port `PlayerHostView.swift`: a plain `UIView` whose video
  subview's `layerClass` is `AVPlayerLayer`), its `AVPictureInPictureController` and an `AVPlayerItemVideoOutput` for
  screenshots.
- The Flutter platform view (`UiKitView`, view type `bilifast/player`) only **attaches** an existing host view. Rules
  this gives:
  - **A player can outlive its widget.** PiP keeps playing after the page closes, and a restored page reattaches the
    same player (`PiPKeeper.swift`).
  - **One AVPlayer per page.** The layer and PiP stay attached across parts (`VideoPageModel.swift:38-40`).
  - **Disposal is explicit.** A closed page that PiP does not hold calls `dispose`. Swift's `PageReleaseTests` exists
    because closed pages never freed.
- **The native view takes no touches.** Flutter's gesture layer sits above it and handles taps, drags and swipe back.
  Whether Flutter on iOS then gets every touch without delay is a slice-1 phone check. Try the platform view gesture
  blocking policies, and real touches.
- The audio session is set natively at launch to `.playback` / `.moviePlayback`, as `BiliNativeApp.swift` does.

### 4.5 Orientation, brightness, volume

- **Port `OrientationController.swift` as a native channel** (`begin`/`end(owner)`, `mask`, `presentation` events,
  `awaitingLandscape`, the lock). Don't rely on `SystemChrome.setPreferredOrientations` alone: the Swift rules exist
  because of real phone bugs (section 7).
- **Full screen is the same page rotated** (a layout switch), never a new route.
- **Brightness and volume:** port `DeviceControls.swift`. A hidden `MPVolumeView` slider sets the volume and stops the
  system volume HUD, and it exists only in full screen. The saved brightness is restored when leaving. The MIT packages
  `screen_brightness` and `flutter_volume_controller` are a fallback.

### 4.6 Login, keychain and storage

- **Cookies:** the keychain generic password with service `com.kaichuan.bilinative.cookies`, account `bilibili`,
  accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and no access group. The value is a JSON object of
  cookie name → value (`App/Account/KeychainStore.swift`).
  - Read and write it through a small native channel in exactly this format. `flutter_secure_storage`'s default service
    name would not match.
  - Writing the same format means going back to a Swift build keeps the login.
- **TV token (不喜欢):** service `com.kaichuan.bilinative.apptoken`, account `bilibili`, raw UTF-8
  (`AppTokenStore.swift`).
- **Never log a cookie or token.** Port `Redactor` first, and route every log line through it.
- **After a failed keychain read, block writes** until a read succeeds or the user logs in or out
  (`AppEnvironment.swift:50-52`). A transient failure must not wipe the login.
- **Settings:** the keys and defaults from `AppSettings.swift` (table in `app-inventory.md`, "Settings"), stored with
  `shared_preferences`.
  - Its iOS backend prefixes keys with `flutter.`, so on first launch copy the Swift app's `UserDefaults` values once
    through the native channel: node, quality, codec, BTR, overlay, autoplay, loop, fit, `coin.alsoLike`,
    `danmaku.settings`, `home.recents`, `emotes.recent`, `playback.failedCodecs`.
- **Fresh install / logged out (slice 8):** a web view on `https://passport.bilibili.com/login`.
  - Bilibili's page does password, SMS, QR and captcha.
  - Clear stale bilibili cookies first. Once a non-empty `SESSDATA` appears, take every bilibili-domain cookie into the
    jar (`LoginView.swift`).
  - Needs a web view that can read cookies: `flutter_inappwebview` (Apache-2.0) or a native `WKHTTPCookieStore` call.
    `webview_flutter`'s cookie manager can't read them.
- **On the PC, no account by default.** The Windows app runs with demo data or logged out. Live logged-in checks use
  responses saved from the ghosthand test Chrome into gitignored `local/` (section 5), never by copying that Chrome's
  cookies into the app unless KaiC says so.

### 4.7 Logs and crash reports

- Port DevLog first, in slice 0:
  - **Event shape:** `{t, seq, session, level, cat, msg, f}`.
  - **Categories:** app, api, engine, server, player, ui.
  - **Redactor:** applies to every message and field.
  - **FileSink:** 20 MB.
  - **NetworkSink:** NDJSON `POST /logs` every 500 ms, buffer 10,000, 2,000 per batch, backoff to 30 s.
  - **Ack and replay:** unconfirmed events are resent.
- `tools/logserver.py` stays as it is.
- **The phone finds the PC** through Bonjour `_bilinative-log._tcp` (port `LogServerDiscovery.swift`, a 32-line
  `NWBrowser`, as a channel) or a manual `IP:port`. This needs `NSLocalNetworkUsageDescription` and
  `NSBonjourServices`.
- **Crashes:**
  - Dart errors from `FlutterError.onError` and `PlatformDispatcher.instance.onError`;
  - native crashes and hangs from MetricKit (port `CrashReporter.swift`).
  - Both go out as `app` events with message `crash` / `hang`. A big stack is split into parts that share a `report`
    id.
- **The network sink and the 开发者 page are compiled in only for dev builds** (a `DEV_TOOLS` define). The Swift app
  ships `DEV_TOOLS` in Release too, which `m1-deferred.md` notes as something to fix before any public release. Keep
  the same switch.

### 4.8 Demo data and screenshots

- Port the `-DemoData` idea: on Windows a `--demo` argument, on iOS `--dart-define=DEMO=true` in CI builds. Canned
  responses come from BiliNative's `ios/Sources/App/DebugSupport/DemoFixtures*.swift` (demo ids `BV1Dm4y1A7aa`, `bb`,
  `cc`; video A has 2 parts and a 合集 with two sections) through a fake transport, so no network or account is
  involved.
- Each screen gets a demo route (the Swift `-DemoScreen` names, listed in `app-inventory.md` section 6), so widget
  tests, the Windows app and CI screenshots can open any screen directly.
- **Comparing with the official app:** take a Windows screenshot of the demo route (ghosthand `screenshot` of the
  440×880 window) and read the matching reference image from `BiliNative/local/official-app-reference/`. Fonts differ
  (Windows draws Chinese in Microsoft YaHei, iOS in PingFang SC), so compare layout, spacing and colour, not pixels.
  Never commit those reference images.

### 4.9 Packages

- Licence-safe and useful: see `piliplus-map.md`. Check each licence at the version you pin.
- **Default to the Flutter SDK plus the Dart team's packages:** `http`, `cupertino_http`, `cronet_http`, `crypto`,
  `pigeon`, `shared_preferences`, `path_provider`, `connectivity_plus`, `leak_tracker`.
- Add `media_kit` (Windows only) and `flutter_inappwebview` (login).
- **No GetX, no Hive, no GPL.** State is plain `ChangeNotifier` / `ValueNotifier` models, the same shape as the Swift
  `@Observable` models. Add a state library only if one is clearly needed.
- **Lints:** `flutter_lints` plus `strict-casts`, `strict-inference` and `strict-raw-types` (KaiC likes strict
  settings).

## 5. Rules

- **Secrets:** never commit, print or log cookies, tokens, `BILI_APP_KEYS`, signed playurl responses, or anything under
  `logs/` or `local/`. Delete imported cookie files at once. BiliNative is a **public** repo.
- **KaiC's account:**
  - No second login anywhere.
  - Few live calls.
  - No loops against the API: no stress tests, no automated feed crawling. One logged-in session made 8 calls for the
    whole spike; stay in that range per slice.
- **Saving a playurl for PC benches:**
  - In the ghosthand test Chrome (KaiC is logged in there), open the video page and call `browser_evaluate` with a
    `filename` so the JSON is written to disk without passing through the conversation.
  - Keep it in gitignored `local/` and delete it after the bench.
  - The spike did exactly this.
- **Licences:**
  - PiliPlus (GPL-3.0) and ATV-Bilibili-demo (GPL-2.0): read only, never copy.
  - BTR (MIT): keep `LICENSE-BTR.txt` next to the engine port.
  - PiliPlus's coin art and icon font: reuse BiliNative's `ios/Resources/Borrowed/` copies (KaiC's personal-use call);
    nothing else.
- **UI:**
  - Simplified Chinese text.
  - Layout and colours follow the official app, but no Bilibili logo or wordmark. Draw our own TV-face thumb.
  - Colours from `Shared/Theme.swift`: pink `#FF6699`, text `#18191C`, secondary text `#9499A0`, page grey `#F1F2F3`.
- **Tools:**
  - ghosthand first for any screen or browser work (`read`/`screenshot` the Windows app; the test Chrome through
    `ghosthand-browser`).
  - Flutter windows often have a broken accessibility tree. When `read` comes back thin, use `screenshot`.
  - Ask KaiC before any `keys` call with `allow_focus=true`.
- **GitHub API budget:**
  - Never `gh run watch`, and never poll in a loop.
  - Check a TestFlight run once, about 20 minutes after `start`.
  - Start long waits in the background so KaiC can keep talking.
- **Repo hygiene:**
  - Work on `main` here. Commit, push and Actions runs are authorised.
  - Never start a signed build before the gate for that slice is green: PC tests, plus the compile check.
  - In BiliNative only the docs change; the Swift app stays as it is.
- **Speed first** (KaiC's call): ship to his phone once the gate is green, let him report, fix in the next build.

## 6. The slices

The rule: the riskiest unknown goes first, then the path a user walks (home → video page → player → page body). Each
slice is usable on its own and ends with a phone check before the next one builds on it.

The tables name:
- what to port from BiliNative (paths under `ios/Sources/App/` = `App/`; package paths under
  `ios/Packages/BiliCore/Sources/`);
- what to look up in PiliPlus;
- the reference screens;
- the phone checklist items that must pass. Item numbers are in `BiliNative/docs/m2-phone-checklist.md`; "M1" means
  `m1-phone-checklist.md`.

### Slice 0: foundations (PC only, no phone, no account traffic) · about 1.5 days

| | |
|---|---|
| Set up | `fvm flutter create --org com.kaichuan --project-name bilifast --platforms ios,android,windows .` at this repo's root, the spike moved to `spike/`; Info.plist and project settings from `testflight-flutter.md` plus `CADisableMinimumFrameDurationOnPhone` = true (120 Hz); `.fvmrc`; Windows runner 440×880 titled BiliFast. |
| Port, tests first | Into `packages/bili_core`: `BiliShared`, `DevLog`, `Danmaku`, `BiliAPI`, `AppLogic`. Translate each XCTest file to `package:test` before the code (BiliSharedTests 6, DevLogTests 39, DanmakuTests 41, BiliAPITests 179, AppLogicTests 47). `BiliAPITests/Fixtures.swift` raw strings become Dart fixture constants; `FakeHTTP` becomes a fake `http.Client`. |
| Reuse from the spike | `lib/api/wbi.dart` (check it against `WBITests`' reference vector), the `SwipeBackPageRoute` and its 5 widget tests. |
| Native, written but checked only in slice 1 | Keychain read/write channel (`KeychainStore.swift`, `AppTokenStore.swift`). |
| Pipeline | `.github/workflows/app-compile.yml` (analyze, test, `flutter build ios --release --no-codesign`); `.github/workflows/testflight.yml` and `scripts/testflight.py`, then `start --dry-run` (`testflight-flutter.md`). |
| BiliNative docs | `CLAUDE.md`: Status entry, where the Flutter app lives now, the rented Mac marked as no longer used. `docs/background.md`: it still says Flutter was rejected for feel; correct it to KaiC's actual reason (PiliPlus's design). |
| Done when | `fvm dart test` in `bili_core` passes every ported test; `fvm flutter test` passes; the compile check is green; the TestFlight dry run is green. |

### Slice 1: the player core on the phone (the kill switch) · about 2 days + 1 TestFlight round

The one thing that can still sink the move: Flutter drawing over a native AVPlayer view on the iPhone.

| | |
|---|---|
| Build, Dart | `DashHLS` (SidxParser, InitSegmentFixer with the `hev1`→`hvc1` rewrite, CodecMapper with the Dolby Vision → `SUPPLEMENTAL-CODECS` mapping, PlaylistBuilder) and `LocalHTTP` (PlaybackRouter, RangeRequest), with DashHLSTests 36 and LocalHTTPTests 13 ported first. A first engine in the isolate: the spike's `lib/ripper/` rebuilt on `RangeTransport` with Swift's `read(track, range)` shape. `TrackSelector` quality and codec choice; 直连 with backup URLs; the stats overlay (`App/Playback/OverlayStats.swift`, `App/Player/StatsOverlay.swift`). |
| Build, native | `PlayerRegistry` + `PlayerHostView` + PiP (`App/Player/PlayerHostView.swift`, `PlayerSurface.swift`), the audio session, the keychain channel live. |
| Build, Flutter on top | Play/pause, a progress bar with seek drag, a test danmaku layer fed by the real `seg.so` of the video (port `DanmakuTimeline` + `LaneLayout`, painter from `App/Danmaku/DanmakuView.swift`), the account name from `nav` (proves the keychain login reuse), a BV input field. |
| PiliPlus | Nothing needed. |
| Phone check (KaiC) | 1. The app opens logged in as him, with no login screen. 2. Paste a 4K HEVC video, a **真彩 HDR** video and a **杜比视界** video (ask KaiC for BV ids; he has 大会员). Compare each against the **official Bilibili app**: the HDR highlights must look the same. The Swift app can't sit next to it, because the Flutter build replaces it. 3. PiP: ⋮/button and swipe home keep playing (item 22). 4. Danmaku stays smooth over the playing video at 120 Hz. 5. Seek drag on the bar works (item 10). 6. BTR starts quickly (M1 feel). Engine speed is not judged here, since parity is slice 2. |
| Pass / fail | **Pass:** 1-5 hold. **Danmaku stutters:** draw danmaku natively inside the host view (port `DanmakuView.swift`) and re-check. **HDR wrong, PiP broken, or touches unreliable over the view:** stop, tell KaiC, and keep Swift. |

### Slice 2: engine parity (PC, simulated CDN) · about 2 days

| | |
|---|---|
| Port, tests first | `RipperTests` (185 tests, 3,665 lines). `SimCDN` first (per-node first byte, speed, status, truncate, stall, wrong range, lying totals, cold ranges, refused queries, Akamai's damaged span, the 8-per-host HTTP/1.1 queue), then `LoopbackServer` for the real transports. |
| Port | The rest of `Ripper`: AutoConcurrency (ladder 8…64, trials, 412/429 back-off), BanList with healing and loss moments, damaged spans, NodeStats, HurryPlacement, PrimaryAssigner, Meter, PieceDownloader (hedges, resume prefix, round pauses), RangeDownloader (meta race, probe head, rescue reserve), RipperSession (prefetch within 45 s, adopted prefetches that survive a cancel, seek detection, playhead eviction, network change, URL replacement, fatal reporting). Numbers in `bilicore-inventory.md` section 4. |
| Transports | `cupertino_http` (iOS) and dart:io (Windows), both through the same tests; `cronet_http` when Android starts. |
| Bench | `bin/ripper_bench.dart` with Swift `ripper-bench`'s flags. On one saved playurl (section 5): `swift run --package-path ios/Packages/BiliCore ripper-bench --playurl local/playurl.json --mb 8` vs `fvm dart run bin/ripper_bench.dart --playurl …`, then `--seeks 6`. |
| Done when | All ported tests pass on Windows. The Dart bench equals or beats Swift on first-MiB time, seek reads and node spread. Then it goes to the phone inside slice 3's build. |

### Slice 3: home and the video page shell · about 1 day

| | |
|---|---|
| Port | `App/Home/` (HomeView top row with 粘贴链接或BV号 and the paste button, FeedModel: refresh at index 1, dedupe by bvid, up to 3 empty pages, generation guard; FeedCard; RecentStore 最近打开, 30 max; AvatarMenu as the 我的 stand-in), `App/VideoPage/AppNavigator.swift` (Navigator 1.0 + the spike's `SwipeBackPageRoute`), the portrait player box at 16:9, autoplay and resume (`AppLogic` ResumePoint, `lastPlayCid`, history's progress), heartbeats (`HeartbeatSchedule`, logged in only). |
| PiliPlus | `lib/pages/rcmd/` only to cross-check the web feed parameters. |
| Reference | Screens 01 and 03. Keep BiliNative's scope (top row + 推荐, avatar menu). The official app's tab bar and category tabs come later, as new features. |
| Phone check | Items 1-4, 43, 45; 31 (history position shows in the official app); 72 (the bar moves); the edge swipe back (part of 70, 73). |

### Slice 4: player interaction · about 1.5 days

| | |
|---|---|
| Port | `App/Player/Chrome/` (ChromeState, PortraitControls, LandscapeChrome, VerticalChrome, ProgressBar with chapters and the TV thumb, PlayerHUD, EndScreens, 3 s hide), `App/Player/PlayerGestureView.swift` + `GestureMath` (tap, double tap, hold 0.35 s → 2×, horizontal seek at 90 s per width, 10 pt axis lock, brightness left / volume right in full screen only, 25 pt edges left to the system), orientation and device controls (section 4.5), `App/Player/Panels/` (SidePanel: right panel in landscape, bottom sheet in portrait, as in-page overlays; Quality with 大会员 and the 125 subtitle, Codec, Speed 3.0X…0.5X, More: 稍后再看, 小窗播放, 定时关闭 with custom 1-180 min, 自动连播, 循环播放, 镜像翻转, 画面尺寸, the 测试 card; Episodes), screenshot (`FrameCapture.swift` via `AVPlayerItemVideoOutput` → Photos). |
| PiliPlus | Not needed: BiliNative has all of it. |
| Reference | Screens 04-06, 09, 15 (portrait controls), 20-21, 25-27. |
| Phone check | Items 5-25, 69. Gesture changes also need a real-touch UI test in CI (section 8). |

### Slice 5: danmaku · about 1 day

| | |
|---|---|
| Port | `App/Danmaku/` (DanmakuController: segments ahead of the playhead, the filter, block rules, the uploader-closed notice, your own danmaku in a white box; DanmakuSettingsPanel with 显示区域 5 stops, 不透明度, 字体大小, 弹幕速度 [11, 9, 7, 5.5, 4] s, the type blocks, 重复弹幕隐藏, 底部字幕区域防挡, 重置; BlockRuleStore cached 10 min, synced with the server; BlockWordsView; DanmakuSendBar following the keyboard by hand, 100 chars; DanmakuStylePanel 25/18, modes 1/5/4, 12 colours + the VIP gradient). |
| PiliPlus | `lib/http/danmaku.dart` only if adding 点赞/举报/撤回 later. |
| Reference | Screens 07-08, 22-24. |
| Phone check | Items 26-30, 52. |

### Slice 6: the page body · about 1 day

| | |
|---|---|
| Port | `App/VideoPage/` IntroTab, UploaderRow + 关注 (unfollow asks 确定不再关注？), TitleBlock (活动 tag, ⌄ to the BV id, description rich runs with seeking timestamps and links), tags, PartStrip/PartList, CollectionSheet (正序/倒序, playing in pink), RelatedList (⋮ 稍后再看), ActionRow + TripleRing (hold 0.2 s + 1.2 s = 三连), ActionsModel (optimistic with rollback per field), CoinDialog (borrowed crates and 22娘, balance asked up to 3 times, 同时点赞内容), FavouriteSheet (only the difference is sent, 新建收藏夹 with 私密), share (native share sheet + `share/add`), 不喜欢 with TVLoginModel/TVLoginSheet (needs `BILI_APP_KEYS`; greyed with 此版本不支持不喜欢 otherwise), the online count every 30 s. |
| PiliPlus | `lib/http/fav.dart:633-740` and `lib/http/video.dart:672-720` to cross-check fav and follow parameters if a call fails. |
| Reference | Screens 03, 15, 18, 19. |
| Phone check | Items 47-49, 51, 53-61. |

### Slice 7: comments · about 1 day

| | |
|---|---|
| Port | `App/Comments/` (CommentsModel: hot/time, offset paging, pinned on page 1, closed sections 12002/12061, like/踩/delete with rollback; CommentsTab, CommentRow with badges, LV, pictures, fan card; PictureViewer; ThreadView sliding over the tab row, closed first by a swipe; Composer + ComposerModel with "回复 @name :" and drafts that survive; EmotePanel 最近使用/所有表情/颜文字; RichTextView), `App/VideoPage/CollapsingPlayer.swift` (shrinks only while paused and not ended, 56 pt 继续播放 bar). |
| PiliPlus | `reply_item_grpc.dart:723-960` only to see rich-text cases BiliNative doesn't cover yet (笔记 cards, votes). |
| Reference | Screens 10-14. |
| Phone check | Items 50, 62-66, 68, 74, 76. |

### Slice 8: the rest of the app · about 0.5 day

| | |
|---|---|
| Port | `App/History/` (cursor paging, 今天/昨天/date groups, 已看完, resume from progress), `App/Settings/SettingsView.swift` (加速: node, BTR; 数据: reset codec memory, clear recents, clear logs; 开发者 in dev builds: 发送日志到电脑, the Bonjour list or manual IP, export logs, 测试崩溃), login web view and logout (clears the jar, the keychain items, the token and the web view data). |
| Reference | Screen 28 (history, if moving to the official layout), 02 (我的, later). |
| Phone check | Items 44, 46, 59. Logging out and back in is the one extra login this allows; skip it unless KaiC wants it tested. |

### Slice 9: page lifecycle and cutover · about 1 day

| | |
|---|---|
| Port | Stacked pages (`RouteAware` + a `RouteObserver`: a covered page pauses and resumes without reloading), `PiPKeeper` (a closed page stays alive while PiP plays it; restore pushes it back; another video releases it), background rules (without PiP the sound stops; autoplay is skipped in the background without PiP), network change (`connectivity_plus` or a native path monitor) → `networkChanged`, the URL refresh, memory warnings → `dropCache`, `leak_tracker` in widget tests for closed pages, and a native player count back to zero after pops. |
| Phone check | Items 33-42, 67, 70, 71, 75, 77, item 32, and the whole M1 checklist (BTR vs 直连 timings on 4 videos). |
| Cutover | Both checklists pass in full → update BiliNative `CLAUDE.md` (the Flutter app is the app; `ios/` is archived reference), retire `testflight.yml` (Swift) or leave it unused, and milestone 3 continues in Flutter. |

### Android (any time after slice 2) · about 1-2 days

- **ExoPlayer (Media3) in a native view.** Media3 is Apache-2.0.
- **It reads DASH:** an MPD built in Dart (SegmentBase with the index ranges) pointing at the local server's `v.mp4` /
  `a.mp4`. There is no HLS bridge and no `hev1` rewrite.
- **HDR goes through a `SurfaceView`.** PiP is Android's own Activity mode.
- **Transport:** `cronet_http`.
- **Login:** the web view (there is no keychain to reuse), which means one more Bilibili login. Ask KaiC first.
- **Install:** sideloaded APK. The signing keystore stays out of the repo.

## 7. Lessons that must survive the move

All of these come from phone logs or phone bugs. Sources are in the two BiliNative inventories.

**Network and engine**
- Bilibili refuses non-browser clients. Send a Safari User-Agent, `Referer: https://www.bilibili.com/`, and
  `buvid3`/`buvid4` from `/x/frontend/finger/spi`. On HTTP 412, drop the buvids, fetch new ones and retry once.
- The unsigned `/x/web-interface/view` got 412 from dart:io in the spike, while the WBI-signed `/x/web-interface/wbi/view`
  worked. Logged out, the web playurl stops at 480P even with `try_look=1`.
- Akamai speaks HTTP/1.1 only and the mirrors speak HTTP/2:
  - Akamai is full at 8 in flight from the start;
  - full nodes are skipped outside a hurry too;
  - a copy picks its node only once it holds a connection.
  - Without this, Akamai carried 48-61 requests while the mirrors idled, with 38 first-byte timeouts and two stalls.
- On dart:io, Akamai closes idle keep-alive sockets. That shows up as `HttpException` before headers; up to 7 per spike
  run. Treat it as a connection loss, not a node failure.
- Ban rules (all of them in `bilicore-inventory.md`, section 4):
  - only 0-byte replies are strikes;
  - losses within 250 ms are one strike;
  - a success heals blip strikes;
  - a 4xx from a node that has never delivered drops only that node+address pair;
  - a busy node's first-byte timeout is no strike;
  - damaged spans (up to two 1 MiB blocks per node and file) are avoided, not struck.
- Hurry mode:
  - a startup or seek read, or a segment less than 10 s ahead, counts as a hurry;
  - 64 KiB pieces;
  - placement by expected finish;
  - copies after 250-600 ms;
  - up to 3 copies.
- Pieces of 64 KiB never leave TCP slow start on warm content, and large pieces lose on cold content: hurry mode is the
  compromise.
- Adopted prefetches survive the player's cancel; AVPlayer gives up on requests after about 5 s.
- Refresh signed URLs 5 minutes before `deadline`. A network change resets bans, health and damage.

**AVPlayer**
- AVPlayer can't play `hev1`-tagged HEVC from HLS. Rewrite the init segment to `hvc1` when its `hvcC` carries
  VPS/SPS/PPS; otherwise mark it unplayable and fall back to another codec (`CodecMemory`, `playback.failedCodecs`).
- Dolby Vision needs the codec mapping to `hvc1…` plus `SUPPLEMENTAL-CODECS` (`CodecMapper.swift`).
- `AVAssetImageGenerator` can't read the local HLS; screenshots come from `AVPlayerItemVideoOutput`.
- The PiP restore handler must be called within 3 s, or AVKit waits.

**UI on iOS**
- Full screen is the same page rotated. Build 1 crashed when a view was handed to a system controller.
- UIKit refuses a rotation during a push animation (error 101). From full screen, go inline first and wait 450 ms
  before pushing a page.
- After the full-screen button, portrait exits only after the phone has really been landscape: lifting it off a table
  reports portrait.
- Orientation ownership: the latest `begin` wins, and a covered page's late `end` must not reset the top page.
- Sheets go up only once the page is back inline **and** the windows are upright, with a timer as backup, because
  transition completions may never fire.
- Panels, the coin dialog, the 合集 sheet, the favourites sheet and the picture viewer are in-page overlays. In Flutter
  that means a `Stack` inside the page, not a modal route that interacts with swipe back and PiP.
- The hidden `MPVolumeView` exists only in full screen. A freshly attached slider ignores a value set in the same run
  loop turn, and volume KVO fires on an audio thread.
- One video at a time. A covered page stops PiP. In the background without PiP, autoplay is skipped, because the next
  part would play as audio only.
- Closed pages must free everything (`PageReleaseTests`). Models must not hold closures over the page.
- The danmaku send bar and the comment composer follow the keyboard by hand.
- Swipe back:
  - It works from the edge and from the middle.
  - The content swipe gives way to the player's seek drag and to sideways scrollers that can still scroll back.
  - On 评论 the first swipe pages to 简介.
  - A swipe closes 评论详情 first.
  - Vertical scrolling must still work.
- Builds 6 and 7 passed gesture tests that only asked delegates, while the swipe never began. **Gestures need
  real-touch tests at about 1500 pt/s.**
- On iOS 27, layouts pushed from the 推荐 root froze in SwiftUI. Flutter doesn't share that bug, but still check pages
  opened from 推荐 and from 历史记录 (items 68-72).

## 8. How to test

| Where | What | Command or tool |
|---|---|---|
| PC | `bili_core` (ported Swift tests, SimCDN) | `fvm dart test` in `packages/bili_core` |
| PC | Widget tests: chrome state, panels, swipe back, page lifecycle with `leak_tracker`, demo screens | `fvm flutter test` at the root |
| PC | The Windows app with demo data or logged out; the engine against real CDN nodes on a saved playurl | `fvm flutter build windows --release`, then the exe; ghosthand `screenshot` |
| PC | Engine bench vs Swift | section 6, slice 2 |
| PC | The Swift reference still passes | `swift test --package-path ios/Packages/BiliCore` |
| CI (`macos-26`) | analyze, tests, unsigned iOS build | `app-compile.yml` on every push |
| CI | Platform-view transitions on the iPhone 17 Pro Max simulator: rotation with the player attached, PiP controller exists and starts, share sheet over landscape (the Swift `PlayerTransitionTests` list) | `integration_test` run by `flutter test integration_test -d <simulator>` in a dispatched job |
| CI | Real touches: swipe back from edge and middle, player seek drag, thread close, scrolling (the Swift `SwipeBackUITests` list) | An XCUITest target (`RunnerUITests`) driving the Flutter app at about 1500 pt/s; `flutter test` alone synthesises pointer events inside Flutter and can't catch UIKit-level gesture problems over the platform view |
| Phone | Each slice's checklist items, with logs streaming to the PC | `uv run tools/logserver.py` in BiliNative; 设置 → 开发者 → 发送日志到电脑; read `logs/<date>/*.jsonl` before guessing |

## 9. Shipping

Everything is in `docs/reference/testflight-flutter.md`. In short:
- **The workflow:** `testflight.yml` in this repo, with its own `testflight` environment. Its concurrency group no longer
  covers the Swift repo's runs; the Swift app is frozen, so the two don't build at once.
- **Toolchain:** Flutter is pinned through `subosito/flutter-action`, with Xcode 26.6 pinned.
- **Signing:** `use-profiles` with an export-options plist, then `flutter build ipa --build-number="$BUILD_NUMBER"`.
- **Build numbers:** they continue above the Swift builds (8 so far) by themselves. A floor of 99 marks the Flutter
  builds clearly.
- **Starting a build:** `scripts/testflight.py start` (after a `--dry-run` whenever the workflow changes), and
  one `gh run view` about 20 minutes later. Report the build number, what changed and the phone steps.

## 10. Risks, kill criteria, open questions

| Risk | Mitigation |
|---|---|
| Flutter widgets over a native view cost extra compositing; danmaku at 120 Hz could stutter. | Slice 1 checks it first. Fallback: native danmaku inside the host view. |
| Touches over the native view arrive late or not at all. | The native view takes no touches; test with real touches in slice 1 and in CI. |
| The Dart engine is behind the Swift one. | Tests first (185 engine tests and SimCDN), and the bench against Swift before it reaches the phone. |
| dart:io is HTTP/1.1 only. | `cupertino_http` on iOS, `cronet_http` on Android. |
| UI jank from the engine. | A background isolate from day one. |
| Each player asks for bytes differently (AVPlayer whole segments, mpv open ranges, ExoPlayer chunks). | Seek detection and prefetch are tuned per player; expect one tuning round per player. |
| Debugging blind on the phone. | DevLog and the log sink are in slice 0, before the first phone build. |
| PiliPlus code leaking in. | Read only; write from BiliNative's Swift. |

**Kill criteria:** slice 1 fails on HDR, PiP or touches → stop and keep Swift. Engine parity can't be reached in
slice 2 → stop before screens, report with the bench numbers, and KaiC decides between option A (Swift engine as a
plugin) and stopping.

**Open questions** (ask KaiC only when the slice reaches them):
- **Slice 1:** which BV ids to test HDR 真彩 and 杜比视界 with.
- **Slice 6:** add `BILI_APP_KEYS` to the `testflight` environment for 不喜欢, or keep it greyed.
- **Android:** when, and whether one more Bilibili login there is acceptable.

## 11. What the spike already has (`D:\Repos\Apps\BiliFast`)

| Spike file | Carry over? |
|---|---|
| `lib/api/wbi.dart` | Yes, after checking it against `WBITests`. |
| `lib/api/models.dart`, `bili_client.dart` | As a start only: port BiliNative's full `BiliAPI` instead. |
| `lib/ripper/byte_range.dart`, `cancel.dart`, `sidx.dart`, `node_catalog.dart`, `resolver.dart` | Starting points, checked against the Swift tests. |
| `lib/ripper/engine.dart` (pool, meter, attempt watchdogs 5.5 s / 4 s / 15 s, piece race with claim-at-permit, 8 per node) | A starting point for slice 1; slice 2 replaces it with the full port. |
| `lib/ripper/session.dart`, `local_server.dart` | mpv-shaped (open-ended ranges, EDL); keep for the Windows player only. |
| `lib/ripper/LICENSE-BTR.txt` | Use BiliNative's original notice wording for the package. |
| `lib/playback.dart` | Becomes `WindowsPlayer`: EDL `edl://!no_chapters;%len%url;!new_stream;…`, `user-agent`/`referrer` set as mpv properties, metrics from mpv properties. |
| `lib/ui/swipe_back_route.dart` + `test/swipe_back_test.dart` | Yes: the Cupertino edge swipe plus a full-page rightward drag, with 5 tests. |
| `lib/bench.dart`, `tool/engine_bench.dart` | Ideas for `ripper_bench.dart`; the A/B bench wrote JSONL to `local/bench`. |
| `windows/runner/main.cpp` | The 440×880 window. |

Spike measurements (Windows, overseas, KaiC's account, one pass each) are in `docs/verdict.md`. BTR started in
1.09-1.68 s with no stalls on 4 videos; 直连 started in 1.87-2.33 s with 1-3 stalls and up to 23.8 s after a jump.

## 12. Size

| Slice | Agent time |
|---|---|
| 0 Foundations | about 1.5 days |
| 1 Player core | about 2 days + a phone round |
| 2 Engine parity | about 2 days |
| 3-8 Screens | about 6 days |
| 9 Lifecycle and cutover | about 1 day + the full checklists |
| Android | about 1-2 days |

That makes about 12-14 days of agent time plus phone rounds. The Swift app took two days for M1 and M2 with
subagents running in parallel, so independent slices (5, 6, 7, 8) can run side by side once 3 and 4 are in.
