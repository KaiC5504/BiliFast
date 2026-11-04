#!/usr/bin/env python3
"""Build on KaiC's Mac mini over SSH (`ssh mac`) and run the result on his iPhone or a simulator.

    python scripts/mac.py phone                     # build HEAD, install on the iPhone over Wi-Fi
    python scripts/mac.py sim [--pad] [--wait 8] [--name shot]
                                                    # build HEAD for the simulator, launch it, screenshot
    python scripts/mac.py stop                      # shut the simulators down

Everything runs headless: nothing opens on the Mac's screen. HEAD is pushed to the Mac's own repo
(the `mac` remote), never through GitHub, so uncommitted changes are left out.

The phone build is development-signed, release mode, with DEV_INSTALL so its profile doesn't count as a
sideload; it replaces the TestFlight install and keeps its login and data. The simulator build is debug
with FAKE_ACCOUNT and MUTE: no account traffic and no sound from the Mac's speakers.

The Mac holds what the repo must not: `~/bilifast-mac/asc.env` (the API key's ids and path, the team,
the signing identity and profile name, the phone's UDID), the build keychain and its password.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "mac-shots"
BUNDLE_ID = "com.kaichuan.bilifast"
SIMULATORS = {
    "phone": ("BiliFast iPhone", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"),
    "pad": ("BiliFast iPad", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB"),
}

PREPARE = r"""
set -euo pipefail
export LANG=en_US.UTF-8 PATH="$HOME/flutter-3.47.7/bin:/opt/homebrew/bin:$PATH"
set -a; . ~/bilifast-mac/asc.env; set +a
cd ~/bilifast-mac/BiliFast
git fetch -q origin build
git checkout -q -f --detach FETCH_HEAD
git log --oneline -1
"""

PHONE = r"""
KC="$HOME/bilifast-mac/signing.keychain-db"
security unlock-keychain -p "$(cat ~/bilifast-mac/keychain.pw)" "$KC"
# A build number from the clock (yymmddHHMM), so the phone shows which install it runs.
build=$(date +%y%m%d%H%M)
flutter build ios --release --config-only --build-number="$build" --dart-define=DEV_INSTALL=true \
  > ~/bilifast-mac/build.log 2>&1
# The profile goes on the Runner target only: set on the command line it lands on the plugins' packages too,
# which refuse one.
echo "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_NAME" > ios/Flutter/MacSigning.xcconfig
echo '#include? "MacSigning.xcconfig"' >> ios/Flutter/Release.xcconfig
if ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
    -destination generic/platform=iOS -derivedDataPath build/dd \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--keychain $KC" build >> ~/bilifast-mac/build.log 2>&1; then
  grep -E "error:" ~/bilifast-mac/build.log | head -20
  echo "build failed: ~/bilifast-mac/build.log on the Mac"
  exit 1
fi
echo "built"
xcrun devicectl device install app --device "$PHONE_UDID" build/dd/Build/Products/Release-iphoneos/Runner.app \
  > ~/bilifast-mac/install.log 2>&1 || { tail -5 ~/bilifast-mac/install.log; exit 1; }
installed=$(xcrun devicectl device info apps --device "$PHONE_UDID" --bundle-id com.kaichuan.bilifast 2>/dev/null \
  | grep -oE "[0-9]+\.[0-9]+\.[0-9]+ +[0-9]+" | head -1)
echo "installed on the iPhone: $installed (this build: $build)"
"""

SIM = r"""
name="{name}"; type="{type}"
udid=$(xcrun simctl list devices available | sed -nE "s/^ *$name \(([0-9A-F-]+)\).*/\1/p" | head -1)
if [ -z "$udid" ]; then
  runtime=$(xcrun simctl list runtimes | sed -nE 's/^iOS .* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+)$/\1/p' | tail -1)
  udid=$(xcrun simctl create "$name" "$type" "$runtime")
fi
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl status_bar "$udid" override --time 9:41 --batteryLevel 100 --batteryState charged \
  --cellularBars 4 --wifiBars 3 > /dev/null 2>&1 || true
if ! flutter build ios --simulator --debug --dart-define=FAKE_ACCOUNT=true --dart-define=MUTE=true \
    --dart-define=DEV_INSTALL=true > ~/bilifast-mac/build.log 2>&1; then
  grep -E "error" ~/bilifast-mac/build.log | head -20
  echo "build failed: ~/bilifast-mac/build.log on the Mac"
  exit 1
fi
echo "built"
xcrun simctl terminate "$udid" {bundle} > /dev/null 2>&1 || true
xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$udid" {bundle} > /dev/null
sleep {wait}
mkdir -p ~/bilifast-mac/shots
xcrun simctl io "$udid" screenshot ~/bilifast-mac/shots/{shot}.png > /dev/null 2>&1
echo "launched on $name"
"""

STOP = r"""
xcrun simctl shutdown all
echo "simulators shut down"
"""


def push_head() -> None:
    dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT,
                           capture_output=True, text=True, check=True).stdout.strip()
    if dirty:
        print("note: uncommitted changes are not in this build", file=sys.stderr)
    subprocess.run(["git", "push", "-q", "--force", "mac", "HEAD:refs/heads/build"], cwd=ROOT, check=True)


def on_mac(script: str) -> None:
    # Bytes, not text: on Windows a text pipe sends \r\n, and bash then reads `set -e\r`.
    result = subprocess.run(["ssh", "-o", "BatchMode=yes", "mac", "bash", "-s"], input=script.encode())
    if result.returncode:
        sys.exit(result.returncode)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("phone")
    sim = commands.add_parser("sim")
    sim.add_argument("--pad", action="store_true", help="the iPad simulator instead of the iPhone's")
    sim.add_argument("--wait", type=int, default=8, help="seconds between launch and the screenshot")
    sim.add_argument("--name", default="launch", help="the screenshot's file name, without .png")
    commands.add_parser("stop")
    args = parser.parse_args()

    if args.command == "stop":
        on_mac(STOP)
        return
    push_head()
    if args.command == "phone":
        on_mac(PREPARE + PHONE)
        return
    name, device_type = SIMULATORS["pad" if args.pad else "phone"]
    on_mac(PREPARE + SIM.format(name=name, type=device_type, bundle=BUNDLE_ID, wait=args.wait, shot=args.name))
    SHOTS.mkdir(parents=True, exist_ok=True)
    target = SHOTS / f"{args.name}.png"
    subprocess.run(["scp", "-q", "-o", "BatchMode=yes", f"mac:bilifast-mac/shots/{args.name}.png", str(target)],
                   check=True)
    print(target)


if __name__ == "__main__":
    main()
