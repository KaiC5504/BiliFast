# Borrowed assets

The art in this folder is not covered by the repository's GPL-3.0 license. The official app's art belongs to
Bilibili; it is used here only so a personal, non-commercial client looks like the official app. Everything else the
app shows is drawn in code, apart from `app_icons/`: BiliFast's own home screen icons, shown small in 设置 → 应用图标.

## From PiliPlus

From [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) (GPL-3.0) at `bb2d86ca`, as files. No PiliPlus code is
used.

- `images/paycoins/`: the coin dialog's art
- `images/noface.jpeg`: Bilibili's default avatar
- `fonts/custom_icon.ttf`: the danmaku toggles and a few other glyphs

## From the official Bilibili Android app (8.43.0)

Taken unchanged:

| File | Original |
| --- | --- |
| `images/loading/tv_1.webp` … `tv_4.webp` | `indicatorFrame1.webp` … `indicatorFrame4.webp` |
| `lottie/player_loading_tv.json` | `assets/player_loading_tv.json` |
| `lottie/player_seek_bar_tv_1.json`, `_2.json` | `assets/player_seek_bar_tv_1.json`, `_2.json` |
| `lottie/story_seek_bar_icon_1.json`, `_2.json` | `assets/story_seek_bar_icon_1.json`, `_2.json` |
| `lottie/feed_like.json` | `assets/inline_click_to_like.json` |
| `images/player/paused_play.png` | `bili_player_play` |
| `images/home/batch_refresh.png` | `ic_promo_index_refresh` |
| `images/card/inline_muted.png`, `inline_sound.png` | `ic_volumn_inline_switch_off`, `_on` |
| `images/card/inline_like.png` | `ic_list_inline_dislike` |
| `images/dynamic/ic_upper_tv_play.png` | `ic_upper_tv_play` |
| `images/friends/page_status_empty.png` | `ic_page_status_empty` |
| `images/friends/attention_group.png` | `ic_attention_group` |
| `images/friends/face_collectible.png` | `ic_tag_nft` |
| `images/space/banner_sound.webp`, `banner_sound_off.webp` | the digital collection's sound disc |
| `images/space/banner_collectible.png` | `ic_space_nft_header` |
| `images/space/banner_region.png` | `ic_nft_icon_ex` |
| `images/home/hot_share_wechat.png`, `hot_share_moments.png` | `bili_socialize_wx_chat`, `bili_socialize_wx_moment` |
| `images/home/hot_share_qq.png`, `hot_share_download.png` | `bili_socialize_qq_chat`, `bili_socialize_download` |
| `images/home/hot_share_watch_later.png` | `ic_hot_share_menu_watch_later` |

Bitmaps changed slightly: `images/dynamic/follow_pointer.png` is `dy_ic_indicator_triangle` cropped to its ink, and
`images/player/pad_end_replay.png` is `ic_endpage_replay_small` at full opacity. `images/message/tab_box_system.png` and
`tab_box_creator.png` are `ic_im_system_notice` and `ic_im_up_assistant` with only their white glyph kept.

Vector drawables, drawn white as PNGs (by `tools/apk_asset.py`) for tinting:

| File | Original |
| --- | --- |
| `images/loading/cover_placeholder.png` | `bili_default_image_tv_2023` |
| `images/card/stat_play.png`, `stat_danmaku.png` | `ic_vector_pegasus_play_count`, `ic_vector_pegasus_danmaku_count` |
| `images/card/up_badge.png` | `ic_info_uploader_name` |
| `images/player/screen_mode_normal.png`, `screen_mode_clean.png` | `bili_story_ctrl_normal`, `bili_story_ctrl_clean` |
| `images/player/speed_lock.png` | `biligame_vector_lock_fill` |
| `images/player/pad_cast_tv.png` | `biliplayer_ic_topbar_tv` |
| `images/player/pad_previous.png` | `bili_mini_player_ctrl_play_prev` |
| `images/dynamic/dy_ic_*.png` | the drawables of the same names |
| `images/dynamic/follow_write.png` | `dy_ic_write` |
| `images/home/pad_tab_*.png` | `ic_vector_tab_bar_{home,partition,moments,mine}_default` and `_selected` |
| `images/home/hot_play_counts.png` | `ic_info_play_counts` |
| `images/message/feed_reply.png` | `ic_bubble_comment_line_v2` |
| `images/message/feed_like.png`, `feed_liked.png` | `ic_vector_like`, `ic_vector_liked` |
| `images/message/feed_gear.png` | `vc_mine_login_settings` |
| `images/message/feed_delete.png` | `biligame_vector_trash_delete_line` |

Glyphs of the app's icon font (`composeResources/.../font/iconfont.ttf`), drawn white as PNGs:

| File | Glyph |
| --- | --- |
| `images/dynamic/*_line.png`, `more_vertical_fill.png` | the glyphs of the same names |
| `images/friends/list_sort_line.png` | `list_sort_line` |
| `images/offline/sheet_dislike.png` | `dislike_line` |
| `images/offline/sheet_watch_later.png` | `arrow_play_next_line` |
| `images/offline/sheet_download.png` | `folder_download_line` |
| `images/offline/sheet_mini_player.png` | `miniplayer_line` |
| `images/offline/sheet_cast.png` | `tv_airplay_line` |
| `images/offline/sheet_share.png` | `arrow_share_line` |
| `images/offline/sheet_done.png` | `checkmark_circle_fill` |
| `images/message/tab_broom.png` | `brush_clear_line` |
| `images/message/tab_entry_reply.png`, `tab_entry_like.png` | `bubble_comment_fill_500`, `hand_thumbsup_fill_500` |
| `images/message/tab_sheet_settings.png`, `tab_sheet_contacts.png` | `nut_setting_line_500`, `person_address_book_line_500` |
| `images/message/tab_sheet_fan_club.png`, `tab_sheet_system.png` | `person_hot_line_500`, `speaker_sound_on_line_500` |
| `images/message/tab_sheet_creator.png` | `brandtv_normal_line_500` |
| `images/message/chat_settings.png` | `nut-setting-line@500` |
| `images/message/chat_push_off.png`, `chat_push_on.png` | `bell-reserve-off-line@500`, `bell-reserve-line@500` |
| `images/message/chat_follow.png`, `chat_following.png` | `person-follow-line@500`, `person-following-line@500` |
| `images/message/chat_picture.png`, `chat_emote.png` | `image-line@500`, `emoji-circle-line@500` |
| `images/message/chat_keyboard.png`, `chat_link.png` | `keyboard-line@500`, `chain-link-line@500` |
