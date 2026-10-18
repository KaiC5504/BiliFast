# BiliFast (Flutter)

KaiC's Bilibili client for iPhone, being moved from Swift (`D:\Repos\Apps\BiliNative`, public repo
`KaiC5504/BiliNative`) to Flutter. This repo is the Flutter app: public `KaiC5504/BiliFast`, branch `main`. It ships as
the same BiliFast app (bundle id `com.kaichuan.bilifast`, App Store Connect Apple ID `6823476667`), so its TestFlight
builds replace the Swift ones on the phone and read the Swift app's keychain login. KaiC's call on 2026-10-17: build it
here rather than in BiliNative `app/`, and push this folder as its own repo.

## Read before working

1. `docs/flutter-move-spec.md`: the spec: decisions and why, architecture, rules, the slices in order, and the lessons
   that must survive. Start with its section 0. Where it says `BiliNative/app/`, read this repo's root.
2. `D:\Repos\Apps\BiliNative\CLAUDE.md`: the Swift app's rules. Most still apply.
3. `docs/reference/`:
   - `bilicore-inventory.md` and `app-inventory.md`: what BiliNative has, with paths. The port's checklist.
   - `piliplus-map.md`: where PiliPlus keeps what; GPL, so read only.
   - `testflight-flutter.md`: how this repo ships to TestFlight.

Work slice by slice (spec section 6). Show KaiC a short plan before each slice and wait for his go. Finish each slice
with what was built, how it works and numbered test steps. For phone slices, include the TestFlight build number.

## Status

- 2026-10-17: slice 0 (foundations): Flutter app at the root, `packages/bili_core` with BiliShared, DevLog, Danmaku,
  BiliAPI and AppLogic ported from Swift tests-first, the keychain channel (checked on the phone in slice 1), CI and the
  signed TestFlight workflow. The spike moved to `spike/`.
- 2026-10-18: slice 0 done. TestFlight dry run green on the first try (run 39038017954: signed, IPA built and checked,
  not uploaded). At KaiC's request the pipeline was cut to one workflow and a local gate (`scripts/gate.py`, 12 s),
  and GitHub calls are kept to what's needed (6 per start, 1 per status).
- 2026-10-18: slice 1 built by seven agents in parallel against shared interfaces, merged, played end to end on
  Windows (muted, logged out), reviewed (Swift and Dart), then one TestFlight run: build 100, green on the first
  try (the Swift compiled first time). The processing wait looped on a missing `timeout` on macOS; fixed. Chinese
  text uses bundled MiSans with the zh-Hans locale (KaiC's choice, as Kazumi). Phone check passed (KaiC, iOS 27.0.1): logged in from the keychain, 4K, 8K, 真彩 HDR and 杜比视界
  played over BTR with URLSession in the engine isolate (no fallback), PiP and danmaku fine. Seen in the logs for
  slice 2: 7 stalls on one 4K video after Akamai was banned, and an 8.3 s first frame on the first open.
- 2026-10-18: slice 2 (engine parity, then speed beyond it). Version 1.0.0, build numbers per version. The engine
  is level with Swift on `bin/ripper_bench.dart` (same flags as Swift's ripper-bench), then went past it, every
  speed-up behind a `RipperConfig` knob whose default is Swift's (the 185 ported tests stay unchanged) and switched on
  in `lib/playback/playback_setup.dart`: prime the start, seek burst, audio first, rate- and bitrate-aware prefetch,
  back buffer, seek hints from a resting finger, keyframe seeks, preconnect, node memory across launches
  (`node_memory.json` in the app's support folder), no exploring in a hurry, ban probation, slow-node tail backups,
  BTR #47's relay fix. Native: a start or seek plays once 3 s are loaded instead of waiting on AVPlayer's rule.
  `--app [--swift] [--seed N] [--off …]` benches seeks the way the app makes them; give each run its own seed, since
  a second run over the same segments meets a warm CDN. Cold 8K seeks on the PC: first byte 148-361 ms against
  Swift's 1.5-2.8 s; whole 15 MiB segments level (median 5.6 s both, the line's limit on a cold CDN).
- 2026-10-18: 1.0.0 (1) on the phone: first frame 0.7-2.8 s (was 8.3), no stalls, seeks median ~1 s. Its log showed
  cosov and the HK nodes taking first copies (judged by body speed alone, cosov looks fastest: it waits over a
  second, then sends the whole piece), Akamai's first byte bimodal (a fifth of requests miss its cache), memory
  warnings every 30-40 s dropping everything, and a seek waiting 4.6 s on a slow prefetch. Fixes, each behind a
  switch that defaults off: `hurryKeepsOffSlow`, `medianEstimates`, `seekHurriesPrefetch`, `trimOnMemoryWarning`,
  `peakBandwidth`, `hurryHedgeMinMs`. The app still plays with 1.0.0 (1)'s settings until the phone picks.
- 2026-10-18: the phone speed test (KaiC's idea): a 速度测试 card in dev builds plays a plan unattended (variants of
  engine settings, cold each pass, the same seeks every time, muted, screen kept on) and logs every number. Plans
  come from the PC (`tools/logserver.py --plan`, `GET /plan`) or the built-in one (A = 1.0.0 (1), B = the fixes,
  C = B with a 120 ms hurried backup and 16 Akamai connections, ABCCBA at 8K); `tools/phone_report.py --latest`
  summarises a run. Tune by editing `tools/speedtest_plan.json` and asking KaiC to tap 开始测试 again: no build.
- 2026-10-18: the first phone speed test (1.0.0 (2), 6 videos, ABCCBA): no variant won. Each video's first pass
  seeked in 5-15 s and every later pass, wherever it seeked, in ~0.3 s: Bilibili's CDN caches a file within a minute
  or two of its first play (longer for a 10 GB 8K file), and the first pass was always A. Two causes of the cold
  seeks: the native start rule judged a seek at the old position before it landed and gave up (245 of 278 seeks;
  half the time of slow seeks was AVPlayer waiting with the data in), fixed for every variant in 1.0.0 (3); and cold
  CDN blocks answering after 3-6 s on every node alike, where `hurryPieceBytes` (smaller hurried pieces) is on test.
  Plans can `rotate` the order per video, and the first pass on each video is marked cold in the logs, the phone's
  table (冷/热) and `phone_report.py`.
- 2026-10-18: the second and last speed test (1.0.0 (3), 6 videos, ABD rotated): the start fix held (no stale
  starts in 168 seeks; the player now waits 0.1 s after the data where it waited 4.6 s). B beat A on warm 8K seeks
  again and is now the app's config; D (`hurryPieceBytes`) was mixed and stays off. Cold 8K/HDR starts on files
  the CDN didn't have failed the 20 s first frame in 4 of 18 passes (aliov 6-10 Mbps, Akamai failing): the CDN's
  limit. KaiC's call: no more tuning rounds; the speed test stays as a check after big engine changes (builtin-3:
  the app against D).
- 2026-10-18: slice 3 (home and the video page shell), shipped as 1.0.0 (4) with engine B.
  - Home: the 推荐 feed in two columns, the link field, the avatar menu (账号, 最近打开, 开发者 in dev builds), and
    最近打开 (30, carried over once from the Swift app's UserDefaults).
  - The paste button is the system's UIPasteControl, so iOS doesn't ask "Allow Paste?" every time.
  - The video page plays on one shared player started at launch, resumes from Bilibili's saved position (the part
    seen last when no part is given), and sends watch-progress heartbeats.
  - Built solo, so KaiC asked for the process that every slice now follows:
    1. seven read-only checking agents (two reviews, silent failures, test gaps, spec, comments, a muted Windows run);
    2. a contracts commit for what the fixers share;
    3. five fix agents in worktrees, each owning its own files;
    4. merge, a Swift review, a final review, a second Windows run;
    5. the gate, then one GitHub run.
  - The checks found:
    - load more looping against the API;
    - an invisible spinner keeping a core busy;
    - 开发者 able to dispose or leave a speed-test engine on the shared player;
    - heartbeats crossing pages;
    - the cover Hero remounting mid-flight;
    - swipe back firing on vertical drags.
  - Worktrees start at an old commit: each fix agent must fast-forward to the contracts commit first.
- 2026-10-19: slice 4 (player interaction), shipped as 1.0.0 (5), the first slice run through
  `.claude/skills/running-a-slice` (designed with KaiC).
  - Built by seven agents against a contracts commit:
    - native rotation, brightness and volume (`lib/device/`, `DeviceChannel.swift`, `DeviceControls.swift`; the
      rules live in Dart);
    - gestures and the HUD;
    - the small player's controls;
    - the landscape and 竖屏 controls;
    - the panels (清晰度, 编码, 倍速, ⋮, 选集);
    - the page's player session (speed kept across parts, 自动连播, loops, 定时关闭, saved settings);
    - the page.
  - Ten checking agents, then five fixers, a tidy-up and a final round.
  - KaiC's rules from this slice:
    - Swipe back starts only from the left edge.
    - The UI must match the official app's screenshots in `local/official-app-reference/` (his iPhone 17 Pro Max,
      440×956 pt); look-alike agents render our screens and pass or fail each one.
    - Nothing ships until every button is pressed on Windows and its effect confirmed.
  - That run found the buttons pressed nothing through accessibility (VoiceOver included); fixed.
  - The Windows app now runs as the phone: 440×956 with the safe areas and a drawn status bar, turned sideways for
    landscape full screen.
  - Left for later slices: danmaku settings and the send field (5); actions, 关注, the uploader's VIP colour, N人正在看
    and search (6). Pasted links now carry their 合集 with no extra call.
- 2026-10-19, after slice 4: 设置 (avatar menu) → 字体 (`lib/settings/`): 系统字体 (SF with PingFang SC, as the
  official app; the iPhone's default), MiSans (bundled; the default elsewhere), or a .ttf/.otf/.ttc imported from Files.
  A change rebuilds every widget in place (`FollowFont`), so styles read `BiliFonts.family` where they're built, never
  in a const. The five MiSans layout nudges in `BiliMetrics` apply only while MiSans is on. Not on TestFlight yet.
- Next, KaiC's order (2026-10-19): slice 6 (the page body, with 推荐视频), then 7 (comments), then 5 (danmaku), so
  the video page looks like the official app sooner. Slice 5 doesn't block 6 or 7.
- Update this section when a slice finishes.

## Layout

- `lib/`: the Flutter app.
  - `lib/account/`: keychain and cookie persistence.
  - `lib/app/`: routes and `AppScope` (the services every page reaches, the shared player among them).
  - `lib/home/`: home, the feed, the avatar menu and 最近打开.
  - `lib/video/`: the video page, its player session (`page_session.dart`, `player_prefs.dart`) and the
    watch-progress reporter.
  - `lib/player_ui/`: the player's controls for each presentation, gestures, the HUD, the end screens, and
    `panels/`.
  - `lib/device/`: rotation (`orientation.dart`, the rules) and brightness/volume, over `DeviceChannel.swift`.
  - `lib/app/phone_frame.dart`: Windows only; the window as KaiC's iPhone.
  - `lib/settings/`: 设置 and 字体, and the font store (`font.json` and imported fonts in the support folder).
  - `lib/shared/theme.dart`: the colour and size tokens (never hardcode colours).
- `packages/bili_core/`: pure Dart, no Flutter import, the port of the Swift package `BiliCore`. One library per Swift
  module: `shared.dart`, `devlog.dart`, `danmaku.dart`, `api.dart`, `logic.dart`.
- `ios/Runner/`: native Swift (`KeychainChannel.swift`; the player view comes in slice 1). New Swift files must be added
  to `ios/Runner.xcodeproj/project.pbxproj` by hand (four entries, see `KeychainChannel.swift`'s).
- `test_ci/`: static tests of the workflows (pins, secrets only in step env, nothing leaks into the public log).
- `tools/`: the PC side of dev builds: `logserver.py` receives the phone's logs into `logs/` and serves the speed
  test plan; `phone_report.py` reads a session; `speedtest_plan.json` is the plan it serves. Run the server with
  `uv run tools/logserver.py` in the background before KaiC tests.
- `lib/speedtest/`: the speed test's plan, runner and results (dev builds only).

## How to test

- Flutter 3.47.7 through fvm: `fvm flutter …` / `fvm dart …` (`flutter` is not on PATH). Pinned in `.fvmrc`, the
  pubspec and both workflows; `test_ci` checks they agree.
- Everything at once: `python scripts/gate.py`. Lanes in parallel: bili_core, the app, `test_ci`, a Swift syntax check
  of `ios/Runner` (`swiftc -parse`; no iOS SDK on the PC), and the Windows release build plus the Windows
  integration tests (real mpv). About 20 s warm. `--quick` skips the Windows lane and records nothing.
- Core: `fvm dart test` in `packages/bili_core`.
- App: `fvm flutter analyze` and `fvm flutter test` at the root.
- Workflows: `uv run --no-project --with pyyaml==6.0.3 python -m unittest discover -s test_ci`.
- Windows app: `fvm flutter build windows --release`, then `build\windows\x64\runner\Release\bilifast.exe`. The window
  is KaiC's iPhone: 440×956 with its safe areas and a drawn status bar, turned to 956×440 for landscape full screen.
  It runs logged out; there is no keychain on Windows. Every button answers accessibility presses, so ghosthand can
  drive the player (`视频画面` toggles the controls).
- GitHub runs nothing on push. `testflight.yml` is the only workflow (KaiC's call, 2026-10-18: keep only the
  workflows that matter, such as shipping to TestFlight). Tests run in the local gate; a dry run of the signed build
  is the iOS compile check. Don't add a workflow without asking; `test_ci` fails if one appears.

## Shipping

The `ios-testflight` skill is the playbook; load it before touching any workflow, signing or Info.plist.
- `.github/workflows/testflight.yml` signs and uploads when `python scripts/testflight.py start` dispatches it. Run
  `start --dry-run` after any workflow change. Secrets are in this repo's `testflight` environment (limited to `main`).
- Version 1.0.0 (KaiC, 2026-10-18), set in both `pubspec.yaml` and the workflow's `BUILD_NAME` (`test_ci` checks they
  agree). Build numbers count from 1 within each version: App Store Connect's latest build of that version plus one
  (iOS needs them unique only per version; the Swift app shipped 0.1.0 (1-8), slice 1 shipped 0.2.0 (100)). A new
  version starts at 1 by itself.
- The loop: `python scripts/gate.py` on the committed tree (it records the commit it passed), push, then
  `python scripts/testflight.py start` (6 GitHub calls). `start` refuses without the gate's record for that exact
  commit, so it can't ship an unchecked commit. No dry run before an ordinary ship: a red upload run costs the same as
  a red dry run, and a green one is on the phone.
- GitHub comes last (KaiC, 2026-10-18): parallel work is merged, checked locally and reviewed (Swift that only the Mac
  can compile gets a review agent) before the one run, and each red run's errors are all fixed together. `status`
  prints every error line of a failed run, and a Release build type-checks the whole Swift module at once, so one run
  shows them all.
- GitHub calls only when the answer is needed (KaiC gets rate-limited): no polling, no extra runs to measure
  things, one `status` per run.
- Don't watch the run: `python scripts/testflight.py status` once (1 call), about 10 minutes after a dry run and 20
  after an upload. There is no watch command on purpose.
- Report the build number, what changed and phone test steps.
- Commit, push and Actions runs (signed builds included) are authorised on `main`.

## Rules that bite

- Public repo. Never commit, print or log secrets, cookies, tokens, signed playurl responses, or anything in `local/`
  or `logs/` (both gitignored). The build log and artifacts are public too.
- KaiC's Bilibili account: no second login, few live calls, no loops against the API. Tests never touch the network.
- No Mac (`ssh macrent`): iOS checks run in GitHub Actions and on his phone.
- No `gh run watch` and no polling GitHub.
- PiliPlus (`D:\Repos\Apps\PiliPlus`) is the main reference for how a feature works (KaiC, 2026-10-18: it's a mature
  Flutter Bilibili client, and BiliFast is largely a new UI over the same behaviour). Before building a feature, read
  how PiliPlus does it (`docs/reference/piliplus-map.md` says where), alongside BiliNative's Swift. It and
  ATV-Bilibili-demo are GPL: write our own code from what they show; never copy their code (KaiC chose to keep BiliFast
  non-GPL, 2026-10-18). Keep BTR's MIT notice with the engine port.
- Danmaku block-word regexes run on Dart's (ECMAScript) `RegExp`, not ICU as in Swift: `(?i)`, possessive and atomic
  groups throw (the rule is skipped), and `\p{Han}` or `\A` mean something else.
- ghosthand first for screen and browser work. Flutter windows often have a thin accessibility tree; use `screenshot`.
- The BiliNative repo: only docs change there now (and Swift fixes if something blocks daily use).
