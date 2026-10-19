# BiliFast (Flutter)

KaiC's Bilibili client for iPhone, being moved from Swift (`D:\Repos\Apps\BiliNative`, public repo
`KaiC5504/BiliNative`) to Flutter. This repo is the Flutter app: public `KaiC5504/BiliFast`, branch `main`. It ships as
the same BiliFast app (bundle id `com.kaichuan.bilifast`, App Store Connect Apple ID `6823476667`), so its TestFlight
builds replace the Swift ones on the phone and read the Swift app's keychain login.

## Read before working

1. `docs/flutter-move-spec.md`: decisions and why, architecture, rules, the slices, and the lessons that must survive.
   Start with its section 0.
2. `docs/reference/`:
   - `bilicore-inventory.md` and `app-inventory.md`: what the Swift app has, with paths. The port's checklist.
   - `piliplus-map.md`: where PiliPlus keeps what; GPL, so read only.
   - `testflight-flutter.md`: how this repo ships to TestFlight.
3. `D:\Repos\Apps\BiliNative\CLAUDE.md` only for the Swift app's behaviour. Where it and this file differ, this file
   wins (no Mac, no Swift workflows, the UI follows the official screenshots).

Every slice runs through `.claude/skills/running-a-slice`: a one-screen plan, KaiC's go, then parallel agents straight
through to TestFlight. Finish with what was built, how it works, numbered phone steps and the build number.

## Status

Shipped and passed on KaiC's phone, newest last. Detail is in git history.

- Slice 0, foundations: `packages/bili_core` (BiliShared, DevLog, Danmaku, BiliAPI, AppLogic ported tests-first), the
  keychain channel, the local gate and the TestFlight workflow.
- Slice 1, the player core: AVPlayer in a native view fed by the Dart engine's local HLS, PiP, a first danmaku layer,
  the keychain login reused. 4K, 8K, 真彩 HDR and 杜比视界 play as in the Swift app.
- Slice 2, the engine: level with Swift on `bin/ripper_bench.dart`, then faster. Each speed-up is a `RipperConfig`
  switch whose default is Swift's (the 185 ported tests stay unchanged); the app's choice (engine B, from two phone
  speed tests) is set in `lib/playback/playback_setup.dart`. The 速度测试 card (dev builds) stays as a check after big
  engine changes: plan builtin-3, read with `tools/phone_report.py --latest`. KaiC's call: no more tuning rounds.
- Slice 3, home and the page shell, 1.0.0 (4): 推荐, the link field and paste control, the avatar menu, 最近打开, the
  shared player, resume and heartbeats.
- Slice 4, player interaction, 1.0.0 (5): rotation, brightness and volume (native, rules in Dart), gestures and the
  HUD, the controls for each presentation, the panels, the page's player session. Then 设置 → 字体.
- Slice 6, the page body, 1.0.0 (6) and (7): 简介, the actions (optimistic, rolled back per field), the coin dialog,
  favourites, 合集 and parts, related videos, full screen's actions and end screens.
- Slice 7, comments, 1.0.0 (8): 评论 and 评论详情, rich text, the picture viewer, the composer (emotes, @, pictures,
  drafts), the paused player shrinking to the 67 pt 继续播放 bar.

Next, KaiC's order: slice 5 (danmaku). Then 8 and 9.

Open items, each waiting on its slice:
- 不喜欢 is grey (此版本不支持不喜欢) until `BILI_APP_KEYS` is in the `testflight` environment and slice 8 brings the
  TV login. KaiC adds it: `gh secret set BILI_APP_KEYS -R KaiC5504/BiliFast --env testflight`, value `appkey:appsec` of
  the 云视听小电视 pair from bilibili-API-collect.
- Slice 8: logged-out actions open the login page. Slice 5: 点我发弹幕 is a toast until then.
- Later: 竖屏 search, 充电鸣谢, the player box following a 16:10 video's height.
- Known limit: Flutter rounds a line to whole points, so comment lines are 24 pt where the official app's are 24.33.

Update this section when a slice ships: one short entry, and any rule it adds goes under "Rules that bite".

## Layout

- `lib/`: the Flutter app.
  - `lib/app/`: routes, `AppScope` (the services every page reaches, the shared player and `PageApi` among them), the
    page-route observer (a page counts as covered only when a page route is pushed over it), Reduce Motion, and
    `phone_frame.dart` (Windows only: the window as KaiC's iPhone).
  - `lib/account/`: keychain and cookie persistence.
  - `lib/home/`: home, the feed, the avatar menu and 最近打开.
  - `lib/player/`: the `BiliPlayer` interface and its iOS and Windows players. `lib/playback/`: the engine's setup,
    the playback controller, codec memory, the danmaku feed.
  - `lib/danmaku/`: the danmaku layer and its painter.
  - `lib/player_ui/`: the player's controls for each presentation, gestures, the HUD, the end screens, `panels/`.
  - `lib/device/`: rotation (`orientation.dart`, the rules) and brightness/volume, over `DeviceChannel.swift`.
  - `lib/video/`: the video page, its player session (`page_session.dart`, `player_prefs.dart`), the tab row
    (`page_tabs.dart`), the page body's model (`page_details_model.dart` over `page_api.dart`; `fake_page_api.dart`
    for tests and `--fake-account`), the watch-progress reporter and `collapsing_player.dart`.
    - `lib/video/intro/`: 简介's pieces. `lib/video/actions/`: the actions model, the coin dialog, the favourites
      sheet, the unfollow confirm and their overlays.
  - `lib/comments/`: 评论, 评论详情, the composer with its emote panel, @ picker and pictures, and
    `comment_overlays.dart`, the in-page layers the page's Stack holds.
  - `lib/settings/`: 设置 and 字体, and the font store.
  - `lib/devtools/`: crash log, log forwarding and discovery of the PC's log server.
  - `lib/speedtest/`: the speed test (dev builds only).
  - `lib/shared/theme.dart`: the colour and size tokens (never hardcode colours).
  - Settings and stores are JSON files in the app's support folder (`player_prefs.json`, `recents.json`,
    `font.json`, `emotes_recent.json`, `node_memory.json`).
- `packages/bili_core/`: pure Dart, no Flutter import, the port of the Swift package `BiliCore`: `shared`, `devlog`,
  `danmaku`, `api`, `logic`, `dash_hls`, `local_http`, `engine`, and `bin/ripper_bench.dart`.
- `ios/Runner/`: native Swift (player registry and host view, keychain, device controls, frame capture, paste
  control, log-server discovery, the one-time carry-over of the Swift app's 最近打开). Pigeon definitions are in
  `pigeons/`. New Swift files must be added to `ios/Runner.xcodeproj/project.pbxproj` by hand (four entries, see
  `KeychainChannel.swift`'s).
- `assets/`: MiSans, and assets taken from PiliPlus (`assets/README.md`).
- `test_ci/`: static tests of the workflow (pins, secrets only in step env, nothing leaks into the public log).
- `tools/`: the PC side of dev builds: `logserver.py` receives the phone's logs into `logs/` and serves the speed
  test plan; `phone_report.py` reads a session. Run `uv run tools/logserver.py` in the background before KaiC tests.

## How to test

- Flutter 3.47.7 through fvm: `fvm flutter …` / `fvm dart …` (`flutter` is not on PATH). Pinned in `.fvmrc`, the
  pubspec and the workflow; `test_ci` checks they agree.
- Everything at once: `python scripts/gate.py`. Lanes in parallel: bili_core, the app, `test_ci`, a Swift syntax check
  of `ios/Runner` (`swiftc -parse`; no iOS SDK on the PC), and the Windows release build plus the Windows
  integration tests (real mpv). `--quick` skips the Windows lane and records nothing.
- Core: `fvm dart test` in `packages/bili_core`. App: `fvm flutter analyze` and `fvm flutter test` at the root.
- Workflow: `uv run --no-project --with pyyaml==6.0.3 python -m unittest discover -s test_ci`.
- Windows app: `fvm flutter build windows --release`, then `build\windows\x64\runner\Release\bilifast.exe`.
  - The window is KaiC's iPhone: 440×956 with its safe areas and a drawn status bar, turned to 956×440 for landscape
    full screen. It runs logged out; there is no keychain on Windows.
  - Every button answers accessibility presses, so ghosthand can drive it (`视频画面` toggles the controls).
  - Flags: `--mute` (always), `--play=<BV>`, and `--fake-account` (a made-up account with the page's calls answered
    by `FakePageApi`: actions and a demo comment section, no account traffic).
  - ghosthand can't scroll or drag, and the 956 pt window is taller than this PC's screen (the bottom ~10 pt of a
    capture is stale). Scrolls, drags and swipes are covered by widget tests at ~1500 px/s instead.
- Look-alike checks render our screens in widget tests at 440×956 (or 956×440), 3×, against KaiC's official
  screenshots in `local/official-app-reference/` (gitignored: look only, never copy or commit).
- GitHub runs nothing on push. `testflight.yml` is the only workflow; don't add one without asking (`test_ci` fails if
  one appears).

## Shipping

The `ios-testflight` skill is the playbook; load it before touching any workflow, signing or Info.plist.
- `python scripts/gate.py` on the committed tree (it records the commit), push, then `python scripts/testflight.py
  start` (6 GitHub calls). `start` refuses a commit the gate didn't pass. Run `start --dry-run` only after a workflow
  or script change.
- Check once: `python scripts/testflight.py status` (1 call), about 11 minutes after an upload (7 after a dry run), as
  a background `sleep` then `status`. Never `gh run watch`, never poll: KaiC gets rate-limited.
- Version 1.0.0, set in both `pubspec.yaml` and the workflow's `BUILD_NAME` (`test_ci` checks they agree). Build
  numbers count from 1 within each version (App Store Connect's latest of that version plus one); the last shipped is
  in Status.
- Secrets are in this repo's `testflight` environment (limited to `main`).
- Commit, push and Actions runs (signed builds included) are authorised on `main`.

## Rules that bite

- Public repo. Never commit, print or log secrets, cookies, tokens, signed playurl responses, or anything in `local/`
  or `logs/` (both gitignored). The build log and artifacts are public too.
- KaiC's Bilibili account: no second login, few live calls, no loops against the API. Tests never touch the network.
- No Mac: iOS checks run in GitHub Actions and on his phone.
- Layout comes only from the official app's screenshots (`local/official-app-reference/`, his iPhone 17 Pro Max,
  440×956 pt). When a screen or state isn't in them, ask KaiC to screenshot it; never fill the gap from PiliPlus or
  the Swift app.
- PiliPlus (`D:\Repos\Apps\PiliPlus`) is a reference for functions only: the APIs and how a feature behaves, plus its
  asset files of the official app's art (`assets/README.md`, never its logos). Never its layout or design. Read it
  before building (`docs/reference/piliplus-map.md`). It and ATV-Bilibili-demo are GPL: write our own code, never
  copy theirs. Keep BTR's MIT notice with the engine port.
- Swipe back starts only from the left edge; a sideways drag elsewhere belongs to the page.
- Nothing ships until every control the change touched has been pressed on Windows and its effect confirmed.
- Text scaling is off at the app's root (`main.dart`), so sizes are the official pt whatever iOS's Text Size says.
  Don't add per-widget clamps.
- Fonts: styles read `BiliFonts.family` where they're built, never in a const, so a 字体 change rebuilds in place. The
  MiSans nudges in `BiliMetrics` apply only while MiSans is on.
- Panels, sheets, dialogs and the comment layers are in-page overlays in the page's Stack, not routes; back closes
  them first.
- Danmaku block-word regexes run on Dart's (ECMAScript) `RegExp`, not ICU as in Swift: `(?i)`, possessive and atomic
  groups throw (the rule is skipped), and `\p{Han}` or `\A` mean something else.
- ghosthand first for screen and browser work; always `--mute`. Flutter windows often have a thin accessibility tree;
  use `screenshot`.
- The BiliNative repo: only docs change there now (and Swift fixes if something blocks daily use).
