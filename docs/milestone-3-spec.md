# Milestone 3: find and follow

KaiC's call on 2026-10-20, after the Flutter move's slices (0-9) were done. Read `CLAUDE.md` and
`docs/flutter-move-spec.md` section 0 first; this file adds only what milestone 3 decides.

## 1. Goal

Today a video is reached only through 推荐, a pasted link, 历史记录 and related videos. Milestone 3 adds the ways the
official app finds and follows videos and people:

- **搜索**: the search box, suggestions and results.
- **UP主空间**: an uploader's own page, from every place an uploader shows.
- **我的收藏** and **稍后再看**: the avatar page's two "soon" shortcuts become real pages.

The **system-font check** (slice 10) came first and shipped in (15) and (16). Its leftovers are set aside, outside
this milestone (KaiC, 2026-10-21; slice 10 below, section 8), so the milestone is slices 11-13.

**Done** = slices 11-13 pass their phone steps on one TestFlight build at the end of the milestone, which also carries
the katakana fix (`5f116e1`) unless it ships before. On that build the phone runs both checklists (BiliNative
`docs/m1-phone-checklist.md` and `m2-phone-checklist.md`) in full; passing them is the cutover (flutter-move-spec,
slice 9), and the Swift app retires.

## 2. Decisions (KaiC's calls)

| Decision | Why |
|---|---|
| Scope is 搜索, UP主空间, 我的收藏 and 稍后再看. | The daily-use gaps. Each reuses the video rows and lists the app already draws. |
| The system-font check runs first. | The comment fix showed MiSans-tuned values are off under PingFang. Fixing the method first means every new screen is checked the same way. |
| One build for the whole milestone. | "No need to ship"; (15) and (16) went out on their own to check the font. |
| Slice 10's leftovers wait (2026-10-21). | Once Japanese names were fixed, the rest of the text was fine to KaiC's eye: the sweep's findings, the marquee title with 章节, 联合创作 and the 合集 prefix, and 查看更多 come later. |
| Later, not now: 动态, 离线缓存, 番剧, 直播. | 动态 has many card types (a milestone of its own); 离线缓存 needs a download path through the engine; 番剧 and 直播 need other players and APIs. |
| System-font values are the app's; MiSans keeps its own nudges. | KaiC uses the system font. MiSans stays as tuned. (Claude's recommendation, accepted with the plan.) |
| Fix anything off by 0.5 pt or more, or 2 % in width. | Smaller differences are below what a 3× screenshot measures reliably. |

## 3. Rules that carry over

Everything under "Rules that bite" in `CLAUDE.md`, in particular:
- Layout only from KaiC's official screenshots (`local/official-app-reference/`). A screen or state not in them is
  asked for, never filled from PiliPlus or the Swift app.
- PiliPlus (`D:\Repos\Apps\PiliPlus`, GPL) for APIs and behaviour only; write our own code.
- KaiC's account: few live calls, no loops, tests never touch the network. Each new endpoint is tried live once, by
  hand, before its slice ships, and its response shape is turned into a fixture with every id and name made up.
- Every slice runs through `.claude/skills/running-a-slice`: a one-screen plan, KaiC's go, parallel agents.
- System-font values come from KaiC's phone screenshots measured with `tools/screen_diff.py` (section 5).

## 4. Slices

### Slice 10: the system-font check

| | |
|---|---|
| Tool | `tools/screen_diff.py` (built in the milestone's first session): measures an ours/official pair of 3× shots. See section 5. |
| Input | KaiC's pairs in `local/differences/font-check/`, `NN-ours-<screen>.png` beside `NN-official-<screen>.png`, same video and state, 字体 系统. |
| Screens | 首页 推荐 (top); the video page's 简介 (uploader, title, actions, the first related videos); 评论详情; the landscape player with its controls; 弹幕设置's portrait sheet; 头像页; 历史记录; 设置; the landscape quality picker. 评论 itself was measured from `local/differences/11-…` and `12-…` and fixed in `3d13ca9`. |
| Work | Measure every pair, list each difference over the threshold with its token, group the fixes by file, one fix round. Values that differ by font become `BiliFonts.nudged ? miSans : system` getters, as `CommentRowTheme.textTop` does. |
| Tests | A widget test per changed value under `BiliFonts.family = BiliFonts.system`, so the system-font values are locked even though PingFang can't render on Windows. |
| Phone check | Each screen beside the official app: sizes, weights, line breaks and spacing match; no thin and thick glyphs in one line. |

After the stand-in fonts came in (`test/fonts`), every screen with an official shot was rendered under the system font
and measured again (2026-10-20). That found two faults no phone shot had shown yet, both fixed before any value: a
style with no font family took its fallback list's first font (the system font is now named, `BiliFonts.system`), and
lines mixing Latin and Chinese grow a point (`BiliFonts.strut`). The value fixes (section 8) were stopped before they
ran. The first of those faults was only half right: iOS has no `CupertinoSystemText` either, so (15) drew every digit
and space from Apple Color Emoji; (16) dropped the fallback list on the phone. On (16) a reply whose name is Japanese
(シロハ_, 单可ト) drew its whole line in a Japanese font, as (14) had; `5f116e1` (committed, not shipped) names SF and
then PingFang SC when iOS matches SF's own family name (CLAUDE.md's font rule). KaiC's calls on what else it found:

- **Not built:** iOS's text shaping (about ⅛ em between Chinese and Latin or digits in titles, descriptions, meta and
  history; a leading 【 or 《 at half width). Lines can end a few points apart and wrap differently; accepted.
- **Added by KaiC, set aside with the fix round:** the landscape title scrolling with faded edges instead of "…", and
  `· 章节 · <chapter>` after the time (the video's view points, which `/x/player/wbi/v2` already returns and
  `PlayerInfo` parses); 竖屏's
  联合创作 block (the staff's avatars, "<name> 等 N 人联合创作 ⌄") and the "合集 · 第N集 |" prefix before the title
  (35).
- **Left out:** the light ⋮ sheets of the small player and 竖屏 (42, 43; ours keeps the dark panel), the emote bar's
  ⚙ 🔍 🕒 cells (14), 51's 记住账号信息 row.
- **Still open:** 查看对话 on a reply to a reply (the conversation API), the small player's 弹幕设置 variant (06, waiting
  for KaiC's 查看更多 shot).
- **Known limit:** the official app draws Chinese at about 0.993 em (a 24-glyph line 2.5 pt shorter than ours); the
  stand-in draws 1 em. Whether Flutter on the phone does too shows on the first build with the fixes.
- **Set aside (KaiC, 2026-10-21), not part of this milestone:** once Japanese names were fixed, the rest looked fine to
  KaiC, so the sweep's findings (section 8), the marquee title with 章节, 联合创作 with the 合集 prefix, the 查看更多
  variant, and one measured oddity wait for later. The oddity: on (16) the first comment of 12's thread
  (`local/differences/12-official-comment-threads.jpg`) draws about 3% wider than the official, each Chinese glyph a
  third of a point further on at the same glyph size, while its previews match; cause unknown.

### Slice 11: 搜索

| | |
|---|---|
| Entry | 首页's top field (01), now a button showing the default word that opens 搜索; its paste button is gone (KaiC). A link typed or pasted in 搜索's field opens its video; anything else searches. A bare av id counts as a link only on its own with 5+ digits, so "AV1" searches. |
| Screens | 52-61 (`52-search-keyboard` … `61-search-random-words`): the empty page (bilibili热搜, 搜索历史, 搜索发现, 反馈), suggestions, 综合 (top, scrolled), 筛选, the ⋮ sheet, 用户. 62-63 (the uploader sheet, the space) are slice 12's. |
| APIs | `/x/web-interface/wbi/search/default` (the word), `/x/v2/search/trending/ranking` (热搜; the same ten words as `s.search.bilibili.com/main/hotword`, in the usual envelope), the app host's `/x/v2/search/recommend` with the Android app's parameters and no cookies (搜索发现; fewer parameters answer -400), `/x/web-interface/suggest` (rows beside `code`, not under `data`), `/x/web-interface/wbi/search/all/v2` (综合's video group), `/x/web-interface/wbi/search/type` (综合 with 筛选, and 用户). Each tried live once, logged out (2026-10-21). PiliPlus: `lib/http/api.dart:256-271,757-764`, `lib/http/search.dart`. |
| Decisions (KaiC) | 搜索历史 on the phone only (`search_history.json`, 20 words). Only the 综合 and 用户 tabs. 综合 draws video rows only: the keyword chips, comment snippets, 相关搜索, other cards and the 4K/高帧数 tags aren't in the web answers. 筛选 keeps 排序方式, 发布时间 (no date range) and 内容时长 (60-120 and 120+ cut on our side from the over-60 bucket); 音画质量 and 范围 are left out. 用户 rows open the space in the browser until slice 12. 完整榜单, 反馈, the ⋮ sheet's feedback, 用户's two sort menus toast 暂未开放. 用户's 大会员 pink names aren't in the web answer. |
| Behaviour | Titles' `<em>` marks draw pink, entities decoded. The buvid cookies are fetched before every search. One search call at a time, suggestions included, with a gap between result pages; suggestions after a 300 ms pause. A load round whose pages a 筛选 cut empties stops and offers 加载更多, so nothing loops against the account. Live covers are drawn still (an animated cover kept the page busy). |

**The bottom bar** (KaiC, with slice 11): 01's 首页 关注 + 消息 我的 under 首页. Only 首页 works: one tap scrolls 推荐 to the top and refreshes it, as KaiC's recording of the official app shows (`local/differences/14-official-home-tab-reload.mp4`); the others toast 暂未开放.

### Slice 12: UP主空间

| | |
|---|---|
| Entry | A face or name, both one tap target. On the video page the uploader row and staff open the uploader sheet (62, 68, 76) under the player, which keeps playing; the sheet's face and 进入空间 open the space. A comment's face or name (a reply preview's name too), an @mention in a comment or 简介, a space link in a comment, and 搜索's 用户 rows open the space directly (75); in full screen the uploader row opens the space. 推荐 cards, 历史记录, 搜索's video rows and related rows don't open uploaders yet. |
| Screens | The sheet: face, name, + 关注, 粉丝/投稿/获赞, 进入空间, a two-column grid of the uploader's videos (the playing one pink), 已经到底啦~ (62, 68, 76). The space: banner and its four buttons, face with its badge, 粉丝/关注/获赞, + 关注, or 已关注 + ▽ when followed (70), with 充电 before either when the uploader takes it (78, 79), name with level and 大会员 label, bio and 详情, tag lines (IP属地), the 小店/充电 cards, the uploader's own tabs, always on 投稿 (the uploader's default tab, 72 and 75, isn't built). Scrolled, a white bar with back, face and + 关注 pill, search and ⋮, the tab row pinned under it (73, 77). 投稿: chips (视频, 图文, 合集/系列), 播放全部, the sort toggle, rows with ⋮ (添加至稍后再看, 分享; 74). Followed: 已关注 opens 加入特别关注 / 设置分组 / 取消关注 / 取消 (71); 关注成功 and 取消关注成功 toast (78, 79). |
| APIs | The official app's, signed with the Android app's key pair (`AppSigner.android`; public, the same in every copy of the app): `app.bilibili.com/x/v2/space` (card, tabs, default tab, chips, counts, banner), `/x/v2/space/archive/cursor` (videos by `order`, paged by the last aid), `/x/v2/space/season/videos` and `/x/v2/space/series` (chips). No cookies go to them. 关注 state is the web card (`uploaderCard`), changes `/x/relation/modify`; 稍后再看 `addToWatchLater`. Each item's `uri` carries a signed play link: never stored or logged. PiliPlus: `lib/http/member.dart`, `lib/models_new/space/`. |
| Decisions (KaiC) | Only 投稿 works: 主页 and 动态 are drawn and toast 暂未开放, and a space whose default is one of them opens on 投稿. 视频 and the 合集/系列 chips list; 图文 toasts. The sort is a toggle (最新发布 ↔ 最多播放, no menu). 播放全部 opens the first video in the current order. Toast 暂未开放: 充电, ▽ (its 你可能感兴趣 strip has no known API), 加入特别关注, 设置分组, 私信, the space's search and ⋮, 详情, the 小店/充电 cards. A video tapped in the sheet opens a new page, as related videos do. Own build, 1.0.0 (19). Later (KaiC): move other calls that need no account to the official API. |

### Slice 13: 我的收藏 and 稍后再看

| | |
|---|---|
| Entry | 头像页's 我的收藏 and 稍后再看 shortcuts (49), which toast "soon" today. |
| Screens | 我的收藏's folder list; inside a folder; a row's ⋮ menu. 稍后再看's list; its row ⋮ menu or edit mode. |
| APIs | 我的收藏: `/x/v3/fav/folder/created/list-all` (in `bili_core`), `/x/v3/fav/folder/collected/list` (folders followed), `/x/v3/fav/resource/list` (a folder's videos, with order and keyword), `/x/v3/fav/resource/batch-deal` (in `bili_core`, to remove). 稍后再看: `/x/v2/history/toview/web` (the list), `/x/v2/history/toview/v2/dels` (remove), `/x/v2/history/toview/clear` (clear watched) if the screenshots offer it. PiliPlus: `lib/http/fav.dart`, `lib/http/user.dart`. |
| Behaviour | A row opens its video page with resume as 历史记录's does. Removing is optimistic and rolled back on failure, as the actions are. |

## 5. `tools/screen_diff.py`

A uv script (Python, opencv-python and numpy pinned in its header, as `turn_video.py`), read only, never on the
network:

- **Input**: an ours and an official image, both 3× (1320 px wide for the 440 pt phone), PNG or JPEG.
- **Alignment**: the two shots are rarely cropped the same; the tool finds the vertical offset where their row
  profiles match best, or takes `--anchor` rows from the user.
- **Elements**: text lines (runs of ink rows), filled boxes (runs of a flat non-white fill, with the rounded corner's
  inset taken out), and hairlines.
- **Per text line**: the centre from the wide (CJK-sized) glyphs only, so descenders and punctuation don't move it;
  left and right ink edges; the glyph pitch from glyph starts; the median glyph height, from which a font size follows
  for a given ratio; and the ink per glyph, which shows the thin-glyph fault.
- **Pairing**: lines are matched in order after alignment; unmatched lines are listed as extra or missing.
- **Report**: a table in pt (px / 3) of ours, official and the difference, each line flagged when over the
  threshold (`--pt 0.5`, `--ratio 0.02`), then the gaps between consecutive elements, which is where spacing faults
  show. `--overlay DIR` writes the pair side by side with the matched lines marked, for a look; the directory is
  the caller's (the scratchpad), never the repo.
- **Tests**: `tools/test_screen_diff.py` draws its pairs with MiSans (`assets/fonts`) in the test itself; nothing from
  `local/` is read or committed. The gate's tools lane runs it.
- **The system font in tests**: since slice 10, look-alike checks render the system path with stand-ins for SF and
  PingFang SC (`test/fonts`, `tools/make_standin_fonts.py`), calibrated with this tool on settings (09): our render
  against the phone's (14) shot and the official one.

## 6. Screenshots KaiC takes

- Slice 10's pairs, as in its table.
- New screens, official app only, into `local/official-app-reference/` numbered from 52 with the screen in the name:
  - 搜索: empty page; typing with suggestions; 综合 results top; scrolled; 筛选 open; 用户 tab.
  - UP主空间: top; 投稿; scrolled with the header collapsed; sort menu; a followed space.
  - 我的收藏: folder list; inside a folder; a row's ⋮.
  - 稍后再看: the list; a row's ⋮ or edit mode.

A screen or state the build needs and these don't show is asked for before that slice starts.

## 7. Build

One build, shipped once at the end of the milestone (the build number follows App Store Connect's latest). (15) and
(16) went out on their own (KaiC, 2026-10-21) with slice 10, the drawn turn and the system-font fixes, and slice 11
with the bottom bar as (17) (KaiC: "build it"). Each slice is
committed on `main` with the gate green; `python scripts/testflight.py start` runs once, after slice 13.

## 8. The stand-in sweep's findings (set aside by KaiC, 2026-10-21; not part of milestone 3)

Six read-only checkers rendered every screen with an official shot under the stand-in fonts and measured it with
`tools/screen_diff.py` (2026-10-20, on `d68cb5a`). Two things changed after they ran, so **re-render and re-measure
each item before changing anything**, and drop what no longer reproduces:
- the system font is named (`BiliFonts.system`), so styles that drew the square test font (the full-screen chrome,
  panels, the status bar, end screens, history, uploader names, counts) now render, and the checkers' merged-font
  workarounds are not needed;
- the SF stand-in takes iOS's line (1950/494 per 2048, was 1980/432), which moved Latin-only lines up about a point;
  items marked † came from Latin-only lines and may be gone.

Values are ours → official, in pt, from the official screenshots (the truth). The official app draws Chinese at about
0.993 em, so a size is the official Han advance / 0.993. Slice 10's system-font sizes were read off (14)'s phone shots,
whose text still carried Material's letter spacing, so several of them are wrong (the sizes below). System-font values
go in the `BiliFonts.nudged ? miSans : system` getters. Run it as one fix round, one agent per group (the groups own
disjoint files), then a look-alike check of every screen again.

**Home, history, settings** (01, 28, 45-48, 50; phone pairs 01, 07-09)
- 01 tab row too tall: 推荐 centre 127.3 vs 123.8, indicator top 144 vs 136, divider 151 vs 141.67, first card 157.5 vs
  148 (`home_page.dart` `_RecommendTab`: top padding 10 → ~6.5, gap 5 → ~0.5, bottom 4 → ~2.67). On the phone too.
- 01 card titles 18 apart vs ~20 (`feed_card.dart` `_lineHeight` 1.3 → 1.4); footer 2.75 and ⋮ 4.33 high
  (`cardFooterInset` 9 → 26/3); card 239 tall vs 242.
- 01 card corner radius 6 vs 13/3: a feed-card token (and the zoom route's end radius), not `BiliMetrics.cardRadius`.
- 01 search field starts 65 vs 64 (avatar gap 12 → 11); placeholder ink starts 101 vs 94.3, colour #9499A0 vs
  #61666D; card ⋮ dots 2.67 wide vs 2 (official: 2 pt dots 4 apart).
- 50/09 bar title 设置 1.5 low (`SettingsTheme.barTitleDrop` system −1.5). 45/08 历史记录 1.0 low (`titleDrop` −1).
- 08 a 0 progress shows "00:00/01:13"; the official shows "01:13" (`history_model.dart` ~258).
- 08 rows: title starts 1.0 right, line 1 0.6 low (`rowTitleTop`), UP/date 0.67-0.9 high (`metaBottom`), 今天 0.67 low
  (`headerTextTop`). 48 sheet words 1.1-1.7 high (stand-in only, `sheetTextDrop`).
- 49 avatar page, 07: pass.

**简介 and the video page** (03, 18, 19, 15, 26; phone pairs 02, 03)
- Title: `IntroTheme.titleText` system 15.25 → 16 (official Han advance 15.86; 03-intro breaks after 理, ours after
  解) and w600 → w500 (official stroke 1.33 vs 1.67).
- 合集 row: ' · ' ~2 pt wider each side officially; `collectionPlaceText` system 12.5 (digits 8.67-9.0 tall vs 9.33,
  "221/221" 41.7 vs 44.3); title 0.67 high.
- 15 coin dialog: "硬币余额 : 873.0" with a half-width colon and spaces (ours "：", 4 pt wider); crates 1.7 high.
- 19 collection sheet: share circle and 收藏 pill 3.2 high; list hairlines and covers 1.3-1.7 high.
- Tab row: danmaku field 98 wide not 97; `tabLabelText` and `danmakuFieldText` system 12.75 → 13.
- 活动 tag rows (older shots 03/18): title 1.17 high, 活动 0.5-0.8 low; confirm on a new shot first.
- 26: pass.

**评论 and 评论详情** (10-14; phone pairs 04, `local/differences/11-…`/`12-…`). Every checked line break matches.
- 04 a one-line reply holding an emote is ~2 pt short (text 24.2 below the name vs 21.5; ⋮ 51.2 vs 49.0):
  `emoteLineGrowth` is lost inside `textMinBottom`.
- 13/04 评论详情 header: title ~14.5 (`threadTitleText`, 14.44 a glyph vs 13.75); title and ✕ centre over the 40 above
  the hairline, not 41; ✕ 12 square vs 12.67.
- 10-13 write-bar prompt ~14.5 not 15 (`fieldText`; 12 glyphs 170.3 vs 178.3), first ink at x 25 vs 26.
- 13/04 thread rows: names and text 0.8-1.5 low (`nameCentre`, `textTop` for thread rows; pictures and meta stay).
- Box, hairline and band 20.0 below ⋮'s middle dot (ours 19.4-19.5), UP chip 22.0 (21.5): `bottom`, `bandGap`,
  `upChipTop` +0.5, `boxGap` +0.58. 热门评论 ~12.5 (`sortTitleText`).

**Danmaku** (07, 08, 22-24, 29-33, 36-39; phone pair 06)
- 31/32 当前弹幕列表: text 0.8 high, a 3-line row 80.67 vs 82.33, pitch 16.0 vs 16.67 (`textLine` 16.33 rounds to 16):
  system `textLine` 17 with even leading, `rowPadY` 15.67.
- 30 屏蔽词 tabs too far apart (正则 +1.0, 举报屏蔽用户 +2.67): `BlockWordsTheme.tabGap` system ~21.
- 32 屏蔽弹幕 eye 20.7×12.7 pointed vs 22×16 rounded, pupil ring ~10 vs 8.7; popover arrow 0.7-1 short.
- 23 swatch rings 1.4 vs ~1.1. 36/37/39 cursor 22 tall vs 20 (iOS draws `cursorHeight + 2`: 18). 37 typed "Hello"
  maybe 14 pt not 15 (†).
- 07, 08, 22, 24, 29, 33: pass.

**竖屏** (09, 35, 40, 41)
- 09 收藏 star 26.7 vs 30 (`favouriteIcon` ~36), 💬 29.3 vs 30.3, share 28.7×24 vs 30×24.7 and 1 high.
- Uploader name 2.33 high; 发弹幕 / 已关闭弹幕 1.5 high (09, 35); + 关注: text 1.5 high, 关注 12.5 not 13, plus 9.67
  wide vs 9, gap 4.3 vs 5.3; 粉丝 line 11 not 11.5.
- Minor: counts maybe 12.5 (†); 40's percentages 0.8 high. 40, 41: pass.

**Landscape** (04-06, 20, 21, 25, 27, 34; phone pairs 05, 10)
- 34 quality button: "1080P" with a small outlined "60帧" capsule above it (ours "1080P60"), centred in a slot of at
  least ~33 pt ending at 879 (ours right-aligned to 871, so 倍速 lands ~28 pt left).
- The faint "N人正在看" corner is hidden under open panels; the official keeps it (05, 06, 10, 20, 21).
- 27 end screen: cover counts ~2 low and ~10 pt (11), icon gap 4.0 (1.67), icon 10 tall (9); UP row 2.3 low, UP badge
  1.33 left; name 1.5 low, 推荐视频 1.2 low; small offsets on 点赞, 收藏, 分享, 关注's + and 充电.
- 05 two-line HDR card: title 1 high, subtitle 1 low; ⓘ 1 low.
- Field placeholder 1.33-1.5 high (04, 05, phone); share icon 1 low (04, 05, phone); 大会员 badge gap 1-1.33 wide;
  ⋮ panel 稍后再看 / 小窗播放 1.5 low; 高级设置 and 适应 1.3-1.7 left of the chevron.
- Minor: 定时关闭 dividers 64 vs 64.67 apart; quality cards 0.67 left; seek thumb 0.67 low; 倍速中 0.8 high.
- 25: pass.

**Structural, by KaiC's calls in slice 10 above:** the marquee title and 章节, 联合创作 and the 合集 prefix are to build;
the light ⋮ sheets (42, 43), the emote bar cells (14) and 记住账号信息 (51) stay out.
