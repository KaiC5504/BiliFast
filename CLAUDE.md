# BiliFast (Flutter)

KaiC's Bilibili client for iPhone, being moved from Swift (`D:\Repos\Apps\BiliNative`, public repo
`KaiC5504/BiliNative`) to Flutter. This repo is the Flutter app: public `KaiC5504/BiliFast`, branch `main`. It ships as
the same BiliFast app (bundle id `com.kaichuan.bilifast`, App Store Connect Apple ID `6823476667`), so its TestFlight
builds replace the Swift ones on the phone and read the Swift app's keychain login. KaiC's call on 2026-10-17: build it
here rather than in BiliNative `app/`, and push this folder as its own repo.

## Read before working

1. `docs/flutter-move-spec.md`: the spec: decisions and why, architecture, rules, the slices in order, and the lessons
   that must survive. Start with its section 0. Where it says `BiliNative/app/`, read this repo's root.
2. `D:\Repos\Apps\BiliNative\CLAUDE.md`: the Swift app's rules. Most still apply.
3. `docs/reference/`:
   - `bilicore-inventory.md` and `app-inventory.md`: what BiliNative has, with paths. The port's checklist.
   - `piliplus-map.md`: where PiliPlus keeps what; GPL, so read only.
   - `testflight-flutter.md`: how this repo ships to TestFlight.

Work slice by slice (spec section 6). Show KaiC a short plan before each slice and wait for his go. Finish each slice
with what was built, how it works and numbered test steps. For phone slices, include the TestFlight build number.

## Status

- 2026-10-17: slice 0 (foundations): Flutter app at the root, `packages/bili_core` with BiliShared, DevLog, Danmaku,
  BiliAPI and AppLogic ported from Swift tests-first, the keychain channel (checked on the phone in slice 1), CI and the
  signed TestFlight workflow. The spike moved to `spike/`.
- 2026-10-18: slice 0 done. TestFlight dry run green on the first try (run 39038017954: signed, IPA built and checked,
  not uploaded). At KaiC's request the pipeline was cut to one workflow and a local gate (`scripts/gate.py`, 12 s),
  and GitHub calls are kept to what's needed (6 per start, 1 per status).
- 2026-10-18: slice 1 built by seven agents in parallel against shared interfaces, merged, played end to end on
  Windows (muted, logged out), reviewed (Swift and Dart), then one TestFlight run: build 100, green on the first
  try (the Swift compiled first time). The processing wait looped on a missing `timeout` on macOS; fixed. Chinese
  text uses bundled MiSans with the zh-Hans locale (KaiC's choice, as Kazumi). Waiting on KaiC's phone check.
- Next: KaiC's slice-1 phone check (spec section 6), then slice 2 (engine parity).
- Update this section when a slice finishes.

## Layout

- `lib/`: the Flutter app. `lib/account/` keychain and cookie persistence, `lib/app/` routes, `lib/shared/theme.dart`
  the colour and size tokens (never hardcode colours).
- `packages/bili_core/`: pure Dart, no Flutter import, the port of the Swift package `BiliCore`. One library per Swift
  module: `shared.dart`, `devlog.dart`, `danmaku.dart`, `api.dart`, `logic.dart`.
- `ios/Runner/`: native Swift (`KeychainChannel.swift`; the player view comes in slice 1). New Swift files must be added
  to `ios/Runner.xcodeproj/project.pbxproj` by hand (four entries, see `KeychainChannel.swift`'s).
- `spike/`: the throwaway spike, kept until later slices have taken what they need (spec section 11). Not analysed.
- `test_ci/`: static tests of the workflows (pins, secrets only in step env, nothing leaks into the public log).

## How to test

- Flutter 3.47.7 through fvm: `fvm flutter …` / `fvm dart …` (`flutter` is not on PATH). Pinned in `.fvmrc`, the
  pubspec and both workflows; `test_ci` checks they agree.
- Everything at once: `python scripts/gate.py`. Lanes in parallel: bili_core, the app, `test_ci`, a Swift syntax check
  of `ios/Runner` (`swiftc -parse`; no iOS SDK on the PC), and the Windows release build plus the Windows
  integration tests (real mpv). About 20 s warm. `--quick` skips the Windows lane and records nothing.
- Core: `fvm dart test` in `packages/bili_core`.
- App: `fvm flutter analyze` and `fvm flutter test` at the root.
- Workflows: `uv run --no-project --with pyyaml==6.0.3 python -m unittest discover -s test_ci`.
- Windows app: `fvm flutter build windows --release`, then `build\windows\x64\runner\Release\bilifast.exe` (440×880
  window). It runs logged out; there is no keychain on Windows.
- GitHub runs nothing on push. `testflight.yml` is the only workflow (KaiC's call, 2026-10-18: keep only the
  workflows that matter, such as shipping to TestFlight). Tests run in the local gate; a dry run of the signed build
  is the iOS compile check. Don't add a workflow without asking; `test_ci` fails if one appears.

## Shipping

The `ios-testflight` skill is the playbook; load it before touching any workflow, signing or Info.plist.
- `.github/workflows/testflight.yml` signs and uploads when `python scripts/testflight.py start` dispatches it. Run
  `start --dry-run` after any workflow change. Secrets are in this repo's `testflight` environment (limited to `main`).
- Build numbers come from App Store Connect plus one, with a floor of 99: the Swift app shipped 1-8, Flutter builds
  start at 100. Version 0.2.0 (the Swift app was 0.1.0).
- The loop: `python scripts/gate.py` on the committed tree (it records the commit it passed), push, then
  `python scripts/testflight.py start` (6 GitHub calls). `start` refuses without the gate's record for that exact
  commit, so it can't ship an unchecked commit. No dry run before an ordinary ship: a red upload run costs the same as
  a red dry run, and a green one is on the phone.
- GitHub comes last (KaiC, 2026-10-18): parallel work is merged, checked locally and reviewed (Swift that only the Mac
  can compile gets a review agent) before the one run, and each red run's errors are all fixed together. `status`
  prints every error line of a failed run, and a Release build type-checks the whole Swift module at once, so one run
  shows them all.
- GitHub calls only when the answer is needed (KaiC gets rate-limited): no polling, no extra runs to measure
  things, one `status` per run.
- Don't watch the run: `python scripts/testflight.py status` once (1 call), about 10 minutes after a dry run and 20
  after an upload. There is no watch command on purpose.
- Report the build number, what changed and phone test steps.
- Commit, push and Actions runs (signed builds included) are authorised on `main`.

## Rules that bite

- Public repo. Never commit, print or log secrets, cookies, tokens, signed playurl responses, or anything in `local/`
  or `logs/` (both gitignored). The build log and artifacts are public too.
- KaiC's Bilibili account: no second login, few live calls, no loops against the API. Tests never touch the network.
- No Mac (`ssh macrent`): iOS checks run in GitHub Actions and on his phone.
- No `gh run watch` and no polling GitHub.
- PiliPlus (`D:\Repos\Apps\PiliPlus`) is the main reference for how a feature works (KaiC, 2026-10-18: it's a mature
  Flutter Bilibili client, and BiliFast is largely a new UI over the same behaviour). Before building a feature, read
  how PiliPlus does it (`docs/reference/piliplus-map.md` says where), alongside BiliNative's Swift. It and
  ATV-Bilibili-demo are GPL: write our own code from what they show; never copy their code (KaiC chose to keep BiliFast
  non-GPL, 2026-10-18). Keep BTR's MIT notice with the engine port.
- Danmaku block-word regexes run on Dart's (ECMAScript) `RegExp`, not ICU as in Swift: `(?i)`, possessive and atomic
  groups throw (the rule is skipped), and `\p{Han}` or `\A` mean something else.
- ghosthand first for screen and browser work. Flutter windows often have a thin accessibility tree; use `screenshot`.
- The BiliNative repo: only docs change there now (and Swift fixes if something blocks daily use).
