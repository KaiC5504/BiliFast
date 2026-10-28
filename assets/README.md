# Borrowed assets

`images/paycoins/` (the coin dialog's crates, coins, arrows and 22娘), `images/noface.jpeg` (Bilibili's default
avatar) and `fonts/custom_icon.ttf` (the 弹 toggles and a few other glyphs) come from PiliPlus (`D:\Repos\Apps\PiliPlus`, GPL-3.0) at `bb2d86ca`, taken as files for this
personal-use app on KaiC's call (2026-10-17, widened 2026-10-19 to any asset PiliPlus has that the official look
needs). No PiliPlus code is copied. `fonts/MiSans-Regular.ttf` is Xiaomi's MiSans.

`images/loading/tv_1.webp` to `tv_4.webp` (the 小电视 that refreshes lists and loads pages) and
`lottie/player_loading_tv.json` (the player's pink 正在缓冲 TV) come from the official Bilibili Android app 8.43.0's
APK, which KaiC downloaded for them (2026-10-21): `indicatorFrame1-4.webp` of its pull-to-refresh resources and
`assets/player_loading_tv.json`, unchanged. The APK itself stays in `local/`.

`lottie/player_seek_bar_tv_1.json` (the seek bar's TV, its eyes sliding from left to right across the animation) and
`lottie/player_seek_bar_tv_2.json` (its blink when the finger lifts) are the same APK's
`assets/player_seek_bar_tv_1.json` and `_2.json`, unchanged.
`lottie/story_seek_bar_icon_1.json` and `_2.json` (竖屏's seek bar TV, its #333 body as on 118 and 19) are the same
APK's `assets/story_seek_bar_icon_1.json` and `_2.json`, unchanged.

`images/loading/cover_placeholder.png` (the faint 小电视 on a cover still loading) is the same APK's vector
`bili_default_image_tv_2023` (the drawing the iPhone app shows; its `bili_default_image_tv` is an older one), and
`images/card/stat_play.png` and `stat_danmaku.png` (the 推荐 card's play and danmaku counts) its
`ic_vector_pegasus_play_count` and `ic_vector_pegasus_danmaku_count`: each drawn white at 3×, cut to its ink and
sized as KaiC's iPhone recording shows it (39 × 36.33 pt and 13.33 × 11.33 pt), drawn tinted.

`images/player/paused_play.png` (竖屏's ▶ over the paused video, 118) is the same APK's `bili_player_play` (xxhdpi),
unchanged: a white 小电视 with the ▶ cut out. KaiC's iPhone draws it at the file's own 3× size (80 × 77 pt; its body
68 pt wide, as on 118) at a quarter of its white, so the video shows through.

`images/player/screen_mode_normal.png` (竖屏's last bottom button for an upright video, 16) is the same APK's vector
`bili_story_ctrl_normal`, level 0 of its `bili_story_screen_mode_selector` (1 is `bili_story_ctrl_clean`, 2
`bili_story_ctrl_full`, the corners a wide video shows): an upright phone with two lines beside half a landscape screen
at 60% white. Drawn white at 3× of its own 24 dp (72 px; 24 pt as 16 measures it) with its stroke alpha and round line
caps, which `apk_asset.py`'s drawings leave out.

`images/home/batch_refresh.png` (the ⟳ after 推荐's 刚刚看到这里，点击刷新, 122) is the same APK's
`ic_promo_index_refresh` (xxhdpi), unchanged: two white arcs with solid arrowheads, the drawing KaiC's iPhone shows (the
APK's `ic_promo_index_refresh_vector` is a newer one, its arrows open and turning the other way). The iPhone draws it at
the file's own 3× size, 14.67 pt, tinted pink.

推荐's big card (122-126) takes the same APK's inline player art, each unchanged: `images/card/inline_muted.png` and
`inline_sound.png` are `ic_volumn_inline_switch_off` and `_on` (xxhdpi, the speaker with its x or its waves, white
with a faint shadow), drawn 22 pt square, as 126's speaker measures; `images/card/inline_like.png` is
`ic_list_inline_dislike` (xxhdpi, a filled thumb, the selector `selector_inline_like_button` tints it), drawn so its
ink is 16.72 pt, as 123's 👍, and tinted #61666D; `lottie/feed_like.json` is `assets/inline_click_to_like.json`, the
thumb turning pink with its burst of small thumbs that 125 shows on a tap. The cover's ▶ is `images/player/paused_play.png`
again, its body 46.67 pt wide at 77% of its white (122). 弹 is the player's own drawn glyph: the iPhone shows 弹 on the
TV where the APK's `ic_danmaku_inline_switch_v2_on` draws lines.

动态 (127-140) takes the same APK's dynamic art (`images/dynamic/`), each a vector drawn white at 3× by
`tools/apk_asset.py extract … --width 72` for tinting: `dy_ic_arrow_share_line_24` (转发), `dy_ic_bubble_comment_line_24`
(评论), `dy_ic_hand_thumbsup_line_24` and `_fill_24` (赞, liked), `dy_ic_star_favorite_line_24` (the post page's ⭐). Their
drawn sizes and greys come from 131, 135 and 140.
关注 takes `dy_ic_write` (`images/dynamic/follow_write.png`, a vector drawn white at 56 px, ink 18.67 pt, sized from
127) and `dy_ic_indicator_triangle` (`follow_pointer.png`, the xxhdpi bitmap cut to its 37 × 21 px ink, drawn
15.67 × 8 pt as 139 shows it).
The card's other glyphs come from the APK's compose icon font
(`assets/composeResources/srcs.common.iconfont.generated.resources/font/iconfont.ttf`), named by the `ref_*_500`
drawables, each drawn white, cut to its ink and scaled to the ink width measured on 127, 131, 135 and 137:
`more_vertical_fill` (eb0f, 10 px), `gift_lottery_line` (ead2, 47 px), `video_circle_line` (eb7f, 49 px),
`lock_locked_line` (eaf9, 30 px), `arrow_share_line` (ea3f, 55 px), `person_unfollow_line` (eb30, 52 px),
`warning_report_triangle_line` (eb89, 56 px). `ic_upper_tv_play` is the APK bitmap unchanged (70% white), drawn 42 pt
wide at 80% opacity, as 128's TV mark.

The iPad page's player (ipad/03, 07, 17) takes the same APK's player art: `images/player/pad_cast_tv.png` (投屏) is
the vector `biliplayer_ic_topbar_tv` and `pad_previous.png` (⏮) is `bili_mini_player_ctrl_play_prev`, each drawn
white at 3× by `tools/apk_asset.py extract … --width` 72 and 35 (24 × 19.33 and 11.67 × 13.33 pt, as 03 measures);
`pad_end_replay.png` (17's 重播, the thick ring with its solid head) is `ic_endpage_replay_small` (xxhdpi), its
alpha raised from the file's 80% to full, as 17 draws it solid white at 19.5 × 21 pt. 小窗 is the APK's
`biliplayer_ic_topbar_floatwindow` drawn in code (`FloatWindowPainter`): the extractor fills its stroked paths.
17's 分享 is the action row's solid arrow (`ActionGlyph.share`), and 全屏 the small player's `FullScreenPainter`.

The iPad's 首页 (ipad/01, 02) takes the same APK's tab bar and scan art, each a vector drawn white at 3× by
`tools/apk_asset.py extract … --width` for tinting, the width the ink measures on 01: `images/home/pad_tab_home.png`
and `_selected` (`ic_vector_tab_bar_home_default` / `_selected`, 60 px), `pad_tab_partition.png`
(`ic_vector_tab_bar_partition_default`, 63 px; its selected file is the same drawing), `pad_tab_moments.png`
(`ic_vector_tab_bar_moments_default`, 63 px, likewise), `pad_tab_mine.png` and `_selected`
(`ic_vector_tab_bar_mine_default` / `_selected`, 63 px), and `pad_scan.png` (`ic_scan_cast`, 54 px, the top's scan).
The top's clock with its turning arrow and its three-dot bubble are drawn in code: the APK has neither.
