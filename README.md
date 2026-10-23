<div align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="160" height="160" alt="BiliFast icon" />
  <h1>BiliFast</h1>
  <p><b>The official Bilibili look, on a faster engine.</b><br/>官方的样子，更快的引擎。</p>

  ![iOS](https://img.shields.io/badge/iOS-iPhone-black?logo=apple)
  ![Flutter](https://img.shields.io/badge/Flutter-3.47.7-02569B?logo=flutter)
  ![Dart](https://img.shields.io/badge/Dart-engine-0175C2?logo=dart)
  ![Shipped via](https://img.shields.io/badge/ships%20via-TestFlight-0D96F6)
</div>

<!--
Screenshots: our own app on the phone, saved to docs/screenshots/ (never the official app's).
<div align="center">
  <img src="docs/screenshots/home.png" width="24%" alt="首页" />
  <img src="docs/screenshots/video.png" width="24%" alt="Video page" />
  <img src="docs/screenshots/landscape.png" width="48%" alt="Full screen" />
</div>
-->

A third-party Bilibili client for iPhone, written in Flutter. It does two things on purpose:

- **It looks like the official app.** Every screen is measured, point by point, against screenshots and recordings
  of the official iPhone app. Its icons, loading TV, placeholders and seek-bar TV come from the official app itself.
  Nothing to relearn.
- **It plays faster.** Video arrives through a Dart port of
  [Bilibili Thread Ripper](https://github.com/MrTangLuyao/Bilibili-thread-ripper) (BTR), which pulls each piece of a
  video from several CDN nodes at once. Apple's own player draws the picture.

A personal project, not affiliated with Bilibili. It replaces its Swift predecessor,
[BiliNative](https://github.com/KaiC5504/BiliNative).

## How playback works

```
 Bilibili CDN nodes ──┬──▶  BTR engine  ──▶  local HLS server  ──▶  AVPlayer
   (several at once)  │     (background       (on the phone)        (Apple's player:
                      │      isolate)                                PiP, HDR, 杜比视界)
                      └──   node health, retries, the fastest node kept
```

The engine runs in its own isolate, shared by every open video page. The player sees an ordinary HLS stream, so
picture-in-picture, HDR and Dolby Vision behave as they do in Apple's apps.

## Features

### Playback
- [x] BTR multi-node download, every quality up to 4K, 8K, 真彩 HDR and 杜比视界
- [x] Picture-in-picture, which keeps playing after the page closes
- [x] The official rotation to full screen, drawn frame by frame
- [x] Gestures: brightness and volume, seeking, double tap, long-press speed
- [x] Quality, speed and episode panels; 竖屏 full screen; end screens
- [x] The seek bar's TV looks the way you drag; the frame preview shows while held
- [x] Resume where you left off; watch progress reported to your history

### 弹幕 Danmaku
- [x] 弹幕设置 that applies live, mid-flight
- [x] 屏蔽词 synced with the account
- [x] 当前弹幕列表 with 👍 and blocking
- [x] Sending, with colours and positions, from every presentation

### Video page
- [x] 简介, tags, 合集 and parts, related videos
- [x] 点赞 / 投币 / 收藏 / 不喜欢, with the coin dialog
- [x] 评论 and 评论详情: rich text, emotes, pictures, @mentions, the composer with drafts
- [x] The uploader sheet over the playing video

### 首页 and 搜索
- [x] 推荐 from the official feed, personalised, with 不感兴趣
- [x] Pull to refresh that starts loading while you hold it
- [x] 搜索: 热搜, history, suggestions, 综合 with 筛选, 用户

### You
- [x] 我的, with your counts, 会员 card and shortcuts
- [x] 装扮: your equipped skin dresses 首页, 我的 and the bottom bar; the status bar follows the skin
- [x] UP主空间 and your own space
- [x] 我的收藏, 稍后再看 with 批量管理, 历史记录
- [x] 设置: fonts, the CDN node, the picture cache, logs for developers

### Built for speed
- [x] Every picture kept on the phone (up to 500 MB) and shown again without reloading
- [x] Covers from the CDN the official app uses, over one kept-open connection, at the exact size they're drawn

### Planned
- [ ] 动态
- [ ] 离线缓存
- [ ] 番剧
- [ ] 直播
- [ ] 人像防挡

## Building

There is no Mac in this project. Everything is built and tested on Windows, and iPhone builds go out through GitHub
Actions to TestFlight.

- Flutter 3.47.7 through [fvm](https://fvm.app): `fvm flutter test`, `fvm flutter analyze`.
- `python scripts/gate.py` runs every check at once: the engine, the app, the workflow, a Swift syntax check, and a
  Windows build that runs the real engine.
- On Windows the app opens as an iPhone-sized window, which is how it is driven and checked before each build.

`lib/` is the app; `packages/bili_core/` is pure Dart: the API client, the BTR engine and its local HLS server,
danmaku, logging and the app's rules. `CLAUDE.md` and `docs/` explain the decisions behind them.

## Disclaimer

BiliFast is an unofficial, personal project for learning and personal use. It is not affiliated with, endorsed by or
connected to Bilibili. It talks to Bilibili's public endpoints with your own login and offers nothing that gets around
what your account is allowed to see. Bilibili's names, art and content belong to Bilibili.

## Credits

- [Bilibili Thread Ripper](https://github.com/MrTangLuyao/Bilibili-thread-ripper): the download engine BiliFast's is
  ported from. MIT; its notice is kept with the port.
- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus): the reference for how Bilibili's APIs behave, and the source
  of a few of the official app's assets (see `assets/README.md`). No PiliPlus code is used.
- [MiSans](https://hyperos.mi.com/font/zh/), the bundled font, is developed and owned by Xiaomi and used under its free
  licence; it isn't covered by this repo's code. 本项目内嵌字体为 MiSans 字体，由小米开发并拥有版权。
- [lottie](https://pub.dev/packages/lottie), [cupertino_http](https://pub.dev/packages/cupertino_http),
  [pigeon](https://pub.dev/packages/pigeon) and the other packages in `pubspec.yaml`.
