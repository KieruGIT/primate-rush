"""Low-detail backdrop: the mock scene's flat night sky, moon, temple
mountain and two jungle ridges, with stepped (banded) lighting and 4x4
Bayer dithering. No painted detail, so it stays quiet behind gameplay.

Written in the same layout as the baked panorama (640 art px wide, a dark
420-row pad on top) so LevelSkin and MenuBackdrop can use it unchanged.

    python tools/art/simple_backdrop.py
"""
from pathlib import Path
import math
import random
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/environment/simple/backdrop-px.png'
W, H, PAD = 640, 427, 420
BAY = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
random.seed(11)
img = np.zeros((H, W, 3), np.float32)
L = np.zeros((H, W, 3), np.float32)


def C(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def px(x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H:
        img[y, x] = c


def rect(x0, y0, x1, y1, c):
    x0, y0, x1, y1 = max(0, int(x0)), max(0, int(y0)), min(W, int(x1)), min(H, int(y1))
    if x1 > x0 and y1 > y0:
        img[y0:y1, x0:x1] = c


def disc(cx, cy, r, c, dither=None):
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r:
                if dither is None or BAY[y % 4, x % 4] < dither:
                    px(x, y, c)


def poly(pts, c):
    ys = [p[1] for p in pts]
    for y in range(int(min(ys)), int(max(ys)) + 1):
        xs = []
        for i in range(len(pts)):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
            if (y0 <= y + .5 < y1) or (y1 <= y + .5 < y0):
                xs.append(x0 + (y + .5 - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for a, b in zip(xs[::2], xs[1::2]):
            rect(round(a), y, round(b), y + 1, c)


def light(cx, cy, r, col, k=1.0):
    y0, y1 = max(0, int(cy - r)), min(H, int(cy + r))
    x0, x1 = max(0, int(cx - r)), min(W, int(cx + r))
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    L[y0:y1, x0:x1] += (np.clip(1 - d, 0, 1) ** 1.6 * k)[..., None] * np.array(col, np.float32)


DY = 120   # push the mock's 270-row layout down into the taller canvas
sky = [C(c) for c in ['#060a1a', '#0a1026', '#0e1634', '#131e44', '#1a2852', '#223463', '#2b3f70']]
for y in range(H):
    t = min(1, max(0, y - 60) / 260) * (len(sky) - 1)
    i = int(t)
    f = t - i
    for x in range(W):
        img[y, x] = sky[min(i + (1 if f > BAY[y % 4, x % 4] else 0), len(sky) - 1)]
for _ in range(170):
    x, y = random.randrange(W), random.randrange(250)
    px(x, y, C('#f4e9cf') * random.choice([0.45, 0.6, 0.8, 1.0]))
for (x, y) in [(40, 40), (170, 84), (300, 30), (600, 150), (250, 120), (470, 60)]:
    for d in (-1, 1):
        px(x + d, y, C('#9fb4e8'))
        px(x, y + d, C('#9fb4e8'))
    px(x, y, C('#ffffff'))

# crescent moon
disc(540, 70, 13, C('#f2e8c8'))
disc(547, 65, 12, sky[1])
disc(540, 70, 24, C('#1c2a5a'), dither=0.18)
light(540, 70, 60, (0.35, 0.42, 0.7), 0.35)

# far mountain with the golden banana temple
ox = 110
mt = [(230, 205), (262, 150), (276, 156), (296, 112), (312, 80), (322, 62), (330, 50), (338, 62), (348, 80),
      (366, 112), (384, 150), (398, 146), (440, 205)]
poly([(x + ox, y + DY) for x, y in mt], C('#121a38'))
poly([(x + ox, y + DY) for x, y in [(330, 50), (338, 62), (348, 80), (366, 112), (384, 150), (398, 146), (440, 205), (330, 205)]], C('#0f1630'))
tx, ty = 330 + ox, 52 + DY
for i, (w, h) in enumerate([(26, 4), (20, 4), (14, 4), (8, 3)]):
    rect(tx - w // 2, ty - i * 4, tx + w // 2, ty - i * 4 + h, C('#1e2a55') if i % 2 == 0 else C('#243263'))
rect(tx - 2, ty - 6, tx + 2, ty - 2, C('#ffd84a'))
for ang in (-0.5, -0.2, 0.15, 0.45):
    for r in range(4, 70):
        x = tx + math.sin(ang) * r
        y = ty - 8 - math.cos(ang) * r
        for w in range(-(r // 14), r // 14 + 1):
            xx, yy = int(x + w), int(y)
            if 0 <= xx < W and 0 <= yy < H and BAY[yy % 4, xx % 4] < 0.35:
                img[yy, xx] = img[yy, xx] * 0.6 + C('#ffd84a') * 0.4
light(tx, ty - 6, 55, (1.0, 0.8, 0.3), 0.9)
# a second, lower hill on the left so the frame is not lopsided
poly([(x - 250, y + DY + 40) for x, y in mt], C('#101834'))


def ridge(base, amp, col, seed, bump):
    rnd = random.Random(seed)
    ph = [rnd.random() * 6 for _ in range(3)]
    for x in range(W):
        h = base + amp * (math.sin(x / 23 + ph[0]) * .5 + math.sin(x / 9 + ph[1]) * .3 + math.sin(x / 4.3 + ph[2]) * .2)
        rect(x, h, x + 1, H, col)
    for _ in range(int(W / 7)):
        disc(rnd.randrange(W), base - amp * 0.4 + rnd.random() * 6, bump * (0.6 + rnd.random() * 0.6), col)


ridge(186 + DY, 10, C('#0b1d24'), 1, 9)
for (x0, h) in [(84, 34), (104, 24), (262, 30), (520, 28)]:
    rect(x0, 206 + DY - h, x0 + 8, 206 + DY, C('#18203c'))
    rect(x0 - 1, 206 + DY - h, x0 + 9, 206 + DY - h + 3, C('#1d2748'))
ridge(204 + DY, 8, C('#0d2522'), 2, 8)
ridge(226 + DY, 6, C('#0a1c1a'), 3, 7)

# stepped lighting, as in the mock
Lq = np.floor(np.clip(L, 0, 1.4) * 7) / 7
out = np.clip(img * (0.82 + Lq * 1.15) + Lq * 22, 0, 255).astype(np.uint8)

# Mirrored copies must meet cleanly: make the right edge match the left.
full = np.zeros((PAD + H, W, 3), np.uint8)
full[:PAD] = C('#060a1a').astype(np.uint8)
full[PAD:] = out
OUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(full, 'RGB').save(OUT, optimize=True)
Image.fromarray(out, 'RGB').resize((W * 2, H * 2), Image.NEAREST).save(ROOT / 'output/low-detail/backdrop-preview.png')
print('saved', OUT, full.shape)
