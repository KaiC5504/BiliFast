# BiliFast

A Bilibili client for iPhone, written in Flutter, with a Dart port of the
[Bilibili Thread Ripper](https://github.com/MrTangLuyao/Bilibili-thread-ripper) multi-node download engine underneath
and Apple's own player for the video. It replaces the Swift version ([BiliNative](https://github.com/KaiC5504/BiliNative))
screen by screen.

A personal project. Not affiliated with Bilibili.

- `lib/`: the app.
- `packages/bili_core/`: pure Dart: API client, logging, danmaku, app rules (and later the download engine).
- `docs/flutter-move-spec.md`: how and why the move happens.

Build and test: see `CLAUDE.md`, "How to test". The BTR port keeps BTR's MIT notice.

The bundled font is MiSans (`assets/fonts/MiSans-Regular.ttf`), developed and owned by Xiaomi and used under its
free licence ([MiSans](https://hyperos.mi.com/font/zh/)); it is not covered by this repo's code. 本项目内嵌字体为 MiSans 字体，由小米开发并拥有版权。
