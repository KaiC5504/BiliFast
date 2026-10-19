# Shipping BiliFast (Flutter) to TestFlight

How this repo (`KaiC5504/BiliFast`) ships as the next BiliFast builds. Read the global `ios-testflight` skill before
touching any of this (`C:\Users\KaiChuan\.claude\skills\ios-testflight\SKILL.md`); its pipeline-critical settings apply
to Flutter too.

## App identity (unchanged from the Swift app)

- Bundle id `com.kaichuan.bilifast`, App Store Connect app `BiliFast`, Apple ID `6823476667` (`ASC_APP_ID`).
- The certificate and App Store profile already exist (Swift builds 1-8). Plain `fetch-signing-files` finds them, so
  never pass `--create-signing` except for a renewal.
- Same bundle id and team, so the keychain items the Swift app wrote are readable here
  (`ios/Runner/KeychainChannel.swift`).

## What is in the repo

- `ios/Runner/Info.plist`: display name BiliFast, `CFBundleIconName` AppIcon (the sprinting TV from `design/icon-options/` plus its dark-appearance version, 1024 px, no alpha),
  `ITSAppUsesNonExemptEncryption` false, `UIBackgroundModes` [audio], `NSAllowsLocalNetworking` (the in-app 127.0.0.1
  server), `NSPhotoLibraryAddUsageDescription` 用于把视频截图保存到相册。, `NSPhotoLibraryUsageDescription` and
  `NSCameraUsageDescription` (comment pictures), `NSLocalNetworkUsageDescription`
  用于把调试日志发送到你电脑上的日志服务器。, `NSBonjourServices` [`_bilinative-log._tcp`], portrait and both
  landscapes on iPhone plus the four iPad entries upload validation wants, `CADisableMinimumFrameDurationOnPhone` (120 Hz).
- Xcode project: `TARGETED_DEVICE_FAMILY = 1`, iOS 26.0, automatic signing with no team (`use-profiles` fills it in).
  No Podfile: Flutter 3.47.7 brings plugins in through SwiftPM. If a later plugin lacks SwiftPM support,
  `flutter build ipa` generates `ios/Podfile` on the runner; commit it with a real `platform :ios` line.
- `.github/workflows/testflight.yml`: BiliNative's signed workflow with Kazumi's Flutter steps.
  - `workflow_dispatch` with `sha`, `upload`, `create_signing`; the SHA guard first; `concurrency: testflight`.
  - `subosito/flutter-action` pinned to Flutter 3.47.7, Xcode 26.6 (build 17F113) checked exactly.
  - `use-profiles --export-options-plist`, then `flutter build ipa --build-name=$BUILD_NAME --build-number=$BUILD_NUMBER`.
  - Build number = App Store Connect's latest build of `BUILD_NAME` + 1, so each version counts from 1 (1.0.0 (1)
    followed 0.2.0 (100)). The processing wait matches version and build number, since numbers repeat across versions.
  - `scripts/ipa_manifest.py` describes and checks the IPA (bundle id, build, purpose strings, App Store profile,
    beta-reports-active); the JSON manifest is the only artifact.
  - On uploads, the last step waits for Apple's `VALID` (every 15 s, up to an hour).
- No other workflow (KaiC, 2026-10-18). Tests run locally in `scripts/gate.py`; a dry run is the iOS compile check.
- `test_ci/test_testflight_workflow.py`: Kazumi's static workflow tests, adapted. Also checks Flutter is pinned the
  same in `.fvmrc`, the pubspec and the workflow, and that `testflight.yml` is the only workflow.
- `test_ci/test_testflight_script.py`: `testflight.py` against a fake `gh`, including how many calls it makes.
- `scripts/testflight.py`: `start [--dry-run] [--create-signing] [--again]`, `status [RUN_ID]`. It refuses to start unless the local gate passed on the commit, and the
  `testflight` environment is limited to `main` and holds all five secrets.

## The `testflight` environment (owner, once)

The ios-testflight skill's manual-steps §5 for repo `BiliFast`: the three `gh api` commands (environment limited to
`main`, fork-PR approval), then the five secrets from the password manager: `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERT_KEY_B64`, `SIGNING_NAME`. Verify with
`gh secret list --env testflight -R KaiC5504/BiliFast`.

## The loop

1. `python scripts/gate.py` on the committed tree (records the commit), then push. Nothing runs on push.
2. `python scripts/testflight.py start` (`--dry-run` only when the workflow or scripts change). It refuses unless the gate passed on that commit. 6 GitHub calls;
   `test_ci/test_testflight_script.py` pins the count.
3. `python scripts/testflight.py status` once (1 call): about 7 minutes after a dry run, 11 after an upload. Never
   `gh run watch` and never poll: on 2026-10-17 polling tripped GitHub's rate limit and blocked KaiC's own requests.
4. Report the build number, what changed and phone steps.

Speed notes (2026-10-18): Flutter's iOS artifacts and packages download while cli-tools installs; Apple processing is
awaited inside the build job (no second runner and install), polling App Store Connect every 15 s; the
flutter-action SDK cache stays off in the signing job (`cache-mode: none`, so no cache another workflow wrote can run
next to the signing key).

**Never** `set -x`, `flutter -v`/`--verbose`, `env`/`printenv`, or upload the IPA, Xcode logs or
`Generated.xcconfig`. The log is public.

## `BILI_APP_KEYS` (不喜欢), when it is added

- Preferred: a generated, gitignored Dart file (`lib/generated/app_keys.dart`) written by a script from the secret, so
  the value never enters `DART_DEFINES` or `Generated.xcconfig`.
- A `--dart-define` would need Kazumi's "Mask encoded … values" step first: Flutter passes defines to Xcode
  base64-encoded as `NAME=value`, and Xcode prints them with `=` escaped as `\=`.
- Either way KaiC adds the secret to the `testflight` environment first (manual-steps §5).
