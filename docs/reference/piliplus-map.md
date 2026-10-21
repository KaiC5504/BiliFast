# PiliPlus map: where to look, and what not to take

PiliPlus is a GPL-3.0 Flutter Bilibili client. Its local checkout is `D:\Repos\Apps\PiliPlus`, at commit `bb2d86ca`
(2026-10-16, "jump to reply source page instead"). Paths below are relative to that folder. It was surveyed read-only
on 2026-10-17.

## The rule

**Read PiliPlus for how a feature works: endpoints, parameters, formats and behaviour. Never copy its code.** That
covers Dart, its Swift and Java helpers, and its patched Flutter widgets. BiliFast stays non-GPL (KaiC, 2026-10-18).
- Write our own version from what it shows, next to BiliNative's Swift.
- Its asset files (images, icon fonts) may be taken when they help match the official look (KaiC, 2026-10-19); what we
  took is listed in `assets/README.md`. Never its logos or branding.
- Functions only, never layout: the official app's screenshots in `local/official-app-reference/` are the only visual
  target. When they don't show a screen or state, ask KaiC to screenshot it; never take PiliPlus's layout instead.

## Repo facts

- pubspec: `version 2.1.6+1`, `sdk >=3.13.0`, `flutter: 3.47.7`. The same Flutter as ours and Kazumi.
- It patches the Flutter SDK at build time (`lib/scripts/*.patch`, `patch.ps1`, `build.ps1`). We do not; use stock
  Flutter.
- State and routing use GetX (`get`, a fork), with Hive CE storage. Neither is needed here.
- It uses **media_kit forks** with APIs not in upstream (`Player.create`, `setMediaHeader`), and no HDR options. Its
  iOS PiP grabs media_kit's pixel buffers into an `AVSampleBufferDisplayLayer` (`ios/Runner/PipPlugin.swift`). It still
  renders 8-bit. That is exactly the path this project avoids by keeping AVPlayer.
- `ios/Runner/Info.plist` has `CADisableMinimumFrameDurationOnPhone`. Flutter on iPhone needs that key to draw above
  60 Hz (ProMotion); ours has it too.

## Packages it uses that are safe for us (licence checked in the local pub cache)

| Need | Package | Licence |
|---|---|---|
| HTTP (optional; dart:io or `cupertino_http`/`cronet_http` may be enough) | dio 5.x, cookie_jar 4.x | MIT |
| Web view with readable cookies (login) | flutter_inappwebview 6.x | Apache-2.0 |
| Brightness | screen_brightness | MIT |
| Volume | flutter_volume_controller | MIT |
| Danmaku canvas (if our own painter is not enough) | canvas_danmaku (upstream, Predidit) | MIT |
| Background audio / Now Playing (only if AVPlayer's own handling falls short) | audio_service, audio_session | MIT |
| Wake lock | wakelock_plus | BSD-3 |
| Network changes | connectivity_plus | BSD |
| MD5 etc. | crypto | BSD |

Check every package's licence again at the version you pin. PiliPlus's git forks were not in the cache.

## Endpoint and format map, by feature

BiliNative's endpoint table (`docs/reference/bilicore-inventory.md`, section 3) is the source of truth. Every row in it
has been called from the phone. Look in PiliPlus only for what BiliNative does not have, or to cross-check a parameter.

| Feature | Where in PiliPlus | Notes for us |
|---|---|---|
| All REST endpoints | `lib/http/api.dart` (class `Api`, about 1000 lines, many with bilibili-API-collect comments); hosts in `lib/http/constants.dart` | Use it as an index for features BiliNative lacks (search, 稍后再看 list, 我的收藏, space, dynamics) |
| Request layer | `lib/http/init.dart` (Dio, HTTP/2 adapter with HTTP/1.1 fallback, retry, adapter reset on iOS connectivity change); `lib/utils/accounts/account_mgr.dart` (cookies, csrf, `access_key`, app signing per request) | Ours: BiliNative's `BiliClient` rules (Safari UA, Referer, csrf from bili_jct, 412 retry with fresh buvid) |
| WBI | `lib/utils/wbi_sign.dart` | Ours is in `bili_core`, checked against BiliNative's `WBITests` vectors |
| App signing | `lib/utils/app_sign.dart`; one android_hd key pair in `lib/common/constants.dart` | Ours: `AppSigner`. UP主空间 (slice 12) signs with that same public pair as `AppSigner.android`: it's the same for every user and tied to no account (KaiC, 2026-10-21). Never copy account-tied values |
| buvid activation | `Request.buvidActive` → `/x/internal/gaia-gateway/ExClimbWuzhi`; `lib/utils/id_utils.dart` | BiliNative only calls `/x/frontend/finger/spi`. Add activation only if 412s come back |
| 推荐 feed | `lib/http/video.dart:53-83` (web, WBI `wbi/index/top/feed/rcmd`); `:114-179` (app `/x/v2/feed/index`, needs `access_key`) | Keep the web feed (BiliNative). The app feed's 不感兴趣 reasons (`three_point_v2`, `/x/feed/dislike`) are a later feature |
| Video detail | `VideoHttp.videoIntro` (`/x/web-interface/wbi/view`); models `lib/models_new/video/video_detail/*` | Same endpoint as BiliNative |
| playurl and quality | `lib/http/video.dart:216-340`; `lib/models/video/play/url.dart` (also merges `dolby.audio` and `flac.audio`); quality ids `lib/models/common/video/video_quality.dart` (129 HDR Vivid, 127 8K, 126 DV, 125 HDR, 120 4K…); audio ids `audio_quality.dart` (30251 Hi-Res, 30250/30255 Dolby Atmos, 30280/30232/30216) | BiliNative picks AAC only. Dolby Atmos / Hi-Res audio would be new. AVPlayer can play E-AC-3 and FLAC in HLS, but check that on the phone before adding it |
| Subtitles, chapters | `VideoHttp.playInfo` (`/x/player/wbi/v2`), `lib/utils/subtitle_utils.dart` | BiliNative reads chapters only. Subtitles would be new |
| Seek thumbnails | `VideoHttp.videoshot` (`/x/player/videoshot`) | New, if wanted |
| Player gestures | `lib/plugin/pl_player/view/view.dart:943-1130` | Ours: BiliNative `GestureMath` and `ChromeState` (90 s per width, 10 pt axis lock, 25 pt edge, hold = 2×) |
| Full screen | `lib/plugin/pl_player/utils/fullscreen.dart` (`SystemChrome.setPreferredOrientations`), native_device_orientation for the sensor | Ours follows BiliNative's `OrientationController` rules (`lib/device/orientation.dart`) |
| Danmaku fetch | gRPC `DmSegMobile` in `lib/grpc/dm.dart` | Ours: web `seg.so` protobuf (BiliNative, proven), with a hand-written protobuf reader. No gRPC needed |
| Danmaku render | `lib/pages/danmaku/view.dart` (canvas_danmaku) | Ours: a painter from BiliNative's `LaneLayout` and `DanmakuView` rules |
| Danmaku settings, block words | `lib/plugin/pl_player/utils/danmaku_options.dart`; `lib/http/danmaku_block.dart` (`/x/dm/filter/user*`) | Same endpoints as BiliNative |
| Danmaku send | `lib/http/danmaku.dart` (`/x/v2/dm/post`; also thumbup `/x/v2/dm/thumbup/add`, report, recall) | Same as BiliNative. Thumbup, report and recall would be new |
| Comments | gRPC `lib/grpc/reply.dart` (MainList, DetailList, DialogList); JSON fallback `lib/http/reply.dart` | Ours: web JSON `/x/v2/reply/wbi/main` with the unsigned fallback (BiliNative) |
| Comment rich text | `lib/pages/video/reply/widgets/reply_item_grpc.dart:723-960` (emotes, @, links, timestamps, 笔记 cards, `{vote:id}`) | Ours: BiliNative `RichText.swift` (emote > mention > link > BV/av > timestamp) |
| Comment send | `lib/http/video.dart:601-646` (`/x/v2/reply/add`, `at_name_to_mid`, pictures) | Ours sends text, @-mentions and pictures (slice 7) |
| Emote panel | `lib/pages/emote/` → `/x/emote/user/panel/web?business=reply` | Same endpoint |
| Like / coin / 三连 / fav / watch later / 关注 | like and coin use **app** endpoints with `access_key` (`/x/v2/view/like`, `/x/v2/view/coin/add`); 三连 is web; fav `lib/http/fav.dart:633-740`; follow `lib/http/video.dart:672-720` | Ours: the web endpoints with csrf (BiliNative). No token needed except for 不喜欢 |
| 不喜欢 | app `/x/v2/view/dislike` with `access_key` | Same as BiliNative (TV QR login token) |
| 合集, 分P, related | `.../ugc/widgets/season.dart`, `page.dart`; `/x/player/pagelist`; `lib/pages/video/related/` | Same data as BiliNative (from `wbi/view` and `archive/related`) |
| History, heartbeat | `UserHttp.historyList` (`/x/web-interface/history/cursor`); heartbeat cadence in `lib/plugin/pl_player/controller.dart:1562-1613` | Ours: BiliNative `HeartbeatSchedule` (every 15 s of position, `-1` when finished) |
| Login | TV QR `lib/http/login.dart` (`/x/passport-tv-login/qrcode/*`), password/SMS with geetest, cookie paste | Ours: reuse BiliFast's keychain cookies; for a fresh install, BiliNative's web login (`passport.bilibili.com/login` in a web view) |
| 我的 | `lib/pages/mine/`; `/x/web-interface/nav`, `/x/web-interface/nav/stat`, `getCoin` | The official layout is in reference screen 02 |
| Settings storage | Hive (`lib/utils/storage*.dart`) | Ours: JSON files in the support folder, keys from BiliNative's `AppSettings` |

## Protobuf

PiliPlus has no `.proto` files, only generated Dart under `lib/grpc/bilibili/`. Its main users are danmaku
(`community/service/dm/v1`) and comments (`main/community/reply/v1`). We need neither: BiliNative decodes `seg.so`
with a 62-line reader (`ProtobufReader.swift`) and reads comments as JSON.

## iOS native code in PiliPlus (for orientation only, not to copy)

| File | What it does |
|---|---|
| `ios/Runner/PipPlugin.swift` (663 lines) | PiP by copying media_kit frames into an `AVSampleBufferDisplayLayer`. Irrelevant for us: we have a real `AVPlayerLayer` |
| `ios/Runner/AppDelegate.swift`, `SceneDelegate.swift` | Plugin registration; iOS 26 `preferredWindowingControlStyle = .minimal` |
| `ios/Runner/Info.plist` | `UIBackgroundModes` audio, `CADisableMinimumFrameDurationOnPhone`, `ITSAppUsesNonExemptEncryption` false, `FlutterDeepLinkingEnabled` false |

AVAudioSession is set from Dart (audio_session `.music()`). Our app sets `.playback` / `.moviePlayback` natively, as
BiliNative does.

## Assets

- Coin dialog art: `assets/images/paycoins/*.png`. Taken, with the default avatar `noface.jpeg` (`assets/README.md`).
- Icon font: `assets/fonts/custom_icon.ttf`, 34 glyphs mapped in `lib/common/widgets/custom_icon.dart`. Taken; danmaku
  off is `0xE801`, on `0xE802`, settings `0xE803`.
- No emote packs are shipped; emotes come from the API at runtime.
- Logos and screenshots under `assets/images/logo/` and `assets/screenshots/` are PiliPlus branding. Never use them.
