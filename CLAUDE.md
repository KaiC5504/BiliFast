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
   - `turn-log.md`: the drawn turn's log lines on both sides, which `tools/phone_report.py --turns` grades.
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
- Slice 5, danmaku, 1.0.0 (9): 弹幕设置 (landscape strip, portrait light sheet; every change live mid-flight), 屏蔽词
  synced with the account, 当前弹幕列表 with 👍 and 屏蔽弹幕, sending with styles from every entry point, own danmaku
  boxed, the small player's danmaku at the official 12.5 pt. The app icon became the pink sprinting TV.
- Slice 8, the rest of the app, 1.0.0 (10): the login page (Bilibili's own, in a web view) and 退出登录, every
  logged-out action opening it (turning upright first), the avatar page (49) in place of the menu, 历史记录 (45-48),
  the full 设置 (50-51: account, 字体, 加速 with the CDN node, 数据, 开发者, 版本, 退出登录), 开发者's log export and
  test crash, the phone's 20 MB log, codec memory kept across launches.
- Fixes from KaiC's clips (`local/differences/`), 1.0.0 (11): the turn to landscape keeps the upright page until the
  screen is landscape, then grows the player; the zoom swipe back into the 推荐 card it came from; 最近在看的视频 from
  the account's history; 简介 for b23.tv and av links (the detail fetched alongside playback, retried).
- Slice 9, page lifecycle, 1.0.0 (12): a player per page on one shared engine; a covered page pauses and resumes
  without a reload; PipKeeper (a closed page lives on in the small window, restore pushes it back, ✕ or another
  video releases it); network changes reset the engine's node health; the drawn turn (开发者 → 旋转动画 自绘 / 系统).

Next: the phone runs both checklists (M1 and M2) in full; then the cutover (spec, slice 9).

Open items, each waiting on its slice:
- The drawn turn, 1.0.0 (14): (13)'s 轮换测试 on the phone, measured frame by frame from KaiC's recording
  (`local/differences/09-ours-rotate-testing-v4.MP4`, `tools/turn_video.py`), found only 请求前关 keeps iOS's own
  rotation out (the others spun 180°), and the page drew its turns in 0 ms or not at all. (14) keeps 系统 and 请求前关
  (开发者 → 旋转动画: 方式, 截图, 起转), draws every turn over 300 ms, and follows a turn that arrives before its
  build. 轮换测试 walks 系统 and 请求前关's six 截图 × 起转 pairs. KaiC compares them by eye against the official app;
  then keep the winning 截图 and 起转, and remove 轮换测试 and the per-frame lines (the summary stays).
- 不喜欢 stays grey (此版本不支持不喜欢): KaiC left out the TV authorisation it needs (a new 云视听小电视 device on the
  account and a borrowed app key).
- Logging out and back in hasn't been tried on the phone (KaiC keeps his one login); Windows and widget tests cover
  the logged-out paths.
- Follow-up slice: 人像防挡 (the mask file from `/x/v2/dm/web/view`); its switch is drawn off and toasts until then.
- Left out by KaiC: 举报 on danmaku, 互动弹幕列表.
- Later: 竖屏 search, 充电鸣谢, the player box following a 16:10 video's height.
- Known limit: Flutter rounds a line to whole points, so comment lines are 24 pt where the official app's are 24.33.

Update this section when a slice ships: one short entry, and any rule it adds goes under "Rules that bite".

## Layout

- `lib/`: the Flutter app.
  - `lib/app/`: routes (the plain swipe back, and `zoom_back_route.dart` for 推荐 cards), `AppScope` (the services every page reaches: `AppPlayback`, which hands each page a player, `PageApi`, the
    `PipKeeper` and the navigator key), the
    page-route observer (a page counts as covered only when a page route is pushed over it), Reduce Motion, and
    `phone_frame.dart` (Windows only: the window as KaiC's iPhone).
  - `lib/account/`: keychain and cookie persistence, the login page and `LoginGate`, the web view's cookies.
  - `lib/home/`: home, the feed, the avatar page (49) and 最近打开.
  - `lib/history/`: 历史记录, its model and the row's ⋮ sheet.
  - `lib/player/`: the `BiliPlayer` interface and its iOS and Windows players. `lib/playback/`: the engine's setup,
    the shared engine (`shared_engine.dart`: one isolate, a lease per controller), the playback controller, codec
    memory, the danmaku feed.
  - `lib/danmaku/`: the danmaku layer, scene and painter; `DanmakuSession` (one per page, on `PlayerUi`), the
    settings and block-rule stores, 添加屏蔽词, 当前弹幕列表, and `send/` (the send bar and style panel) with
    `danmaku_overlays.dart`, the send layer in the page's Stack. The 弹幕设置 panel is in `lib/player_ui/panels/`.
  - `lib/player_ui/`: the player's controls for each presentation, gestures, the HUD, the end screens, `panels/`.
  - `lib/device/`: rotation (`orientation.dart`, the rules) and brightness/volume, over `DeviceChannel.swift`.
  - `lib/video/`: the video page, its playback (`page_playback.dart`: the controller, session and watch reporter, which
    outlive the page for the small window), `pip_keeper.dart`, its player session (`page_session.dart`,
    `player_prefs.dart`), the tab row
    (`page_tabs.dart`), the page body's model (`page_details_model.dart` over `page_api.dart`; `fake_page_api.dart`
    for tests and `--fake-account`), the watch-progress reporter and `collapsing_player.dart`.
    - `lib/video/intro/`: 简介's pieces. `lib/video/actions/`: the actions model, the coin dialog, the favourites
      sheet, the unfollow confirm and their overlays.
  - `lib/comments/`: 评论, 评论详情, the composer with its emote panel, @ picker and pictures, and
    `comment_overlays.dart`, the in-page layers the page's Stack holds.
  - `lib/settings/`: 设置, 字体, CDN 节点 and the confirm alert, and the font store.
  - `lib/devtools/`: crash log, the phone's log files, log forwarding and discovery of the PC's log server;
    `turn_cycle.dart` and its badge (轮换测试, the turn test build only).
  - `lib/speedtest/`: the speed test (dev builds only).
  - `lib/shared/theme.dart`: the colour and size tokens (never hardcode colours).
  - Settings and stores are JSON files in the app's support folder (`player_prefs.json`, `recents.json`,
    `font.json`, `emotes_recent.json`, `node_memory.json`, `danmaku_settings.json`, `codec_memory.json`,
    `log_server.json`); the log is in the caches folder.
- `packages/bili_core/`: pure Dart, no Flutter import, the port of the Swift package `BiliCore`: `shared`, `devlog`,
  `danmaku`, `api`, `logic`, `dash_hls`, `local_http`, `engine`, and `bin/ripper_bench.dart`.
- `ios/Runner/`: native Swift (player registry and host view, keychain, the login web view's cookies, device
  controls, frame capture, paste control, log-server discovery, the one-time carry-over of the Swift app's 最近打开). Pigeon definitions are in
  `pigeons/`. New Swift files must be added to `ios/Runner.xcodeproj/project.pbxproj` by hand (four entries, see
  `KeychainChannel.swift`'s).
- `assets/`: MiSans, and assets taken from PiliPlus (`assets/README.md`).
- `design/icon-options/`: the app icon's five candidates and `make_icons.py`; A is the app's.
- `test_ci/`: static tests of the workflow (pins, secrets only in step env, nothing leaks into the public log).
- `tools/`: the PC side of dev builds: `logserver.py` receives the phone's logs into `logs/` and serves the speed
  test plan; `phone_report.py` reads a session; `turn_video.py` measures the turns in a screen recording. Run `uv run tools/logserver.py` in the background before KaiC tests.

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
- A logged-out action goes through `AppScope`'s `loginGate` (on the video page, its `_requestLogin`, which turns the
  phone upright first), never a 请先登录 toast. The login replays nothing; the gate always shows the page, since a
  -101 can come while the app still thinks it is logged in.
- The video page lays out by the screen's shape, not the orientation's presentation: Flutter's iOS engine keeps the
  old size for the first half of a turn, so landscape is laid out only once the size is wide (`_laidOut`, which
  `PlayerUi`'s panels and gestures follow). Code that acts on what the user asked for reads the presentation.
- The drawn turn (旋转动画 请求前关): `TurnTakeover.swift` holds UIView animations off from before the rotation is
  requested until the turn completes, the only way found to keep iOS's out-of-process rotation out (turning them off
  inside viewWillTransition is too late: iOS still spun the window in 1.0.0 (12) and (13)). The window then turns at
  once with a zero duration, Flutter gets the turned size at once under a still picture, and the video page draws the
  turn from −angle to 0 over 300 ms and calls `turnDrawn(id)`, or the picture lifts after 0.5 s. The turn can reach
  Dart before the build that follows the change of presentation, so `_turnStarted` follows it first. It is armed only while a video page owns
  the orientation; a page that is covered or leaves gives it up first. While the page draws a turn, its geometry is
  the official 01 clip's (300 ms ease-in-out, the body hanging from the box's bottom-left, cut at the turning
  window's edge); grows it doesn't draw (系统, Windows) keep the centred body.
- One player per page (BiliNative's one AVPlayer per page), all on one engine isolate. A covered page pauses, stops
  its small window, drops its prefetch and gives up auto PiP; its loads start paused while covered. It resumes when
  shown only if it was playing, and not while another page's video is in the small window. A page popped while its
  small window plays goes to `PipKeeper` (`PagePlayback` lives on); any other popped page releases its player.
  The restored page is pushed without a slide, or AVKit flies the window off screen.
- 弹幕设置 is one set for every presentation. 添加屏蔽词 and 当前弹幕列表 are landscape only (the portrait sheet, 40
  and 41, has no rows for them); turning to portrait with either open goes back to 弹幕设置.
- Danmaku block-word regexes run on Dart's (ECMAScript) `RegExp`, not ICU as in Swift: `(?i)`, possessive and atomic
  groups throw (the rule is skipped), and `\p{Han}` or `\A` mean something else.
- ghosthand first for screen and browser work; always `--mute`. Flutter windows often have a thin accessibility tree;
  use `screenshot`.
- The BiliNative repo: only docs change there now (and Swift fixes if something blocks daily use).
