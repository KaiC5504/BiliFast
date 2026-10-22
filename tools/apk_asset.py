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
  uv run tools/apk_asset.py dump [--out local/apk-assets]
      everything, by real name, for browsing: README.md there says what is where; index.csv lists it all
"""

import argparse
import csv
import re
import xml.etree.ElementTree as ElementTree
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


ANDROID = "{http://schemas.android.com/apk/res/android}"
DENSITIES = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", "nodpi", "anydpi", "(default)"]
# The APK's own assets/ folder already has real names; these kinds are art, the rest is code and models.
ART = {"png", "webp", "jpg", "gif", "json", "svga", "svg", "ttf", "otf", "mp3", "m4a", "mp4", "zip"}


def densest(files):
    def rank(item):
        qualifier = item[0]
        if "night" in qualifier:
            return len(DENSITIES) + 1
        return next((i for i, d in enumerate(DENSITIES) if d in qualifier), len(DENSITIES))

    return min(files, key=rank)


def colour(table, value):
    """An Android colour attribute as an SVG colour and opacity; references resolved through the table."""
    if not value:
        return None
    if value.startswith("@"):
        try:
            entries = table.get_res_configs(int(value[1:], 16))
            argb = int(re.search(r"data='0x([0-9a-f]+)'", str(entries[0][1])).group(1), 16)
        except Exception:
            return ("#808080", 1.0)
    else:
        hexes = value.lstrip("#")
        if len(hexes) in (3, 4):
            hexes = "".join(c * 2 for c in hexes)
        argb = int(hexes, 16) | (0xFF000000 if len(hexes) == 6 else 0)
    return (f"#{argb & 0xFFFFFF:06x}", ((argb >> 24) & 0xFF) / 255)


def vector_svg(table, xml: str, scale: float):
    root = ElementTree.fromstring(xml)
    view_w = float(root.get(ANDROID + "viewportWidth"))
    view_h = float(root.get(ANDROID + "viewportHeight"))
    width = max(1, round(float(re.sub(r"[a-z]+", "", root.get(ANDROID + "width", str(view_w)))) * scale))
    height = max(1, round(float(re.sub(r"[a-z]+", "", root.get(ANDROID + "height", str(view_h)))) * scale))

    def attr(node, name, default=None):
        return node.get(ANDROID + name, default)

    def walk(node) -> str:
        out = []
        for child in node:
            tag = child.tag.split("}")[-1]
            if tag == "group":
                px, py = float(attr(child, "pivotX", 0)), float(attr(child, "pivotY", 0))
                tx = float(attr(child, "translateX", 0)) + px
                ty = float(attr(child, "translateY", 0)) + py
                transform = (
                    f"translate({tx} {ty}) rotate({float(attr(child, 'rotation', 0))}) "
                    f"scale({float(attr(child, 'scaleX', 1))} {float(attr(child, 'scaleY', 1))}) translate({-px} {-py})"
                )
                out.append(f'<g transform="{transform}">{walk(child)}</g>')
            elif tag == "path" and attr(child, "pathData"):
                fill = colour(table, attr(child, "fillColor"))
                stroke = colour(table, attr(child, "strokeColor"))
                parts = [f'd="{attr(child, "pathData")}"']
                if fill:
                    parts.append(f'fill="{fill[0]}" fill-opacity="{fill[1] * float(attr(child, "fillAlpha", 1))}"')
                else:
                    parts.append('fill="none"')
                if stroke and float(attr(child, "strokeWidth", 0)) > 0:
                    parts.append(
                        f'stroke="{stroke[0]}" stroke-opacity="{stroke[1] * float(attr(child, "strokeAlpha", 1))}" '
                        f'stroke-width="{attr(child, "strokeWidth")}"'
                    )
                if attr(child, "fillType") in ("1", "evenOdd"):
                    parts.append('fill-rule="evenodd"')
                out.append(f"<path {' '.join(parts)}/>")
        return "".join(out)

    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {view_w} {view_h}">{walk(root)}</svg>'
    )
    return svg, width, height


def draw_svg(svg: str, width: int, height: int, out: Path) -> None:
    import skia

    dom = skia.SVGDOM.MakeFromStream(skia.MemoryStream(svg.encode()))
    surface = skia.Surface(width, height)
    canvas = surface.getCanvas()
    canvas.clear(skia.ColorTRANSPARENT)
    dom.setContainerSize(skia.Size(width, height))
    dom.render(canvas)
    surface.makeImageSnapshot().save(str(out), skia.kPNG)


DUMP_README = """# The official app's art (Android 8.43.0), by real name

Made by `uv run tools/apk_asset.py dump`. Never commit anything from here: extract what a screen needs with
`apk_asset.py extract` and note it in `assets/README.md` (CLAUDE.md's Art rule).

- `drawable/`, `mipmap/`: each resource's densest file under its real name. Vectors are drawn in their own colours
  at 3x as `<name>.png` beside their `<name>.xml`; shapes, layer-lists and selectors are `<name>.xml` only (they
  name other resources as @7F...). `.9.png` files are nine-patches.
- `raw/`, `anim/`: Lottie (`.json`), sounds and animations.
- `assets/`: the APK's own folder (already real names), art kinds only.
- `index.csv`: name, type, kind (vector, png, webp, shape, layer-list, selector...), density, file, pixels.
  Search it or the file names, e.g. `grep -i default_image index.csv`.
"""


def dump(archive, table, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for package_types in table.resource_keys.values():
        for kind in ("drawable", "mipmap", "raw", "anim", "animator"):
            for name, resource_id in sorted(package_types.get(kind, {}).items()):
                try:
                    files = files_of(table, resource_id)
                except Exception:
                    continue
                if not files:
                    continue
                qualifier, path = densest(files)
                base = path.rsplit("/", 1)[-1]
                suffix = base[base.index(".") :] if "." in base else ""
                folder = out / kind
                folder.mkdir(exist_ok=True)
                data = archive.read(path)
                if suffix != ".xml":
                    target = folder / f"{name}{suffix}"
                    target.write_bytes(data)
                    rows.append((name, kind, suffix.lstrip("."), qualifier, f"{kind}/{target.name}", ""))
                    continue
                try:
                    text = AXMLPrinter(data).get_xml().decode()
                except Exception:
                    continue
                (folder / f"{name}.xml").write_text(text, encoding="utf-8")
                found = re.search(r"<([a-zA-Z-]+)", text)
                tag = found.group(1) if found else "xml"
                if tag == "vector":
                    try:
                        svg, width, height = vector_svg(table, text, 3)
                        draw_svg(svg, width, height, folder / f"{name}.png")
                        rows.append((name, kind, "vector", qualifier, f"{kind}/{name}.png", f"{width}x{height}"))
                        continue
                    except Exception as error:
                        print(f"vector {name} not drawn: {type(error).__name__}", file=sys.stderr)
                rows.append((name, kind, tag, qualifier, f"{kind}/{name}.xml", ""))
    for info in archive.infolist():
        name = info.filename
        if not name.startswith("assets/") or name.endswith("/"):
            continue
        base = name.rsplit("/", 1)[-1]
        ext = base.rsplit(".", 1)[-1].lower() if "." in base else ""
        if ext not in ART:
            continue
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(name))
        rows.append((base, "assets", ext, "", name, ""))
    with open(out / "index.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["name", "type", "kind", "density", "file", "pixels"])
        writer.writerows(rows)
    (out / "README.md").write_text(DUMP_README, encoding="utf-8")
    print(f"{len(rows)} resources into {out}")


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
    dumping = sub.add_parser("dump")
    dumping.add_argument("--out", type=Path, default=DEFAULT_APK.parent / "apk-assets")
    args = parser.parse_args()

    archive, table = load(args.apk)
    if args.command == "dump":
        dump(archive, table, args.out)
        return 0
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
