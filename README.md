# BiliFlutter spike

A throwaway spike that answers one question: can BiliFast (the Swift iOS Bilibili client in
`D:\Repos\Apps\BiliNative`) move to Flutter without losing playback speed or picture quality?
The answer is in [docs/verdict.md](docs/verdict.md): go, as Flutter screens with Apple's player kept on iOS.
The handover for the move is [docs/flutter-move-spec.md](docs/flutter-move-spec.md), with the source inventories in
`docs/reference/`.

What is here:

- `lib/api/`: the web API calls BiliNative's `BiliClient` makes (WBI signing, 推荐 feed, view, playurl).
- `lib/ripper/`: a minimal Dart port of the BTR multi-node engine (BiliNative's `Sources/Ripper`), serving the
  player through a local HTTP server. BTR's MIT notice is in `lib/ripper/LICENSE-BTR.txt`.
- `lib/ui/`: the 推荐 feed, one video page with a BTR / 直连 switch and a stats panel, and a page route with
  Flutter's Cupertino edge swipe plus a swipe back from anywhere in the content.
- `lib/bench.dart`: an automated A/B run (each video in both modes, order alternating).
- `tool/engine_bench.dart`: engine-only throughput, the counterpart of BiliNative's `ripper-bench`.

## Run it (Windows)

Flutter 3.47.7 is installed through fvm (`C:\Users\KaiChuan\scoop\apps\fvm\current\versions\3.47.7`).

```
flutter build windows --release
build\windows\x64\runner\Release\bili_flutter_spike.exe
```

Options: `--qn 120` (highest quality to pick), `--playurl-dir local/playurl` (play saved playurl responses named
`<BV>.json` instead of calling the API; logged out, Bilibili's DASH stops at 480P),
`--bench BV1,BV2` or `--bench feed:4` (automated A/B, results in `local/bench/*.jsonl`).

Tests: `flutter test` (swipe back on a Windows target). Engine only: `dart run tool/engine_bench.dart --mb 24`.

`local/` is gitignored: saved playurl responses carry signed media URLs and never get committed.
