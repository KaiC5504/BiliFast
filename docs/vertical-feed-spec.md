# 竖屏: the swipe feed, 清屏, the speed lock (slice spec)

Planned 2026-11-12 from GitHub issue 2 (豎屏視頻全屏後無法上下切換視頻) and KaiC's references 180-187. **Not started: it
waits for KaiC's go.** It ships with the iPhone identity as 1.4.0 (1), after a dev build on his phone. The slice runs
through `.claude/skills/running-a-slice`; this file is its plan and the facts behind it.

## 1. What it builds

| # | Item | References (`local/official-app-reference/iphone/`) |
|---|---|---|
| A | Swiping up and down in 竖屏 moves to the next and the previous video | 185 (recording: two slow swipes, then normal ones), 186 |
| B | The last bottom button by the video's shape: 横屏全屏 for a wide video, 清屏 for an upright or square one | 184, 09, 118 (wide); 180, 186 and 185's third and fourth videos (upright) |
| C | 清屏: the controls hidden but for 人正在看, play or pause with the time, the progress line and the bottom bar | 180 (paused), 186 (playing) |
| D | Holding for 2×, dragging down to lock it, 取消 to unlock | 182 (hint), 183 (armed), 186 from 12.5 s (armed, then locked) |
| E | The move into 竖屏 and back out | 187 |
| F | The uploader sheet in 竖屏: a look-alike check only, it is built | 181 |

Not in this slice: 竖屏's search button (the top bar keeps its room), ads and live rooms in the feed, the variant
without 详情页 (section 7).

## 2. What the official app does

### The swipe (185, 186; measured at 60 fps)

- The whole page follows the finger one to one: picture, danmaku, right column, uploader, title, progress line and
  bottom bar. The top bar (‹, 人正在看, search, ⋮) and the status bar stay where they are.
- While the page moves, everything but the pictures is at about 10% (the feed's own
  `config.swipe_opacity.other_ui_alpha_percent` is 10); it comes back when the page settles. Both pages are dimmed,
  the arriving one too.
- One swipe moves exactly one screen (956 pt). The neighbour's picture is already in its place under the screen
  (above it for the previous video), at the size its own shape gives it; its controls are there too, dimmed.
- Slow drags: released at about 64% of the screen, the page finished the rest in about 120 ms. Normal swipes: the
  finger moves about 100 pt in about 0.1 s, the page travels the rest by itself, 220 to 270 ms in all.
- The settle: after the finger lifts, the distance left roughly halves every frame (ratios 0.41 to 0.56 a frame), so
  it lands within 120 to 170 ms with no bounce.
- Not shown: a slow drag let go early (use half the screen as the line), and a swipe down on the first video (resist
  and spring back).
- The arriving video starts playing as the page settles. The official app has it loaded beforehand; ours shows its
  first-frame picture until the video plays.
- 清屏 turns off on a swipe: the next video arrives with its controls.

### The feed: `GET app.bilibili.com/x/v2/feed/index/story`

Signed as the iPhone identity with the app token. Beside the common fields:

| Field | First page | Later pages |
|---|---|---|
| `aid`, `cid` | the video 竖屏 was entered on | the same |
| `trackid` | the entry card's `track_id` | the same |
| `display_id` | `1` | `2`, `3`, … |
| `pull` | `1` | `0` |
| `from`, `from_spmid`, `spmid` | `7`, `tm.recommend.0.0` (from a 推荐 card), `main.ugc-video-detail-vertical.0.0` | left out |
| `auto_play`, `open_event`, `epid`, `ogv_style` | `0`, `cold`, `0`, `0` | left out |
| `contain`, `video_mode`, `voice_balance`, `client_attr` | `0`, `1`, `1`, `1` | the same |
| `collection_second_feed_iaa`, `material_no`, `room_id` | `1`, `0`, `0` | the same |
| `extra_content` | `{"story_video_bg_play_listen":"0"}` | the same |
| `fnval`, `fnver`, `force_host`, `fourk`, `qn`, `qn_policy`, `soft_fnval` | `17364`, `0`, `0`, `1`, `120`, `0`, `0` | the same |
| `network`, `player_net`, `player_extra_content` | `wifi`, `1`, the screen in pixels | the same |
| `product_id`, `product_type`, `server_name`, `sp_id` | empty | empty |
| `teenagers_age` | `16` | the same |

`ad_extra` is left out. The official app asks again once the user is within three videos of the end.

The answer is `data.items` (6 and 5 in the capture) and `data.config`. The first page's first item is the entered
video itself. An item's `goto` is `vertical_av` (a video: kept), `vertical_live` or `vertical_ad_av` (dropped). A
video item carries: `bvid`, `title`, `cover`, `ff_cover` (its first frame), `duration`, `dimension` (`width`,
`height`, `rotate`; wide videos are in the feed too), `player_args` (`aid`, `cid`), `owner` (`mid`, `name`, `face`,
`fans`, `relation.status`), `stat` (`view`, `like`, `reply`, `coin`, `favorite`, `share`, `danmaku`), `track_id`,
`report_flow_data` (not on every item), `idx`, and where they apply `season` (合集: `title`, `current_index`,
`total`), `staff_info` (联合创作), `top_search_bar`, `desc`, `pubdate`.

### Reports of a play in 竖屏

The heartbeat's `spmid` is `main.ugc-video-detail-vertical.0.0`, `from` is `default-value`, `from_spmid` stays the
entry's (`tm.recommend.0.0`), and `track_id` / `report_flow_data` are the item's own. `auto_play` is `0` for the
entered video and `99` for every video swiped to. The history report's `source` is `story-single` for the entered
video and `story-series` for the ones swiped to.

### The last bottom button

The APK's `bili_story_screen_mode_selector`: level 0 `bili_story_ctrl_normal` (ours: `screen_mode_normal.png`),
level 1 `bili_story_ctrl_clean`, level 2 `bili_story_ctrl_full` (the corners). A wide video shows the corners and
goes to landscape full screen. An upright or square video shows `normal`, and `clean` while 清屏 is on; a tap
switches 清屏. Today ours draws `normal` for an upright video but sends it to landscape.

### 清屏 (180, 186)

Gone: ‹, search, ⋮, the right column, the uploader row, the title, the search bar. Kept: 人正在看 (dimmed, top
left), the danmaku, the progress line, the bottom bar (发弹幕, 弹, 详情页, the button as `clean`), and at the bottom
left above the progress line a play or pause glyph with `00:07 / 01:18`. Paused, the big ▶ over the picture is not
drawn; the glyph at the bottom left is ▶.

### The speed lock (182, 183, 186)

Holding plays at 2× with 倍速中 at the top, as now, and the controls give way to a line under the progress line:
`↓ 拖动到此处锁定倍速`. With the finger dragged down onto it the line becomes a lighter band reading `🔒 松手锁定倍速`.
Let go there and the speed stays, with a pill at the top in 倍速中's place: `🔒 锁定倍速中 | 取消`. 取消 goes back to
1×. Let go anywhere else and the hold ends as it does now. The lock is the APK's `biligame_vector_lock_fill`.

### Into 竖屏 and out (187)

Going in from the video page: the body cuts to black at once and the picture slides from the top box down to its
place in 竖屏; the controls appear when it lands. Coming out: the picture slides back up to the top box and the body
is there at once (the official app shows grey placeholders until its page loads; ours has the page already).

## 3. Decisions (KaiC's, not yet confirmed; the recommendations)

1. Next videos come from the official feed when the held token is the iPhone identity's; with no token or an Android
   token, from the current video's related list. So every user gets the swipe and nobody is asked to confirm a login
   in the middle of one.
2. In 竖屏 the vertical drag stops setting brightness and volume, since the official app gives that drag to the
   swipe. Landscape and the small player keep them.
3. One player per page stays: the next video shows its first-frame picture and starts about a second after the page
   settles, with the engine prefetching it where it can.

## 4. Our code today

- `Presentation.vertical` (`lib/device/orientation.dart`); `uprightTakesVertical` reads `PlayerPrefs.verticalFullScreen`
  at `begin`. A wide video reaches 竖屏 through the small player's 竖屏 button. Off on the iPad.
- `VerticalChrome` (`lib/player_ui/vertical_chrome.dart`) draws every control; `VideoPlayerArea`
  (`lib/video/video_player_area.dart`) picks it and sizes the picture's band (`_verticalBand`: 0.969 of the height for
  an upright video, 0.83 for a wide one). The page's Stack places the area as `page-player`
  (`lib/video/video_page.dart`), full screen in 竖屏; the native view is built once and already moves with
  `Positioned` and `Transform`.
- Gestures are all in `PlayerGestureLayer` (`lib/player_ui/player_gestures.dart`): tap, hold (2×, `SpeedUpHud` in
  `player_hud.dart`), one axis-locked drag (sideways seeks; up and down set brightness and volume), the left-edge
  swipe.
- `PagePlayback.openOnPage` opens another video on the same controller: the details, comments, related list and
  danmaku follow; it shows no cover, only the loading TV. `replaceVideoPage` leaves full screen, so the feed must use
  `openOnPage`.
- In 竖屏 the video loops at its end (`loopsAtEnd`). The page's related list is `List<VideoCard>`, which has no
  dimension.
- `PlayerUi` (`lib/player_ui/player_ui.dart`) is the value every piece of the player's interface gets; the page
  builds it once (`video_page.dart`, `_ui = PlayerUi(`).
- Tests: `test/player_ui/vertical_chrome_test.dart`, `vertical_look_alike_test.dart` (118, 16),
  `vertical_seek_look_alike_test.dart` (19, 20), `player_gestures_test.dart`, `video_page_test.dart`,
  `video_player_area_test.dart`, `orientation_test.dart`.

## 5. Shared pieces (the contracts commit)

- `packages/bili_core`: `StoryItem` and the stubbed `BiliClient.storyFeed` (a new part, `bili_client_story.dart`);
  `PlaySource` gains the page it reports from and the history report's `source`, with `PlaySource.story`;
  `historyReport` takes `source`.
- `lib/video/story/story_feed.dart`: `StoryFeed` (the entries known so far with the entered video first, the index
  playing, `moveNext`, `movePrevious`, `wantMore`) and `StoryEntry` (what a neighbour page draws from: bvid, cid,
  title, cover, first frame, width and height, uploader, counts, its `PlaySource`). `PagePlayback.story` returns one;
  `openOnPage` takes the play's source.
- `lib/video/story/story_drag.dart`: `StoryDrag`, a listenable with the page's offset in points (negative towards the
  next video) and whether a drag or its settle is under way, and `start`, `update`, `end(velocity)`, `cancel`. The
  gesture layer drives it, the pager owns it, the chrome follows it.
- `PlayerUi` gains `story`, `storyDrag`, `clean` (清屏 on) and `speedLock`, all optional, built by the page.
- `lib/player_ui/speed_lock.dart`: `SpeedLock`, a notifier over off, holding, armed, locked.
- `lib/player_ui/vertical_chrome_preview.dart`: the stub of a neighbour page's still controls, drawn from a
  `StoryEntry`.
- Theme classes for each agent's tokens, each in its own place in `theme.dart`.
- Art: `screen_mode_clean.png` (`bili_story_ctrl_clean`; `tools/apk_asset.py extract` fails on its clip path, the
  dump's render in `local/apk-assets/drawable/` is the same picture) and `speed_lock.png` (`biligame_vector_lock_fill`), noted
  in `assets/README.md`.
- `docs/reference/official-iphone-calls.md`: the feed and the 竖屏 report labels from section 2.

## 6. Agents

| Agent | Builds | Owns |
|---|---|---|
| story-api | the feed call, the item's decoding, the report labels | `packages/bili_core`: `bili_client_story.dart`, `story_models.dart`, `play_source.dart`, `bili_client_report.dart`, their tests |
| story-feed | the list: the official feed or the related list, paging within three of the end, going back, dropping ads and live rooms, the source each play reports | `lib/video/story/` (the feed's own files), `lib/video/page_playback.dart`, `lib/video/watch_reporter.dart`, their tests |
| pager | the page following the finger, the neighbours' pictures, the settle, the first frame held until the video plays, 清屏 off on a move | `lib/video/story/story_pager.dart`, `lib/video/video_page.dart`, `lib/video/video_player_area.dart`, their tests |
| gestures | the vertical drag handed to `StoryDrag` in 竖屏, the hold dragged down to the lock, the hint, the armed band, the locked pill | `lib/player_ui/player_gestures.dart`, `player_hud.dart`, `speed_lock.dart`, their tests |
| chrome | the last button by shape, 清屏's layout, the dim and the fixed top bar while `StoryDrag` moves, the neighbour's still controls | `lib/player_ui/vertical_chrome.dart`, `vertical_chrome_preview.dart`, their tests and look-alikes |
| transition | E, after the pager has merged (the same file) | `lib/video/video_page.dart` |

Every swipe also answers accessibility actions (下一个视频, 上一个视频), since ghosthand can't drag and VoiceOver
needs them.

## 7. Checks, and what is not known

- The usual check round. Look-alikes at 440×956, 3×, under the system font: 清屏 against 180 and a frame of 186;
  the hint and the armed band against 182 and 183; the locked pill against 186 at 15.5 s; the bottom bar of an
  upright video against 185 at 9.0 s and of a wide one against 184; the uploader sheet against 181.
- The swipe's travel and timing are tested against section 2's numbers in widget tests; the Windows run presses
  every touched control and moves between videos through the accessibility actions.
- Not known: why the first upright video in 185 has no 详情页 button and a wider 发弹幕 box (nothing in the feed's
  data marks it; ours always shows 详情页); where a slow drag is cancelled; a swipe down on the first video; whether
  the Android identity may ask the story feed (it is not asked).

## 8. Done when (KaiC's phone)

1. In 竖屏, a swipe up brings the next video in under the finger, the controls dim, and it plays when it settles; a
   swipe down goes back.
2. Swiping on keeps bringing videos, with no ads and no live rooms.
3. 详情页 on a video swiped to opens that video's own page.
4. An upright video's last button is 清屏, on and off as 180 and 186; a wide video's still goes to landscape.
5. Holding shows the hint, dragging down arms it, letting go locks the speed, 取消 unlocks.
6. A sideways drag still seeks, a tap still pauses, the left-edge swipe still goes back.
7. Going into 竖屏 and coming out move as 187.
8. The official app's 历史记录 shows the videos swiped through.

Only the phone can prove: how the swipe feels, how soon the next video starts, the feed answering under the token,
and the reports being accepted (the log's `watch report` lines).
