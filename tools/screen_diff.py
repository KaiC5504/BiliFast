#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy==2.5.4", "pillow==13.0.0"]
# ///
"""Where our screen differs from the official app's, from two 3x phone screenshots of the same screen.

    uv run tools/screen_diff.py local/differences/11-ours-comment-threads.jpg local/differences/12-official-comment-threads.jpg
    uv run tools/screen_diff.py OURS OFFICIAL --anchor 87.3:88.3 --x 50:440 --overlay <scratchpad dir>

Widget tests render MiSans while the phone draws PingFang, so values settled on Windows can be off on the phone; this
measures the phone. Everything is reported in pt (px / --scale, 3 for the iPhone).

Ink is any pixel further from its row's median than --ink, darker or lighter (white text on the player), so grey text
in a grey box counts and the box itself doesn't. Ink joined across gaps narrower than --join pt makes an element: a line of text, or an image when it is tall
or solid; pieces of one line less than a character apart (a full-width comma's blank) are joined too. A line's centre
and glyph size come from its Chinese-sized glyphs only, so Latin letters, descenders and punctuation don't move them.
Flat fills of a shade other than white (a reply box, a pill, a card on a grey page) and hairlines are found
separately.

Two whole screens (the same size) are lined up as they are, by the status bar. Crops are lined up by the vertical
offset where their ink profiles agree best, then by their first few paired text lines, so a fault lower down doesn't
pull the top out of line. --anchor (a y in each, in pt) sets it instead.
Elements are paired in reading order, row by row. For each pair the report gives ours and the official centre, the
difference, the change in the step from the pair before (where a spacing fault shows, without the drift of every
fault above it), the left and right edges, the glyph height (the font size) and the ink (weight and size together;
thin, blurred glyphs read low). Steps, left edges and widths are marked from --pt, glyph sizes from twice --ratio and
ink from five times it.
"""
from __future__ import annotations

import argparse
import dataclasses
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw


@dataclasses.dataclass
class Element:
    kind: str  # "text" or "image"
    top: int
    bottom: int
    left: int
    right: int
    centre: float
    glyph: float  # median height of the line's Chinese-sized glyphs, px
    glyphs: int
    ink: float

    @property
    def height(self) -> int:
        return self.bottom - self.top


@dataclasses.dataclass
class Fill:
    kind: str  # "box" or "rule"
    top: int
    bottom: int
    left: int
    right: int
    shade: int


def load(path: pathlib.Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("L"), dtype=np.float32)


def ink_mask(grey: np.ndarray, threshold: float) -> tuple[np.ndarray, np.ndarray]:
    """Pixels further from their row's median than threshold, darker or (white text on the player) lighter, and how
    far (0-1)."""
    background = np.median(grey, axis=1, keepdims=True)
    depth = np.abs(background - grey)
    return depth > threshold, depth / 255.0


def _runs(row: np.ndarray) -> list[tuple[int, int]]:
    edges = np.diff(np.concatenate(([0], row.view(np.int8), [0])))
    return list(zip(np.flatnonzero(edges == 1).tolist(), np.flatnonzero(edges == -1).tolist()))


def components(mask: np.ndarray, join: int) -> list[tuple[int, int, int, int]]:
    """Bounding boxes (top, bottom, left, right) of the mask's pieces, with gaps up to `join` px in a row bridged."""
    parent: list[int] = []

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    boxes: list[list[int]] = []
    previous: list[tuple[int, int, int]] = []
    for y in range(mask.shape[0]):
        current: list[tuple[int, int, int]] = []
        for start, end in _runs(mask[y]):
            if current and start - current[-1][1] <= join:
                index = current[-1][2]
                current[-1] = (current[-1][0], end, index)
                boxes[index][3] = max(boxes[index][3], end)
                continue
            index = len(parent)
            parent.append(index)
            boxes.append([y, y + 1, start, end])
            current.append((start, end, index))
        for start, end, index in current:
            boxes[index][1] = y + 1
            for p_start, p_end, p_index in previous:
                if p_start < end and start < p_end:
                    a, b = find(index), find(p_index)
                    if a != b:
                        parent[b] = a
        previous = current
    merged: dict[int, list[int]] = {}
    for index, box in enumerate(boxes):
        root = find(index)
        if root in merged:
            m = merged[root]
            m[0], m[1] = min(m[0], box[0]), max(m[1], box[1])
            m[2], m[3] = min(m[2], box[2]), max(m[3], box[3])
        else:
            merged[root] = list(box)
    return sorted((tuple(box) for box in merged.values()), key=lambda b: (b[0], b[2]))  # type: ignore[misc]


def _glyphs(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Each glyph-ish column run of a line's mask: (left, right, top, bottom)."""
    out = []
    for left, right in _runs(mask.any(axis=0)):
        rows = np.flatnonzero(mask[:, left:right].any(axis=1))
        out.append((left, right, int(rows[0]), int(rows[-1]) + 1))
    return out


def _measure(mask: np.ndarray, depth: np.ndarray, top: int, bottom: int, left: int, right: int, *,
             scale: float) -> Element:
    piece = mask[top:bottom, left:right]
    glyphs = _glyphs(piece)
    tallest = max(b - t for _, _, t, b in glyphs)
    wide = [(l, r, t, b) for l, r, t, b in glyphs if b - t >= 0.85 * tallest and r - l >= 0.8 * (b - t)]
    return Element(
        kind="image" if piece.mean() > 0.55 or bottom - top > 40 * scale else "text",
        top=top, bottom=bottom, left=left, right=right,
        centre=float(np.median([top + (t + b) / 2 for _, _, t, b in wide])) if wide else (top + bottom) / 2,
        glyph=float(np.median([b - t for _, _, t, b in wide])) if wide else float(bottom - top),
        glyphs=len(wide),
        ink=float(depth[top:bottom, left:right][piece].sum()),
    )


def elements(grey: np.ndarray, *, scale: float, ink: float, join_pt: float, xs: tuple[int, int]) -> list[Element]:
    mask, depth = ink_mask(grey, ink)
    mask[:, : xs[0]] = False
    mask[:, xs[1] :] = False
    found = [
        _measure(mask, depth, top, bottom, left, right, scale=scale)
        for top, bottom, left, right in components(mask, round(join_pt * scale))
        if bottom - top >= 2 * scale and right - left >= 2 * scale
    ]
    # A full-width comma leaves most of a character's width blank, more in a tracked line; pieces of one line of text
    # less than a character apart are one line.
    merged: list[Element] = []
    for element in reading_order(found):
        last = merged[-1] if merged else None
        size = max(last.glyph, element.glyph) if last is not None else 0
        if (last is not None and last.kind == element.kind == "text" and last.glyphs and element.glyphs
                and 0 <= element.left - last.right <= 1.1 * size and abs(element.centre - last.centre) <= 0.3 * size):
            merged[-1] = _measure(mask, depth, min(last.top, element.top), max(last.bottom, element.bottom),
                                  last.left, element.right, scale=scale)
        else:
            merged.append(element)
    return merged


def reading_order(found: list[Element]) -> list[Element]:
    """Rows of elements whose centres fall within the first one's height, top to bottom, each left to right, so two
    shots order a row's elements alike even when one sits a pixel higher."""
    rows: list[list[Element]] = []
    for element in sorted(found, key=lambda e: e.top):
        row = rows[-1] if rows else None
        if row is not None and row[0].top <= element.centre <= row[0].bottom:
            row.append(element)
        else:
            rows.append([element])
    return [element for row in rows for element in sorted(row, key=lambda e: e.left)]


def fills(grey: np.ndarray, *, scale: float) -> list[Fill]:
    """Areas of one flat non-white shade at least 30 pt wide: boxes, and hairlines when 3 px tall or less. Text inside
    a box is bridged over, as ink within an element is."""
    rounded = np.rint(grey).astype(np.int16)
    flat = np.zeros(grey.shape, dtype=bool)
    flat[:, 1:-1] = (np.abs(rounded[:, 1:-1] - rounded[:, :-2]) <= 2) & (np.abs(rounded[:, 1:-1] - rounded[:, 2:]) <= 2)
    candidates = flat & (rounded >= 200) & (rounded <= 251)
    counts = np.bincount(rounded[candidates].ravel(), minlength=256)
    shades = [
        shade
        for shade in range(200, 252)
        if counts[shade] >= 600 and counts[shade] == counts[max(200, shade - 2) : shade + 3].max()
    ]
    out = []
    for shade in shades:
        mask = candidates & (np.abs(rounded - shade) <= 2)
        for top, bottom, left, right in components(mask, round(15 * scale)):
            if right - left < 30 * scale:
                continue
            if bottom - top <= 3:
                out.append(Fill("rule", top, bottom, left, right, shade))
            elif bottom - top >= 4 * scale:
                out.append(Fill("box", top, bottom, left, right, shade))
    return sorted(out, key=lambda f: (f.top, f.left))


def offset(ours: list[Element], official: list[Element], height: int, scale: float) -> float:
    """The official minus ours y, in px, that best lines up the two shots' text rows."""
    def profile(found: list[Element]) -> np.ndarray:
        out = np.zeros(height, dtype=np.float32)
        for e in found:
            if e.kind == "text":
                out[e.top : e.bottom] += 1
        return out

    a, b = profile(ours), profile(official)
    best, best_score = 0, -1.0
    reach = round(height / 3)
    for shift in range(-reach, reach + 1):
        if shift >= 0:
            x, y = a[: height - shift], b[shift:]
        else:
            x, y = a[-shift:], b[: height + shift]
        score = float((x * y).sum()) / max(1.0, float(np.sqrt((x * x).sum() * (y * y).sum())))
        if score > best_score + 1e-6 or (abs(score - best_score) <= 1e-6 and abs(shift) < abs(best)):
            best, best_score = shift, score
    return float(best)


def pair(ours: list[Element], official: list[Element], shift: float, scale: float) -> list[tuple[Element | None, Element | None]]:
    """Matches in reading order (a sequence alignment), favouring the same left edge, width and glyph size."""
    def cost(a: Element, b: Element) -> float:
        if a.kind != b.kind:
            return 1e9
        dy = abs(b.centre - shift - a.centre) / scale
        if dy > 40:
            return 1e9
        return (abs(b.left - a.left) / scale + 0.3 * abs((b.right - b.left) - (a.right - a.left)) / scale
                + 2 * abs(b.glyph - a.glyph) / scale + 0.15 * dy)

    skip = 25.0
    n, m = len(ours), len(official)
    table = np.zeros((n + 1, m + 1))
    table[:, 0] = np.arange(n + 1) * skip
    table[0, :] = np.arange(m + 1) * skip
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            table[i, j] = min(table[i - 1, j - 1] + cost(ours[i - 1], official[j - 1]),
                              table[i - 1, j] + skip, table[i, j - 1] + skip)
    out: list[tuple[Element | None, Element | None]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and table[i, j] == table[i - 1, j - 1] + cost(ours[i - 1], official[j - 1]):
            out.append((ours[i - 1], official[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and table[i, j] == table[i - 1, j] + skip:
            out.append((ours[i - 1], None))
            i -= 1
        else:
            out.append((None, official[j - 1]))
            j -= 1
    return out[::-1]


@dataclasses.dataclass
class Row:
    ours: Element | None
    official: Element | None
    dy: float | None = None
    step: float | None = None
    dleft: float | None = None
    dright: float | None = None
    glyph: float | None = None
    ink: float | None = None
    marks: list[str] = dataclasses.field(default_factory=list)


def compare(pairs, shift: float, scale: float, pt: float, ratio: float) -> list[Row]:
    rows = []
    before: tuple[Element, Element] | None = None
    for a, b in pairs:
        row = Row(a, b)
        if a is not None and b is not None:
            row.dy = (b.centre - shift - a.centre) / scale
            row.dleft = (b.left - a.left) / scale
            row.dright = (b.right - a.right) / scale
            if before is not None:
                row.step = ((b.centre - before[1].centre) - (a.centre - before[0].centre)) / scale
            if a.kind == "text":
                row.glyph = a.glyph / b.glyph if b.glyph else None
                row.ink = a.ink / b.ink if b.ink else None
                # Two edges each read to a pixel, so a width is marked from 2 px.
                wider = ((a.right - a.left) - (b.right - b.left)) / scale
                if abs(wider) >= max(pt, 2 / scale):
                    row.marks.append(f"width {wider:+.2f} ({wider * scale / max(1, b.right - b.left):+.0%})")
                if row.glyph is not None and abs(row.glyph - 1) >= 2 * ratio:
                    row.marks.append(f"size {row.glyph - 1:+.0%}")
                if row.ink is not None and abs(row.ink - 1) >= 5 * ratio:
                    row.marks.append(f"ink {row.ink - 1:+.0%}")
            if row.step is not None and abs(row.step) >= pt:
                row.marks.append(f"step {row.step:+.2f}")
            if abs(row.dleft) >= pt:
                row.marks.append(f"left {row.dleft:+.2f}")
            before = (a, b)
        rows.append(row)
    return rows


def compare_fills(ours: list[Fill], official: list[Fill], shift: float, scale: float, pt: float) -> list[str]:
    lines = []
    used: set[int] = set()
    for a in ours:
        best = None
        for index, b in enumerate(official):
            if index in used or b.kind != a.kind or abs(b.shade - a.shade) > 4:
                continue
            distance = abs(b.top - shift - a.top) + abs(b.left - a.left)
            if distance <= 60 * scale and (best is None or distance < best[0]):
                best = (distance, index)
        if best is None:
            lines.append(f"  {a.kind} {_span(a, scale)} only in ours")
            continue
        used.add(best[1])
        b = official[best[1]]
        deltas = {"top": (b.top - shift - a.top) / scale, "bottom": (b.bottom - shift - a.bottom) / scale,
                  "left": (b.left - a.left) / scale, "right": (b.right - a.right) / scale}
        marks = [f"{k} {v:+.2f}" for k, v in deltas.items() if abs(v) >= pt]
        lines.append(f"  {a.kind} {_span(a, scale)} vs {_span(b, scale)}  " + ("  ".join(marks) if marks else "same"))
    for index, b in enumerate(official):
        if index not in used:
            lines.append(f"  {b.kind} {_span(b, scale)} only in the official")
    return lines


def _span(f: Fill, scale: float) -> str:
    return f"{f.top / scale:.2f}-{f.bottom / scale:.2f} x {f.left / scale:.1f}-{f.right / scale:.1f} shade {f.shade}"


def _num(value: float | None, digits: int = 2, sign: bool = True) -> str:
    if value is None:
        return ""
    return f"{value:+.{digits}f}" if sign else f"{value:.{digits}f}"


def report(rows: list[Row], fill_lines: list[str], shift: float, scale: float) -> str:
    out = [f"official = ours {shift / scale:+.2f} pt (pt = px / {scale:g})", "",
           f"{'#':>3} {'kind':5} {'ours':>7} {'official':>8} {'dy':>6} {'step':>6} {'left':>6} {'right':>6} "
           f"{'glyph':>6} {'ink':>5}  marks"]
    for number, row in enumerate(rows, 1):
        a, b = row.ours, row.official
        kind = (a or b).kind  # type: ignore[union-attr]
        out.append(
            f"{number:>3} {kind:5} {_num(a.centre / scale if a else None, sign=False):>7} "
            f"{_num(b.centre / scale if b else None, sign=False):>8} {_num(row.dy):>6} {_num(row.step):>6} "
            f"{_num(row.dleft):>6} {_num(row.dright):>6} "
            f"{'' if row.glyph is None else f'{row.glyph:.3f}':>6} {'' if row.ink is None else f'{row.ink:.2f}':>5}  "
            + ("only in ours" if b is None else "only in the official" if a is None else "  ".join(row.marks))
        )
    out += ["", "fills"] + (fill_lines or ["  none"])
    flagged = sum(1 for row in rows if row.marks or row.ours is None or row.official is None)
    out += ["", f"{flagged} of {len(rows)} elements flagged"]
    return "\n".join(out)


def overlay(ours_path: pathlib.Path, official_path: pathlib.Path, rows: list[Row], shift: float,
            folder: pathlib.Path) -> pathlib.Path:
    with Image.open(ours_path) as a, Image.open(official_path) as b:
        left, right = a.convert("RGB"), b.convert("RGB")
    canvas = Image.new("RGB", (left.width + right.width, max(left.height, right.height)), "white")
    canvas.paste(left, (0, 0))
    canvas.paste(right, (left.width, 0))
    draw = ImageDraw.Draw(canvas)
    for number, row in enumerate(rows, 1):
        colour = (230, 40, 40) if row.marks or row.ours is None or row.official is None else (40, 160, 70)
        for element, dx in ((row.ours, 0), (row.official, left.width)):
            if element is None:
                continue
            draw.rectangle((element.left + dx, element.top, element.right + dx, element.bottom), outline=colour, width=2)
            draw.text((element.left + dx - 28, element.top), str(number), fill=colour)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{ours_path.stem}__{official_path.stem}.png"
    canvas.save(path)
    return path


def run(ours_path: pathlib.Path, official_path: pathlib.Path, *, scale: float = 3, ink: float = 30, join: float = 12,
        pt: float = 0.5, ratio: float = 0.02, anchor: tuple[float, float] | None = None,
        xs: tuple[float, float] | None = None) -> tuple[str, list[Row], float]:
    ours_grey, official_grey = load(ours_path), load(official_path)
    columns = (0, ours_grey.shape[1]) if xs is None else (round(xs[0] * scale), round(xs[1] * scale))
    ours = elements(ours_grey, scale=scale, ink=ink, join_pt=join, xs=columns)
    official = elements(official_grey, scale=scale, ink=ink, join_pt=join, xs=columns)
    whole = ours_grey.shape == official_grey.shape
    if anchor is not None:
        shift = (anchor[1] - anchor[0]) * scale
    elif whole:
        shift = 0.0
    else:
        shift = offset(ours, official, max(ours_grey.shape[0], official_grey.shape[0]), scale)
    pairs = pair(ours, official, shift, scale)
    if anchor is None and not whole:
        top = [b.centre - a.centre for a, b in pairs if a is not None and b is not None and a.kind == "text"][:5]
        if top:
            shift = float(np.median(top))
    rows = compare(pairs, shift, scale, pt, ratio)
    fill_lines = compare_fills(fills(ours_grey, scale=scale), fills(official_grey, scale=scale), shift, scale, pt)
    return report(rows, fill_lines, shift, scale), rows, shift


def _pair_of(text: str) -> tuple[float, float]:
    first, second = text.split(":")
    return float(first), float(second)


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ours", type=pathlib.Path)
    parser.add_argument("official", type=pathlib.Path)
    parser.add_argument("--scale", type=float, default=3, help="px per pt (3 on the iPhone 17 Pro Max)")
    parser.add_argument("--ink", type=float, default=30, help="how far from its row's median ink is (0-255)")
    parser.add_argument("--join", type=float, default=12, help="gaps narrower than this (pt) stay in one element")
    parser.add_argument("--pt", type=float, default=0.5, help="mark positions off by this much (pt)")
    parser.add_argument("--ratio", type=float, default=0.02, help="mark glyph sizes off by twice this share, ink 5x")
    parser.add_argument("--anchor", type=_pair_of, help="OURS_Y:OFFICIAL_Y in pt, the same point in both shots")
    parser.add_argument("--x", type=_pair_of, dest="xs", help="LEFT:RIGHT in pt, the columns to measure")
    parser.add_argument("--overlay", type=pathlib.Path, help="write the pair side by side, elements boxed, here")
    args = parser.parse_args(argv)
    for path in (args.ours, args.official):
        if not path.is_file():
            parser.error(f"no such file: {path}")
    text, rows, shift = run(args.ours, args.official, scale=args.scale, ink=args.ink, join=args.join, pt=args.pt,
                            ratio=args.ratio, anchor=args.anchor, xs=args.xs)
    print(text)
    if args.overlay is not None:
        print(f"\noverlay: {overlay(args.ours, args.official, rows, shift, args.overlay)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
