# BiliFast (BiliNative) iOS app: inventory for a Flutter rebuild

Snapshot of BiliNative `main` at `a956b99` (2026-10-17), read-only.

**Path shorthand.** `App/` means `D:/Repos/Apps/BiliNative/ios/Sources/App/`. Every other path is written in full. Where I give a line number (`:N`), it is the line in that file.

---

## 1. `ios/Sources` layout

`D:/Repos/Apps/BiliNative/ios/Sources/` holds only `App/`: 132 Swift files, 19,394 lines.

Other things under `ios/`:
- `ios/project.yml`
- `ios/scripts/make_test_media.py`: uses ffmpeg to build Bilibili-like DASH test media (avc/hevc video and audio files with a sidx, plus `meta.json`) for CI.
- `ios/Resources`
- `ios/Tests`
- `ios/Packages/BiliCore`: modules AppLogic, BiliAPI, BiliShared, Danmaku, DashHLS, DevLog, LocalHTTP, Ripper, ripper-bench.
- `ios/Generated/` is gitignored. CI writes `AppKeys.swift` and `BiliNative-Info.plist` there.

### `App/` root: 7 files, 364 lines
AppDelegate 9, AppEnvironment 212, AppInfo 13, AppSettings 73, BiliNativeApp 28, Once 14, RootView 15.

- **What it does.** `@main BiliNativeApp` runs `DevLogSetup.install()` and `BorrowedIcon.registerFont()`. It sets the AVAudioSession to `.playback`/`.moviePlayback`, then shows `RootView` in a `WindowGroup` with `AppEnvironment` injected.
- `AppDelegate` returns `OrientationController.shared.mask`.
- `AppEnvironment` is the app-wide container: settings, recents, navigator, `CookieJar` plus Keychain persistence, `BiliClient`, the BTR `PlaybackRouter`/`LocalServer`, transports, `CodecMemory`, `BlockRuleStore`, account state, mid, face and emote packages. It also handles login and logout.
- **Key types:** `AppEnvironment.Account` (`unknown`, `loggedOut`, `loggedIn(name:vip:)`, `expired`), `AppSettings` (+`NodeChoice`), `Once`.

### `App/Account`: 5 files, 534 lines
AppTokenStore 53, KeychainStore 71, LoginView 105, TVLoginModel 109, TVLoginSheet 196.

- Keychain storage for the cookies and for the app token.
- The web login screen (a WKWebView).
- The TV QR-login confirmation that yields the access token 不喜欢 needs.
- **Key types:** `KeychainStore`, `AppTokenStore`, `LoginView`/`LoginWebView`, `TVLoginModel` (+`State`), `TVLoginSheet`, `TVConfirmWebView`, `TVLoginGate`/`tvLoginGate`.

### `App/Comments`: 12 files, 2,071 lines
CommentBadges 153, CommentRow 381, CommentsModel 336, CommentsTab 205, CommentsTheme 144, Composer 217, ComposerModel 96, EmotePanel 171, PictureViewer 81, RecentEmotes 29, RichTextView 187, ThreadView 71.

- Covers the 评论 tab, 评论详情 (reply thread), the composer with emotes, the full-screen picture viewer and rich text (emotes, mentions, links, timestamps).
- **Key types:** `CommentsModel` (+`ThreadState`), `ReplyTarget`, `PictureViewing`, `CommentDrafts`, `CommentsTab`, `SortHeader`, `ListFooter`, `CommentBar`, `CommentRow`, `CommentAvatar`, `CommentMeta`, `ReplyPreview`, `LevelBadge`, `PinnedTag`, `ThreadView`, `Composer`, `ComposerModel`, `EmotePanel`, `RecentEmotes`, `RichTextView`/`RichTextActions`, `EmoteCache`.

### `App/Danmaku`: 9 files, 2,000 lines
BlockRuleStore 125, BlockWordsView 229, DanmakuController 227, DanmakuSendBar 243, DanmakuSendModel 102, DanmakuSettings 37, DanmakuSettingsPanel 511, DanmakuStylePanel 216, DanmakuView 310.

- Fetches danmaku segments and filters them, renders them on a CADisplayLink, and holds the 弹幕设置 panel, the synced block words, and sending with the style panel.
- **Key types:** `DanmakuController`, `DanmakuView`, `DanmakuSettings`, `DanmakuSettingsPanel`, `BlockRuleStore`, `BlockWordsView`, `DanmakuSendModel`/`DanmakuStyle`, `DanmakuSendBar`, `DanmakuStylePanel`, `DanmakuSendTheme`.

### `App/DebugSupport`: 24 files, 2,088 lines, all `#if DEBUG`
ActionPromptsDemo 37, ActionsDemo 40, ChromeDemo 81, CommentsDemo 68, DanmakuSendDemo 38, DebugSupport 366, DemoFixtures+Actions 29, +BlockRules 30, +Comments 242, +Composer 129, +Danmaku 94, +DanmakuSend 11, +Favourites 35, +Home 150, +Intro 66, +VideoPage 126, DemoFixtures 63, DemoPanel 21, DemoPlayback 145, DemoTransport 12, HeapReferrers 176, IntroDemo 50, LeakCheckDemo 43, PlaybackFixtures 36.

- Supports `-DemoData` (canned JSON through `DemoTransport`, nothing goes to the network) and the `-DemoScreen`/`-DemoPanel` staging used for screenshots.
- `DemoPlayback` plays the CI test media from `MEDIA_DIR`.
- Also holds test helpers (`FakeCDNServer`, `FixturePlayback`, `CapturingLogSink`) and the leak checker (`HeapReferrers` scans the heap).
- Demo IDs: bvidA/B/C = `BV1Dm4y1A7aa`/`bb`/`cc`. Video A has 2 parts and opens a 合集 with two sections.

### `App/DevTools`: 6 files, 626 lines
CrashReport 253, CrashReporter 97, DevLogSetup 94, DeviceInfo 31, LogPoster 119, LogServerDiscovery 32.

- File log sink (always on), the network log sink to the PC (only with `DEV_TOOLS`), Bonjour discovery, and MetricKit crash/hang reports.
- **Key types:** `DevLogSetup`, `LogTarget`, `LogPoster`, `LogServerDiscovery`, `CrashReporter`, `CrashReport`.

### `App/History`: 2 files, 354 lines
HistoryModel 127, HistoryView 227.

- 历史记录 (video history only), grouped by day, with endless scroll.
- **Key types:** `HistoryModel`, `HistorySection`, `HistoryView`, `RetryMessage`.

### `App/Home`: 5 files, 818 lines
AvatarMenu 130, FeedCard 150, FeedModel 84, HomeView 414, RecentStore 40.

- The home screen is the app shell: the link field, the 推荐 feed, the avatar dropdown (which stands in for 我的) and 最近打开.
- **Key types:** `HomeView`, `TopRow`, `RecommendTab`, `FeedGrid`, `RecentsView`, `FeedModel`, `FeedCardView`/`FeedMetrics`, `AccountAvatar`, `AvatarMenu`, `RecentStore`, `PlayerRoute`.

### `App/Playback`: 7 files, 1,751 lines
CodecMemory 42, DirectPlaylistLoader 41, LocalServer 296, OverlayStats 37, PlaybackBuilder 194, PlaybackController 1064, SeekTimer 77.

- Glue between the BTR engine and AVPlayer:
  - a 127.0.0.1 HTTP server for HLS;
  - direct mode through the `bilinative://playlist/...` resource loader;
  - per-part `PlaybackController` with modes BTR / 直连 / 直连（回退）, quality, codec and BTR switches;
  - stall and seek timing.
- **Key types:** `PlaybackController` (`Mode`, `Phase`), `PlaybackEnvironment`, `BiliPlayURLProvider`, `LocalServer`, `PlaybackBuilder`, `CodecMemory`, `OverlayStats`, `PlayingStream`, `SeekTimer`, `StallFilter`.

### `App/Player`: 7 files, 769 lines (3,494 with subfolders)
DeviceControls 126, FrameCapture 37, OrientationController 167, PlayerGestureView 104, PlayerHostView 237, PlayerSurface 39, StatsOverlay 59.

- The video surface (a plain UIView holding the AVPlayerLayer, the danmaku container and the gesture view), PiP, rotation, brightness and volume, and screenshots.
- **Key types:** `PlayerHostView` (+`FitMode`), `PlayerSurface`, `PlayerGestureView`/`PlayerGestureEvent`, `OrientationController` (`Presentation`: `inline`, `landscape`, `vertical`), `DeviceControls`, `FrameCapture`, `StatsOverlay`.

### `App/Player/Chrome`: 10 files, 1,655 lines
ChromeLayer 102, ChromeState 158, ChromeTheme 46, EndScreens 320, LandscapeChrome 338, PlayerHUD 60, PortraitControls 226, ProgressBar 150, TVThumb 35, VerticalChrome 220.

- Controls for the three presentations, the gesture HUD, the progress bar with chapters and the TV-face thumb, and the end screens.
- **Key types:** `ChromeState`, `HUD`, `ChromeLayer`, `PortraitControls`, `LandscapeChrome`, `VerticalChrome`, `EndScreenPortrait`/`EndScreenLandscape`, `ProgressBar`, `HiddenProgressLine`, `PlayerHUD`, `TVThumb`, `ChromeButton`, `MoreButton`, `PlayButton`, `CoinGlyph`, `QualityLabel`, `ScreenInsets`, `VerticalLayout`.

### `App/Player/Panels`: 6 files, 1,070 lines
EpisodesPanel 58, MorePanel 229, PanelLayer 86, QualityPanel 105, SidePanel 532, SpeedPanel 60.

- Panels over the player: a right-side panel in landscape, a bottom sheet in portrait.
- **Key types:** `PlayerPanel` (`quality`, `codec`, `speed`, `more`, `episodes`, `danmakuSettings`), `PanelLayer`, `SidePanel`, `PanelMetrics`, `TapCatcher` (id `panel.dismiss`), `PanelProbe`, `QualityPanel`, `CodecPanel`, `SpeedPanel`, `MorePanel`, `EpisodesPanel`, and the Panel* row widgets.

### `App/Settings`: 1 file, 160 lines
SettingsView 160. The 设置 sheet, including the 开发者 section.

### `App/Shared`: 6 files, 348 lines
BorrowedIcon 86, ImageLoader 96, RemoteImage 36, RichLink 40, Theme 44, Toast 46.

- Theme colours, the image cache, the borrowed icon font and art, the `bilinative://` rich-link scheme, and the toast.
- **Key values:**
  - `Theme.pink` = #FF6699, `text` #18191C, `secondaryText` #9499A0, `pageGrey` #F1F2F3.
  - Danmaku glyph code points in `custom_icon`: off 0xE801, on 0xE802, settings 0xE803.

### `App/VideoPage`: 25 files, 4,786 lines
ActionPrompts 26, ActionRow 170, ActionsModel 346, AppEnvironment+Playback 23, AppNavigator 102, BackSwipe 175, CoinDialog 390, CollapsingPlayer 104, CollectionSheet 319, FavouriteSheet 406, IntroTab 83, LoginGate 70, PageLifecycle 226, PageTabs 171, PageTheme 29, PartList 123, PiPKeeper 93, PlaybackControlling 44, RelatedList 129, TitleBlock 218, TripleRing 61, UploaderRow 93, VideoPageModel 681, VideoPageView 694, VideoRoute 10.

- The video page and its lifecycle in the navigation stack, actions, sheets, PiP keeping, swipe back and the collapsing player.
- **Key types:** `VideoPageView`, `VideoPageModel`, `VideoRoute`, `AppNavigator`/`AppPage`, `PageLifecycle`/`PageProbe`, `PiPKeeper`, `BackSwipe`, `PageTabsState`/`PageTab`/`PageSheet`, `ActionsModel`, `ActionPrompts`, `CoinDialog`, `FavouritesModel`/`FavouriteSheet`, `CollectionSheet`, `PartStrip`/`PartList`, `CollapsingPlayer`, `InlineFirst`, `LoginGate`.

---

## 2. Features → files

### 推荐 home feed
- `App/Home/HomeView.swift`
  - `NavigationStack(path: navigator.path)`.
  - `TopRow`: avatar, a "粘贴链接或BV号" field and a `PasteButton`. A paste is detected when the text grows by more than one character and `LinkParser` accepts it.
  - `RecommendTab` shows only 推荐.
  - `FeedGrid` is a 2-column `LazyVGrid`. It loads more when the 4th card from the end appears, supports `.refreshable`, and shows `RetryMessage` on failure.
  - A "选择分P" dialog appears for multi-part pasted links.
  - The feed refreshes when the login state flips (:64-75).
  - `watchLater` shows the toast 已添加至稍后再看.
- `App/Home/FeedModel.swift`: refresh asks for index 1, load more asks for the next index. It dedupes by bvid, asks up to 3 pages when one adds nothing, and uses a generation guard.
- `App/Home/FeedCard.swift`: 4:3 cover with counts and duration, 2-line title, tag / UP badge / uploader, and a ⋮ Menu with "稍后再看".
- Demo data: `App/DebugSupport/DemoFixtures+Home.swift`.

### Tab bar / shell
- **There is no tab bar.** `App/RootView.swift` shows `HomeView`; when the scene becomes active it refreshes the account if the state is unknown.
- Navigation is `App/VideoPage/AppNavigator.swift`:
  - `AppPage` is `.video(VideoRoute)`, `.history` or `.recents`;
  - `open` pushes a page; `show(model)` pushes a page for an existing model (the PiP restore);
  - `videoPageDestinations(history:recents:)` declares the destinations.
- `App/Home/AvatarMenu.swift:24-25` replaces 我的 with a dropdown: account row, then 历史记录, 最近打开, 设置.

### Video page

**Page container**
- `App/VideoPage/VideoPageView.swift`:
  - `PageLayout` measures size and safe area with `onGeometryChange` (:363-385).
  - `PlayerArea` holds the player and tab row, the thread overlay and the sheets.
  - `PlayerBox` holds the surface, stats, chrome and status.
  - Also: the comments model, actions, prompts, the login and TV-login gates, and the unfollow alert.
- `App/VideoPage/VideoPageModel.swift` covers load, part and episode play, end handling, heartbeats, side loads (related, uploader, tags, relation), the online count poll (30 s), the sleep timer and PiP.
- `App/VideoPage/PageLifecycle.swift`, `App/VideoPage/PageTabs.swift`, `App/VideoPage/PageTheme.swift`.

**Portrait player at the top**
- `PlayerBox` in VideoPageView.swift: 16:9 height (`width*9/16`) inline.
- `App/Player/Chrome/PortraitControls.swift`:
  - top: back, ⋮;
  - bottom: play, `ProgressBar`, time, 竖屏 button, 全屏 button;
  - when hidden, `HiddenProgressLine`.

**简介 tab**
- `App/VideoPage/IntroTab.swift`
- `UploaderRow.swift` (UploaderRow, FollowPill)
- `TitleBlock.swift`: 活动 tag, ⌄ expand to BV id, reprint notice, description rich runs, tags; `FlowLayout`.
- `ActionRow.swift`
- `PartList.swift` (`PartStrip`)
- `CollectionSheet.swift` (`CollectionRow`)
- `RelatedList.swift`

**评论 tab**
- `App/Comments/CommentsTab.swift`, used from VideoPageView :415-421.
- `CommentsSlot` is the spinner shown before the aid is known.

**评论详情**
- `App/Comments/ThreadView.swift`.
- Shown over the tab row in VideoPageView :500-513, sliding in from the bottom.
- A swipe back closes it through `BackSwipe.claim` (:547-573).

### Player

**Surface**
- `App/Player/PlayerSurface.swift` (UIViewRepresentable) and `App/Player/PlayerHostView.swift`:
  - a `VideoView` subview whose `layerClass` is `AVPlayerLayer`, plus `danmakuContainer` and `gestureView`;
  - `FitMode` (fit / fill / stretch / ratio16x9 / ratio4x3) sets gravity and the frame;
  - mirroring uses a transform;
  - `AVPlayerItemVideoOutput` is attached for screenshots.
- One AVPlayer per page: `VideoPageModel.player` (:38-40).

**Chrome**
- `App/Player/Chrome/ChromeLayer.swift` switches on `OrientationController.presentation`.
- `App/Player/Chrome/LandscapeChrome.swift`:
  - top bar: title (the part name for multi-part videos), "N人正在看", avatar and "+ 关注"/"已关注";
  - top-right icons: 点赞, 评论, 收藏, 投币, 分享, ⋮;
  - right edge: 截图 and the lock;
  - bottom: time, bar, play, 弹 toggle, 弹幕设置, the "发个友善的弹幕见证当下" field, 倍速, quality, 选集;
  - a faint online count while the controls are hidden.
- `App/Player/Chrome/VerticalChrome.swift` (竖屏): back, ⋮, action column, title + views, 发弹幕 field with the 弹 toggle, 详情页 (exits to inline), 横屏全屏.
- `ProgressBar.swift`: chapter ticks, the chapter title while dragging, vertical style.
- `TVThumb.swift`, `PlayerHUD.swift` (倍速中 pill, seek label, brightness/volume), `ChromeTheme.swift` (hide delay 3 s).

**Gestures**
- `App/Player/PlayerGestureView.swift`:
  - tap; double tap; hold (0.35 s);
  - a 1-finger pan with an axis lock;
  - vertical "level" pans only in full screen;
  - in full screen, the 25 pt screen edges are left to the system.
- `App/Player/Chrome/ChromeState.swift:70-125`:

  | Gesture | Effect |
  |---|---|
  | tap | show/hide chrome |
  | double tap | `togglePlay` |
  | hold | rate 2 and `HUD.speedUp`; release restores `page.rate` |
  | horizontal drag | seek, 90 s per screen width (`GestureMath`), shown via `scrubbing` |
  | vertical drag, left half | brightness |
  | vertical drag, right half | volume |

- `App/Player/DeviceControls.swift`: brightness is saved and restored; a hidden `MPVolumeView` slider sets volume; hardware volume changes post a notification.
- Constants live in BiliCore `AppLogic/GestureMath.swift`: `seekSecondsPerWidth` 90, `axisLockDistance` 10, `edgeInset` 25.

**Full screen, rotation lock, OrientationController**
- `App/Player/OrientationController.swift`:
  - `presentation`, `mask` (when locked in landscape it keeps the current side);
  - `begin`/`end(owner:)` (the latest begin wins);
  - `deviceOrientationChanged` (ignored when locked or the video is vertical);
  - `awaitingLandscape`: after the button, portrait only exits once the phone has really been landscape;
  - `requestGeometryUpdate` with a revert when refused.
- Called from:
  - `App/AppDelegate.swift`;
  - the full-screen button in PortraitControls.swift:89-95 (a vertical video goes to `enterVertical`);
  - the 竖屏 button (:48-58);
  - the lock in LandscapeChrome.swift:44-47.

**Panels**
- `App/Player/Panels/PanelLayer.swift` (routing), `SidePanel.swift` (default side width 0.4, portrait height 0.62; quality uses 0.3, speed is a column at 0.32, ⋮ uses 0.8).
- 清晰度 — `QualityPanel.swift`: 自动 plus options best first, a 大会员 badge, the subtitle 绚丽色彩，沉浸体验 for qn 125, and the toast 开通大会员后可观看. 高级设置 opens `CodecPanel` (HEVC / AV1 / AVC).
- 倍速 — `SpeedPanel.swift`: 3.0X, 2.0X, 1.5X, 1.25X, 1.0X, 0.75X, 0.5X. A column in landscape, a 4-column grid in portrait.
- ⋮ — `MorePanel.swift`:
  - 稍后再看, 小窗播放;
  - 定时关闭: 不开启 / 15:00 / 30:00 / 60:00 / 自定义 (wheel, 1-180 minutes);
  - 自动连播;
  - 循环播放: 单集循环 / 列表循环 / 不循环;
  - 镜像翻转;
  - 画面尺寸: 适应 / 填充 / 拉伸 / 16:9 / 4:3;
  - a 测试 card: BTR 加速, 显示统计.
- 选集 — `EpisodesPanel.swift`: the parts, otherwise the 合集 section holding the current video.
- Not built (compared against docs/official-app-reference.md):
  - in ⋮: 听视频, 投屏, 后台听视频, 色觉辅助, 播放反馈, 编辑播放器;
  - in 弹幕设置: 人像防挡 and 当前弹幕列表.

**End screens**
- `App/Player/Chrome/EndScreens.swift`:
  - portrait: 推荐视频 with the first related video, 立即播放, 重播, 分享;
  - landscape: uploader with 关注, 重播 | 点赞 投币 收藏 分享, a row of related videos.
- Shown when `VideoPageModel.ended`.

**Screenshot**
- `App/Player/FrameCapture.swift`, called from `LandscapeChrome.capture()` (:242-250).
- Toasts: 已保存到相册 / 保存失败.

**PiP**
- `PlayerHostView` creates an `AVPictureInPictureController(playerLayer:)` with `canStartPictureInPictureAutomaticallyFromInline = true` (:180-186). The restore handshake is `restoreForPiPStop` (:132-151).
- `App/VideoPage/PiPKeeper.swift`:
  - keeps the page that was closed while PiP plays it;
  - `pageShown` decides whether the shown page may resume;
  - `willPlay` releases the kept page (one video at a time);
  - `restore` calls `navigator.show(model)`.
- `VideoPageModel`: `pipChanged`, `continueInPiP`, `cover()` stops PiP, and autoplay is allowed in the background only with PiP (:314-319).
- `VideoPageView.init(model:)` and `AppNavigator.existingModel` let a restored page reuse its model.

### Danmaku
- **Display:** `App/Danmaku/DanmakuView.swift` (CADisplayLink reads the player clock; lanes; outlined text; the user's own danmaku get a white box). `DanmakuController.swift` fetches segments ahead of the playhead, filters them, applies block rules, notices when the uploader closed danmaku, and has `showOwn`. `DanmakuSettings.swift`.
- **弹幕设置:** `DanmakuSettingsPanel.swift`:
  - 显示区域 (5 stops), 不透明度;
  - 查看更多 adds 字体大小 and 弹幕速度 (极慢, 较慢, 适中, 较快, 极快);
  - 按弹幕类型屏蔽: 固定, 滚动, 彩色, 高级, 计数;
  - 重复弹幕隐藏, 底部字幕区域防挡, 弹幕观看屏蔽词;
  - 添加屏蔽词 >, 重置弹幕设置.
- **Block words:** `BlockWordsView.swift` (关键词 / 正则 / 用户; swipe to delete; inside the panel in landscape, a pushed page in portrait). `BlockRuleStore.swift` is shared, cached for 10 minutes, and stores a user UID as its hash.
- **Sending:**
  - `DanmakuSendBar.swift`: an A (style) button, the field and send; 100 characters max; follows the keyboard by hand.
  - `DanmakuSendModel.swift` (`DanmakuStyle`): font size 25 / 18, mode 1 / 5 / 4, 12 colours plus a VIP gradient.
  - `DanmakuStylePanel.swift`: 弹幕字号, 弹幕类型, 弹幕颜色.
  - Entry points: the 点我发弹幕 field in `PageTabRow`, the landscape field, the 竖屏 发弹幕 field.

### Actions
- `App/VideoPage/ActionsModel.swift`: optimistic updates with a per-field rollback. Covers like, dislike, triple, coin (max 2, or 1 for a repost), favourites, follow, share count, and prompts.
- `ActionRow.swift`:
  - 点赞: tap toggles like; long press does 三连 (`TripleTiming` delay 0.2 s + fill 1.2 s, `TripleRing.swift`);
  - 不喜欢 is dimmed when the build has no keys;
  - 投币, 收藏, 分享 (UIActivityViewController via `SharePresenter`).
- **Coin dialog:** `CoinDialog.swift` is an in-page overlay with crates for 1 or 2 coins, the balance, and 同时点赞内容 (`coin.alsoLike`). The balance is asked up to 3 times (VideoPageView.swift:299-322).
- **Favourites:** `FavouriteSheet.swift` with `FavouritesModel`. It sends only the difference, supports 新建收藏夹 with 私密, and shows a light bottom sheet in portrait or a dark panel in landscape.
- **不喜欢:**
  - `ActionsModel.toggleDislike` (:125-148) sets `needsAppToken` when there is no token, or when the server answers -101 / -2;
  - VideoPageView.swift:94-95 and :151-155 open the gate;
  - `App/Account/TVLoginModel.swift` and `TVLoginSheet.swift` (title "授权不喜欢").
- **Watch later:** `MorePanel.swift:207-229` (`VideoPageModel.addToWatchLater`), the feed card menu, and the ⋮ on related rows.

### 关注
- `ActionsModel.tapFollow`: following again asks "确定不再关注？" (alert at VideoPageView.swift:87-93).
- Shown in `UploaderRow.FollowPill`, `LandscapeChrome` ("+ 关注" / "已关注"), `VerticalChrome.swift:84` and `EndScreens.swift:153`.

### 分P
- `PartList.swift`: `PartStrip` ("选集 N/M >" chips) and `PartList` as a sheet.
- `EpisodesPanel.swift`; HomeView's "选择分P" dialog.
- Without a cid, `VideoPageModel.open` picks Bilibili's `lastPlayCid` (:218-227).

### 合集 sheet
- `CollectionSheet.swift`: `CollectionRow`, and `CollectionSheet` (title, intro with 展开, 选集 with 正序/倒序, the playing episode in pink with `PlayingBars`).
- `PageSheetFrame` is an overlay, never a presented controller.
- Opened by setting `PageTabsState.sheet = .collection`.

### Related videos
- `RelatedList.swift` (`RelatedRow`, `VideoCounts`, `VideoThumb`, ⋮ 稍后再看).
- `VideoPageModel.fetchRelated` and `openRelated` push a new page.
- From full screen, `ChromeLayer.open` returns inline first and waits 450 ms.

### Comments

**Model:** `CommentsModel.swift`
- sort hot / time; offset paging; the pinned comment;
- sections closed by codes 12002 / 12061;
- thread paging;
- `toggleLike`, `toggleHate`, `delete` (with confirmation), all with rollback.

**Views**
- `CommentsTab.swift`: 热门评论 / 最新评论, 按热度 / 按时间, footer "没有更多了" or "还没有评论，快来抢沙发吧", and the "哎呦，不错哦，发条评论吧" bar.
- `CommentRow.swift`: pendant, 大, LV badge, fan card, pictures, meta line (回复 👍 👎 ⋮ 复制 / 删除), `ReplyPreview` ("共N条回复").
- `CommentBadges.swift`, `CommentsTheme.swift`, `PictureViewer.swift`.
- `RichTextView.swift` together with `App/Shared/RichLink.swift`: the `bilinative` scheme carries timestamps and video ids.

**Composer:** `Composer.swift`, `ComposerModel.swift` (root/parent, the prefix "回复 @name :", drafts that survive), `EmotePanel.swift` (最近使用, 所有表情, 颜文字), `RecentEmotes.swift`, `AppEnvironment.loadEmotePackages`.

**Player shrinking to 继续播放:**
- `CollapsingPlayer.swift`: bar height 56; shrinks only while paused and not ended; the `collapsingPlayerScroll` modifier; `CollapsedPlayerBar` with 继续播放, back and ⋮.
- `VideoPageView.PlayerArea` (:453-529, uses `collapseFrom`).

### 历史记录
- `App/History/HistoryModel.swift`:
  - pages through the cursor until an empty page; -101 means `needsLogin`;
  - day groups 今天 / 昨天 / date;
  - `route(for:)` resumes at the saved progress; progress -1 means finished, shown as 已看完, and starts at 0.
- `HistoryView.swift`: 登录后查看历史记录, 还没有看过视频, a progress bar on each cover.
- History is fed by heartbeats (`VideoPageModel.sendHeartbeat`, only when logged in).

### 我的
- No 我的 page; `AvatarMenu`. The account row shows one of:
  - 未登录 with a 登录 pill;
  - 登录已过期 with 重新登录;
  - the name (pink for VIP), a 大会员 badge and 退出;
  - 无法获取账号信息，点按重试.

### Settings: `App/Settings/SettingsView.swift` plus `App/AppSettings.swift`

**Settings screen sections**
- 加速: CDN 节点 (海外节点 / 大陆节点), BTR 加速（默认）.
- 数据: 重置编码记忆, 清除最近观看, 清除日志.
- 开发者 (`DEV_TOOLS` builds only).
- 版本 and an MIT note for BTR.

**UserDefaults keys and defaults** (AppSettings.swift:18-32, :57-72)

| Key | Default | Notes |
|---|---|---|
| `settings.node` | `"overseas"` | or `mainland` |
| `settings.quality` | `120` | 120 = 4K, 80 = 1080P |
| `settings.codec` | `"hevc"` | or `av1`, `avc` |
| `settings.btr` | `true` | |
| `settings.overlay` | `true` | |
| `settings.log.enabled` | `false` | |
| `settings.log.manual` | `""` | |
| `settings.log.service` | `""` | |
| `player.autoplay` | `true` | |
| `player.loop` | `"none"` | `single`, `list`, `none` |
| `player.fit` | `"fit"` | |
| `coin.alsoLike` | `true` | |
| `danmaku.settings` | JSON, see below | |

`danmaku.settings` defaults:
- `enabled` true, `area` 0.5 (stops 0.1 / 0.25 / 0.5 / 0.75 / 1.0), `opacity` 1.0, `scale` 1.0;
- `speed` 2 = index into [11, 9, 7, 5.5, 4] seconds;
- `filter`: `blockFixed`, `blockScroll`, `blockColored`, `blockAdvanced`, `blockCount`, `dedupe` and `hideBottom` all false; `applyRules` true.

**Other UserDefaults keys**

| Key | Contents |
|---|---|
| `home.recents` | JSON `[PlayerRoute]`, capped at 30 |
| `playback.failedCodecs` | `[String]` |
| `playback.hev1LabelsHoldHEV1` | Bool |
| `emotes.recent` | JSON of token / url / large, capped at 14 |
| `danmaku.styleHintSeen` | `@AppStorage` Bool, default false |
| `devtools.crashReportsSent` | |

DEBUG-only launch keys: `DemoData`, `DemoScreen`, `DemoPanel`, `DemoPortrait`, `DemoPauseAt`, `DemoDanmakuMore`, `DemoBlockWords`.

### 开发者 page
- SettingsView.swift:58-102, compiled only with `#if DEV_TOOLS`:
  - 发送日志到电脑 toggle;
  - the Bonjour service list (`LogServerDiscovery`), or 或手动输入 IP:端口;
  - a status line;
  - 准备导出日志 / 导出日志文件;
  - 测试崩溃 → asks "让应用立即崩溃？" → `fatalError("开发者测试崩溃")`.
- `DevLogSetup`:
  - a FileSink in `Caches/logs`, last 20 MB;
  - a NetworkSink with an ack store that replays unsent events.
- `LogPoster` sends `POST /logs`, `application/x-ndjson`, with a 10 s deadline.

### Login
- `App/Account/LoginView.swift` is a WKWebView on `https://passport.bilibili.com/login` (:74). Bilibili's own page handles password, SMS or QR and its captcha.
  - Stale bilibili cookies are deleted before the page loads (:65-84).
  - It watches the cookie store and `didFinish`.
  - Once a non-empty `SESSDATA` appears, every bilibili-domain cookie (name→value) goes to `env.didLogin` (:95-103).
- `AppEnvironment.didLogin` (:166-180) merges the cookies into the `CookieJar` and retries the account check 3 times.
- Logout (:182-195) clears the jar, the Keychain cookies, the app token and all `WKWebsiteDataStore` data.
- `LoginGate` presents it, returning inline first.

### Swipe back
- `App/VideoPage/BackSwipe.swift` takes over `interactivePopGestureRecognizer` and iOS 26's `interactiveContentPopGestureRecognizer`, and adds a `ClaimedSwipe` pan used to close 评论详情.
- Installed from `PageLifecycle.locate()` (PageLifecycle.swift:178). Both pages hide the navigation bar.
- Tested with real touches in `SwipeBackUITests`.

### Autoplay and resume
- **Autoplay rule** (BiliCore `AppLogic/Autoplay.swift`):
  - 单集循环 replays;
  - otherwise, if autoplay is on or the loop is the list: the next part, then the next 合集 episode;
  - a list loop wraps to the start.
- `VideoPageModel.handleEnd` (:305-325) applies it; in the background without PiP it shows the end screen instead.
- **Resume** (`VideoPageModel.start`, :280-303): without a start time, the part loads paused, then seeks to `ResumePoint.start` (same cid only, and not within 5 s of the end), then plays. `VideoRoute.startSeconds` overrides this.
- The playback rate is kept across parts.

---

## 3. Login and cookie storage

### Cookies
- File: `App/Account/KeychainStore.swift`.
- Item:
  - `kSecClass` = `kSecClassGenericPassword`;
  - `kSecAttrService` = `"com.kaichuan.bilinative.cookies"` (:15);
  - `kSecAttrAccount` = `"bilibili"` (:16).
- `kSecAttrAccessible` = `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, set on save (:56).
- No `kSecAttrAccessGroup`, no synchronizable flag.
- **Value format:** `JSONEncoder` of `[String: String]`, a flat JSON object of cookie name → value. No domain, path or expiry is stored.
- Functions:
  - `load()` returns `.cookies`, `.notFound` or `.failed(OSStatus)`;
  - `saveCookies(_:)` tries `SecItemUpdate`, then `SecItemAdd` on `errSecItemNotFound`; an empty dict deletes the item;
  - `deleteCookies()`.
- How the app uses it (`App/AppEnvironment.swift`):
  - loaded at init (:59-63);
  - persisted on every `CookieJar.onChange` through the serial queue `bilinative.cookies.persist` (:72-78);
  - writes are blocked after a failed read until a read succeeds or the user logs in or out (:50-52, :197-211);
  - demo mode puts dummy cookies in the jar and never persists them (:69-71).

### TV-login token for 不喜欢
- File: `App/Account/AppTokenStore.swift`.
- Same pattern as the cookies:
  - generic password, service `"com.kaichuan.bilinative.apptoken"` (:8), account `"bilibili"` (:9);
  - the same accessibility attribute (:38);
  - the value is the token as raw UTF-8 bytes.
- `TVLoginModel` saves it after `/x/passport-tv-login/qrcode/auth_code` and polling `/x/passport-tv-login/qrcode/poll` every 2 s, tolerating 5 network failures.
- It is deleted on logout (AppEnvironment.swift:186-189), and when the server answers -101 / -2.
- The call it enables is `/x/v2/view/dislike` on the app API host, sent without cookies.

### `BILI_APP_KEYS`
- `D:/Repos/Apps/BiliNative/tools/write_app_keys.py <out>` reads the env var `BILI_APP_KEYS` in the form `appkey:appsec`.
  - It masks both halves with `::add-mask::`.
  - It writes `ios/Generated/AppKeys.swift` containing `enum AppKeys { static let tv: (key: String, secret: String)? }`.
  - When the variable is missing or malformed, it writes `nil` and prints a notice.
- It runs in the "App keys" step of both workflows, with `secrets.BILI_APP_KEYS`, before xcodegen. The m2 checklist sets it as a repo secret with `gh secret set BILI_APP_KEYS`.
- `project.yml` compiles `Generated/AppKeys.swift`.
- The app reads it through `AppSigner.tv` (TVLoginModel.swift:6-11). `nil` means 不喜欢 is greyed and taps show "此版本不支持不喜欢".

---

## 4. `ios/project.yml`
- Bundle id `com.kaichuan.bilifast` (tests `.tests`, UI tests `.uitests`). iOS 26.0, iPhone only (`TARGETED_DEVICE_FAMILY` 1).
- Swift 5.0, `MARKETING_VERSION` 0.1.0, `CURRENT_PROJECT_VERSION` 1, Automatic signing, `developmentLanguage` zh-Hans.
- **Info.plist** (`Generated/BiliNative-Info.plist`):
  - `CFBundleDisplayName` BiliFast;
  - `ITSAppUsesNonExemptEncryption` false;
  - `UILaunchScreen` {};
  - `UIBackgroundModes`: [audio];
  - `NSAppTransportSecurity.NSAllowsLocalNetworking` true;
  - `NSPhotoLibraryAddUsageDescription`: 用于把视频截图保存到相册。;
  - `NSLocalNetworkUsageDescription`: 用于把调试日志发送到你电脑上的日志服务器。;
  - `NSBonjourServices`: [`_bilinative-log._tcp`];
  - `UISupportedInterfaceOrientations`: Portrait, LandscapeLeft, LandscapeRight;
  - iPad orientations add PortraitUpsideDown.
- **Entitlements:** none declared, and there is no `.entitlements` file in the repo.
- **Compilation conditions:** Debug has `DEBUG DEV_TOOLS`. Release has `DEV_TOOLS` as well. m1-deferred lists this as something to fix before any public release.
- **Schemes:** `BiliNative` (app plus `BiliNativeTests`, archive in Release) and `BiliNativeUI` (`BiliNativeUITests` only).
- **Resources** (`D:/Repos/Apps/BiliNative/ios/Resources`):
  - `Assets.xcassets/AppIcon.appiconset/icon-1024.png`;
  - `Localizable.xcstrings`, which is empty (sourceLanguage zh-Hans);
  - `Borrowed/` (from PiliPlus): `custom_icon.ttf`, `ic_22_gun_sister.png`, `ic_22_mario.png`, `ic_22_not_enough_pay.png`, `ic_coins_one.png`, `ic_coins_two.png`, `ic_left.png`, `ic_left_disable.png`, `ic_panel_close.png`, `ic_pay_coins_box.png`, `ic_pay_coins_close.png`, `ic_right.png`, `ic_right_disable.png`, `ic_thunder_1.png`, `ic_thunder_2.png`, `ic_thunder_3.png`.

---

## 5. `ios/Tests`

### AppTests: 34 files, 5,754 lines, 243 tests
Format: file — lines / test count.

| File | Lines / tests |
|---|---|
| ActionPresentationTests | 245/5 |
| ActionsDislikeTests | 136/8 |
| ActionsModelTests | 346/16 |
| AppKeysTests | 13/1 |
| AppSettingsTests | 36/2 |
| AppTokenStoreTests | 45/4 |
| BlockRuleStoreTests | 177/12 |
| BorrowedIconTests | 23/2 |
| ChromeStateTests | 162/4 |
| CodecMemoryTests | 24/2 |
| CommentsModelTests | 342/10 |
| ComposerModelTests | 241/7 |
| CrashReportTests | 177/7 |
| DanmakuControllerTests | 231/10 |
| DanmakuSendTests | 188/10 |
| FavouritesModelTests | 43/1 |
| FeedModelTests | 119/4 |
| HistoryModelTests | 147/6 |
| HomeFlowTests | 226/3 |
| ImageLoaderTests | 100/5 |
| IntroTabTests | 215/7 |
| KeychainStoreTests | 25/2 |
| LocalServerTests | 232/14 |
| LogPosterTests | 90/6 |
| PageLifecycleTests | 320/9 |
| PageReleaseTests | 98/1 |
| PanelPresentationTests | 228/7 |
| PlaybackIntegrationTests | 177/8 |
| PlaybackPolicyTests | 176/19 |
| PlayerTransitionTests | 284/10 |
| RecentStoreTests | 33/2 |
| SmokeTests | 23/3 |
| TVLoginModelTests | 293/10 |
| VideoPageModelTests | 539/26 |

### UITests: `SwipeBackUITests.swift`, 107 lines, 7 tests

### What the key tests check
- **PlayerTransitionTests**, all on the simulator:
  - enter and leave landscape while the surface stays in its window and is re-laid out;
  - a vertical video ignores turning, and the lock holds landscape;
  - landscape entered by the button waits for a real turn before portrait exits;
  - a refused rotation reverts to inline;
  - `end` forgets the vertical flag and the lock;
  - a covered page keeps ownership and its vertical flag, whatever order the stack events arrive in;
  - popping in landscape returns to portrait;
  - the PiP controller exists, can start automatically, and starts and stops without the surface leaving its window (skipped where PiP is unsupported);
  - the share sheet comes up over landscape and goes away;
  - vertical pans are refused inline and accepted in full screen, and the edges are detected.
- **PageReleaseTests:** pushes a real `VideoPageView` with demo data, pops it, and asserts `VideoPageModel`, `ActionsModel` and `CommentsModel` are freed. Closures once captured the page view's state.
- **SwipeBackUITests**, launched with `-DemoData YES` and opening a feed card, swiping at about 1500 pt/s:
  - edge swipe on 简介 and on the player goes back;
  - a swipe in the middle of 简介 goes back;
  - on 评论, the first swipe pages to 简介 and the second goes back;
  - a sideways drag in the middle of the player stays on the page (it seeks);
  - a swipe closes the reply thread first;
  - 简介 still scrolls vertically.

---

## 6. Debug launch arguments
- `-DemoData YES`: invented fixtures, demo cookies, `DemoPlayback`.
- `-DemoScreen <name>`, from the `shoot` list in `.github/workflows/ios-compile.yml` and from code:
  - `settings` (shot without `-DemoData`), `home-menu`, `history`, `page`;
  - `danmaku-send`, `danmaku-style`, `danmaku-portrait`, `danmaku-landscape`, `danmaku-send-inline`;
  - `player-portrait`, `player-landscape`, `player-vertical`, `hud-speed`;
  - `end-portrait`, `end-landscape`;
  - `page-intro`, `page-intro-expanded`, `sheet-collection`, `page-collapsed`;
  - `comments`, `comments-thread`, `picture-viewer`, `composer-emotes`;
  - `page-actions-active`, `player-landscape-actions`, `coin-dialog`, `favourite-sheet`;
  - `leak-check`: code and the workflow's `leaks` step only.
- Plain `-DemoData YES` with no screen gives `00-demo-home`. A launch with no arguments gives `01-first-launch`.
- Modifiers:
  - `-DemoPanel quality|codec|speed|more|episodes|danmaku` (`codec` and `episodes` exist in code but are not in the shoot list);
  - `-DemoPortrait YES`, `-DemoDanmakuMore YES`, `-DemoBlockWords YES`;
  - `-DemoPauseAt <s>` (26 for the danmaku shots).
- Where they are handled: `HomeView.stageDemo` (:93-113), `ChromeDemo.route`, `IntroDemo`, `CommentsDemo`, `ActionsDemo`, `ActionPromptsDemo`, `DanmakuSendDemo`, `DemoPanel`, `LeakCheckDemo`.

---

## 7. CI and TestFlight

### `.github/workflows/testflight.yml`
- Started only by `workflow_dispatch` with inputs `sha`, `upload`, `create_signing`. Runs only on main and only if `sha` is the head.
- Environment `testflight`; concurrency group `testflight`; `cache-mode: none`.
- Env: `BUNDLE_ID` com.kaichuan.bilifast, `ASC_APP_ID` "6823476667", `PROJECT` ios/BiliNative.xcodeproj, `SCHEME` BiliNative, `BUILD_NUMBER_FLOOR` "0", `APP_STORE_CONNECT_DISABLE_JWT_CACHE` 1.
- Secret names: `BILI_APP_KEYS`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERT_KEY_B64`, `SIGNING_NAME`.
- Job "Signed build" on `macos-26`:
  1. Select the newest Xcode; Python 3.13; `pip install --require-hashes -r scripts/testflight-requirements.txt` (Codemagic cli-tools).
  2. App keys.
  3. `brew install xcodegen` and `cd ios && xcodegen generate`.
  4. Signing: `keychain initialize` with a random password; `app-store-connect fetch-signing-files --type IOS_APP_STORE [--create]` using the base64 cert key; `keychain add-certificates`; `security set-key-partition-list`.
  5. `xcode-project use-profiles`.
  6. **Build number:** `app-store-connect get-latest-testflight-build-number $ASC_APP_ID --all-versions`, then `next = max(latest, BUILD_NUMBER_FLOOR) + 1`. A new app counts as latest 0.
  7. `xcode-project build-ipa --archive-xcargs "COMPILER_INDEX_STORE_ENABLE=NO CURRENT_PROJECT_VERSION=$BUILD_NUMBER"`.
  8. `app-store-connect publish` when uploading.
- Job "Apple processing" on `ubuntu-latest`: polls `builds list ... processingState` every 30 s for up to 1 h. VALID passes; FAILED or INVALID fails.

### `D:/Repos/Apps/BiliNative/scripts/testflight.py`
- Repo `KaiC5504/BiliNative`, workflow `testflight.yml`, environment `testflight`.
- Required environment secrets: the 3 `APP_STORE_CONNECT_*` and `CERT_KEY_B64`.
- Commands:
  - `status`;
  - `start [--dry-run] [--create-signing] [--again]`: checks the environment is locked to main and has its secrets, refuses a sha that already shipped or a busy run, dispatches with `sha=origin/main`, and verifies the run title;
  - `watch`.

### `.github/workflows/ios-compile.yml`
- Triggers: a push touching `ios/**`, `tools/write_app_keys.py` or the workflow, and dispatch with inputs `tests`, `shots`, `leaks`, `runner`.
- Runner: `inputs.runner || 'macos-26'`; the choice is `macos-26` or `xcode-27`.
- Steps:
  1. Select the newest Xcode.
  2. `swift test` for BiliCore, only on a main push (`FULL_RUN`).
  3. App keys; xcodegen.
  4. Assert Debug has `DEBUG` and `DEV_TOOLS`, and Release has `DEV_TOOLS`.
  5. Boot the newest iOS simulator, preferring an iPhone 17 Pro Max.
  6. `build-for-testing` unsigned.
  7. Cache or build test media with ffmpeg.
  8. `test-without-building` (optionally `-only-testing`).
  9. Optional leak check.
  10. Release build in the background (`FULL_RUN`).
  11. Install, launch and screenshot every `shoot` entry.
  12. Collect crash reports; upload the `simulator-screenshots` artifact.

---

## 8. Docs

### `D:/Repos/Apps/BiliNative/docs/official-app-reference.md`
A table of 28 screenshots (01-28), then these sections:

| Section | What the screen shows |
|---|---|
| 01 首页 | Avatar and search, category tabs (推荐 selected), 2-column cards with 16:10 cover, counts, duration, 2-line title, tag / UP / ⋮; bottom tab bar 首页 关注 + 消息 我的. |
| 02 我的 | Header (avatar, pink name, LV, 大会员 pill, B币 / 硬币), stats, 续订会员 card, 4 shortcuts, 我的服务 grid. |
| 03 Video page, portrait | 16:9 player; 简介 / 评论 tabs with 弹; uploader row; title with 活动 tag and ⌄; meta; action row; 合集 row; chips; related list. |
| 04 Player, landscape | Top bar (title, online, avatar + 关注), top-right icons, screenshot / lock on the right edge, time and bar with the TV-face thumb, bottom row with danmaku input, 倍速, quality. |
| 05 清晰度 picker | Right panel of cards (自动, HDR 真彩, 4K…) with 大会员 pills and 高级设置 >. |
| 06 倍速 picker | Right-aligned text column 3.0X to 0.5X on the dimmed video. |
| 07-08 弹幕设置 panel | Sliders, 按弹幕类型屏蔽 icons, toggles, 更多工具, 重置. |
| 09 竖屏 full screen | Black page; right column of actions; uploader, title, progress; 发弹幕 field, 详情页, full screen. |
| 10-12 评论 and shrinking player | Comment row anatomy, sort header, bottom bar; the paused player shrinks to a 继续播放 bar. |
| 13 评论详情 | Root comment, grey band, "相关回复共N条" with sort. |
| 14 Reply composer | White sheet, toolbar, 7-column emote grid, package tabs. |
| 15 投币 dialog and portrait player controls | Crates for 1 / 2 coins, mascot, balance, 同时点赞内容; the small player's control layout. |
| 18 简介 expanded | BV id, no-reprint notice, description, tags, topic chip. |
| 19 合集 sheet | Grabber, title, intro, 选集 正序, episode rows with the playing one pink. |
| 20-21 ⋮ panel | 4 buttons, 定时关闭 segments, a toggle card, a feedback card. |
| 22-23 Danmaku input | Dark bar above the keyboard; style panel with 字号, 类型, 颜色. |
| 24 弹幕设置 查看更多 | Adds 字体大小 and 弹幕速度. |
| 25 Hold to speed up | "⏩ 倍速中" pill. |
| 26-27 End of a video | Portrait 推荐视频 card with 立即播放, 重播, 分享; landscape with uploader, actions and a related row. |
| 16-17, 28 Milestone 4 | 我的收藏 folders / videos; 历史记录 chips and day groups. |
| Notes for building | The requested gestures, a custom AVPlayerLayer overlay instead of AVKit chrome, and 人像防挡 left out. |

### `docs/m1-phone-checklist.md`
- **Setup 1-5:** run logserver; install; turn on 发送日志到电脑 and allow local network; pick the PC; log in.
- **Measure each video 1-11:** official app timing; paste link; set 编码 (H.264 / AV1) and BTR; reopen from 最近打开; check the mode pill; record 首帧 / 画质 / codec; 3 seeks recording 跳转恢复; 2 minutes of 卡顿; flip BTR and repeat; turn BTR back on; an extra HEVC run on video 1.
- **Results:** pass criteria, the per-video mode order and seek percentages, and the table.
- **Also check 1-7:** stats box in landscape; 清晰度 matches 画质; Dolby Vision; Wi-Fi to cellular; background then BTR; account row retry; PiP, lock screen and rotation.
- **Troubleshooting** and **When done.**

### `docs/m2-phone-checklist.md`
- **Build A**
  - Opening and resuming 1-4: paste; 最近打开; resume from the official app's position; a finished video starts at 0.
  - Small player 5-10: controls auto-hide after 3 s with a pink line; double tap; hold 2×; horizontal seek (90 s per width); vertical drag scrolls the page; drag the bar with chapters.
  - Full screen 11-17: rotate; button; brightness and volume HUD; rotation lock; 竖屏; vertical video; screenshot.
  - Panels 18-21: 清晰度 and 高级设置; 倍速 kept across parts; every ⋮ row; tap outside closes.
  - PiP 22: swipe home keeps playing; without PiP the sound stops.
  - Ends and autoplay 23-25: next 合集 episode; end screens; 选集.
  - Danmaku 26-30: flight, no overlap, follows the video; toggle; settings; block words synced with the official app; sending with styles.
  - History and speed 31-32.
- **Before build B:** set `BILI_APP_KEYS` (steps 1-3).
- **Build B**
  - PiP and stacked pages 33-42: PiP survives leaving the page; restore; ✕; another video closes PiP; autoplay inside PiP; related video pauses and resumes the page below; PiP on a related page; a cancelled back swipe; restore with a stack; vertical then landscape page.
  - 首页 and 历史记录 43-46: feed and refresh; ⋮ 稍后再看; paste; avatar menu and history.
  - Video page 47-52: tabs; expand title (timestamps seek, links open Safari); 合集 sheet and parts; collapsing player; related; 点我发弹幕.
  - Actions 53-59: like and 三连 hold; coin dialog; favourites with 新建; share count; 关注 / unfollow confirm; in full screen; logged out (rotates upright before the login sheet).
  - 不喜欢 60-61.
  - Comments 62-66: sort; thread; pictures; like / 踩 / delete; composer with emotes; reply prefixes; drafts.
  - Memory 67.
- **Build 6, 68-72:** 推荐-opened page fixes on iOS 27: comments load; full screen and 竖屏 layouts; edge swipe; back button; the progress bar moves.
- **Build 8, 73-77:** swipe back from the middle and the edge; 评论 pages to 简介 first; a player drag seeks; the thread closes by sliding down; lists still scroll.

### `docs/m1-results.md`
- Verdict **go**: on every video tried in both modes, BTR started faster and stalled far less. KaiC called it "way better" than the official app.
- First frames:
  - BTR: 0.57-1.04 s on 1080P60, 1.4-2.0 s on 4K;
  - direct: stalls of 18 s and more, and one 4K open that never started.
- Weak spots: a cold 4K start of 8.7 s, and the first seconds after a jump into an unloaded 4K part. Both are what hurry mode targets.
- Build 1 bugs, all fixed in build 2:
  - full screen crashed because a hosting controller was a child of AVPlayerViewController;
  - the socket was taken in the background;
  - 卡顿 counted drag waits.
- The regression test named there, `FullScreenTests.swift`, no longer exists. `PlayerTransitionTests` replaced it.
- Hurry mode PC bench: cold first MiB about 1.6 s with hurry on vs 4.39 s off.
- Phone build 3: jumps resume in 0.02-1.1 s with BTR vs 9-12.6 s direct. Akamai was overloaded at 48-64 threads.

### `docs/m1-deferred.md`
- The review ledger of minor findings per M1 task.
- To act on before any public release: Release still compiles `DEV_TOOLS`; there is no non-DEV_TOOLS configuration.
- Other notes:
  - a stale SESSDATA stays in the jar while expired;
  - the log pipeline (duplicate batches, ack store);
  - edge cases in the LinkParser / WBI / sidx parsers;
  - Dolby Vision and locale phone checks.

### `docs/superpowers/`
- `plans/2026-10-16-hurry-mode.md` (473 lines): plan for engine hurry mode (expected-finish placement, small pieces, hedged copies).
- `plans/2026-10-16-m1-playback-core.md` (10,390 lines): the M1 plan, 29 tasks with full code (package modules, app, CI).
- `plans/2026-10-17-m2-video-page.md` (1,267 lines): the M2 plan (player, video page, danmaku, actions, comments, history) in builds A and B.
- `specs/2026-10-16-m1-playback-core-design.md` (367 lines): M1 design (why, BTR engine, go/no-go).
- `specs/2026-10-17-m2-video-page-design.md` (451 lines): M2 design for the player and video page.

---

## 9. `tools/` (`D:/Repos/Apps/BiliNative/tools/`)

### `logserver.py`
- A uv script that depends on zeroconf.
- `ThreadingHTTPServer` on 0.0.0.0, `--port` default 47321, options `--no-bonjour` and `--quiet`.
- Endpoints:
  - `GET /health` returns `ok`;
  - `POST /logs` takes an NDJSON body, one event per `\n`, and returns 200 `ok`; anything else is 404.
- Files are written to `logs/<YYYY-MM-DD>/<session>.jsonl`, where the session is alphanumeric and at most 64 characters.
- Bonjour: registers `_bilinative-log._tcp.local.` named "BiliNative log on <host>" with property `path=/logs`. It prints the LAN addresses so the phone can enter them manually.
- The app side: `LogTarget` is `.service(name:)` or `.manual(host:port:)`, and `LogPoster` writes a raw HTTP/1.1 `POST /logs` over `NWConnection`.

### `check-app.sh` and `check-app.ps1`
- A local compile check in WSL Ubuntu using xtool's Darwin SDK and the Swift toolchain.
- Options: `--release`, `--device`, `--app-only`, `--warnings`, `--repo`.
- It rsyncs the sources into `~/.cache/bilinative-check/<hash>`, writes nil AppKeys, builds with SwiftPM from `app-check/Package.swift`, and prints errors mapped to repo paths.
- The PowerShell file is a wrapper.
- `app-check/README.md` explains it; `setup-wsl.sh` installs Swift 6.4.1, xtool 1.22.2 and the SDK from the Xcode xip.

### `mac-test.sh`
- Tars the checkout, uncommitted changes included, and sends it to `macrent` over SSH.
- On the Mac: takes a lock in `~/.mac-test.lock`, writes nil AppKeys, runs xcodegen, picks a simulator (default iPhone 17 Pro Max), then `build-for-testing` and `test-without-building`.
- Options: `--tests`, `--ui` (the BiliNativeUI scheme), `--build-only`, `--launch`, `--sim`, `--repo`.

### `write_app_keys.py`
See section 3.

### Tests and helpers
- `test_logserver.py`, `test_write_app_keys.py`: unittest suites.
- `scripts/icons.py` draws the icon concepts and installs the chosen one.

---

## 10. Hard-won rules (file:line)

### System controllers, hosting controllers, overlays
- `D:/Repos/Apps/BiliNative/CLAUDE.md:79-83`: code that hands a view to a system controller needs a simulator test of that transition. Never make a hosting controller a child of a system controller whose views it may move. Build 1 crashed this way.
- `App/Player/PlayerHostView.swift:20-21`: video, danmaku and gestures live in one plain UIView, so rotation and PiP never move them into a system controller.
- `App/Player/PlayerHostView.swift:23-24`: the AVPlayerLayer sits on its own subview so letterboxing and mirroring never touch danmaku or gestures.
- `App/Player/OrientationController.swift:5-6`: full screen is the same page rotated, never a presented controller.
- These are in-page overlays, never presented controllers:
  - `App/Player/Panels/SidePanel.swift:49`
  - `App/VideoPage/CoinDialog.swift:39-40`
  - `App/VideoPage/CollectionSheet.swift:243-244`
  - `App/VideoPage/FavouriteSheet.swift:118-119`
  - `App/Comments/PictureViewer.swift:5-6`
- `App/VideoPage/LoginGate.swift:4-5`: a sheet goes up only after the page is back inline.
- `App/VideoPage/LoginGate.swift:18-35`: wait for the scene to report portrait **and** for its windows to be upright. A transition coordinator can accept a completion and never call it, so a timer backs it up.
- `App/Account/TVLoginSheet.swift:162-163`: the sheet closes before the tap that asked for it goes through.
- `App/Player/Panels/SidePanel.swift:73-74`: drive the slide with a flag, not insertion transitions. A transition fades the dismiss layer's UIKit host to alpha 0, and a re-opened panel then stayed invisible to touches.
- UIKit hit testing reaches SwiftUI content only through a UIKit view, so these wrap content in a non-scrolling scroll view:
  - `App/Player/Panels/SidePanel.swift:154-155`
  - `App/VideoPage/CoinDialog.swift:382-383` (`hitTestable`)

### Rotation and orientation
- `App/Player/OrientationController.swift:21-23`: after the button, lifting the phone off a table reports portrait, so portrait exits only after a real landscape turn.
- `App/Player/OrientationController.swift:49-58`: the most recent `begin` wins; a covered page's late `end` must not reset the top page.
- `App/Player/OrientationController.swift:113-134`: the scene is asked again even when nothing changed, and a refused rotation reverts. Going inline is never undone (:125).
- `D:/Repos/Apps/BiliNative/docs/background.md:196-197`: UIKit refuses a rotation while a push animates (error 101).
- `App/Player/Chrome/ChromeLayer.swift:65`: nothing pushes from full screen; go inline first, then wait 450 ms.
- `App/Player/Chrome/ChromeLayer.swift:85-86`: a reader that ignores the safe area reports none, so the window is asked as well.
- `App/Player/DeviceControls.swift:31-33`: the hidden MPVolumeView exists only in full screen, because it also suppresses the system HUD.
- `App/Player/DeviceControls.swift:61`: a freshly attached slider ignores a value set in the same run loop turn.
- `App/Player/DeviceControls.swift:80`: volume KVO fires on an audio thread.
- `App/Player/FrameCapture.swift:7-8`: AVAssetImageGenerator cannot read the local HLS, so frames come from `AVPlayerItemVideoOutput`.

### PiP
- `App/VideoPage/PiPKeeper.swift:4-6`: one video at a time; restore brings back the same page.
- `App/VideoPage/PiPKeeper.swift:31-35`: the page below can be shown before the popped PiP page is reported removed.
- `App/Player/PlayerHostView.swift:132-133`: AVKit waits on the restore handler, so it is always called within 3 s.
- `App/VideoPage/VideoPageModel.swift:38-40`: one AVPlayer per page, so the layer and PiP stay attached across parts.
- `App/VideoPage/VideoPageModel.swift:314-315`: in the background without PiP, the next part would play as audio only, so autoplay is skipped.
- `App/VideoPage/VideoPageModel.swift:408-409`: a covered page stops PiP.

### Page lifecycle and memory
- `App/VideoPage/PageLifecycle.swift:4-7` and `:47-52`: SwiftUI's onAppear/onDisappear can't be trusted (an onAppear fires as a back swipe starts and none comes back if it's cancelled). The page's place in the UINavigationController decides, re-checked at 300 ms, 1 s and 2.5 s.
- `App/VideoPage/PageLifecycle.swift:125-127`: during an interactive pop, UIKit has already removed the page from `viewControllers`.
- `App/VideoPage/PageLifecycle.swift:147-148`: transition-coordinator completions may never fire.
- `App/VideoPage/PageLifecycle.swift:169-170`: find the page's controller once and keep it.
- `App/VideoPage/VideoPageView.swift:338-339`: models hold `PageSignals`, never closures over the page view, or a popped page is never freed (`PageReleaseTests`).
- `App/VideoPage/VideoPageView.swift:391-393` and `:547-548`: closures put in the environment or in statics must be weak, because UIKit views keep the environment in their traits.
- `App/VideoPage/VideoPageModel.swift:434-437`: a closed page drops its UIKit views.
- `App/VideoPage/AppNavigator.swift:25-27`: keep the model entry while a pop animates, because SwiftUI rebuilds the destination.

### iOS 27 / 26 layout bug
- `App/VideoPage/VideoPageView.swift:363-365` and `docs/background.md:188-195`: on iOS 27, a page pushed from the 推荐 root never re-ran its GeometryReader content (the same happens on iOS 26 for a page pushed as the stack appears). The page now measures itself with `onGeometryChange` into state.
- `CLAUDE.md:109-110`: run `HomeFlowTests` on `-f runner=xcode-27` after layout changes.

### Swipe back
- `App/VideoPage/BackSwipe.swift:4-11` and `docs/background.md:198-205`: with the navigation bar hidden, UIKit's delegate refuses both swipes back in a private `_gestureRecognizer:shouldReceiveEvent:`. `BackSwipe` answers every receive and begin question itself.
- `App/VideoPage/BackSwipe.swift:85-90`: `responds(to:)` hides `*houldReceive*` and `*houldBegin*` from the original delegate.
- `App/VideoPage/BackSwipe.swift:59-64`: the swipe begins only with a page to go back to, no transition running, inline presentation, and no claim on it.
- `App/VideoPage/BackSwipe.swift:109-111`: on a quick flick, the direction comes from where the touch landed, because the pan's translation isn't set yet.
- Drags inside the page wait for the swipe. The content swipe gives way to the player's seek and to a sideways scroller that can still scroll back.
- `CLAUDE.md:117-120`: gestures need real-touch UI tests (`tools/mac-test.sh --ui`). Builds 6 and 7 passed delegate-only tests while the swipe never began.

### Keyboard and process rules
- `App/Danmaku/DanmakuSendBar.swift:4-6` and `App/Comments/Composer.swift:5-7`: these follow the keyboard by hand, because the page ignores safe areas or keyboard avoidance.
- `CLAUDE.md:66-73`: no GPL code copied; the borrowed PiliPlus art is a deliberate exception; UI text is Simplified Chinese; the network log sink is `DEV_TOOLS` only.
- `CLAUDE.md:169-176`: never `gh run watch` or poll in a loop (it tripped GitHub's rate limit); never start a signed build before the gate is green.
