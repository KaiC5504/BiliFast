"""Draws a thin pink line where the cat icon's white ear rims meet the cream background.

uv run --with numpy --with scipy --with pillow design/icon-options/ear_outline.py f-cat-timeline-source.png f-cat-timeline.png 4
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, out, width = sys.argv[1], sys.argv[2], float(sys.argv[3])
S = 4
im = np.asarray(Image.open(src).convert('RGB')).astype(float)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
h, w = r.shape
bg = (abs(r - 250) <= 3) & (abs(g - 245) <= 3) & (abs(b - 241) <= 4)
fig = ndimage.binary_fill_holes(ndimage.binary_opening(~bg, iterations=2))
white = (r >= 251) & (g >= 248) & (b >= 247) & ~bg
white[int(0.5 * h):] = False
white = ndimage.binary_opening(white, iterations=2)
lab, n = ndimage.label(white)
keep = np.zeros_like(white)
for i in range(1, n + 1):
    blob = lab == i
    if blob.sum() > 2000 and (blob & ndimage.binary_dilation(bg, iterations=3)).any():
        keep |= blob
near = ndimage.binary_dilation(keep, iterations=int(width) + 6)
# supersample the silhouette so the line is smooth
f = ndimage.zoom(ndimage.gaussian_filter(fig.astype(float), 1.5), S, order=1) > 0.5
d = ndimage.distance_transform_edt(~f) / S
a = np.clip(width + 0.5 - d, 0, 1) * (d > 0)
a = a.reshape(h, S, w, S).mean(axis=(1, 3))
a *= ndimage.gaussian_filter(near.astype(float), 3)
pink = np.array([244, 150, 178], float)
res = im * (1 - a[..., None]) + pink * a[..., None]
Image.fromarray(res.round().astype(np.uint8)).save(out)
