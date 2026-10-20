#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools==4.60.1"]
# ///
"""Stand-ins for the iPhone's system font (SF, with PingFang SC for Chinese) in widget tests and look-alike checks.

    uv run tools/make_standin_fonts.py

PingFang and SF are Apple's, licensed only for Apple devices, so the PC can't have them, and tests of the system path
drew Flutter's square test font. These are open fonts bent towards them: Noto Sans SC for PingFang SC and Inter for
SF (both OFL, from Google Fonts at a pinned commit). Each takes the line metrics of the font it stands in for, and its
glyphs are scaled (and Inter's spacing tracked) to the ink KaiC's phone shots show, measured with
tools/screen_diff.py; the numbers below say which shot settled them. Widths of Chinese text match exactly (every Han
glyph is one em in both); Latin letters are a different design and only come close.

The output goes to test/fonts/, renamed as the OFL asks of modified fonts, with both licences;
test/support/stand_in_fonts.dart loads it under the names the system path asks for. Han characters are cut to GB2312
and every one the code and tests use: a character outside both draws as the test font's box, and running this again
picks up the new ones (tools/test_make_standin_fonts.py fails until it is run).
"""
from __future__ import annotations

import copy
import hashlib
import pathlib
import re
import urllib.request

from fontTools import subset
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "standin-fonts"
OUT = ROOT / "test" / "fonts"

COMMIT = "47d54ca1ebb14fd864695f1d39dc734f39017c33"
SOURCES = {
    "NotoSansSC.ttf": ("ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf",
                       "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"),
    "NotoSansSC-OFL.txt": ("ofl/notosanssc/OFL.txt", "1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9"),
    "Inter.ttf": ("ofl/inter/Inter%5Bopsz,wght%5D.ttf",
                  "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"),
    "Inter-OFL.txt": ("ofl/inter/OFL.txt", "5b9321a4298cfeb6b34354164a1c3afc3db114569984c502b9b35d988fd58c57"),
}

# PingFang SC's line: ascent and descent per em (CoreText's 1.4 em line, 1.06 above the baseline).
SC_ASCENT, SC_DESCENT = 1.06, 0.34
# Noto's Han ink scaled about the ideographic em box's centre, then raised, both per em, to PingFang's. Settings (09):
# the same height and width at 14-20 pt, a pixel lower on the same baseline.
SC_SCALE, SC_RISE = 1.0, -0.022
# The weight class each file answers to, and where on Noto's wght axis PingFang's stroke is matched.
SC_WEIGHTS = {"Regular": (400, 400), "Medium": (500, 500), "Semibold": (600, 600)}

# SF's line per em on iOS: UIFont.systemFont(ofSize: 17) is 16.19 above the baseline and 4.10 below (its lineHeight
# 20.29). macOS's .SFNS (1980/432, as capsize has it) puts mixed Latin and Chinese lines a point lower than the phone.
LATIN_ASCENT, LATIN_DESCENT = 1950 / 2048, 494 / 2048
# Inter scaled to SF's ink, its advances changed by a share of an em, and the optical size taken. SF's capitals and
# digits are 3% shorter (its cap height, 0.705 em, against Inter's 0.728; settings 09 on the phone). Widths are SF's
# untracked, as Flutter draws it: "Wi-Fi" in the official 09 (UIKit, tracked -0.15 pt at 14 pt) and "1.0.0 (14)" in
# ours, less the extra pixel a glyph (14)'s tracked text took on the phone, put SF 0.01 em wider than Inter scaled.
# Brackets hang 0.07 em lower ("(14)").
LATIN_SCALE, LATIN_TRACKING, LATIN_OPSZ = 0.968, 0.01, 14
LATIN_LOWERED, LATIN_DROP = "()[]{}", 0.07
LATIN_WEIGHTS = {"Regular": (400, 400), "Medium": (500, 500), "Semibold": (600, 600), "Bold": (700, 700)}

HAN = re.compile(r"[㐀-䶿一-鿿豈-﫿\U00020000-\U0003ffff]")
HANGUL = range(0xAC00, 0xD7B0)
SCANNED = ("lib", "test", "packages", "integration_test")


def fetch(name: str) -> pathlib.Path:
    path = CACHE / name
    url, digest = SOURCES[name]
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        CACHE.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(f"https://raw.githubusercontent.com/google/fonts/{COMMIT}/{url}").read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise SystemExit(f"{name}: the download's hash isn't the pinned one")
        path.write_bytes(data)
    return path


def gb2312() -> set[str]:
    chars = set()
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return chars


def repo_han() -> set[str]:
    chars = set()
    for folder in SCANNED:
        for path in (ROOT / folder).rglob("*"):
            if path.suffix in {".dart", ".json"} and path.is_file():
                chars.update(HAN.findall(path.read_text(encoding="utf-8", errors="ignore")))
    return chars


def cut(font: TTFont, keep: set[int]) -> None:
    options = subset.Options()
    options.hinting = False
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.layout_features = ["*"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=keep)
    subsetter.subset(font)


def set_line(font: TTFont, ascent: float, descent: float) -> None:
    em = font["head"].unitsPerEm
    up, down = round(ascent * em), round(descent * em)
    hhea, os2 = font["hhea"], font["OS/2"]
    hhea.ascent, hhea.descent, hhea.lineGap = up, -down, 0
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = up, -down, 0
    os2.usWinAscent, os2.usWinDescent = up, down
    os2.fsSelection |= 1 << 7  # USE_TYPO_METRICS, so every rasteriser reads the same line


def transform(font: TTFont, scale: float, centre: tuple[float, float], rise: float, chars: str | None = None) -> None:
    """Scales the outlines of chars (every glyph when None) about centre and raises them; advances stay, side bearings
    follow the ink."""
    if scale == 1 and rise == 0:
        return
    glyf, hmtx, glyphs = font["glyf"], font["hmtx"], font.getGlyphSet()
    cx, cy = centre
    matrix = (scale, 0, 0, scale, cx - cx * scale, cy - cy * scale + rise)
    cmap = font.getBestCmap()
    names = font.getGlyphOrder() if chars is None else [cmap[ord(c)] for c in chars if ord(c) in cmap]
    for name in names:
        recorded = DecomposingRecordingPen(glyphs)
        glyphs[name].draw(recorded)
        pen = TTGlyphPen(None)
        recorded.replay(TransformPen(pen, matrix))
        glyph = pen.glyph()
        glyph.recalcBounds(glyf)
        glyf[name] = glyph
        advance, _ = hmtx[name]
        hmtx[name] = (advance, getattr(glyph, "xMin", 0))


def track(font: TTFont, share: float) -> None:
    amount = round(share * font["head"].unitsPerEm)
    if amount == 0:
        return
    hmtx = font["hmtx"]
    for name in font.getGlyphOrder():
        advance, lsb = hmtx[name]
        if advance:
            hmtx[name] = (advance + amount, lsb)


def rename(font: TTFont, family: str, style: str, weight: int) -> None:
    names = font["name"]
    names.names = [n for n in names.names if n.nameID not in {1, 2, 3, 4, 6, 16, 17, 25}]
    postscript = f"{family.replace(' ', '')}-{style}"
    for name_id, value in {1: family, 2: "Regular", 3: f"BiliFast;{postscript}", 4: f"{family} {style}",
                           6: postscript, 16: family, 17: style}.items():
        names.setName(value, name_id, 3, 1, 0x409)
    font["OS/2"].usWeightClass = weight
    # The source's dates, so the same numbers make the same bytes and git sees no change.
    font.recalcTimestamp = False
    for table in ("STAT", "MVAR", "HVAR"):
        if table in font:
            del font[table]


def build_sc(source: pathlib.Path) -> list[str]:
    han = gb2312() | repo_han()
    base = TTFont(source)
    keep = {cp for cp in base.getBestCmap()
            if cp not in HANGUL and (not HAN.match(chr(cp)) or chr(cp) in han)}
    cut(base, keep)
    written = []
    for style, (weight, axis) in SC_WEIGHTS.items():
        font = instantiateVariableFont(copy.deepcopy(base), {"wght": axis})
        transform(font, SC_SCALE, (500, 380), SC_RISE * 1000)
        set_line(font, SC_ASCENT, SC_DESCENT)
        rename(font, "BiliFast StandIn SC", style, weight)
        name = f"StandInSC-{style}.ttf"
        font.save(OUT / name)
        written.append(name)
    return written


def build_latin(source: pathlib.Path) -> list[str]:
    written = []
    for style, (weight, axis) in LATIN_WEIGHTS.items():
        font = instantiateVariableFont(TTFont(source), {"wght": axis, "opsz": LATIN_OPSZ})
        cut(font, set(font.getBestCmap()))
        transform(font, 1, (0, 0), -LATIN_DROP * font["head"].unitsPerEm, LATIN_LOWERED)
        # A larger em scales outlines, advances and kerning alike.
        font["head"].unitsPerEm = round(font["head"].unitsPerEm / LATIN_SCALE)
        track(font, LATIN_TRACKING)
        set_line(font, LATIN_ASCENT, LATIN_DESCENT)
        rename(font, "BiliFast StandIn Text", style, weight)
        name = f"StandInText-{style}.ttf"
        font.save(OUT / name)
        written.append(name)
    return written


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    written = build_sc(fetch("NotoSansSC.ttf")) + build_latin(fetch("Inter.ttf"))
    (OUT / "NotoSansSC-OFL.txt").write_bytes(fetch("NotoSansSC-OFL.txt").read_bytes())
    (OUT / "Inter-OFL.txt").write_bytes(fetch("Inter-OFL.txt").read_bytes())
    for name in written:
        print(f"{name}: {(OUT / name).stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
