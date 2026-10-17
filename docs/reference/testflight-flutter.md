# Shipping the Flutter app to TestFlight from BiliNative `app/`

How to build a Flutter app from BiliNative's `app/` folder and ship it as the next BiliFast builds. It reuses BiliNative's
existing `testflight` environment and borrows Kazumi's Flutter build steps. Read the global `ios-testflight` skill
before touching any of this (`C:\Users\KaiChuan\.claude\skills\ios-testflight\SKILL.md`). Its pipeline-critical
settings apply to Flutter too.

Facts below come from 2026-10-17 reads of `D:\Repos\Apps\Kazumi` and `D:\Repos\Apps\BiliNative`, plus read-only `gh`
calls (secret names only).

## What already exists

- **App identity:** bundle id `com.kaichuan.bilifast`, App Store Connect app `BiliFast`, Apple ID `6823476667`
  (`ASC_APP_ID`). The display name is BiliFast; the Swift target and scheme are `BiliNative`.
- **The `testflight` environment** on `KaiC5504/BiliNative` holds `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERT_KEY_B64` and `SIGNING_NAME`. It is limited to
  `main` (custom branch policies, one policy: `main`). The repo itself has no secrets.
- **`BILI_APP_KEYS` is not set anywhere.** That is why 不喜欢 ships greyed out.
- **Signing files already exist:** the App Store certificate and profile for `com.kaichuan.bilifast` (Swift builds 1-8).
  Plain `fetch-signing-files` finds them, so never pass `--create`/`create_signing` for the Flutter build.
- **Build numbers:** the last Swift upload was build 8 (run 39012161549). BiliNative's step asks App Store Connect for
  the highest build across all versions and adds 1, so the first Flutter upload gets 9 or more with no floor change.
  To make Flutter builds easy to tell apart, give the Flutter workflow `BUILD_NUMBER_FLOOR: "99"` (first Flutter build
  100). Later Swift builds would then also continue above 100, since both read the same latest number.
- **Toolchain on the PC:** fvm 4.3.1 (scoop) with Flutter 3.41.9, 3.47.6 and **3.47.7** (Dart 3.13.5). `flutter` and
  `dart` are not on PATH; call `fvm flutter …`, or the full path
  `C:\Users\KaiChuan\scoop\apps\fvm\current\versions\3.47.7\bin\flutter.bat`. Kazumi pins 3.47.7 everywhere (`.fvmrc`,
  pubspec `environment: flutter: 3.47.7`, workflow `flutter-version: 3.47.7`). Check for a newer stable before starting
  (KaiC's rule: latest stable) and pin one version in all three places.

## Must-do changes in BiliNative before the first Flutter push

1. **`.gitignore`:** line 4 `*.xcodeproj/` would hide `app/ios/Runner.xcodeproj/` (confirmed with
   `git check-ignore -v --no-index`). Add `!/app/ios/Runner.xcodeproj/` right after it. The unanchored `local/` line
   also matches `app/local/`, which is what we want.
2. **Create the project with the right id:** `fvm flutter create --org com.kaichuan --project-name bilifast
   --platforms ios,android,windows app`, then check that `PRODUCT_BUNDLE_IDENTIFIER = com.kaichuan.bilifast` appears in
   all 3 Runner configs. Without `--project-name`, the folder name would give `com.kaichuan.app`.
3. **`app/ios/Runner/Info.plist`:**
   - `CFBundleDisplayName` BiliFast.
   - `ITSAppUsesNonExemptEncryption` false.
   - Keep the template's 4 `UISupportedInterfaceOrientations~ipad` entries.
   - `UIBackgroundModes` [audio].
   - `NSAppTransportSecurity.NSAllowsLocalNetworking` true (the in-app 127.0.0.1 server).
   - `NSPhotoLibraryAddUsageDescription` 用于把视频截图保存到相册。
   - `NSLocalNetworkUsageDescription` 用于把调试日志发送到你电脑上的日志服务器。
   - `NSBonjourServices` [`_bilinative-log._tcp`].
   - Portrait, LandscapeLeft and LandscapeRight for iPhone.
4. **Xcode project settings:**
   - `TARGETED_DEVICE_FAMILY = 1` (iPhone only, like the Swift app).
   - Deployment target 26.0, to match the Swift app (it also gets the newest AVKit and PiP behaviour).
   - Leave `DEVELOPMENT_TEAM` unset with automatic signing; `use-profiles` fills both in.
5. **Podfile:** the spike (Flutter 3.47.7) has none; plugins come in through SwiftPM (`FlutterGeneratedPluginSwiftPackage`).
   If a plugin lacks SwiftPM support, `flutter build ipa` generates `ios/Podfile` on the Mac runner. Commit it, with a
   real `platform :ios` line.

## The signed workflow: a second file, `.github/workflows/testflight-flutter.yml`

Keep `testflight.yml` (Swift) working until cutover. Copy it and change only what is listed here.

**Keep from BiliNative's `testflight.yml`, unchanged**
- The trigger is `workflow_dispatch` with `sha`, `upload` and `create_signing`.
- `run-name: TestFlight ${{ inputs.upload && 'upload' || 'dry run' }} ${{ inputs.sha }}`. `testflight.py` matches runs
  on the prefixes `TestFlight upload` / `TestFlight dry run`.
- **`concurrency: {group: testflight, cancel-in-progress: false}`, the same group as the Swift workflow.** Swift and
  Flutter runs then queue behind each other and can never pick the same build number.
- `permissions: contents: read`, `cache-mode: none`, `APP_STORE_CONNECT_DISABLE_JWT_CACHE: "1"`, `BUNDLE_ID`, `ASC_APP_ID`.
- The `build` job settings: `if: github.ref == 'refs/heads/main'`, `runs-on: macos-26`, `timeout-minutes: 60`,
  `environment: testflight`.
- Steps:
  - The SHA guard as the first step.
  - Checkout `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` with `persist-credentials: false`.
  - `actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0` (3.13), then the hash-locked cli-tools
    install (`scripts/testflight-requirements.txt`, `codemagic-cli-tools==0.70.0`), with `openssl@3` on PATH.
  - "Create signing files", as it is: random keychain password, masked PEM lines, a masked p12 password, p12 cleanup
    and `set-key-partition-list`.
  - "Pick the build number": BiliNative's version, which survives an app with no builds yet. Kazumi's simpler parse
    does not.
  - The upload, `app-store-connect publish --path "$IPA"`.
  - The `processed` job, with `if: inputs.upload`. Kazumi's variant always runs and, on a dry run, polls the
    `BUILD_NUMBER_FLOOR` build, which does not exist here.

**Remove**
- The "App keys" step, which writes Swift into `ios/Generated`. Re-add a Dart version only once `BILI_APP_KEYS` exists
  (see below).
- "Generate the Xcode project" (xcodegen), the `PROJECT`/`SCHEME` env and `xcode-project build-ipa`.

**Add, from Kazumi's `testflight.yaml`**
- `subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2.23.0` with `channel: stable`,
  `flutter-version: <pinned>` and `cache: false`.
- An Xcode pin, as Kazumi does it:
  - `XCODE_VERSION: "26.6"`, `XCODE_BUILD: 17F113`.
  - `sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app`.
  - Fail unless `xcodebuild -version` shows that build.
  - Flutter 3.47.7 with Xcode 26.6 is the pair Kazumi has proven.
- `flutter pub get` with `working-directory: app`.
- "Apply signing settings":
  `xcode-project use-profiles --project app/ios/Runner.xcodeproj --export-options-plist "$RUNNER_TEMP/export_options.plist" --code-signing-setup-verbose-logging`
- "Build IPA", with `working-directory: app`:
  ```
  flutter build ipa --release \
    --build-name=0.2.0 \
    --build-number="$BUILD_NUMBER" \
    --export-options-plist="$RUNNER_TEMP/export_options.plist"
  ```
  - Require exactly one `build/ios/ipa/*.ipa`.
  - Write an absolute path to `IPA` (`"$GITHUB_WORKSPACE/app/$ipa"`), since the upload step runs from the repo root.
  - Keep `--build-name` at or above the Swift app's `0.1.0`.
- Optional, recommended: Kazumi's `scripts/ipa_manifest.py` describe and check steps, with the manifest uploaded as the
  only artifact. Set `PURPOSE_STRINGS` to the keys listed above.

**Never** `set -x`, `flutter -v`/`--verbose`, `env`/`printenv`, or upload the IPA, Xcode logs or
`Generated.xcconfig`. The log is public.

## `BILI_APP_KEYS` (不喜欢) in the Flutter build, when it is added

There are two ways to bring the key pair in:
- **A generated, gitignored Dart file** (`app/lib/generated/app_keys.dart`), written by an extended
  `tools/write_app_keys.py`. This is the preferred way: the value never enters `DART_DEFINES` or `Generated.xcconfig`.
- A `--dart-define`. If you go this way, copy Kazumi's "Mask encoded … values" step first. Flutter passes defines to
  Xcode base64-encoded as `NAME=value`, and Xcode prints them with `=` escaped as `\=`, so every encoding and offset
  needs masking.

Either way, the secret must first be added to the `testflight` environment by KaiC. That is a manual step from the
skill, step 5.

## `scripts/testflight.py`

- Add `--flutter` (sets `WORKFLOW = "testflight-flutter.yml"`), or copy the script.
- Its `runs()`, `last_shipped()` and busy checks are per workflow; the shared concurrency group covers a Swift run in
  flight.
- `start --dry-run` after any workflow change. Then `start` (upload), and check the result once with
  `gh run view <id>` about 20 minutes later. **Never** `gh run watch` and never poll: on 2026-10-17 polling tripped
  GitHub's rate limit and blocked KaiC's own requests.

## Compile check for `app/`

- `ios-compile.yml` will **not** run on `app/` changes: its path filter `ios/**` matches from the repo root. Leave it for
  the Swift app.
- Add `.github/workflows/app-compile.yml`, based on Kazumi's `ios-check.yaml`:
  - `on: push: paths: ["app/**", ".github/workflows/app-compile.yml"]`, plus `workflow_dispatch`.
  - `macos-26`.
  - flutter-action with `cache: false`.
  - In `app/`: `flutter pub get`, `flutter analyze`, `flutter test`, then `flutter build ios --release --no-codesign`.
  - No `environment` and no secrets.
- Most checks run on the PC instead: `fvm flutter analyze` and `fvm flutter test` in `app/`, plus a Windows build of the
  same app.

## Kazumi files worth reading

- `D:\Repos\Apps\Kazumi\.github\workflows\testflight.yaml`, the signed Flutter build.
- `D:\Repos\Apps\Kazumi\.github\workflows\ios-check.yaml`, the unsigned compile.
- `D:\Repos\Apps\Kazumi\scripts\testflight.py` and `scripts\ipa_manifest.py`.
- `D:\Repos\Apps\Kazumi\test\ci\`: static tests of the workflow YAML (pins, secrets only in step env, no `--create`, no
  leaks), run with `uv run --no-project --with pyyaml==6.0.3 python -m unittest discover -s test/ci`. Port the ones that
  apply; with two TestFlight workflows, allow both in `OtherWorkflowsTest`.
- Kazumi-only pieces to skip: `partner_check.py` guards, the dandanplay masks, `brew install cmake ninja`, and the
  build-time bundle id `sed` (Kazumi is a fork; this app commits its own id).
