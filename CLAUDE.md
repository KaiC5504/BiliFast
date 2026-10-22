# BiliFast (Flutter)

KaiC's Bilibili client for iPhone, being moved from Swift (`D:\Repos\Apps\BiliNative`, public repo
`KaiC5504/BiliNative`) to Flutter. This repo is the Flutter app: public `KaiC5504/BiliFast`, branch `main`. It ships as
the same BiliFast app (bundle id `com.kaichuan.bilifast`, App Store Connect Apple ID `6823476667`), so its TestFlight
builds replace the Swift ones on the phone and read the Swift app's keychain login.

## Read before working

1. `docs/flutter-move-spec.md`: decisions and why, architecture, rules, the slices, and the lessons that must survive.
   Start with its section 0.
2. `docs/milestone-3-spec.md`: the current milestone (find and follow), its slices, APIs and screenshots.
3. `docs/reference/`:
   - `bilicore-inventory.md` and `app-inventory.md`: what the Swift app has, with paths. The port's checklist.
   - `piliplus-map.md`: where PiliPlus keeps what; GPL, so read only.
   - `testflight-flutter.md`: how this repo ships to TestFlight.
   - `turn-log.md`: the drawn turn's log lines on both sides, which `tools/phone_report.py --turns` times; `tools/turn_video.py` grades a recording.
4. `D:\Repos\Apps\BiliNative\CLAUDE.md` only for the Swift app's behaviour. Where it and this file differ, this file
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
- The system font, 1.0.0 (15) (KaiC's call: its own build to check): slice 10's font fixes and comment fix, the drawn
  turn, and the text fixes the stand-in fonts found: the system font named (`BiliFonts.system`), PingFang's strut on
  text mixing Latin and Chinese (`BiliFonts.strut`; text fields drew a mixed line 23 pt where Chinese takes 22).
  Milestone 3 is paused (KaiC, 2026-10-20); its spec keeps the sweep's decisions. On the phone every system-font digit
  and space came out wide and low: see (16).
- The system font's fallback, 1.0.0 (16): slice 10 had given the system font a fallback list (Apple Color Emoji, then
  PingFang SC), and iOS has no family named `CupertinoSystemText`, so Apple Color Emoji, the first family that
  matched, drew every run's digits and spaces at emoji width. The phone's system path now names no fallback, as (14)
  did: SF is iOS's default and PingFang SC its own fallback for Chinese.
- Slice 11, 搜索, and the bottom bar, 1.0.0 (17) (KaiC: its own build): 首页's field opens 搜索 (52-61; the paste
  button is gone, a link pasted or typed in 搜索 opens its video), 热搜, 搜索历史 kept on the phone, 搜索发现,
  suggestions, 综合 with 筛选 and 用户 (rows open the space in the browser until slice 12), the ⋮ sheet's 稍后再看;
  01's bottom bar, where only 首页 works (one tap scrolls 推荐 up and refreshes it). Also carries the katakana fix.
- The loading TV, 1.0.0 (18): the official app's 小电视 (its four refresh faces and the player's pink Lottie, from the
  8.43.0 APK) in place of the spinning circle: 推荐's pull and 首页-tap refresh, the avatar page's and 历史记录's
  pulls (14), the first loads of 搜索, 历史记录 and 评论 over 正在努力加载... (64, 67; 搜索 hides its tab row until a new
  keyword answers), and the player's 正在缓冲... with the engine's speed for loads, reloads and waits past 750 ms (65,
  66). Loading more keeps the small system spinner, as the official app does. 首页's tab row ends at 01's hairline
  (it was 9.33 pt low since slice 3).
- Slice 12, UP主空间, 1.0.0 (19) (KaiC: its own build): the uploader row's and staff's face and name (one target) open
  the uploader sheet under the playing video (62, 68, 76): counts, 关注, the uploader's videos, 进入空间. The space (63,
  69-75, 77-79): banner, counts, 关注 with 充电 / 已关注 / ▽ and the 取消关注 sheet, the collapsing white bar with the
  tab row pinned, always on 投稿 (chips for 视频 and 合集/系列, the 最新发布 ↔ 最多播放 toggle, 播放全部, rows with ⋮'s
  稍后再看 and 分享). Comments' face and name, reply previews' names, @mentions (comments and 简介), space links and
  搜索's 用户 rows open the space. The space's calls are the official app's (`app.bilibili.com`, `AppSigner.android`);
  关注 stays on the web calls, kept in step everywhere by `FollowBook`.
- Slice 13, 我的收藏, 稍后再看 and the official login, 1.0.0 (20): the app token (`AppAuth`), confirmed once with the
  web login (see (21)), kept with its expiry, renewed once within 30 days of the end, asked
  again when rejected; PiliPlus's split by host. Official with the token: 推荐 (personalised, videos only; the web
  feed without the token), its ⋮ sheet with 不感兴趣 and its reasons (90-92), 点赞, 投币 and 不喜欢 (now live, 88,
  89). 我的收藏 (80-84, 99-101): folders as cards or a list, a folder, 视频, 取消收藏, 创建 with a picked cover.
  稍后再看 (85, 86, 93-98): 全部 / 未看完, the sort, 播放全部, 删除, 一键清除, 批量管理 with 复制到 / 移动到. Settings
  files now live in the folder iOS names (path_provider): until (19) none survived a relaunch on the phone. Shipped
  without the Windows press-through (the PC was locked; KaiC's call), on widget tests' accessibility presses.
- The official login's confirm, 1.0.0 (21): on (20) the confirm call with the web login got -101 (it takes only the
  official app's own token, PiliPlus issue 2933), and its page in a web view said 请在哔哩哔哩客户端内打开. 授权 now
  opens that page in the official app (`bilibili://browser?url=`); the user taps 确认 there and comes back, and the
  return polls for the token (at most 5 polls). Without the official app it toasts 请先安装哔哩哔哩客户端. Passed on
  KaiC's phone.
- 我的收藏's 视频, 1.0.0 (22): on (21) `/x/v3/fav/tab` answered code 0, but no tab named 视频 was found. The finder
  now looks at any depth and takes the id as a number or a string; a miss logs the tabs' names and ids (`fav tabs
  without 视频`).
- 1.0.0 (23), three fixes. The seek bar (KaiC's recording `102-player-seek-drag.mov`): a touch takes hold of the
  current position instead of jumping to the finger; a drag moves it by the distance dragged (the bar's travel is the
  whole video), and a tap on the bar seeks nowhere, in every presentation. 我的收藏's 视频: (22)'s log showed
  `/x/v3/fav/tab?tab_id=0` holds only the top tabs (收藏=1, 追更=2), so 视频 is looked for among 收藏's sub tabs
  (`tab_id=1`, two calls at most). The comment picture viewer (105): a vertical swipe carries the picture with the
  finger, shrinking to 60% while the black fades to the comments; past 100 pt or a flick it flies off and closes,
  otherwise it settles back. Long pictures (scrolling) and zoomed ones keep their drags. Not built: the viewer's
  查看原图, ⋮ sheet (分享, 保存图片) and comment bar (103, 104).
- The seek preview, 1.0.0 (24) (102): holding landscape's bar fades every control but the bar and shows the frame
  (170 × 95 pt, 1 pt white border, 6 pt corners, 184 pt from the top) with the time 15 pt under it. Frames are
  `/x/player/videoshot` (`index=1`), fetched once per part on the first hold, every sheet cached as it arrives; the
  time shows alone until then. The small player and 竖屏 keep their bars as they were (no screenshot of theirs).

Next: milestone 3, "find and follow" (KaiC's call, 2026-10-20), the rest shipped as one build at its end (slice 10,
the system-font check, shipped in (15) and (16); its leftovers are set aside, below):
1. KaiC's phone check of (20), then the milestone's closing build and both checklists.
Each new screen waits for KaiC's official screenshots. On that build the phone runs both checklists (M1 and M2) in
full; passing them is the cutover (spec, slice 9). Later: 动态, 离线缓存, 番剧, 直播.

Open items, each waiting on its slice:
- The drawn turn, shipped in 1.0.0 (15): (14)'s recording
  (`local/differences/10-ours-rotate-testing-v5.MP4`, measured with `tools/turn_video.py`) matched the official turn
  with 请求前关, the picture cut and the turn started at once. (15) keeps only that as 开发者 → 旋转动画 自绘, beside
  系统; the test build's choices, 轮换测试 and the per-frame log lines are gone. On the phone: the turn both ways
  against the official app.
- Japanese names under the system font, `5f116e1`, shipped in 1.0.0 (17): on (16) a
  reply whose name is katakana (シロハ_, 单可ト) drew its whole line in a Japanese font; the launch check now names SF,
  then PingFang SC (the font rule below). On the phone: those replies draw like the others, and the log's
  `system font fallback` reads pingFang true (false means iOS didn't match `.AppleSystemUIFont`; the app then stays
  as (16)).
- Slice 10's leftovers, set aside by KaiC (2026-10-21; `docs/milestone-3-spec.md`, slice 10 and section 8): the
  stand-in sweep's findings (re-measure, then one fix round by screen group), the landscape title marquee with 章节,
  竖屏's 联合创作 and 合集 prefix, 弹幕设置's 查看更多 variant for the small player (waiting on KaiC's screenshot), and
  12's first comment drawing about 3% wide on (16), cause unknown.
- The official login on the phone: the confirm in the official app worked on (21) (token for 180 days, the official
  推荐 answered). Still to check: 推荐's mix against the official 首页, 不感兴趣's reason ids (inferred), 我的收藏's
  视频 (the official app's `/x/v3/fav/tab/fav` with cookies, untried), the cover upload, and the launch log's
  `support folder` line (on (20) the danmaku settings came back after a relaunch: loaded, changed true).
  Not built: 追更, the folder search, 批量 in folders, folder rows' progress line (the web list has none), 卡片/列表
  remembered across launches. The Windows press-through of slice 13 is still owed.
- Logging out and back in hasn't been tried on the phone (KaiC keeps his one login); Windows and widget tests cover
  the logged-out paths.
- Follow-up slice: 人像防挡 (the mask file from `/x/v2/dm/web/view`); its switch is drawn off and toasts until then.
- 搜索 on the phone: the keyboard's 搜索 key (ghosthand's Enter doesn't reach the Windows app), results with the
  real login (no -412), the … under PingFang (the stand-in draws it mid-height), and the zoom back into a 推荐 card
  half under the bottom bar. Left out of 搜索 for now: 番剧/直播/影视/图文, the keyword chips, comment snippets,
  相关搜索, 筛选's 音画质量/范围/date range, 大会员 names, 用户's sort menus (no screenshot of them open).
- The loading TV on the phone: no recording shows a pull in progress (ours holds the first face until the pull would
  refresh), 历史记录's first load or a speed past 1024 KB/s (ours writes MB/s); 评论 before the aid is known was only
  seen under an ad card. A pause before the first frame may leave 正在缓冲... up (older than (18), unconfirmed). The
  @ list, emote panel and 收藏 sheet keep their spinners (no recording).
- UP主空间 on the phone: 关注 / 取消关注 on the real account (FollowBook keeping the page, sheet and space in step), the
  bolt on 硬核会员's level badge (`level_info.identity` 2) and 充电 only for uploaders who take it (`elec.show`), both
  unseen live; the -404 page's 用户不存在或已注销 and the collapsed bar's 已关注 pill are guesses (no screenshot).
  Not built: 主页/动态/小店/收藏 (toast), the uploader's default tab, 你可能感兴趣 after 关注 (no known API), medals and
  找我官方合作 after the name, 图文. Uploader names on 推荐 cards, 历史记录, 搜索's video rows and related rows don't
  open the space yet (no screenshot of what the official app does). 分享 on Windows opens an invisible share window
  that freezes the app (share_plus; the phone is fine): checks skip it.
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
  - `lib/home/`: home, the feed, the bottom bar (`home_tab_bar.dart`, its glyphs in `tab_bar_icons.dart`), the avatar
    page (49) and 最近打开.
  - `lib/search/`: 搜索: the page, the empty page and suggestions, `SearchModel` over `SearchApi` (`fake_search_api.dart`
    for tests and `--fake-account`), the history store, `search_glyphs.dart`, and `results/` (tabs, rows, 筛选, the ⋮
    sheet). `lib/video/link_opener.dart` opens a pasted link's video for 搜索 and `--play=`.
  - `lib/history/`: 历史记录, its model and the row's ⋮ sheet.
  - `lib/space/`: UP主空间: `SpaceApi` (the official app's calls; `fake_space_api.dart` for tests and `--fake-account`),
    the route and `UploaderTap` / `openUploader` (the video page's sheet, else the space), `SpaceFollow` and
    `FollowBook` (关注 in step across pages), the uploader sheet, the space page (header, bar, tabs, the 取消关注 sheet)
    and 投稿's list (`space_videos.dart`).
  - `lib/favourites/`: 我的收藏 (folders, a folder, 视频, the 创建 page `new_folder_page.dart` that 稍后再看 shares).
  - `lib/watch_later/`: 稍后再看 (the list, its sheets and 批量管理).
  - `lib/account/app_auth*.dart`: the official login's token, its confirm, and the hand-off of Bilibili's confirm page
    to the official app (`app_auth_client.dart`).
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
  - `lib/devtools/`: crash log, the phone's log files, log forwarding and discovery of the PC's log server.
  - `lib/speedtest/`: the speed test (dev builds only).
  - `lib/shared/theme.dart`: the colour and size tokens (never hardcode colours). `lib/shared/loading_tv.dart`: the
    loading TV every list and page uses (`lib/player_ui/player_loading.dart` is the player's).
  - Settings and stores are JSON files in the app's support folder (`player_prefs.json`, `recents.json`,
    `font.json`, `emotes_recent.json`, `search_history.json`, `node_memory.json`, `danmaku_settings.json`,
    `codec_memory.json`, `log_server.json`); the log is in the caches folder.
- `packages/bili_core/`: pure Dart, no Flutter import, the port of the Swift package `BiliCore`: `shared`, `devlog`,
  `danmaku`, `api`, `logic`, `dash_hls`, `local_http`, `engine`, and `bin/ripper_bench.dart`.
- `ios/Runner/`: native Swift (player registry and host view, keychain, the login web view's cookies, device
  controls, frame capture, paste control, log-server discovery, the one-time carry-over of the Swift app's 最近打开). Pigeon definitions are in
  `pigeons/`. New Swift files must be added to `ios/Runner.xcodeproj/project.pbxproj` by hand (four entries, see
  `KeychainChannel.swift`'s).
- `assets/`: MiSans, assets taken from PiliPlus, and the loading TV's from the official APK (`assets/README.md`).
- `design/icon-options/`: the app icon's five candidates and `make_icons.py`; A is the app's.
- `test_ci/`: static tests of the workflow (pins, secrets only in step env, nothing leaks into the public log).
- `tools/`: the PC side of dev builds: `logserver.py` receives the phone's logs into `logs/` and serves the speed
  test plan; `phone_report.py` reads a session; `turn_video.py` measures the turns in a screen recording;
  `screen_diff.py` measures our screenshot against the official one (milestone 3, slice 10); `make_standin_fonts.py`
  makes the system font's stand-ins in `test/fonts`. Run `uv run tools/logserver.py` in the background before KaiC tests.

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
  screenshots in `local/official-app-reference/` (gitignored: look only, never copy or commit), and measure the pair
  with `tools/screen_diff.py`. They render the system font, as the phone does: `BiliFonts.family = BiliFonts.system` with
  `test/support/stand_in_fonts.dart` loaded; `test/support/look_alike.dart` sizes the view as the phone and saves the
  3× PNG.
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
- KaiC's Bilibili account: no second login (the one exception, KaiC's call in slice 13: the app token, confirmed once with
  the web login), few live calls, no loops against the API. Tests never touch the network.
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
- The theme's `BiliFonts.untracked` keeps Material's 0.1-0.5 pt letter spacing out of every style: tracked Chinese at
  3× lands between pixels and draws some glyphs thin. Keep it in both `ThemeData`s.
- The phone draws the system font by default: SF, with PingFang SC for Chinese. Both are Apple's and can't be on the
  PC, so tests of the system path load open stand-ins (`test/fonts`, made by `tools/make_standin_fonts.py`: Noto Sans
  SC and Inter given PingFang's and SF's line metrics, glyph places and widths, measured off the phone); without
  them that path draws Flutter's square test font. On settings (09) they land within a pixel of the phone, but
  stroke weight and Latin shapes still differ, so system-font values are still settled from KaiC's phone screenshots
  (ours beside the official), measured in px / 3. New Chinese in code or tests needs the script run again (the tools
  lane fails until it is).
- Fonts: styles read `BiliFonts.family` where they're built, never in a const, so a 字体 change rebuilds in place. The
  MiSans nudges in `BiliMetrics` apply only while MiSans is on. The system font is `BiliFonts.system`
  (`CupertinoSystemText`). iOS's engine registers no family by that name (only `CupertinoSystemDisplay`), so on the
  phone it matches nothing and the default, SF, draws. So in a fallback list the first family the phone has becomes
  every run's font (1.0.0 (15) listed Apple Color Emoji and drew digits and spaces emoji-wide). With no list, the first
  character SF lacks has iOS pick a font, which the engine keeps for the rest of the line (a katakana name drew its
  whole reply in a Japanese font). So at launch `BiliFonts.settleSystemFallback` names SF by UIKit's family name
  (`.AppleSystemUIFont`), then PingFang SC, but only if that name draws Latin exactly as the default does; otherwise
  nothing, and it logs which (`system font fallback`). Nothing else sets `BiliFonts.systemFallback`;
  `test/flutter_test_config.dart` sets the PingFang stand-in, because tests register the SF stand-in under the name
  the phone doesn't have. A test that passes under the stand-ins can still be wrong on the phone wherever font
  resolution differs.
- 搜索 keeps one search call out at a time, suggestions included, with a gap between result pages; a load round
  that adds no row (a 筛选 cut them all) stalls until the user asks again, so nothing loops against the account.
  The keyword is the user's text: never log it, nor an error's `toString` (cupertino_http's carries the URL).
- Loading shows the official TV (`LoadingTv`, `LoadingTvState`, `loadingTvRefreshIndicator`; the player's
  `PlayerLoading`), never a spinning circle, except for loading more under a list and inside buttons, where the
  official app keeps the small system spinner too.
- Two logins, split by host as PiliPlus does: a call to `app.bilibili.com` carries the app token (`access_key`) and
  the Android signature, never cookies (`bili_client_official.dart`); every other call carries the web login's cookies.
  The token never reaches a log, a fixture or an error message; an official account call without it throws
  `BiliError.noAppToken` and its feature asks `AppAuth.request` instead. 推荐 is never fetched from the official feed
  without the token (that feed is generic). The token is confirmed only in the official app: Bilibili's confirm call
  answers the web login -101, and its page refuses any web view.
- UP主空间's calls are the official app's (`app.bilibili.com`), signed with `AppSigner.android` (a public pair, the
  same for everyone; KaiC allowed it in the repo) and sent with no cookies. An archive item's `uri` carries a signed
  play link: never keep, log or put it in a fixture. 关注 stays on the web card and `/x/relation/modify`.
- A control wrapped in `Semantics(excludeSemantics: true)` needs its own `onTap:` on the Semantics (`ChromeTap`'s
  pattern): excluding drops the GestureDetector's tap action, and VoiceOver and ghosthand then press nothing (slice
  12's space shipped that way to its first Windows check).
- Panels, sheets, dialogs and the comment layers are in-page overlays in the page's Stack, not routes; back closes
  them first.
- A logged-out action goes through `AppScope`'s `loginGate` (on the video page, its `_requestLogin`, which turns the
  phone upright first), never a 请先登录 toast. The login replays nothing; the gate always shows the page, since a
  -101 can come while the app still thinks it is logged in.
- The video page lays out by the screen's shape, not the orientation's presentation: Flutter's iOS engine keeps the
  old size for the first half of a turn, so landscape is laid out only once the size is wide (`_laidOut`, which
  `PlayerUi`'s panels and gestures follow). Code that acts on what the user asked for reads the presentation.
- The drawn turn (旋转动画 自绘): `TurnTakeover.swift` holds UIView animations off from before the rotation is
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
