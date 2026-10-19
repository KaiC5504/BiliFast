"""Draws the BiliFast app-icon options as SVG (default and iOS dark appearance) and renders 1024 px PNGs.

Run: uv run --no-project --with pillow==11.1.0 python design/icon-options/make_icons.py
"""
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

PALETTES = {
    "light": dict(
        bg=("#FF8DB4", "#FF6699", "#EE4C82"),
        glow=("#FFFFFF", 0.30),
        ink=("#FFFFFF", "#FFF1F6"),
        shadow=("#B3164C", 0.32),
        sub=0.62,
    ),
    "dark": dict(
        bg=("#2A1F2A", "#1A141C", "#0E0B10"),
        glow=("#FF6699", 0.26),
        ink=("#FF94BA", "#FF5C93"),
        shadow=("#000000", 0.55),
        sub=0.55,
    ),
}
BLUE = ("#5AD6FF", "#1FA8F0")
BLUSH = "#FF86AF"


def frame(p, mark, extra_defs="", bg_override=None):
    top, mid, bottom = p["bg"]
    glow_color, glow_alpha = p["glow"]
    ink_top, ink_bottom = p["ink"]
    shadow_color, shadow_alpha = p["shadow"]
    background = bg_override or (
        '<rect width="1024" height="1024" fill="url(#bg)"/>'
        '<rect width="1024" height="1024" fill="url(#glow)"/>'
    )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
    <stop offset="0" stop-color="{top}"/><stop offset="0.5" stop-color="{mid}"/><stop offset="1" stop-color="{bottom}"/>
  </linearGradient>
  <radialGradient id="glow" cx="300" cy="170" r="760" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{glow_color}" stop-opacity="{glow_alpha}"/><stop offset="1" stop-color="{glow_color}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="ink" x1="0" y1="180" x2="0" y2="860" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{ink_top}"/><stop offset="1" stop-color="{ink_bottom}"/>
  </linearGradient>
  <linearGradient id="blue" x1="0" y1="300" x2="0" y2="780" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{BLUE[0]}"/><stop offset="1" stop-color="{BLUE[1]}"/>
  </linearGradient>
  <filter id="lift" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="{shadow_color}" flood-opacity="{shadow_alpha}"/>
  </filter>
  {extra_defs}
</defs>
{background}
{mark}
</svg>
"""


def rounded_triangle(cx, cy, w, h, fill, r=14):
    pts = f"{cx - w / 2:.1f},{cy - h / 2:.1f} {cx + w / 2:.1f},{cy:.1f} {cx - w / 2:.1f},{cy + h / 2:.1f}"
    return (f'<polygon points="{pts}" fill="{fill}" stroke="{fill}" '
            f'stroke-width="{2 * r}" stroke-linejoin="round"/>')


def dash(p):
    """A: the TV leans into a sprint, antennae blown back, speed streaks behind it."""
    cx, cy, w, h, sw = 626, 560, 440, 344, 62
    top = cy - h / 2
    k = math.tan(math.radians(11))
    tv = f"""<g transform="translate({cx} {cy}) skewX(-11) translate({-cx} {-cy})">
  <rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="108" fill="none" stroke="url(#ink)" stroke-width="{sw}"/>
  <path d="M{cx - 58} {top} L{cx - 150} {top - 112}" stroke="url(#ink)" stroke-width="48" stroke-linecap="round"/>
  <path d="M{cx + 62} {top} L{cx + 6} {top - 128}" stroke="url(#ink)" stroke-width="48" stroke-linecap="round"/>
  <rect x="{cx - 68 - 27}" y="{cy - 58}" width="54" height="104" rx="27" fill="url(#ink)"/>
  <rect x="{cx + 68 - 27}" y="{cy - 58}" width="54" height="104" rx="27" fill="url(#ink)"/>
</g>"""
    streaks = []
    for dy, length, alpha in ((-96, 96, p["sub"] + 0.2), (8, 140, 1.0), (108, 70, p["sub"])):
        y = cy + dy
        edge = cx - w / 2 - sw / 2 - (y - cy) * k
        x2 = edge - 42 - 22
        streaks.append(f'<path d="M{x2 - length:.1f} {y} L{x2:.1f} {y}" stroke="url(#ink)" '
                       f'stroke-opacity="{alpha:.2f}" stroke-width="44" stroke-linecap="round"/>')
    return f'<g filter="url(#lift)">{"".join(streaks)}{tv}</g>'


def ff_face(p):
    """B: a solid TV whose eyes are a fast-forward mark, looking ahead."""
    cx, cy, w, h = 512, 566, 512, 424
    top = cy - h / 2
    inset = 54
    eye = "#FFFFFF"
    body = f"""<rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="122" fill="url(#ink)"/>
<rect x="{cx - w / 2 + inset}" y="{top + inset}" width="{w - 2 * inset}" height="{h - 2 * inset}" rx="74" fill="url(#blue)"/>"""
    antennae = "".join(
        f'<path d="M{cx + s * 88} {top + 8} L{cx + s * 150} {top - 104}" stroke="url(#ink)" stroke-width="40" stroke-linecap="round"/>'
        f'<circle cx="{cx + s * 150}" cy="{top - 104}" r="31" fill="url(#ink)"/>'
        for s in (-1, 1)
    )
    face = (rounded_triangle(cx - 58, cy - 12, 86, 104, eye)
            + rounded_triangle(cx + 64, cy - 12, 86, 104, eye)
            + f'<ellipse cx="{cx - 150}" cy="{cy + 72}" rx="34" ry="19" fill="{BLUSH}"/>'
            + f'<ellipse cx="{cx + 150}" cy="{cy + 72}" rx="34" ry="19" fill="{BLUSH}"/>'
            + f'<path d="M{cx - 30} {cy + 74} Q{cx} {cy + 100} {cx + 30} {cy + 74}" fill="none" stroke="{eye}" '
              f'stroke-width="18" stroke-linecap="round"/>')
    return f'<g filter="url(#lift)">{antennae}{body}</g>{face}'


def danmaku(p):
    """C: the face is live comments, and the fastest one flies out of the screen."""
    cx, cy, w, h, sw = 520, 572, 520, 400, 60
    top = cy - h / 2
    tv = f"""<rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="112" fill="none" stroke="url(#ink)" stroke-width="{sw}"/>
<path d="M{cx - 70} {top} L{cx - 134} {top - 104}" stroke="url(#ink)" stroke-width="48" stroke-linecap="round"/>
<path d="M{cx + 70} {top} L{cx + 134} {top - 104}" stroke="url(#ink)" stroke-width="48" stroke-linecap="round"/>"""
    left = cx - w / 2
    bars = (f'<path d="M{left - 92} {cy - 86} L{cx + 40} {cy - 86}" stroke="url(#ink)" stroke-width="56" stroke-linecap="round"/>'
            f'<path d="M{cx - 70} {cy + 6} L{cx + 160} {cy + 6}" stroke="url(#blue)" stroke-width="56" stroke-linecap="round"/>'
            f'<path d="M{cx - 160} {cy + 98} L{cx + 40} {cy + 98}" stroke="url(#ink)" stroke-opacity="{p["sub"]}" '
            f'stroke-width="56" stroke-linecap="round"/>')
    return f'<g filter="url(#lift)">{tv}{bars}</g>'


def bolt(p):
    """D: the old BiliFast bolt comes back as one of the antennae."""
    cx, cy, w, h, sw = 512, 586, 488, 392, 60
    top = cy - h / 2
    tv = f"""<rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="116" fill="none" stroke="url(#ink)" stroke-width="{sw}"/>
<path d="M{cx - 84} {top} L{cx - 158} {top - 112}" stroke="url(#ink)" stroke-width="48" stroke-linecap="round"/>"""
    # A bolt striking down, its tip resting on the TV's top edge.
    shape = "20,-220 70,-220 38,-140 80,-140 0,0 18,-100 -25,-100"
    bolt_svg = (f'<g transform="translate({cx + 92} {top + 6}) rotate(14) scale(1.12)">'
                f'<polygon points="{shape}" fill="url(#ink)" stroke="url(#ink)" stroke-width="18" stroke-linejoin="round"/></g>')
    face = (f'<circle cx="{cx - 82}" cy="{cy - 24}" r="36" fill="url(#ink)"/>'
            f'<circle cx="{cx + 82}" cy="{cy - 24}" r="36" fill="url(#ink)"/>'
            f'<path d="M{cx - 54} {cy + 40} H{cx + 54} A54 54 0 0 1 {cx - 54} {cy + 40} Z" fill="url(#ink)" '
            f'stroke="url(#ink)" stroke-width="10" stroke-linejoin="round"/>')
    return f'<g filter="url(#lift)">{tv}{bolt_svg}{face}</g>'


def glass(p, mode):
    """E: a liquid-glass TV floating over a pink-to-blue light, a play mark for a face."""
    cx, cy, w, h = 512, 574, 560, 428
    top = cy - h / 2
    if mode == "light":
        base = ("#FF8DB4", "#FF6699", "#EE4C82")
        rim = (0.95, 0.35)
        frost = (0.40, 0.16)
        shade = ("#9C1446", 0.30)
        tip_l, tip_r = "#FFFFFF", "#FFFFFF"
    else:
        base = ("#2A1F2A", "#1A141C", "#0E0B10")
        rim = (0.70, 0.14)
        frost = (0.16, 0.05)
        shade = ("#000000", 0.6)
        tip_l, tip_r = "#FF8DB5", "#6FD8FF"
    orb2 = "" if mode == "light" else f'<circle cx="{cx - 236}" cy="{cy - 150}" r="100" fill="url(#gorb2)"/>'
    # Frosted glass: inside the body the whole backdrop is redrawn blurred, so the orbs behind it soften.
    defs = f"""<linearGradient id="gbase" x1="0" y1="0" x2="0.35" y2="1">
    <stop offset="0" stop-color="{base[0]}"/><stop offset="0.5" stop-color="{base[1]}"/><stop offset="1" stop-color="{base[2]}"/>
  </linearGradient>
  <radialGradient id="gsheen" cx="300" cy="170" r="760" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{0.30 if mode == "light" else 0.0}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="gorb" x1="0" y1="0" x2="0.7" y2="1">
    <stop offset="0" stop-color="#8FE6FF"/><stop offset="1" stop-color="#139FEE"/>
  </linearGradient>
  <linearGradient id="gorb2" x1="0" y1="0" x2="0.7" y2="1">
    <stop offset="0" stop-color="#FFC2D7"/><stop offset="1" stop-color="#FF4F8E"/>
  </linearGradient>
  <linearGradient id="gfrost" x1="0" y1="{top}" x2="0" y2="{top + h}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{frost[0]}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="{frost[1]}"/>
  </linearGradient>
  <linearGradient id="grim" x1="{cx - w / 2}" y1="{top}" x2="{cx + w / 2}" y2="{top + h}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{rim[0]}"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="{rim[1]}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="{rim[0] * 0.75:.2f}"/>
  </linearGradient>
  <filter id="frosted" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="34"/></filter>
  <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="28"/></filter>
  <filter id="halo" x="-60%" y="-60%" width="220%" height="220%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="16" result="b"/>
    <feFlood flood-color="#FFFFFF" flood-opacity="0.5"/><feComposite in2="b" operator="in" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <clipPath id="body"><rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="150"/></clipPath>
  <mask id="outside"><rect width="1024" height="1024" fill="#FFFFFF"/><rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="150" fill="#000000"/></mask>
  <g id="backdrop">
    <rect width="1024" height="1024" fill="url(#gbase)"/>
    <rect width="1024" height="1024" fill="url(#gsheen)"/>
    <circle cx="{cx + 190}" cy="{cy + 136}" r="164" fill="url(#gorb)"/>
    {orb2}
  </g>"""
    antennae = "".join(
        f'<path d="M{cx + s * 96} {top - 12} L{cx + s * 158} {top - 108}" stroke="#FFFFFF" stroke-opacity="0.92" '
        f'stroke-width="34" stroke-linecap="round"/>'
        f'<circle cx="{cx + s * 158}" cy="{top - 108}" r="30" fill="{tip}" filter="url(#halo)"/>'
        for s, tip in ((-1, tip_l), (1, tip_r))
    )
    body = (f'<g mask="url(#outside)"><rect x="{cx - w / 2}" y="{top + 30}" width="{w}" height="{h}" rx="150" '
            f'fill="{shade[0]}" opacity="{shade[1]}" filter="url(#soft)"/></g>'
            f'<g clip-path="url(#body)"><use href="#backdrop" filter="url(#frosted)"/>'
            f'<rect width="1024" height="1024" fill="url(#gfrost)"/>'
            f'<ellipse cx="{cx - 120}" cy="{top - 10}" rx="300" ry="96" fill="#FFFFFF" opacity="0.35" filter="url(#soft)"/></g>'
            f'<rect x="{cx - w / 2 + 6}" y="{top + 6}" width="{w - 12}" height="{h - 12}" rx="144" fill="none" '
            f'stroke="url(#grim)" stroke-width="12"/>')
    face = f'<g filter="url(#halo)">{rounded_triangle(cx + 18, cy, 150, 172, "#FFFFFF", r=26)}</g>'
    return frame(PALETTES[mode], antennae + body + face, defs, '<use href="#backdrop"/>')


OPTIONS = [
    ("a-dash", dash),
    ("b-ff-face", ff_face),
    ("c-danmaku", danmaku),
    ("d-bolt", bolt),
    ("e-glass", None),
]


def squircle_mask(size):
    """iOS-style continuous-corner mask, close enough for a preview."""
    scale = 4
    big = size * scale
    mask = Image.new("L", (big, big), 0)
    n = 5.0
    r = big / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(c) ** (2 / n), c)
        y = r + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def render(svg_path, png_path):
    subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
         "--default-background-color=00000000", "--window-size=1024,1024",
         f"--screenshot={png_path}", svg_path.as_uri()],
        check=True, capture_output=True,
    )
    # App Store Connect refuses an icon with an alpha channel.
    Image.open(png_path).convert("RGB").save(png_path, optimize=True)


def contact_sheet(names):
    sizes = (180, 120, 60, 40)
    pad = 24
    col_w = sum(sizes) + pad * (len(sizes) + 1)
    row_h = sizes[0] + pad * 2
    sheet = Image.new("RGB", (col_w * 2, row_h * len(names)), "#FFFFFF")
    dark = Image.new("RGB", (col_w, row_h * len(names)), "#111013")
    sheet.paste(dark, (col_w, 0))
    for row, name in enumerate(names):
        for col, mode in enumerate(("light", "dark")):
            src = Image.open(OUT / f"{name}{'' if mode == 'light' else '-dark'}.png")
            x = col * col_w + pad
            for size in sizes:
                icon = src.resize((size, size), Image.LANCZOS)
                y = row * row_h + pad + (sizes[0] - size) // 2
                sheet.paste(icon, (x, y), squircle_mask(size))
                x += size + pad
    sheet.save(OUT / "check-small-sizes.png")


def main():
    names = []
    for name, draw in OPTIONS:
        names.append(name)
        for mode in ("light", "dark"):
            svg = glass(None, mode) if name == "e-glass" else frame(PALETTES[mode], draw(PALETTES[mode]))
            stem = name if mode == "light" else f"{name}-dark"
            svg_path = OUT / f"{stem}.svg"
            svg_path.write_text(svg, encoding="utf-8")
            render(svg_path, OUT / f"{stem}.png")
            print("rendered", stem)
    contact_sheet(names)


if __name__ == "__main__":
    sys.exit(main())
