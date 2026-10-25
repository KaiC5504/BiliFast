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
