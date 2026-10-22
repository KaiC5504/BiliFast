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

`images/loading/cover_placeholder.png` (the faint 小电视 on a cover still loading) is the same APK's vector
`bili_default_image_tv_2023` (the drawing the iPhone app shows; its `bili_default_image_tv` is an older one), and
`images/card/stat_play.png` and `stat_danmaku.png` (the 推荐 card's play and danmaku counts) its
`ic_vector_pegasus_play_count` and `ic_vector_pegasus_danmaku_count`: each drawn white at 3×, cut to its ink and
sized as KaiC's iPhone recording shows it (39 × 36.33 pt and 13.33 × 11.33 pt), drawn tinted.
