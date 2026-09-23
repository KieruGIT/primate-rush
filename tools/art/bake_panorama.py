"""Bake the approved jungle panorama into on-grid pixel art for the game.

assets/environment/approved/jungle-panorama.png (1536x1024, painted AI art)
-> assets/environment/approved/jungle-panorama-px.png

640 art pixels wide, drawn at 2x in game (JungleBackdrop.ZOOM), so it shares
the monkeys' and tiles' pixel size. Area-averaged, pulled 25% toward the
night haze so it stays scenery and never competes with a platform, and
locked to 48 colours. A dark band is added above so zoomed-out cameras
never see past its top edge. Needs Pillow + numpy.

    python tools/art/bake_panorama.py
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'assets/environment/approved/jungle-panorama.png'
OUT = ROOT / 'assets/environment/approved/jungle-panorama-px.png'
WIDTH = 640
PAD_TOP = 420
HAZE = np.array([22, 34, 70], float)
CONTRAST = 0.75

im = Image.open(SRC).convert('RGB')
h = round(im.height * WIDTH / im.width)
small = np.asarray(im.resize((WIDTH, h), Image.Resampling.BOX)).astype(float)
small = HAZE + (small - HAZE) * CONTRAST
top = small[:4].mean(axis=(0, 1))
top = top * 0.85
pad = np.repeat(np.repeat(top[None, None], PAD_TOP, 0), WIDTH, 1)
art = np.concatenate([pad, small], 0)
# Ordered-dither the join over 48 rows so the pad has no hard edge.
bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
for i in range(48):
    y = PAD_TOP + i
    t = i / 48.0
    mask = bayer[y % 4][np.arange(WIDTH) % 4] > t
    art[y][mask] = top
art = np.clip(art, 0, 255).astype(np.uint8)
q = Image.fromarray(art).quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
q.convert('RGB').save(OUT)
print('panorama', WIDTH, 'x', h + PAD_TOP, '->', OUT)
