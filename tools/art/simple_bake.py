"""Bake the low-detail (simplified chibi) monkeys into the game's atlas format.

The simplified style is hand-authored pixel grids: front-facing chibi, big
head, hard 1px outline, one highlight and one shadow tone per colour. Each
species has its own body grid. Every grid pixel becomes a 3x3 block in the
64px atlas cell, so the game can keep drawing atlases at 2x.

Outputs assets/monkeys/simple/<species>/{atlas,portrait,arm_reach,arm_grip,
arm_release}.png and assets/monkeys/simple/rig.json, the same contract as
tools/art/pixel_bake.py, so MonkeySprite only needs ART_DIR switched.

    python tools/art/simple_bake.py
"""
from pathlib import Path
import json
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/monkeys/simple'
REVIEW = ROOT / 'output/low-detail'
BLOCK = 3          # grid pixel -> atlas pixels
CELL = 64
FEET = 62


def C(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(c, f, white=False):
    return tuple(int(round(v + (255 - v) * f)) if white else int(round(v * f)) for v in c)


# Body grids. Letters: O outline, F fur, D fur shadow, H fur highlight,
# T face, S chest/cheek, E eye white, P pupil, M mouth.
GRID = {
    'chimp': dict(rows=['.....OOOOOO.....', '....OFHHFFDO....', '.OOOFHFFFFFDOOO.', 'OTTOFTTFFTTDOTTO',
                        'OTTOTEPTTEPTOTTO', '.OOOTTTTTTTTOOO.', '....OTTMMTTO....', '....ODTTTTDO....',
                        '...OFFOOOOFDO.OO', '..OFFOTTTTODDOFO', '..OOFOTTTTODOODO', '...OFFOOOOFDOO..', '...OOO....OOO...'],
                  head=(0, 7), arm_rows=(8, 10), L=(2, 4, 5), R=(11, 12, 10), legs_rows=(11, 12), legs_cols=(2, 13),
                  waist=10, shoulder=(11, 8), arm_t=5),
    'kong': dict(rows=['........OOOO........', '.......ODDDDO.......', '......ODDDDDDO......',
                       '......OTPTTPTO......', '......OTTMMTTO......', '....OOODTTTTDOOO....', '...OFHHFDDDDFHHFO...',
                       '..OFFFSSSSSSSSFFDO..', '.OFFFOSSSSSSSSOFFDO.', '.OFFFOSSSSSSSSOFFDO.', '.OFFFOOSSSSSSOOFFDO.',
                       '.OFFFO.ODDDDO.OFFDO.', 'OFFFFO.ODDDDO.OFFDDO', 'ODDDDO.ODOODO.ODDDDO', 'OOOOO.ODDOODDO.OOOOO',
                       '......OOO..OOO......'],
                 head=(0, 5), arm_rows=(7, 14), L=(0, 4, 5), R=(15, 19, 14), legs_rows=(14, 15), legs_cols=(6, 13),
                 waist=10, shoulder=(15, 7), arm_t=7),
    'orang': dict(rows=['........OOOO........', '.......OFHHFO.......', '..OOOOOFFFFFFOOOOO..',
                        '..OSSSOTPTTPTOSSSO..', '..OSSSOTTMMTTOSSSO..', '...OOOODTTTTDOOOO...', '...OFHHFFFFFFFHHFO..',
                        '..OFFFFDFFFFDFFFFDO.', '.OFFFOFFFFFFFFOFFDO.', '.OFFFOFFFFFFFFOFFDO.', '.OFFFOOFFFFFFOOFFDO.',
                        '.OFFFO.ODDDDO.OFFDO.', '.OFFFO.ODDDDO.OFFDO.', '.OFFFO.ODDDDO.OFFDO.', 'OFFFFO.ODDDDO.OFFDDO',
                        'ODDDDO.ODOODO.ODDDDO', 'OOOOO.ODDOODDO.OOOOO', '......OOO..OOO......'],
                  head=(0, 5), arm_rows=(7, 16), L=(0, 4, 5), R=(15, 19, 14), legs_rows=(16, 17), legs_cols=(6, 13),
                  waist=12, shoulder=(15, 7), arm_t=6),
    'lanky': dict(rows=['.....OOOO.....', '....OHFFDO....', '...OFTTTTDO...', '...OTPTTPTO...',
                        '...OFTMMTDO.D.', '....OFFFDO..DD', '...OOFFFFOO..D', '..OFOFTTFOFO.D', '..OFOFTTFODO.D',
                        '..OFOFTTFODO.D', '..OFOFFFDODO.D', '..OFOOFFOODODD', '..OFOD..DODO..', '..ODOD..DODO..',
                        '..OOOD..DOOO..', '.....D..D.....', '....OD..DO....', '....OO..OO....'],
                  head=(0, 5), arm_rows=(7, 14), L=(2, 3, 4), R=(10, 11, 9), legs_rows=(15, 17), legs_cols=(4, 9),
                  waist=11, shoulder=(10, 7), arm_t=4),
    'pip': dict(rows=['....OOOO....', '...OHFFDO...', '..OFTTTTDO..', '..OTPTTPTO..', '..OFTMMTDO..',
                      '...OFFFDO.OD', '..OFOTTODOD.', '..OFOTTODO.D', '...OFOODO.D.', '...OO..OO...'],
                head=(0, 4), arm_rows=(6, 8), L=(2, 3, 4), R=(8, 9, 7), legs_rows=(9, 9), legs_cols=(2, 9),
                waist=7, shoulder=(8, 6), arm_t=4),
}

# Game species -> grid + colours. Five distinct monkeys.
SPECIES = {
    'macaque':   dict(grid='pip',   fur='#9a6a3c', face='#f0cfa8', skin='#dcb088'),
    'capuchin':  dict(grid='chimp', fur='#3b3438', face='#d8b494', skin='#b8906e'),
    'gorilla':   dict(grid='kong',  fur='#3a3440', face='#b89a8a', skin='#8a7a7a'),
    'orangutan': dict(grid='orang', fur='#c8621e', face='#e0a878', skin='#c98a5a'),
    'gibbon':    dict(grid='lanky', fur='#e3d6b8', face='#4a3a34', skin='#b8a488', pupil='#f4e9cf'),
}


def padded(g, n=2):
    """Blank rows on top so jump/squash shifts never clip the head."""
    out = dict(g)
    out['rows'] = ['.' * len(g['rows'][0])] * n + list(g['rows'])
    for k in ('head', 'arm_rows', 'legs_rows'):
        out[k] = (g[k][0] + n, g[k][1] + n)
    out['waist'] = g['waist'] + n
    out['shoulder'] = (g['shoulder'][0], g['shoulder'][1] + n)
    return out


def pal(sp):
    s = SPECIES[sp]
    fur, face, skin = C(s['fur']), C(s['face']), C(s['skin'])
    return {'O': C('#1a0f0a'), 'F': fur, 'D': mix(fur, 0.68), 'H': mix(fur, 0.3, True), 'T': face,
            'S': mix(face, 0.78), 'E': (255, 255, 255), 'P': C(s.get('pupil', '#111111')), 'M': C('#5a2a1a'),
            'W': C('#fff4e0'), 'h': skin, 'l': mix(skin, 0.35, True), 'k': mix(skin, 0.72)}


def frame(g, legs='stand', lift_l=0, lift_r=0, noarm=False, dy=0, dx_head=0, face=None, squash=False, blink=False):
    rows = [list(r) for r in g['rows']]
    W = len(rows[0])
    a0, a1 = g['arm_rows']

    def arm_cells(side):
        c0, c1, _ = g[side]
        return [(r, c) for r in range(a0, a1 + 1) for c in range(c0, c1 + 1)]

    if noarm:
        for r, c in arm_cells('R'):
            rows[r][c] = '.'
        e = g['R'][2]
        for r in range(a0, a1 + 1):
            if rows[r][e] != '.':
                rows[r][e] = 'O'
    for side, lift in (('L', lift_l), ('R', 0 if noarm else lift_r)):
        if not lift:
            continue
        cells = {(r, c): rows[r][c] for r, c in arm_cells(side)}
        for rc in cells:
            rows[rc[0]][rc[1]] = '.'
        for (r, c), v in cells.items():
            if v != '.' and r - lift >= 0:
                rows[r - lift][c] = v
        e = g[side][2]
        for r in range(a0, a1 + 1):
            if rows[r][e] != '.':
                rows[r][e] = 'O'
    l0, l1 = g['legs_rows']
    c0, c1 = g['legs_cols']
    mid = (c0 + c1) / 2
    if legs in ('stride', 'together'):
        out = 1 if legs == 'stride' else -1
        for r in range(l0, l1 + 1):
            old = rows[r][:]
            for c in range(c0, c1 + 1):
                rows[r][c] = '.'
            for c in range(c0, c1 + 1):
                if old[c] != '.':
                    nc = c - out if c < mid else c + out
                    if c0 - 1 <= nc <= c1 + 1:
                        rows[r][nc] = old[c]
    if legs == 'tuck':
        for c in range(c0, c1 + 1):
            rows[l1][c] = '.'
    h0, h1 = g['head']
    for r in range(h0, h1 + 1):
        for c in range(W):
            ch = rows[r][c]
            if face == 'stun' and ch == 'E':
                rows[r][c] = 'T'
            if face == 'stun' and ch == 'M':
                rows[r][c] = 'P'
            if face == 'grit' and ch == 'M':
                rows[r][c] = 'W'
            if blink and ch in 'EP':
                rows[r][c] = 'O' if ch == 'P' else 'T'
    if dx_head:
        for r in range(h0, h1 + 1):
            row = rows[r]
            rows[r] = (['.'] * dx_head + row[:-dx_head]) if dx_head > 0 else (row[-dx_head:] + ['.'] * -dx_head)
    if squash:
        w = g['waist']
        top = [rows[r][:] for r in range(0, w)]
        for r in range(1, w + 1):
            rows[r] = top[r - 1]
        rows[0] = ['.'] * W
    if dy < 0:
        rows = rows[-dy:] + [['.'] * W for _ in range(-dy)]
    return [''.join(r) for r in rows]


BALL = {'pip': 9, 'chimp': 11, 'kong': 14, 'orang': 14, 'lanky': 11}


def ball(size, step):
    """Rolled-up monkey: an outlined fur ball, lit from the top left, with
    the face (and a tuck of ear) travelling round it one eighth per frame."""
    import math
    r = size / 2.0
    ang = step * math.pi / 4.0
    fx, fy = r + math.cos(ang) * r * 0.45, r + math.sin(ang) * r * 0.45
    ex, ey = r - math.cos(ang) * r * 0.55, r - math.sin(ang) * r * 0.55
    rows = []
    for y in range(size):
        row = ''
        for x in range(size):
            cx, cy = x + 0.5, y + 0.5
            d = math.hypot(cx - r, cy - r)
            if d > r:
                row += '.'
            elif d > r - 1.0:
                row += 'O'
            elif math.hypot(cx - fx, cy - fy) < r * 0.34:
                # face patch: two eyes across the travel direction
                lx, ly = cx - fx, cy - fy
                across = -lx * math.sin(ang) + ly * math.cos(ang)
                along = lx * math.cos(ang) + ly * math.sin(ang)
                row += 'P' if abs(abs(across) - r * 0.14) < 0.5 and abs(along) < 0.6 else 'T'
            elif math.hypot(cx - ex, cy - ey) < r * 0.2:
                row += 'D'
            elif (cx - r) + (cy - r) < -r * 0.9 and d < r - 1.5:
                row += 'H'
            elif (cx - r) + (cy - r) > r * 0.6:
                row += 'D'
            else:
                row += 'F'
        rows.append(row)
    return rows


def render(rows, p, block=BLOCK):
    h, w = len(rows), len(rows[0])
    im = Image.new('RGBA', (w * block, h * block), (0, 0, 0, 0))
    px = im.load()
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in p:
                for dy in range(block):
                    for dx in range(block):
                        px[x * block + dx, y * block + dy] = p[ch] + (255,)
    return im


def pose_spec(pose):
    """Frame recipe for every pose in MonkeyFrames.POSES."""
    name, _, n = pose.partition('_')
    i = int(n) if n.isdigit() else 0
    walk = [dict(legs='stride', lift_l=1), dict(legs='together', dy=-1), dict(legs='stride', lift_r=1), dict(legs='together', dy=-1)]
    grit = dict(noarm=True, squash=True, dx_head=-1, face='grit')
    hit = dict(legs='stride', noarm=True, dx_head=1, face='grit')
    table = {
        'idle': [{}, {}, dict(squash=True), dict(squash=True)],
        'run': walk + walk,
        'jump': [dict(legs='tuck', lift_l=2, lift_r=2, dy=-1)] * 2 + [dict(legs='stride', lift_l=3, lift_r=3)],
        'fall': [dict(legs='stride', lift_l=3, lift_r=3)] * 2,
        'land': [dict(squash=True), dict(squash=True), {}],
        'climb': [dict(legs='stride', lift_l=3), dict(legs='together'), dict(legs='stride', lift_r=3),
                  dict(legs='together'), dict(legs='stride', lift_l=3), dict(legs='together')],
        'swing': [dict(legs='together', noarm=True, lift_l=1), dict(legs='stride', noarm=True, lift_l=1)] * 2,
        'punch': [grit, grit, hit, hit, {}],
        'slap': [grit, grit, hit, hit, {}],
        'kick': [dict(squash=True), dict(legs='stride', dx_head=-1), dict(legs='stride', dx_head=1), dict(legs='stride'), {}],
        'dash': [dict(legs='stride', dx_head=1)] * 4,
        'roll': [dict(legs='tuck', squash=True)] * 8,
        'stun': [dict(face='stun', squash=True), dict(face='stun'), dict(face='stun', squash=True), dict(face='stun')],
        'wave': [dict(lift_r=3), dict(lift_r=2), dict(lift_r=3), dict(lift_r=2)],
        'cheer': [dict(lift_l=3, lift_r=3), dict(lift_l=3, lift_r=3, dy=-1)] * 2,
    }
    if pose == 'blink':
        return dict(blink=True), 0
    specs = table.get(name, [{}])
    turn = (i % 4) * 90 if name == 'roll' else 0
    return specs[min(i, len(specs) - 1)], turn


def arm_image(g, p, hand):
    """Horizontal arm: tiled shaft on the left, the hand on the right."""
    t = g['arm_t']
    seg = ['OOOOOOOO', 'HHHHHHHH'] + ['FFFDFFFF' if i == (t - 4) // 2 else 'FFFFFFFF' for i in range(t - 4)] + ['DDDDDDDD', 'OOOOOOOO']
    seg = seg[:t] if t < 4 else seg
    hands = {
        'open': ['...OO......', '..OhhO.OOOO', 'OOOhhOOhhhO', 'OFFhhhhOOOO', 'OFFhhhhhhhO', 'OFFhhhhOOOO',
                 'OOOhhhhhhhO', '..OhhhOOOOO', '...OOO.....'],
        'fist': ['...OOOOO.', '..OllllhO', 'OOOhlhlhO', 'OFFhhhhhO', 'OFFOhhhkO', 'OOOhhhhkO', '..OhhhkkO', '...OOOOO.'],
    }[hand]
    shaft_len = 16
    hw, hh = len(hands[0]), len(hands)
    H = max(hh, len(seg))
    rows = [['.'] * (shaft_len + hw - 3) for _ in range(H)]
    so = (H - len(seg)) // 2
    for y, r in enumerate(seg):
        for x in range(shaft_len):
            rows[so + y][x] = r[x % len(r)]
    ho = (H - hh) // 2
    for y, r in enumerate(hands):
        for x, ch in enumerate(r):
            if ch != '.':
                rows[ho + y][shaft_len - 3 + x] = ch
    return render([''.join(r) for r in rows], p), hw * BLOCK


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    src = (ROOT / 'scripts/player/MonkeyFrames.gd').read_text()
    poses = {n: int(i) for n, i in re.findall(r'&"([a-z]+_?\d*|blink)": (\d+)', src.split('const ANIMS')[0])}
    rig = {}
    review = Image.new('RGBA', (CELL * 12, CELL * len(SPECIES)), (40, 52, 90, 255))
    for row, (sp, spec) in enumerate(SPECIES.items()):
        g = padded(GRID[spec['grid']])
        p = pal(sp)
        folder = OUT / sp
        folder.mkdir(exist_ok=True)
        atlas = Image.new('RGBA', (CELL * 8, CELL * 9), (0, 0, 0, 0))
        pivots = {}
        gh, gw = len(g['rows']), len(g['rows'][0])
        for pose, index in poses.items():
            kw, turn = pose_spec(pose)
            if pose.startswith('roll_'):
                img = render(ball(BALL[spec['grid']], int(pose.split('_')[1])), p)
                turn = 0
            else:
                img = render(frame(g, **kw), p)
            w, h = img.size
            x, y = (CELL - w) // 2, FEET - h
            if turn:
                sq = Image.new('RGBA', (max(w, h), max(w, h)), (0, 0, 0, 0))
                sq.paste(img, ((sq.width - w) // 2, (sq.height - h) // 2))
                img = sq.rotate(-turn)
                w, h = img.size
                x, y = (CELL - w) // 2, FEET - h
            cx, cy = (index % 8) * CELL, (index // 8) * CELL
            crop = img.crop((max(0, -x), max(0, -y), w, h))
            atlas.alpha_composite(crop, (cx + max(0, x), cy + max(0, y)))
            sx, sy = g['shoulder']
            lift = kw.get('squash', False)
            pivots[pose] = [x + sx * BLOCK + 1 - 32, y + (sy + (1 if lift else 0) + kw.get('dy', 0)) * BLOCK + 1 - 64]
        atlas.save(folder / 'atlas.png')

        # Portrait: head rows at 3x, centred in 40x40 (2x if it would not fit)
        h0, h1 = g['head']
        head = [r for r in g['rows'][h0:h1 + 1]]
        cols = [i for i in range(gw) if any(r[i] != '.' for r in head)]
        head = [r[cols[0]:cols[-1] + 1] for r in head]
        b = BLOCK if len(head[0]) * BLOCK <= 40 and len(head) * BLOCK <= 40 else 2
        port = render(head, p, b)
        canvas = Image.new('RGBA', (40, 40), (0, 0, 0, 0))
        canvas.alpha_composite(port, ((40 - port.width) // 2, (40 - port.height) // 2))
        canvas.save(folder / 'portrait.png')

        hand_px = []
        for name, hand in (('reach', 'open'), ('grip', 'fist'), ('release', 'open')):
            img, hp = arm_image(g, p, hand)
            img.save(folder / ('arm_%s.png' % name))
            hand_px.append(hp)
        rig[sp] = {'pivots': pivots, 'height': (gh - 2) * BLOCK, 'hand_px': hand_px, 'palette': len(p), 'grid': spec['grid']}

        for c, pose in enumerate(['idle_0', 'run_0', 'run_1', 'jump_0', 'fall_0', 'climb_0', 'swing_0', 'punch_0', 'punch_2', 'stun_0', 'roll_1', 'blink']):
            i = poses[pose]
            review.alpha_composite(atlas.crop(((i % 8) * CELL, (i // 8) * CELL, (i % 8 + 1) * CELL, (i // 8 + 1) * CELL)), (c * CELL, row * CELL))
    (OUT / 'rig.json').write_text(json.dumps(rig, indent=1))
    review.resize((review.width * 2, review.height * 2), Image.NEAREST).save(REVIEW / 'simple-review.png')
    print('baked', list(SPECIES))


if __name__ == '__main__':
    main()
