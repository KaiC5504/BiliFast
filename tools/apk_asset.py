# /// script
# requires-python = ">=3.12"
# dependencies = ["androguard==4.1.3", "skia-python==144.1", "numpy", "pillow"]
# ///
"""Finds and extracts the official app's art from its APK (kept in local/, never committed).

The APK's files have scrambled names, so resources are found by their real names through resources.arsc.

  uv run tools/apk_asset.py find <word>...          names of drawables containing every word
  uv run tools/apk_asset.py show <name>             its file per density, and a vector's or layer-list's XML
  uv run tools/apk_asset.py extract <name> <out.png> [--width PX]
      a bitmap as it is; a vector drawn white, cut to its ink and scaled to PX wide (3x pixels), for tinting
"""

import argparse
import re
import sys
import zipfile
from pathlib import Path

from loguru import logger

logger.remove()
from androguard.core.axml import ARSCParser, AXMLPrinter  # noqa: E402

DEFAULT_APK = Path(__file__).resolve().parent.parent / "local" / "iBiliPlayer-bili.apk"


def load(apk: Path):
    archive = zipfile.ZipFile(apk)
    table = ARSCParser(archive.read("resources.arsc"))
    for package in table.get_packages_names():
        for locale in table.get_locales(package):
            table.get_types(package, locale)  # the parser fills resource_keys lazily
    return archive, table


def drawables(table) -> dict[str, int]:
    found: dict[str, int] = {}
    for types in table.resource_keys.values():
        found.update(types.get("drawable", {}))
    return found


def files_of(table, resource_id: int) -> list[tuple[str, str]]:
    out = []
    for config, value in table.get_res_configs(resource_id):
        match = re.search(r"data='0x([0-9a-f]+)'", str(value))
        if match and "type='string'" in str(value):
            out.append((config.get_qualifier() or "(default)", table.stringpool_main.getString(int(match.group(1), 16))))
    return out


def render_vector(xml: str, width: int, out: Path) -> None:
    import numpy as np
    import skia
    from PIL import Image

    view_w = float(re.search(r'viewportWidth="([\d.]+)"', xml).group(1))
    view_h = float(re.search(r'viewportHeight="([\d.]+)"', xml).group(1))
    paths = re.findall(r'android:pathData="([^"]+)"', xml)
    scale = 2048 / view_w
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{view_w * scale}" height="{view_h * scale}" '
        f'viewBox="0 0 {view_w} {view_h}">'
        + "".join(f'<path fill="#ffffff" fill-rule="evenodd" d="{d}"/>' for d in paths)
        + "</svg>"
    )
    dom = skia.SVGDOM.MakeFromStream(skia.MemoryStream(svg.encode()))
    size = (int(view_w * scale), int(view_h * scale))
    surface = skia.Surface(*size)
    canvas = surface.getCanvas()
    canvas.clear(skia.ColorTRANSPARENT)
    dom.setContainerSize(skia.Size(*size))
    dom.render(canvas)
    alpha = surface.makeImageSnapshot().toarray()[:, :, 3]
    ys, xs = np.where(alpha > 0)
    ink = Image.fromarray(alpha[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1])
    height = round(ink.height * width / ink.width)
    small = ink.resize((width, height), Image.LANCZOS)
    Image.merge("LA", (Image.new("L", small.size, 255), small)).save(out, optimize=True)
    print(f"{out}: {width}x{height} px, {width / 3:.2f} x {height / 3:.2f} pt at 3x")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    sub = parser.add_subparsers(dest="command", required=True)
    find = sub.add_parser("find")
    find.add_argument("words", nargs="+")
    show = sub.add_parser("show")
    show.add_argument("name")
    extract = sub.add_parser("extract")
    extract.add_argument("name")
    extract.add_argument("out", type=Path)
    extract.add_argument("--width", type=int, help="pixels wide at 3x, for a vector")
    args = parser.parse_args()

    archive, table = load(args.apk)
    names = drawables(table)
    if args.command == "find":
        for name in sorted(n for n in names if all(w in n for w in args.words)):
            print(name)
        return 0
    if args.name not in names:
        print(f"no drawable named {args.name}", file=sys.stderr)
        return 1
    files = files_of(table, names[args.name])
    if args.command == "show":
        for density, path in files:
            print(density, path)
            if path.endswith(".xml"):
                print(AXMLPrinter(archive.read(path)).get_xml().decode())
        return 0
    # The densest bitmap, else the vector.
    order = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", "(default)"]
    density, path = min(files, key=lambda f: next((i for i, d in enumerate(order) if d in f[0]), len(order)))
    if path.endswith(".xml"):
        xml = AXMLPrinter(archive.read(path)).get_xml().decode()
        if "<vector" not in xml:
            print(f"{path} is not a vector; `show` it and extract what it references", file=sys.stderr)
            return 1
        render_vector(xml, args.width or 48, args.out)
    else:
        args.out.write_bytes(archive.read(path))
        print(f"{args.out}: {path} ({density}) as it is")
    return 0


if __name__ == "__main__":
    sys.exit(main())
