# Hand-authored foliage. Leaf clumps drawn once, then placed by hand.
#
#   H  leaf sun      L  leaf        D  leaf dark     K  canopy frame (darkest)
#   b  bark light    k  bark        n  bark dark     o  outline

PAL = {
    'H': (190, 236, 118, 255),
    'L': (86, 178, 88, 255),
    'D': (44, 120, 70, 255),
    'K': (22, 70, 52, 255),
    'b': (122, 86, 52, 255),
    'k': (74, 53, 38, 255),
    'n': (46, 32, 24, 255),
    'o': (18, 34, 30, 255),
    '.': None,
}

# A leaf clump: lit along its top-left, dark along its bottom-right, with a
# notched silhouette so it never reads as an ellipse.
CLUMP = [
    "..HHHH..",
    ".HHHHHHL",
    "HHLLLLLL",
    "LLLLLLLD",
    "LLLLLDDD",
    ".LDDDDD.",
    "..DD.D..",
]
CLUMP_BIG = [
    "...HHHHHH...",
    "..HHHHHHHHL.",
    ".HHHHLLLLLLL",
    "HHLLLLLLLLLD",
    "LLLLLLLLLLDD",
    "LLLLLLLLDDDD",
    ".LLLDDDDDDD.",
    "..DD.DDD.DD.",
]
CLUMP_SM = [
    ".HHH.",
    "HHLLL",
    "LLLLD",
    ".LDD.",
]

def grid(w, h, ch='.'):
    return [[ch] * w for _ in range(h)]

def stamp(g, x, y, pat):
    for dy, line in enumerate(pat):
        for dx, ch in enumerate(line):
            if ch == '.':
                continue
            px, py = x + dx, y + dy
            if 0 <= py < len(g) and 0 <= px < len(g[0]):
                g[py][px] = ch

DARKEN = {'H': 'L', 'L': 'D', 'D': 'K', 'K': 'K'}

def shade(pat, steps):
    """One clump, moved down the value ramp. Lower clumps in a crown sit in
    the shadow of the ones above them, which is what gives the mass form
    instead of a field of identical bubbles."""
    out = []
    for line in pat:
        row = ''
        for ch in line:
            for _ in range(steps):
                ch = DARKEN.get(ch, ch)
            row += ch
        out.append(row)
    return out

def outline(g, col='o'):
    """Outlines the OUTER silhouette only, and fills enclosed gaps with the
    darkest green. Outlining every gap between clumps drew a keyline round
    each one and turned the crown into a pile of separate bushes."""
    from collections import deque
    h, w = len(g), len(g[0])
    outside = [[False] * w for _ in range(h)]
    q = deque()
    for y in range(h):
        for x in range(w):
            on_border = x in (0, w - 1) or y in (0, h - 1)
            if on_border and g[y][x] == '.':
                outside[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and g[ny][nx] == '.' and not outside[ny][nx]:
                outside[ny][nx] = True
                q.append((nx, ny))
    for y in range(h):
        for x in range(w):
            if g[y][x] != '.':
                continue
            if not outside[y][x]:
                g[y][x] = 'K'          # an enclosed pocket, not a hole
                continue
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and g[ny][nx] not in '.o':
                    g[y][x] = col
                    break
    return g

def rows(g):
    return [''.join(r) for r in g]

# --- The big crown ------------------------------------------------------
# Placed bottom row first so later clumps overlap earlier ones, and shifted
# left as they rise: the light is up and to the left, so the mass leans that
# way. Every coordinate below was chosen, not rolled.
def crown_big():
    W, H = 56, 38
    g = grid(W, H)
    # Bottom tier: deepest shade, widest spread, clumps overlapping by a
    # third so they fuse into one silhouette rather than sitting side by side.
    for x, y in [(0, 19), (8, 21), (17, 20), (26, 21), (35, 20), (43, 18)]:
        stamp(g, x, y, shade(CLUMP_BIG, 2))
    for x, y in [(3, 12), (12, 14), (21, 13), (30, 14), (39, 12)]:
        stamp(g, x, y, shade(CLUMP_BIG, 1))
    for x, y in [(8, 6), (17, 4), (26, 7), (35, 5)]:
        stamp(g, x, y, CLUMP)
    for x, y in [(15, 1), (24, 0), (31, 2)]:
        stamp(g, x, y, CLUMP)
    # Leaf tips hanging out of the underside.
    for x, y in [(5, 25), (16, 27), (27, 26), (38, 27), (47, 24)]:
        stamp(g, x, y, ["DD", "DD", ".D"])
    return outline(g)

def crown_small():
    W, H = 38, 26
    g = grid(W, H)
    for x, y in [(0, 13), (7, 15), (14, 14), (21, 15), (28, 13)]:
        stamp(g, x, y, shade(CLUMP, 2))
    for x, y in [(3, 7), (11, 8), (19, 7), (26, 8)]:
        stamp(g, x, y, shade(CLUMP, 1))
    for x, y in [(8, 1), (16, 2), (23, 1)]:
        stamp(g, x, y, CLUMP)
    for x, y in [(4, 18), (14, 20), (25, 19)]:
        stamp(g, x, y, ["DD", ".D"])
    return outline(g)

def shrub():
    W, H = 26, 14
    g = grid(W, H)
    for x, y in [(0, 7), (6, 8), (12, 7), (17, 8)]:
        stamp(g, x, y, shade(CLUMP, 1))
    for x, y in [(3, 2), (10, 3), (16, 2)]:
        stamp(g, x, y, CLUMP_SM)
    return outline(g)

def fern():
    W, H = 26, 18
    g = grid(W, H)
    # Blades drawn one at a time from the root, each a stepped taper.
    blades = [(-3, -1.0), (-2, -0.6), (0, -0.2), (1, 0.25), (3, 0.65), (4, 1.0)]
    root = (W // 2, H - 1)
    for i, (lean, spread) in enumerate(blades):
        length = 13 if abs(spread) < 0.5 else 10
        for step in range(length):
            x = int(root[0] + spread * step * 0.9)
            y = root[1] - step
            half = 2 if step < length * 0.55 else 1
            for dx in range(-half, half + 1):
                if 0 <= x + dx < W and 0 <= y < H:
                    g[y][x + dx] = 'L' if step % 3 else 'D'
            if 0 <= x < W and 0 <= y < H and step > 2:
                g[y][x] = 'H'
    return outline(g)

SPRITES = {
    'crown_big': rows(crown_big()),
    'crown_small': rows(crown_small()),
    'shrub': rows(shrub()),
    'fern': rows(fern()),
}

if __name__ == '__main__':
    from png import write_png, render
    write_png('crowns.png', render(SPRITES, PAL, zoom=6, cols=2, bg=(58, 120, 110, 255)))
    for n, g in SPRITES.items():
        print(n, len(g[0]), 'x', len(g))
