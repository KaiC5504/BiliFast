# Milestone 3: find and follow

KaiC's call on 2026-10-20, after the Flutter move's slices (0-9) were done. Read `CLAUDE.md` and
`docs/flutter-move-spec.md` section 0 first; this file adds only what milestone 3 decides.

## 1. Goal

Today a video is reached only through 推荐, a pasted link, 历史记录 and related videos. Milestone 3 adds the ways the
official app finds and follows videos and people:

- **搜索**: the search box, suggestions and results.
- **UP主空间**: an uploader's own page, from every place an uploader shows.
- **我的收藏** and **稍后再看**: the avatar page's two "soon" shortcuts become real pages.

Before any new screen, a **system-font check** puts the existing screens right on KaiC's phone, which draws in
PingFang (字体 系统, the default on iOS), while every widget test and look-alike check renders MiSans.

**Done** = all four slices pass their phone steps on one TestFlight build, 1.0.0 (16), which also carries the drawn
turn of (15) and the comment fix (`3d13ca9`). On that build the phone runs both checklists (BiliNative
`docs/m1-phone-checklist.md` and `m2-phone-checklist.md`) in full; passing them is the cutover (flutter-move-spec,
slice 9), and the Swift app retires.

## 2. Decisions (KaiC's calls)

| Decision | Why |
|---|---|
| Scope is 搜索, UP主空间, 我的收藏 and 稍后再看. | The daily-use gaps. Each reuses the video rows and lists the app already draws. |
| The system-font check runs first. | The comment fix showed MiSans-tuned values are off under PingFang. Fixing the method first means every new screen is checked the same way. |
| One build for the whole milestone. | "No need to ship"; (15) and the comment fix wait for it. |
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
| Tests | A widget test per changed value under `BiliFonts.family = null`, so the system-font values are locked even though PingFang can't render on Windows. |
| Phone check | Each screen beside the official app: sizes, weights, line breaks and spacing match; no thin and thick glyphs in one line. |

### Slice 11: 搜索

| | |
|---|---|
| Entry | 首页's top bar (01). The bar already takes a pasted link; a link typed or pasted there still opens its video, anything else searches. |
| Screens | The empty search page (history, 热搜); typing with suggestions; results (综合 first, top and scrolled); the 筛选 menu; the 用户 tab. |
| APIs | `/x/web-interface/wbi/search/default` (the placeholder word), `s.search.bilibili.com/main/hotword` (热搜), `/x/web-interface/suggest`, `/x/web-interface/wbi/search/all/v2` (综合), `/x/web-interface/wbi/search/type` (a tab, with order, duration and partition filters), `/x/web-interface/history/search` (account history) if 12's screenshots show it synced; otherwise history is local. PiliPlus: `lib/http/api.dart:256-271`, `lib/http/search.dart`. |
| Behaviour | Results' video rows open the video page; 用户 rows open UP主空间 (slice 12). Titles carry `<em class="keyword">` highlights to draw in pink, and HTML entities to decode. Search needs the `buvid3` cookie the app already gets (`/x/frontend/finger/spi`). |
| Risk | Search answers -412 when called too fast; the client keeps one request in flight and debounces suggestions. |

### Slice 12: UP主空间

| | |
|---|---|
| Entry | 简介's uploader row and staff, a comment's avatar and name, an @mention (today it opens space.bilibili.com in the browser), the 推荐 card's uploader, 搜索's 用户 rows. |
| Screens | The space's top (face, name, level, 粉丝/关注/获赞, 关注 button); 投稿 (the videos list); scrolled, the header collapsed; the sort menu (最新发布 / 最多播放); a space already followed. |
| APIs | `/x/space/wbi/acc/info` (the card), `/x/relation/stat` (counts), `/x/space/upstat` (获赞, play counts), `/x/space/wbi/arc/search` (videos by order); `/x/relation/modify` for 关注 is already in `bili_core`. PiliPlus: `lib/http/member.dart`, `lib/http/api.dart:335-381`. |
| Risk | `arc/search` is known to answer -352 to clients without the browser's `dm_img_*` fields; PiliPlus moved to the app endpoint `/x/v2/space/archive/cursor`, which needs app signing (`app_signer.dart` exists for the TV login). Try the web call once live; fall back to the app one. |

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

## 6. Screenshots KaiC takes

- Slice 10's pairs, as in its table.
- New screens, official app only, into `local/official-app-reference/` numbered from 52 with the screen in the name:
  - 搜索: empty page; typing with suggestions; 综合 results top; scrolled; 筛选 open; 用户 tab.
  - UP主空间: top; 投稿; scrolled with the header collapsed; sort menu; a followed space.
  - 我的收藏: folder list; inside a folder; a row's ⋮.
  - 稍后再看: the list; a row's ⋮ or edit mode.

A screen or state the build needs and these don't show is asked for before that slice starts.

## 7. Build

1.0.0 (16), shipped once at the end of the milestone (the last TestFlight build was (14)). Each slice is committed
on `main` with the gate green; `python scripts/testflight.py start` runs once, after slice 13.
