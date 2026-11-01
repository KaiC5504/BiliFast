# The closing checklist

**Result (KaiC, 2026-11-01): passed by daily use.** KaiC uses the app every day and sees no bugs, so M2 and C1-C9
are marked passed as a whole rather than step by step. M1's hand-timed table is replaced by the 速度测试 card's
built-in plan (`builtin-4`: the app's BTR against 直连, rotated, every number in the log), run once on the next build,
read with `tools/phone_report.py --latest`; its table goes into the README. The steps below stay as the reference for
what the app does.

Milestone 3's closing check and the cutover from the Swift app. It carries BiliNative's
`docs/m1-phone-checklist.md` (steps M1-1 to M1-11, M1-A1 to M1-A7) and `m2-phone-checklist.md` (M2-1 to M2-77) under
their old numbers, rewritten where the Flutter app now does it differently. Then every phone check owed since 1.0.0
(17) (C1 to C9). Passing M1 and M2 in full is the cutover (flutter-move-spec, slice 9); a C step that fails is fixed
in the next build and doesn't hold the cutover back.

**Build:** 1.3.0 (5) as it is on TestFlight. `main` has changed only the README and the release notes' wording since,
so no new build is needed for this check.

**Before starting:** on the PC run `uv run tools/logserver.py`; on the phone 设置 → 开发者 → 发送日志到电脑 with the
PC ticked (已连接). Leave it on for every step: most answers are in `logs/` afterwards. Write down only the step
numbers that fail, roughly when, and what you saw.

Logged out (M2-59), a second login and the TV authorisation stay off the phone (KaiC keeps his one login): Windows and
the widget tests cover them.

## M1: BTR against 直连

Three videos that stutter in the official app (cold, 4K or high bitrate). Each video gets two runs, BTR and 直连, in
the order the table says.

- **Where things are now:** 编码 is under 清晰度 (full screen, tap the quality name) → 高级设置. BTR 加速 and 显示统计
  are in ⋮'s 测试 card (dev builds), BTR 加速 also under 设置 → 加速. The stats box's 模式 line says BTR or 直连 (there
  is no pill).
- **Why 编码 matters:** both runs must play the same stream. Set 编码 to **H.264** (or **AV1** if H.264 is greyed out
  or fails; the same for all three videos). Only the extra run is on HEVC.
- **Seeking rule:** a seek counts only if it lands past the grey buffered part. If 跳转恢复 shows about 0.00 秒, seek
  further ahead and write the new one down. One drag per seek, then wait for playback before the next.

1. Official app, at least video 1: time to first frame and one seek (drag to 50%) with a stopwatch.
2. Copy the link in the official app. In BiliFast tap 首页's search field (搜索 opens) and paste the link: the video
   opens.
3. Set 编码 to H.264 (or AV1) and BTR 加速 on or off for this video's first run (table). ⋮ → 显示统计 on.
4. Go back, then open the same video from the avatar page's 最近在看的视频 (or 历史记录). It may start where you
   stopped; 首帧 counts from the open either way.
5. The stats box's 模式 says BTR in a BTR run and 直连 in a 直连 run. 直连（回退） in a BTR run: note it.
6. Write down 首帧, 画质 and the codec on the 画质 line. If the codec isn't the one picked, write down what shows.
7. Seek three times at this run's percentages; after each write down 跳转恢复.
8. Let it play 2 minutes untouched; write down 卡顿.
9. Flip BTR 加速 and repeat 4-8 with the other percentages. Always reopen (step 4).
10. Afterwards turn BTR 加速 back on.
11. Video 1 only, extra run: BTR on, 编码 HEVC, reopen, 首帧, one seek at 50%, 卡顿.

| video | run | mode | 编码 picked | codec shown | 首帧 | seek 1 跳转恢复 | seek 2 | seek 3 | 卡顿 after 2 min | 画质 shown |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 1 | 1st (30/50/70%) | BTR | | | | | | | | |
| 1 | 2nd (40/60/80%) | 直连 | | | | | | | | |
| 1 | extra | BTR | HEVC | | | | n/a | n/a | | |
| 2 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 2 | 1st (30/50/70%) | 直连 | | | | | | | | |
| 2 | 2nd (40/60/80%) | BTR | | | | | | | | |
| 3 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 3 | 1st (30/50/70%) | BTR | | | | | | | | |
| 3 | 2nd (40/60/80%) | 直连 | | | | | | | | |

Passes when, on all three, BTR beats 直连 on 首帧 and 跳转恢复 with no more 卡顿, and feels at least as good as the
official app. Also:

- A1. In landscape full screen the stats box sits top left and covers none of the buttons.
- A2. 清晰度's ticked row matches the 画质 line (1080P 高码率 shows under the 1080P tag since (35)), never higher than
  what plays.
- A3. A 4K HDR video and a 杜比视界 one play; note if 模式 says 直连（回退）.
- A4. Wi-Fi off in Control Center mid-video: playback goes on (a short pause is fine, never stuck or 播放失败).
- A5. BTR on, the app in the background a few minutes, then a different video: 模式 says BTR.
- A6. If the account row ever says 登录已过期，重新登录 or 无法获取账号信息，点按重试, tap it: it clears or brings the
  name back.
- A7. The small window (swipe home while playing), the lock screen's play, pause and seek, and turning to landscape
  and back: playback goes on each time.

## M2: the player, the page and the entry points

### Opening and resuming

1. Paste a copied link into 搜索 (as M1-2): the video page opens and plays.
2. Go back; open it again from 最近在看的视频: it opens.
3. Watch another video to the middle in the official app, then open it in BiliFast: it starts where you stopped
   (give or take a few seconds).
4. A video you finished in the official app starts at 0.

### The small player

5. Tap the video: back, ⋮, play, the bar with the TV, time, 竖屏 and full screen show; after 3 s they hide, leaving
   the thin pink line.
6. Double-tap pauses; again plays.
7. Hold: 倍速中 at the top, 2×; let go, back to 1×. With danmaku on they speed up and slow down smoothly, never
   stepping back and forth (35).
8. Drag sideways across the video: a time label; let go and it jumps there (a full-width drag is 90 s).
9. *(Changed in 1.3.0 (1).)* Drag up or down on the video's left half: brightness, with full screen's level pill in
   the box; the right half: volume. Outside the video the page scrolls.
10. *(Changed in (23).)* Touch the bar's TV: it takes hold where the video is, without jumping to the finger; a drag
    moves it by how far you drag; a tap on the bar seeks nowhere. While held the bar is 4 pt and the TV's eyes look
    the way you drag, then blink after you let go (30). With 看点 the ticks show and the chapter title shows while
    dragging.

### Full screen

11. Turn sideways: full screen (the drawn turn by default: 开发者 → 旋转动画 自绘). Upright: the small player.
12. The full-screen button, then back (top left): the same.
13. In full screen drag up and down on the left (brightness) and right (volume): the pill shows in the middle, not
    iOS's volume HUD. After leaving full screen the brightness stays as set (30).
14. The lock on the right edge, then upright: it stays sideways. Unlock, upright: it returns.
15. 竖屏 in the small player: upright full screen with 竖屏's controls, which never hide (118). One tap plays or
    pauses at once; paused shows the ▶ and the time on the centre line. Back returns.
16. *(Changed in (39).)* An upright video: the small player's box takes its shape (up to 4:3 tall), its bottom row has
    only 竖屏; playing, the box gives up height above 16:9 as you scroll. Turning sideways does nothing. In 竖屏 it
    centres, starts over from 0 at the end, a swipe right from the left edge goes back, and holding the bar shows the
    6 pt pink bar with the story TV over the frame and the time (19, 20).
17. Full screen's screenshot button: allow Photos the first time; 已保存到相册, the frame is in Photos.

### Panels

18. 清晰度 slides in from the right; a lower quality switches and keeps playing; 大会员 rows are badged. 高级设置: another
    编码 switches.
19. 倍速 1.5X plays faster and stays for the next part.
20. ⋮, every row. In the small player and 竖屏 ⋮ is the white sheet (42, 43): its squares (分享 opens iOS's sheet,
    缓存 opens C8's sheet), then the rows.
    - 稍后再看: 已添加至稍后再看; it is in 稍后再看 here (C3) and in the official app.
    - 小窗播放 starts the small window.
    - 定时关闭 → 自定义 → 1 minute: it pauses after a minute.
    - 自动连播, 循环播放 (单集循环 replays at the end), 镜像翻转 flips, 画面尺寸 (适应, 填充, 拉伸, 16:9, 4:3).
    - 测试: BTR 加速 switches 模式 in the stats; 显示统计 shows and hides the box.
21. *(Changed in (36).)* Every panel (清晰度, 倍速, 弹幕设置 and its lists, 更多, 选集) closed by a pick, a tap outside
    or back leaves the bare video, in full screen and the small player; going from one panel to another keeps them up.

### Picture in picture

22. Playing, swipe home: the small window plays; its button returns to the app. With 小窗 off, swipe home: the sound
    stops.

### Ends and autoplay

23. A few seconds before the end of a 合集 video with 自动连播 on: the next episode plays on the same page.
24. 自动连播 off, let a video end: the small player's end screen (推荐视频 with 立即播放, 重播, 分享; the box shrinks
    to 16:9 for an upright video and grows back on 重播) and full screen's (the uploader, 重播, related). 分享 opens
    iOS's sheet with the link.
25. A multi-part video: 选集 in full screen, another part plays.

### Danmaku

26. They fly without overlapping and follow the video: pause stops them, a seek clears and restarts them, 2× speeds
    them up.
27. 弹 turns them off and on.
28. 弹幕设置 (the strip in landscape, the light sheet upright): 显示区域, 不透明度, and under 查看更多 字体大小 and
    弹幕速度, each live. Each 按弹幕类型屏蔽 square, 重复弹幕隐藏, 底部字幕区域防挡. ↻ 重置弹幕设置 puts them back.
29. In landscape, 添加屏蔽词 with a word that shows: those danmaku go. It is in the official app's 弹幕屏蔽; delete it
    here and it is gone there too.
30. Send one from full screen's field: it shows at once in a white box. A, another colour, size and top or bottom;
    会员 colours work.

### History and speed

31. After watching a while, the official app's 历史记录 has it near where you stopped.
32. 模式 says BTR; first frame and 卡顿 feel as in M1.

### The small window and stacked pages

*(Changed in (34): a video opened from a video page replaces it, and back goes to where the first video was opened.
Stacked pages are now reached through a space: a video page → the uploader's face → 进入空间 → a video there stacks
the second video over the space over the first.)*

33. Play, ⋮ → 小窗播放, back off the page: the small window plays on.
34. Its restore button: the same page comes back at the same place, no reload, the video back in the player.
35. Again, leave the page, ✕ on the small window: it closes and the sound stops. Any video then plays normally.
36. Again, leave the page, open another video: the small window closes before the new one starts.
37. A 合集 or multi-part video with 自动连播 on, a few seconds before the end, small window, swipe home: the next
    episode plays in the small window.
38. A related video replaces the page: back goes to 首页 (or wherever the first was opened), not to the first video.
    The same for a video in 简介, in a comment and in the uploader sheet.
39. Video A → its space → video B. Back to the space, back to A: A carries on where it was, no reload, and was paused
    meanwhile.
40. On B start the back swipe from the left edge, drag halfway and let go: B springs back still playing, turning still
    works. Swipe all the way: the space shows and B stops.
41. On B start the small window, go back to A, tap restore: B's page comes back on top at the same place; back from it
    lands on the space, A still paused under it.
42. An upright video → its space → a landscape video, then back: turning sideways on the upright video does nothing
    (16). On the landscape one, full screen, swipe right from the left edge: if the page closes, the space shows
    upright.

### 首页 and 历史记录

43. 推荐: two columns with counts, duration and the uploader, and one big card per page playing muted where it
    settles (38; a tap opens it with sound). 首页 tapped or a pull: the TV for about 1.5 s, then the new cards on top
    with their covers in, then 刚刚看到这里，点击刷新 and the old cards (37). The pull changes nothing until you let go.
    Scrolling folds the header's top row and slides in the magnifier; near the top it opens again. Scrolling a long
    way keeps loading, with no repeats.
44. A card's ⋮ → 稍后再看: a toast; it is in 稍后再看. ⋮ → 不感兴趣 and a reason: the card goes (90-92).
45. A link pasted in 搜索 opens its video (as 1).
46. The avatar (首页, top left): its page with 最近, ⚙, the four shortcuts and 最近在看的视频 (全部 › opens 历史记录);
    ⚙ → 设置 shows the name in pink and 大会员. 历史记录 groups 今天, 昨天 and 更早, a progress line on each cover, 已看完
    on finished ones. A row opens at its place (a finished one at 0). A pull keeps the list while it reloads.

### The video page

47. 简介 and 评论, sideways swipes switch them. The uploader row: face, name, fans, videos, 关注.
48. The title's ⌄: the BV id, description and tags. A time in the description seeks; a web address opens Safari; an
    @name opens the space.
49. A 合集 row's sheet with the playing one pink, another plays. A multi-part video's 选集 chips and full list switch.
50. Paused, scroll up: the player shrinks to the 67 pt 继续播放 bar; tapping it scrolls back and plays. Playing, a 16:9
    player never shrinks. At the end the end screen stays.
51. A related video replaces the page (38).
52. 点我发弹幕 beside the tabs: the bar opens over the keyboard and sends as 30.

### Actions

53. 点赞 turns pink, the count up; again, back. Hold 1.5 s: rings fill round 点赞, 投币, 收藏, then 三连. Let go early:
    nothing, and the like doesn't toggle.
54. 投币: the crates, 22娘, the balance; 1 or 2 by the arrows or a sideways swipe, swipe up or tap 22娘: the coin flies
    and 投币 is pink. 同时点赞内容 also likes. The coins show in the official app.
55. 收藏: tick one folder, untick another, 完成; both show in the official app. + 新建收藏夹 (私密 on): it shows ticked.
56. 分享 opens iOS's sheet; after sharing, the count goes up.
57. 关注 → 已关注; again, 确定不再关注？ first, 确定 unfollows. The uploader sheet and the space say the same.
58. In landscape and in 竖屏 the action icons work alike; 评论 brings the small player back on 评论.
59. Logged out: Windows and widget tests only (above).

### 不喜欢

60. *(Changed in (20).)* With the app token (授权 done in (21)), 不喜欢 is live: tap, it turns on; again, off.
61. *(Gone: the TV authorisation is left out.)*

### Comments

62. 评论: faces, pink VIP names, LV, pictures, emotes. 按热度 / 按时间 reload in that order. The end says 没有更多了.
63. 共N条回复 opens 评论详情 with ✕; its sort and scroll. A picture opens full screen; swipe between them; tap closes.
    A vertical swipe carries it with the finger, shrinking; past 100 pt or a flick it flies off and closes (23).
64. Like a comment, 踩 another, both toggle back. Your own: ⋮ → 删除 asks and removes it.
65. 哎呦，不错哦，发条评论吧: the composer with the keyboard; emotes (最近使用 fills), 发布: it shows at the top and in
    the official app.
66. 回复 on a comment and inside a thread: "回复 @name :" where it belongs, under the right comment in the official
    app. Close and reopen the composer: the text is still there.

### Memory

67. Ten or so videos one after another (related ones replace each other; go back to 首页 and open the next), then the
    small window and back: smooth, and nothing plays in the background.

### From builds 6 and 8 of the Swift app

68. 评论 loads on a video from 推荐 and on one from 历史记录.
69. The full-screen button and back, sideways and upright, 竖屏 and its back: each time the player fills its space,
    and back in the small player a tap shows and hides the controls.
70. *(Changed: the swipe back starts only from the left edge.)* A swipe right from the left edge, on the player and on
    简介 or 评论: the page goes back. In full screen the same swipe does nothing to the page.
71. 评论, back to 简介: the back button is still at the player's top left.
72. Playing, the line under the small player moves.
73. *(Changed.)* On 简介, a swipe right from the middle does nothing; from the left edge it goes back.
74. On 评论, a swipe right from the middle goes to 简介; from the left edge it goes back.
75. A sideways drag in the middle of the small player seeks; the page stays.
76. *(Changed: from the left edge only.)* In 评论详情 a swipe right from the left edge: the thread follows down and
    closes, the video stays. A short one let go early springs back.
77. 简介, the related videos and 评论 scroll up and down as before.

## C: everything since 1.0.0 (17)

Each line names the build that brought it. A guess (no official screenshot of it) is marked *guess*: say only if it
looks wrong beside the official app.

### C1. 搜索 (17)

1. 首页's field opens 搜索: 热搜, 搜索历史 (kept after a relaunch), 搜索发现.
2. Typing shows suggestions; the keyboard's 搜索 key searches.
3. 综合: results with real covers (no 搜索失败, no -412), 筛选's sort and duration, more results as you scroll.
4. 用户: rows open the space.
5. A row's ⋮ → 稍后再看.
6. The … at a cut title sits at the baseline, not mid-height.
7. Back from a result opened from 推荐 zooms into its card, also a card half under the bottom bar.

### C2. UP主空间 (19) and the own space (26)

1. The uploader's face or name on a video page opens the sheet under the playing video: counts, 关注, videos, 进入空间.
2. The space: banner, counts, 关注 (充电 only for uploaders who take it), 已关注 with ▽ and the 取消关注 sheet; scrolled,
   the white bar with the tabs pinned.
3. 投稿: 视频 and 合集/系列, 最新发布 ↔ 最多播放, 播放全部, ⋮'s 稍后再看 and 分享. 动态 lists their posts.
4. Comments' faces and names, reply previews' names, @mentions and 搜索's 用户 rows open the space.
5. 关注 and 取消关注 here, on the sheet and on the page stay in step.
6. Your own face (我的 or a comment of yours): your space with 空间头图 and its NO., the frame and 大, 编辑资料, the
   勋章 pills, LV with the bar; 主页's 收藏, 追番, 最近投币, 最近点赞 (items show) and 拥有的个性装扮; 投稿, 收藏, 追番.

### C3. 我的收藏 and 稍后再看 (20-22)

1. 我的收藏: folders as cards and as a list, a folder's videos, 视频 (the videos tab), 取消收藏, 创建 with a cover.
2. 稍后再看: 全部 / 未看完, the sort, 播放全部, 删除, 一键清除, 批量管理 with 复制到 / 移动到.
3. Both show what the official app shows.

### C4. 我的, 装扮 and pictures (25-33)

1. The bar's 我的: the header (frame, 大, LV, the vip pill, B币, 硬币), the counts, the 会员 card (opens in the official
   app), the shortcuts, 更多服务's 设置. It shows at once on launch (kept from last time) and refreshes on a pull.
2. With a 装扮 worn: 我的's header art, 首页's top, the bar's art and icons; the status bar icons readable over it;
   its 加载动画 on 推荐's pull at the TV's size (37), armed at 60 pt (38).
3. Covers come in fast and stay up coming back to a page (no blank, then reload). 设置 → 清除图片缓存 shows the size
   and clears.

### C5. 动态 (1.1.0 (1))

1. The bar's 关注: 全部 / 视频, 最常访问 with its pink dots, 更多 → 我的关注 (search, 推荐排序, 最近关注).
2. Against 127, 128, 135: the cards' author row, frame, verify mark, fan card number, 全文 folds, pictures, reposts,
   UP主的推荐, ↗ / 💬 / 👍.
3. A face in 最常访问: the sheet of their posts (139).
4. Video cards play muted where they settle, one at a time; a tap opens the page with sound carrying on.
5. A picture post and a repost open their post page (131, 132, 134, 140): IP属地, 评论 / 赞和转发, comments (reply,
   like, delete your own), the bottom bar's 💬, ⭐, 👍.
6. 👍 stays in step between the list, the post page and a space's 动态. ⋮ → 取消关注 works.
7. *Guess:* 关注 tapped again refreshes; no danmaku on 动态 videos; 展开 opens in place.

### C6. Video page extras (23, 24, 35, 38)

1. Landscape: hold the bar: everything but the bar fades and the frame preview shows (170 × 95) with the time under
   it.
2. 1080P 60帧 and 1080P 高码率 read 1080P under an outlined tag (35).
3. The 推荐 big card (38): its size, danmaku, counts, the speaker and 弹, the loop, 👍; half off screen after you let go,
   it pauses. Does 推荐's mix feel like the official 首页's (it asks as the Android phone)?

### C7. Watch history for cached videos (1.3.0 (3))

1. Watch a cached video in airplane mode, then go online: the official app's 历史记录 has it at that place (the log's
   `history outbox` says sent).
2. Watch further on another device, then open the cached part online here: it starts where the other device stopped.

### C8. 离线缓存 (1.3.0 (1)-(5))

1. ⋮ → 缓存: 画质 defaults to the best you get, sizes like 约 78.4MB, 缓存全部, 查看缓存's dot, 已使用 / 剩余.
2. Cache one 4K, one 杜比视界 and one HDR video: each plays from the phone in airplane mode, danmaku included, and
   ⋮'s 查看详情页 opens the online page.
3. 离线缓存 (我的 or the avatar page): 正在缓存 stacked, 已缓存视频 grouped by 合集, 正在缓存's page (全部暂停/开始,
   同时缓存数量, edit, 确定要删除吗?), a group's page, search.
4. Leave the app mid-download for 20 minutes or more, several times (this is how the phone picks its way: the log's
   `offline trip` and `offline trials`). The Live Activity shows 离线缓存 with progress while it continues.
5. Swipe the app away mid-download: they stop; the next open carries on.
6. After the next TestFlight update the cached videos are still there and play.
7. The cover's progress line; the small player's level drags (the first volume step after the view goes up).
8. *Guess:* the paused and failed marks, 定时关闭 and 画面尺寸's light pages in the white ⋮, failure lines, search
   results, edit on 离线缓存, the inline level pill's size, 竖屏 for an upright cached video.

### C9. The iPad (1.2.0 (1))

1. 首页 against 01, 02 (three columns, the one-row header, the bar 首页 分区 动态 我的).
2. The video page sideways (03, 04: 32 pt band, 437 pt related column) and upright (06); paused, the pink 立即播放 bar
   (05, 20); turning keeps the place.
3. Full screen both ways (08-19, 24), danmaku over the whole screen (09, 25), an upright video pillarboxed.
4. The launch log's `form factor` says pad via native on the iPad and phone via native on the iPhone (seen on both on
   2026-10-31: passed).
5. *Guess:* full screen held upright, the upright 评论 tab and shrink, the sheets at the left column's width.
