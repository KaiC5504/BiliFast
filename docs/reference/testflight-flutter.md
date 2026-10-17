# Shipping BiliFast (Flutter) to TestFlight

How this repo (`KaiC5504/BiliFast`) ships as the next BiliFast builds. Read the global `ios-testflight` skill before
touching any of this (`C:\Users\KaiChuan\.claude\skills\ios-testflight\SKILL.md`); its pipeline-critical settings apply
to Flutter too. Rewritten 2026-10-17 in slice 0, when the app moved here from the planned `BiliNative/app/`.

## App identity (unchanged from the Swift app)

- Bundle id `com.kaichuan.bilifast`, App Store Connect app `BiliFast`, Apple ID `6823476667` (`ASC_APP_ID`).
- The certificate and App Store profile already exist (Swift builds 1-8). Plain `fetch-signing-files` finds them, so
  never pass `--create-signing` except for a renewal.
- Same bundle id and team, so the keychain items the Swift app wrote are readable here
  (`ios/Runner/KeychainChannel.swift`).

## What is in the repo

- `ios/Runner/Info.plist`: display name BiliFast, `CFBundleIconName` AppIcon (the pink Bolt, 1024 px, no alpha),
  `ITSAppUsesNonExemptEncryption` false, `UIBackgroundModes` [audio], `NSAllowsLocalNetworking` (the in-app 127.0.0.1
  server), `NSPhotoLibraryAddUsageDescription` 用于把视频截图保存到相册。, `NSLocalNetworkUsageDescription`
  用于把调试日志发送到你电脑上的日志服务器。, `NSBonjourServices` [`_bilinative-log._tcp`], portrait and both
  landscapes on iPhone plus the four iPad entries upload validation wants, `CADisableMinimumFrameDurationOnPhone` (120 Hz).
- Xcode project: `TARGETED_DEVICE_FAMILY = 1`, iOS 26.0, automatic signing with no team (`use-profiles` fills it in).
  No Podfile: Flutter 3.47.7 brings plugins in through SwiftPM. If a later plugin lacks SwiftPM support,
  `flutter build ipa` generates `ios/Podfile` on the runner; commit it with a real `platform :ios` line.
- `.github/workflows/testflight.yml`: BiliNative's signed workflow with Kazumi's Flutter steps.
  - `workflow_dispatch` with `sha`, `upload`, `create_signing`; the SHA guard first; `concurrency: testflight`.
  - `subosito/flutter-action` pinned to Flutter 3.47.7, Xcode 26.6 (build 17F113) checked exactly.
  - `use-profiles --export-options-plist`, then `flutter build ipa --build-name=0.2.0 --build-number=$BUILD_NUMBER`.
  - Build number = App Store Connect's latest + 1, floor 99, so Flutter builds start at 100.
  - `scripts/ipa_manifest.py` describes and checks the IPA (bundle id, build, purpose strings, App Store profile,
    beta-reports-active); the JSON manifest is the only artifact.
  - The `processed` job waits for Apple's `VALID` on uploads.
- `.github/workflows/app-compile.yml`: on every push, analyze and tests on Linux (bili_core, the app, `test_ci`), then
  `flutter build ios --release --no-codesign` on `macos-26`. No secrets, no environment.
- `test_ci/test_testflight_workflow.py`: Kazumi's static workflow tests, adapted. Also checks Flutter and Xcode are
  pinned the same in `.fvmrc`, the pubspec and both workflows, and that no other workflow can sign or upload.
- `scripts/testflight.py`: `start [--dry-run] [--create-signing] [--again]`, `status`. It refuses to start unless the
  `testflight` environment is limited to `main` and holds all five secrets.

## The `testflight` environment (owner, once)

The ios-testflight skill's manual-steps §5 for repo `BiliFast`: the three `gh api` commands (environment limited to
`main`, fork-PR approval), then the five secrets from the password manager: `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERT_KEY_B64`, `SIGNING_NAME`. Verify with
`gh secret list --env testflight -R KaiC5504/BiliFast`.

## The loop

1. Push; wait for the "App compile check" to go green.
2. `python scripts/testflight.py start` (after `--dry-run` whenever the workflow or scripts change).
3. One `gh run view <id>` about 20 minutes later. Never `gh run watch` and never poll: on 2026-10-17 polling tripped
   GitHub's rate limit and blocked KaiC's own requests.
4. Report the build number, what changed and phone steps.

**Never** `set -x`, `flutter -v`/`--verbose`, `env`/`printenv`, or upload the IPA, Xcode logs or
`Generated.xcconfig`. The log is public.

## `BILI_APP_KEYS` (不喜欢), when it is added

- Preferred: a generated, gitignored Dart file (`lib/generated/app_keys.dart`) written by a script from the secret, so
  the value never enters `DART_DEFINES` or `Generated.xcconfig`.
- A `--dart-define` would need Kazumi's "Mask encoded … values" step first: Flutter passes defines to Xcode
  base64-encoded as `NAME=value`, and Xcode prints them with `=` escaped as `\=`.
- Either way KaiC adds the secret to the `testflight` environment first (manual-steps §5).
