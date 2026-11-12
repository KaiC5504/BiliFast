# The official iPhone app's calls

What the official iPhone app (9.18.0, build 91800100) sends, read from its own traffic on 2026-11-12: field names,
fixed values and timing. Ids, tokens and anything per account or per device are left out; where one is needed its
form is given. BiliFast's iPhone identity (`OfficialIdentity.iphone`) sends these.

## Signing

`appkey=27eb53fc9058f8c3`; `sign` is the MD5 of the sorted, percent-encoded fields followed by the pair's secret
(`AppSigner.iphone`), the same rule as the Android pair. A token only works with the pair that issued it: Bilibili
answers -663 for another's. The TV QR login (`/x/passport-tv-login/qrcode/auth_code` and `/poll`) issues a token
under this pair when its two calls are signed with it; `auth_code` is asked with `local_id=0`, `mobi_app=iphone`,
`platform=ios`.

## Sent with every call

Fields:

| Field | Value |
|---|---|
| `actionKey` | `appkey` |
| `build` | `91800100` |
| `c_locale`, `s_locale` | `zh-Hans_CN` |
| `device` | `phone` |
| `mobi_app` | `iphone` |
| `platform` | `ios` |
| `disable_rcmd` | `0` |
| `statistics` | `{"appId":1,"platform":1,"version":"9.18.0"}` (the feed), `{"appId":1,"version":"9.18.0","abtest":"","platform":1}` (reports) |
| `access_key` | the token, on account calls |
| `appkey`, `ts`, `sign` | as above |

Headers:

| Header | Value |
|---|---|
| `User-Agent` | `bili-universal/91800100 CFNetwork/1.0 Darwin/27.2.0 os/ios model/<model> mobi_app/iphone build/91800100 osVer/<iOS version> network/2 channel/<channel>` |
| `app-key` | `iphone` |
| `env` | `prod` |
| `buvid` | the device id: `Y`, then three characters, then 32 upper-case hex characters (36 in all), the Android id's rule with a one-letter prefix: an MD5 in upper case, preceded by its characters 2, 12 and 22 |
| `session_id` | 8 lower-case hex characters, one per launch |

`<model>` is the marketing name (`iPhone 17 Pro Max`), `<channel>` the store channel (`pink_overseas` on the App
Store outside China). The app also sends `x-bili-ticket`, `x-bili-trace-id`, `x-bili-mid`, `guestid` and a few
`x-bili-*-bin` headers; 推荐 answers 0 without any of them.

## 推荐: `GET app.bilibili.com/x/v2/feed/index`

Beside the common fields:

| Field | Value |
|---|---|
| `idx` | `0` with nothing on screen, otherwise the `idx` of the first card on screen (cards come in descending `idx`) |
| `pull` | `1` for a refresh, `0` for more below |
| `flush` | `0` on the launch's first page, `6` for a pull down, `8` for more below (the Android app's `PegasusFlush`) |
| `open_event` | `cold` on the launch's first page, otherwise empty |
| `login_event` | `0` |
| `auto_refresh_state` | `1` |
| `autoplay_card` | `11` |
| `channel` | the store channel |
| `client_attr` | `1` |
| `column` | `2` |
| `device_name` | the model |
| `fnval`, `fnver`, `force_host`, `fourk` | `17364`, `0`, `0`, `1` |
| `guidance`, `https_url_req` | `0`, `0` |
| `inline_danmu`, `inline_sound`, `inline_sound_cold_state` | `2`, `1`, `2` |
| `network`, `player_net` | `wifi`, `1` |
| `player_extra_content` | `{"short_edge":"1320","long_edge":"2868"}` (the screen in pixels) |
| `qn`, `qn_policy` | `120`, `0` |
| `recsys_mode`, `soft_fnval`, `video_mode`, `voice_balance`, `window_size_type` | `0`, `0`, `1`, `1`, `1` |

Left out on purpose: `ad_extra`, `banner_hash` and the `splash_*` fields, which belong to ads and the launch screen.
Load-more's `idx` and `flush` come from the Android app's code; the capture holds refreshes only.

The answer's cards are as the Android identity's (`card_goto`, `card_type`, `player_args`, `args`, `three_point_v2`
and the rest), with the big card (`inline_av_v2`) first. Each video card also carries `idx` (a number), `track_id`
(a string) and `report_flow_data` (a JSON string); its `uri` repeats the last two as `trackid` and
`report_flow_data`.

## A play's reports

For a video opened from a 推荐 card, in order:

1. As playback starts: a start heartbeat, every time field `0`, `start_ts=0`.
2. As the play ends (the page left, the next video, the video finishing): an end heartbeat with the times, then a
   history report.

The app also posts an encrypted play-start report (`/x/report/click/ios`) beside the start heartbeat, and logs
events to `dataflow.biliapi.com`; neither is reproduced.

### Heartbeat: `POST api.bilibili.com/x/report/heartbeat/mobile`

A signed form (`application/x-www-form-urlencoded`), the common fields and:

| Field | Start | End |
|---|---|---|
| `aid`, `cid`, `mid` | the video, its part, the account | same |
| `type`, `sub_type` | `3`, `0` | same |
| `epid`, `sid`, `epid_status` | `0` | same |
| `session`, `sessionID` | one 32-character lower-case hex id per play, the same value in both | same |
| `start_ts` | `0` | Unix seconds when the play began |
| `played_time` | `0` | seconds of the video played |
| `actual_played_time` | `0` | seconds spent playing |
| `total_time` | `0` | seconds since the play began, pauses included |
| `paused_time` | `0` | seconds paused |
| `last_play_progress_time` | `0` | the position at the end |
| `max_play_progress_time` | `0` | the furthest position reached |
| `list_play_time`, `miniplayer_play_time` | `0` | `0` |
| `video_duration` | the video's length | same |
| `quality` | the playing quality (`80`) | same |
| `play_type` | `1` | `1` |
| `play_mode` | `1` | `1` |
| `play_status`, `user_status` | `0` | `0` |
| `auto_play` | `0` for a video the user opened, `99` for one that followed on its own | same |
| `network_type` | `1` (Wi-Fi) | same |
| `is_audio_play`, `is_auto_qn` | `2`, `0` | same |
| `cur_language`, `perfer_type` | empty | empty |
| `from` | `7` on the video page (`default-value` in 竖屏's feed) | same |
| `from_spmid` | `tm.recommend.0.0` from a 推荐 card | same |
| `spmid` | `united.player-video-detail.0.0` on the video page, `main.ugc-video-detail-vertical.0.0` in 竖屏 | same |
| `track_id` | the card's `track_id` | same |
| `report_flow_data` | the card's `report_flow_data`, left out when the card had none | same |
| `extra` | `{"player_report_json":"","material_no":""}` | same |
| `idfa` | `00000000-0000-0000-0000-000000000000` (tracking not allowed) | same |
| `idfv` | iOS's identifierForVendor | same |
| `teenagers_age` | `16` | same |
| `polaris_action_id` | 8 upper-case hex characters, new for each report | same |

In the capture an 8 s play of a 10 s video ended with `played_time=8`, `actual_played_time=8`, `total_time=8`,
`last_play_progress_time=7`, `max_play_progress_time=7`. The end report's `extra` also names the stream's file,
which is left out. The answer is a small JSON with `code` 0.

### History: `POST api.bilibili.com/x/v2/history/report`

A signed form, the common fields and: `aid`, `cid`, `type=3`, `sub_type=0`, `epid=0`, `sid=0`, `progress` (seconds,
`-1` for a video watched to its end), `duration`, `start_ts` (when the play began), `device_ts` (now), `scene=front`,
`teenagers_age=16`, and `source`. The capture shows `source` only for 竖屏 (`story-single`, `story-series`); the
video page's value is not known, so BiliFast leaves `source` out.

## 竖屏's feed: `GET app.bilibili.com/x/v2/feed/index/story`

Not built yet (GitHub issue 2). Page 1 is asked with the video the user entered on (`aid`, `cid`), `display_id=1`,
`pull=1`, `from=7`, `from_spmid=tm.recommend.0.0`, `spmid=main.ugc-video-detail-vertical.0.0`, the card's `trackid`,
`contain=0`, `auto_play=0`, `video_mode=1` and the feed's player fields; the next page with the same `aid`, `cid`
and `trackid`, `display_id=2`, `pull=0`. The official app asks again once the user is within three cards of the end.
