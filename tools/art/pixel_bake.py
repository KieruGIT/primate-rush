"""Bake the approved Astra sprite studies into crisp in-game pixel art.

Why this exists: the AI sheets are painted at ~150px per monkey with soft
shading. Shrinking them with nearest-neighbour picking (the first importer)
grabs random pixels out of that shading, so outlines break into dots and the
sprite reads as blurry noise once the game draws it at 2x.

This baker instead:
  1. Cuts every pose out by its real silhouette (connected components over
     the whole sheet), so poses that cross the manifest grid are not clipped.
  2. Uses ONE scale per monkey per sheet, so a monkey never changes size
     between frames.
  3. Downscales by area-averaging (premultiplied), which is what a pixel
     artist does by eye, then snaps alpha to hard 0/255.
  4. Locks each monkey to a small palette, removes stray pixels and redraws a
     clean 1px dark outline on the silhouette.
  5. Plants feet on the same baseline and centres on the feet, not the tail.

Outputs go to assets/monkeys/crisp/<species>/ (atlas.png, portrait.png,
arm_reach/grip/release.png) plus assets/monkeys/crisp/rig.json. The pose
index contract is MonkeyFrames.POSES, same as before. Source art is never
modified. Needs Pillow + numpy only.

    python tools/art/pixel_bake.py
"""
from pathlib import Path
from collections import deque
import json
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'output/monkey-animation-prototype/locked-design-pack'
OUT = ROOT / 'assets/monkeys/crisp'
REVIEW = ROOT / 'output/monkey-animation-prototype/integration'
SPECIES = ['macaque', 'capuchin', 'gorilla', 'orangutan', 'gibbon']
# Standing height in art pixels inside the 64px cell (drawn at 2x in game).
ARM_THICK = {'macaque': 7, 'capuchin': 8, 'gorilla': 11, 'orangutan': 10, 'gibbon': 6}
HEIGHTS = {'macaque': 46, 'capuchin': 46, 'gorilla': 52, 'orangutan': 50, 'gibbon': 50}
PALETTE_SIZE = 22
OUTLINE = np.array([22, 14, 12], float)
SHEETS = {
    'approved': ('approved-design.png', [0, 168, 325, 480, 634, 785, 940, 1091, 1250, 1410, 1536], [0, 200, 389, 577, 776, 1024]),
    'move': ('locomotion.png', [0, 150, 275, 394, 508, 640, 765, 890, 1010, 1140, 1265, 1385, 1536], [0, 208, 389, 580, 777, 1024]),
    'action': ('traversal-reactions.png', [0, 150, 285, 425, 565, 700, 830, 974, 1110, 1270, 1400, 1536], [0, 208, 387, 582, 783, 1024]),
    'body': ('swing-components/swing-bodies.png', [0, 450, 780, 1120, 1536], [0, 211, 388, 579, 775, 1024]),
    'arm': ('swing-components/stretch-arms.png', [0, 542, 1013, 1536], [0, 207, 389, 581, 782, 1024]),
}


# ---------------------------------------------------------------- masks
def dilate(m, r=1):
    out = m.copy()
    for _ in range(r):
        n = out.copy()
        n[1:] |= out[:-1]; n[:-1] |= out[1:]; n[:, 1:] |= out[:, :-1]; n[:, :-1] |= out[:, 1:]
        out = n
    return out


def foreground(img):
    """Opaque mask. RGBA sheets already carry alpha; RGB sheets get their
    dark navy backdrop flood-filled away from the border."""
    a = np.asarray(img).astype(float)
    if img.mode == 'RGBA' and a[..., 3].min() < 10:
        return a[..., 3] > 110
    rgb = a[..., :3]
    border = np.concatenate([rgb[:6].reshape(-1, 3), rgb[-6:].reshape(-1, 3), rgb[:, :6].reshape(-1, 3), rgb[:, -6:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    dist = np.sqrt(((rgb - bg) ** 2).sum(-1))
    bluish = (rgb[..., 2] - rgb[..., 0]) > 4
    bglike = (dist < 36) & bluish | (dist < 12)
    outside = np.zeros(bglike.shape, bool)
    outside[0] = bglike[0]; outside[-1] = bglike[-1]; outside[:, 0] = bglike[:, 0]; outside[:, -1] = bglike[:, -1]
    while True:
        grown = dilate(outside) & bglike
        if grown.sum() == outside.sum():
            break
        outside = grown
    return ~outside


def label(mask, step=3, grow=1):
    """Connected components on a coarse grid (no scipy). Returns a full-size
    label image, 0 = background."""
    h, w = mask.shape
    hh, ww = (h + step - 1) // step, (w + step - 1) // step
    pad = np.zeros((hh * step, ww * step), bool); pad[:h, :w] = mask
    small = pad.reshape(hh, step, ww, step).any(axis=(1, 3))
    small = dilate(small, grow) if grow else small
    lab = np.zeros(small.shape, np.int32); n = 0
    for y, x in zip(*np.nonzero(small)):
        if lab[y, x]:
            continue
        n += 1; lab[y, x] = n; q = deque([(y, x)])
        while q:
            cy, cx = q.popleft()
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < hh and 0 <= nx < ww and small[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n; q.append((ny, nx))
    full = np.repeat(np.repeat(lab, step, 0), step, 1)[:h, :w]
    return np.where(mask, full, 0), n


def cut_sheet(key):
    """Every pose on a sheet as (row, col) -> RGBA crop, found by silhouette."""
    name, xs, ys = SHEETS[key]
    img = Image.open(SRC / name)
    img = img.convert('RGBA') if img.mode == 'RGBA' else img.convert('RGB')
    mask = foreground(img)
    lab, n = label(mask, step=2, grow=0) if img.mode == 'RGBA' else label(mask)
    rgba = np.asarray(img.convert('RGBA')).copy()
    cells = {}
    pieces = []
    for i in range(1, n + 1):
        yy, xx = np.nonzero(lab == i)
        if len(yy) < (250 if img.mode == 'RGBA' else 900):
            continue
        # Poses that touch their neighbour come out as one blob. Split it at
        # the thinnest column near each grid line, never through a body.
        x0, x1 = xx.min(), xx.max()
        inner = [b for b in xs[1:-1] if x0 + 25 < b < x1 - 25]
        if inner:
            counts = np.bincount(xx - x0, minlength=x1 - x0 + 1)
            cuts = []
            for b in inner:
                lo, hi = max(0, b - 50 - x0), min(len(counts) - 1, b + 50 - x0)
                cuts.append(x0 + lo + int(np.argmin(counts[lo:hi + 1])))
            edges = [x0] + cuts + [x1 + 1]
            cut_mass = [0] + [int(counts[c - x0]) for c in cuts] + [0]
            for k, (a0, a1) in enumerate(zip(edges, edges[1:])):
                sel = (xx >= a0) & (xx < a1)
                if sel.sum() >= 250:
                    # a cut through more than a sliver of body = damaged pose
                    pieces.append((yy[sel], xx[sel], max(cut_mass[k], cut_mass[k + 1]) > 14))
        else:
            pieces.append((yy, xx, False))
    damaged = set()
    for yy, xx, bad in pieces:
        cy, cx = yy.mean(), xx.mean()
        col = int(np.searchsorted(xs, cx, side='right') - 1)
        row = int(np.searchsorted(ys, cy, side='right') - 1)
        col = min(max(col, 0), len(xs) - 2); row = min(max(row, 0), len(ys) - 2)
        cells.setdefault((row, col), []).append((yy, xx))
        if bad:
            damaged.add((row, col))
    out = {}
    for rc, parts in cells.items():
        yy = np.concatenate([p[0] for p in parts]); xx = np.concatenate([p[1] for p in parts])
        y0, y1, x0, x1 = yy.min(), yy.max() + 1, xx.min(), xx.max() + 1
        crop = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        crop[yy - y0, xx - x0] = rgba[yy, xx]
        crop[yy - y0, xx - x0, 3] = 255
        out[rc] = crop
    out['damaged'] = damaged
    return out


# ---------------------------------------------------------------- pixel art
def shrink(crop, s):
    """Area-average downscale with premultiplied alpha, hard alpha after."""
    h, w = crop.shape[:2]
    tw, th = max(1, round(w * s)), max(1, round(h * s))
    a = crop[..., 3:4].astype(float) / 255.0
    pre = np.concatenate([crop[..., :3] * a, a * 255], -1).astype(np.float32)
    chans = [np.asarray(Image.fromarray(pre[..., c]).resize((tw, th), Image.Resampling.BOX)) for c in range(4)]
    pre = np.stack(chans, -1)
    alpha = pre[..., 3] / 255.0
    rgb = np.where(alpha[..., None] > 1e-3, pre[..., :3] / np.maximum(alpha[..., None], 1e-3), 0)
    return np.clip(rgb, 0, 255), alpha > 0.5


def build_palette(samples):
    pix = np.concatenate([rgb[m] for rgb, m in samples]).astype(np.uint8)
    side = int(np.ceil(np.sqrt(len(pix))))
    strip = np.zeros((side * side, 3), np.uint8); strip[:len(pix)] = pix; strip[len(pix):] = pix[0]
    im = Image.fromarray(strip.reshape(side, side, 3))
    q = im.quantize(colors=PALETTE_SIZE, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:PALETTE_SIZE * 3], float).reshape(-1, 3)
    return np.vstack([pal, OUTLINE])


def snap(rgb, mask, pal):
    d = ((rgb[..., None, :] - pal[None, None]) ** 2).sum(-1)
    idx = d.argmin(-1)
    out = pal[idx]
    return out, mask


def clean(rgb, m):
    m = m.copy()
    for _ in range(2):
        p = np.pad(m, 1)
        nb = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        m = np.where(m & (nb <= 1), False, m)          # lonely specks
        fill = (~m) & (nb == 4)                           # pinholes
        if fill.any():
            src = np.roll(rgb, 1, axis=1)
            rgb = np.where(fill[..., None], src, rgb)
            m = m | fill
    return rgb, m


def outline(rgb, m):
    """Darken the silhouette edge where the part is at least 3px thick, so
    thin limbs keep their colour but every body gets a crisp 1px contour."""
    p = np.pad(m, 2)
    H, W = m.shape
    edge = np.zeros_like(m)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        out_n = ~p[2 + dy:2 + dy + H, 2 + dx:2 + dx + W]
        inner = p[2 - dy:2 - dy + H, 2 - dx:2 - dx + W] & p[2 - 2 * dy:2 - 2 * dy + H, 2 - 2 * dx:2 - 2 * dx + W]
        edge |= m & out_n & inner
    lum = rgb @ np.array([0.3, 0.59, 0.11])
    rgb = rgb.copy()
    rgb[edge & (lum > 40)] = OUTLINE
    return rgb


def to_rgba(rgb, m):
    out = np.zeros(rgb.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = m * 255
    return out


def trim(a):
    ys, xs = np.nonzero(a[..., 3])
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ---------------------------------------------------------------- bake
def pose_source(pose):
    kind, _, n = pose.partition('_'); i = int(n or 0)
    if kind == 'idle': return 'move', i
    if kind == 'blink': return 'move', 2
    if kind == 'run': return 'move', 8 + (i // 2) % 4
    if kind == 'jump': return 'action', [0, 1, 2][i]
    if kind == 'fall': return 'action', 2
    if kind == 'land': return 'action', [3, 3, 0][i]
    if kind == 'climb': return 'action', [4, 5, 6, 5, 4, 5][i]
    if kind == 'swing': return 'body', [0, 1, 2, 3][i]
    if kind in ('punch', 'slap', 'kick'): return 'body', 0
    if kind == 'dash': return 'move', 8 + i
    if kind == 'roll': return 'approved', 1 + (i // 2) % 4
    if kind == 'stun': return 'action', 7 + i
    if kind in ('wave', 'cheer'): return 'move', i % 4
    return 'approved', 0


def main():
    OUT.mkdir(parents=True, exist_ok=True); REVIEW.mkdir(parents=True, exist_ok=True)
    frames_src = ROOT / 'scripts/player/MonkeyFrames.gd'
    poses = dict((name, int(idx)) for name, idx in re.findall(r'&"([a-z]+_?\d*|blink)": (\d+)', frames_src.read_text().split('const ANIMS')[0]))
    cuts = {k: cut_sheet(k) for k in SHEETS}
    rig = {}
    review_rows = []
    for row, sp in enumerate(SPECIES):
        H = HEIGHTS[sp]
        idle_h = np.median([cuts['move'][(row, c)].shape[0] for c in range(4) if (row, c) in cuts['move']])
        base = H / idle_h
        scale = {
            'move': base,
            'action': base,
            'body': base,
            'arm': base,
            'approved': H / cuts['approved'][(row, 0)].shape[0],
        }
        # shrink everything first, then one palette for the whole monkey
        shrunk = {}
        for pose in poses:
            key, col = pose_source(pose)
            if key == 'move' and col >= 8 and (row, col) in cuts['move']['damaged']:
                col -= 4          # overlapping run study: use the clean walk pose
            crop = cuts[key].get((row, col))
            if crop is None:
                crop = cuts['move'][(row, 0)]; key = 'move'
            s = scale[key]
            if pose.startswith('land_0') or pose.startswith('land_1'):
                pass
            fit = min(1.0, 62 / (crop.shape[0] * s), 62 / (crop.shape[1] * s))
            shrunk[pose] = shrink(crop, s * fit)
        arms = []
        for i in range(3):
            src = cuts['arm'][(row, i)]
            thick = (src[..., 3] > 0).sum(0)
            shaft = np.median(thick[int(len(thick) * .2):int(len(thick) * .55)])
            arms.append(shrink(src, ARM_THICK[sp] / shaft))
        face_src = cuts['approved'][(row, 0)]
        fh, fw = face_src.shape[:2]
        face_src = face_src[:int(fh * 0.56), int(fw * 0.18):]
        face = shrink(face_src, min(34 / face_src.shape[0], 36 / face_src.shape[1]))
        pal = build_palette(list(shrunk.values()) + arms + [face])

        def finish(pair):
            rgb, m = pair
            rgb, m = snap(rgb, m, pal)
            rgb, m = clean(rgb, m)
            return trim(to_rgba(outline(rgb, m), m))

        folder = OUT / sp; folder.mkdir(exist_ok=True)
        atlas = np.zeros((576, 512, 4), np.uint8)
        pivots = {}
        for pose, index in poses.items():
            spr = finish(shrunk[pose])
            h, w = spr.shape[:2]
            feet = spr[int(h * 0.65):, :, 3] > 0
            fx = np.nonzero(feet)[1].mean() if feet.any() else w / 2
            x = int(round(32 - fx)); x = min(max(x, 0), 64 - w)
            y = 62 - h
            cx, cy = (index % 8) * 64, (index // 8) * 64
            dst = atlas[cy + y:cy + y + h, cx + x:cx + x + w]
            sel = spr[..., 3] > 0
            dst[sel] = spr[sel]
            pivots[pose] = [x + round(w * .29) - 32, y + round(h * .40) - 64]
        Image.fromarray(atlas).save(folder / 'atlas.png')

        port = finish(face)
        canvas = np.zeros((40, 40, 4), np.uint8)
        ph, pw = port.shape[:2]
        oy, ox = (40 - ph) // 2, (40 - pw) // 2
        canvas[oy:oy + ph, ox:ox + pw] = port
        Image.fromarray(canvas).save(folder / 'portrait.png')

        hand_px = []
        for i, name in enumerate(['reach', 'grip', 'release']):
            arm = finish(arms[i])
            Image.fromarray(arm).save(folder / ('arm_%s.png' % name))
            hand_px.append(int(round(arm.shape[1] * 0.26)))
        rig[sp] = {'pivots': pivots, 'height': H, 'hand_px': hand_px, 'palette': len(pal)}

        samples = ['idle_0', 'run_0', 'run_2', 'jump_1', 'climb_1', 'roll_0', 'swing_0', 'punch_2', 'stun_1', 'land_0']
        tiles = [atlas[(poses[p] // 8) * 64:(poses[p] // 8 + 1) * 64, (poses[p] % 8) * 64:(poses[p] % 8 + 1) * 64] for p in samples]
        arm_tile = np.zeros((64, 140, 4), np.uint8)
        g = np.asarray(Image.open(folder / 'arm_grip.png'))[:, :140]
        arm_tile[20:20 + min(44, g.shape[0]), :g.shape[1]] = g[:44]
        review_rows.append(np.concatenate(tiles + [arm_tile], 1))
    (OUT / 'rig.json').write_text(json.dumps(rig, indent=1))
    rv = np.concatenate(review_rows, 0)
    bg = Image.new('RGBA', (rv.shape[1], rv.shape[0]), (28, 44, 58, 255))
    bg.alpha_composite(Image.fromarray(rv))
    bg.resize((rv.shape[1] * 3, rv.shape[0] * 3), Image.Resampling.NEAREST).save(REVIEW / 'crisp-review.png')
    print('baked', ', '.join(SPECIES), '->', OUT)


if __name__ == '__main__':
    main()
