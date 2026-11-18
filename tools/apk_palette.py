# /// script
# requires-python = ">=3.12"
# dependencies = ["androguard==4.1.3"]
# ///
"""The official app's colour palette, day and night, from its APK's resources.arsc (the APK stays in local/).

Bilibili names its palette Ga0-Ga13 (greys), Wh0 (white), Pi0-Pi10 (pink) and so on; each has a day value and,
for night mode, a `night` one. 深色模式 takes its colours from here.

  uv run tools/apk_palette.py dump                  writes local/apk-palette.json: every colour's day and night
  uv run tools/apk_palette.py name <Ga1> ...        a colour's day and night by name
  uv run tools/apk_palette.py day <FFF1F2F3> ...    the palette names whose day value is this (ARGB or RGB hex),
                                                    with their night values; the nearest ones when none is exact
"""

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_APK = ROOT / "local" / "iBiliPlayer-bili.apk"
DEFAULT_JSON = ROOT / "local" / "apk-palette.json"

# The palette's own names, as against the thousands of feature colours.
PALETTE = re.compile(r"(Ga|Wh|Bl|Pi|Lb|Or|Ye|Gr|Re|Br|Cy|Pu|Si|Ly|Lg|Ma|Ba)\d+(_[a-z]+)?")


def dump(apk: Path) -> dict[str, dict[str, str]]:
    from loguru import logger

    logger.remove()
    from androguard.core.axml import ARSCParser

    table = ARSCParser(zipfile.ZipFile(apk).read("resources.arsc"))
    package = table.get_packages_names()[0]
    for locale in table.get_locales(package):
        table.get_types(package, locale)
    out = {}
    for name, resource in table.resource_keys[package].get("color", {}).items():
        values = {}
        for config, entry in table.get_res_configs(resource):
            found = re.search(r"type='int_color_\w+' data='0x([0-9a-f]+)'", repr(entry))
            if found:
                values[config.get_qualifier() or "default"] = found.group(1).rjust(8, "0").upper()
        if "default" in values:
            out[name] = values
    return out


def load(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        sys.exit(f"{path} is missing: run `uv run tools/apk_palette.py dump` first")
    return json.loads(path.read_text())


def rgb(value: str) -> tuple[int, int, int]:
    value = value[-6:]
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    d = sub.add_parser("dump")
    d.add_argument("--apk", type=Path, default=DEFAULT_APK)
    d.add_argument("--out", type=Path, default=DEFAULT_JSON)
    n = sub.add_parser("name")
    n.add_argument("names", nargs="+")
    v = sub.add_parser("day")
    v.add_argument("values", nargs="+")
    args = parser.parse_args()

    if args.command == "dump":
        colours = dump(args.apk)
        args.out.write_text(json.dumps(colours, indent=0, sort_keys=True))
        night = sum("night" in v for v in colours.values())
        print(f"{len(colours)} colours, {night} with a night value -> {args.out}")
        return 0

    colours = load(DEFAULT_JSON)
    palette = {k: v for k, v in colours.items() if PALETTE.fullmatch(k) and "night" in v}
    if args.command == "name":
        for name in args.names:
            value = colours.get(name)
            print(f"{name}: day {value['default']} night {value.get('night', '-')}" if value else f"{name}: none")
        return 0

    for value in args.values:
        want = rgb(value.removeprefix("0x").removeprefix("#"))
        exact = [k for k, v in palette.items() if rgb(v["default"]) == want]
        if not exact:
            ranked = sorted(palette, key=lambda k: max(abs(a - b) for a, b in zip(rgb(palette[k]["default"]), want)))
            exact = ranked[:3]
            print(f"{value}: no exact match, nearest:")
        else:
            print(f"{value}:")
        for k in sorted(exact):
            print(f"  {k:8} day {palette[k]['default']} night {palette[k]['night']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
