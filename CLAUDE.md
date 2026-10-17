# BiliFast (Flutter spike and handover)

This folder (renamed from `BiliFlutterSpike` on 2026-10-17) holds the spike that decided BiliFast (KaiC's Swift iOS Bilibili client, `D:\Repos\Apps\BiliNative`) moves to Flutter, and
the handover for doing it. The spike itself is throwaway. It has its own git repo with no remote; KaiC hasn't OK'd a
public repo for it, so never push it.

## Read before working

1. `docs/flutter-move-spec.md`: the spec. It covers what was decided and why, the architecture, the rules, the slices in
   order, and the lessons that must survive. Start with its section 0.
2. `D:\Repos\Apps\BiliNative\CLAUDE.md`: the Swift app's rules. Most still apply to the Flutter app.
3. `docs/reference/`:
   - `bilicore-inventory.md` and `app-inventory.md`: what BiliNative has, with paths.
   - `piliplus-map.md`: where PiliPlus keeps what; it is GPL, so read only.
   - `testflight-flutter.md`: shipping from BiliNative `app/`.

## Where the real work happens

The Flutter app is built in **`D:\Repos\Apps\BiliNative\app\`** (KaiC's choice, 2026-10-17: "Same app, BiliNative
repo"). It ships as the same BiliFast app and reuses his keychain login. A session started in this folder reads the
docs here, then works in BiliNative by absolute path.
- Commit there on `main`. Commit, push and Actions runs are authorised there.
- Touch only `app/`, the new workflows, `.gitignore`, `scripts/testflight.py` and the docs. The Swift app in `ios/` stays
  as it is.

Work slice by slice (spec section 6). Show KaiC a short plan before each slice and wait for his go. Finish each slice
with what was built, how it works and numbered test steps. For phone slices, include the TestFlight build number.

## Rules that bite

- Never commit, print or log secrets, cookies, tokens, signed playurl responses, or anything in `local/` or `logs/`.
  BiliNative is public.
- KaiC's Bilibili account:
  - no second login;
  - few live calls;
  - no loops against the API.
- No Mac (`ssh macrent`, `tools/mac-test.sh`): KaiC is stopping it. iOS checks run in GitHub Actions and on his phone.
- No `gh run watch` and no polling GitHub; check a TestFlight run once, about 20 minutes after `start`.
- PiliPlus and ATV-Bilibili-demo are GPL: read for endpoints and formats, never copy. Keep BTR's MIT notice with the
  engine.
- ghosthand first for screen and browser work.
- Load the `ios-testflight` skill before any workflow, signing or Info.plist change.

## Running the spike (reference only)

- Flutter 3.47.7 is installed through fvm (`fvm flutter …`; `flutter` is not on PATH).
- `fvm flutter build windows --release`, then run `build\windows\x64\runner\Release\bili_flutter_spike.exe`. It runs
  logged out at 480P; options are in `README.md`.
- `fvm flutter test` runs the swipe-back tests.
- `local/` is gitignored and holds saved playurl responses and bench output. Delete saved playurls after use.
