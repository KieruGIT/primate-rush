# Hand-authored terrain tiles, 18x18, one character per pixel.
#
#   .  transparent      o  outline
#   G  grass sun        g  grass          d  grass dark     m  moss
#   E  dirt light       e  dirt           r  dirt dark
#   b  bark light       k  bark           n  bark dark
#
# Built by stamping named shapes at coordinates chosen one at a time. The
# placement is authored, not random: scattered single pixels read as static,
# clustered forms with a lit top and a dark underside read as rock.

SIZE = 18

PALETTE = {
    'o': (22, 30, 28, 255),
    'G': (158, 220, 92, 255),
    'g': (86, 170, 74, 255),
    'd': (46, 112, 60, 255),
    'm': (58, 132, 66, 255),
    'E': (138, 96, 60, 255),
    'e': (104, 68, 44, 255),
    'r': (64, 41, 28, 255),
    'b': (122, 86, 52, 255),
    'k': (74, 53, 38, 255),
    'n': (46, 32, 24, 255),
    '.': None,
}

def grid(ch='.'):
    return [[ch] * SIZE for _ in range(SIZE)]

def stamp(g, x, y, pattern):
    for dy, line in enumerate(pattern):
        for dx, ch in enumerate(line):
            if ch == ' ':
                continue
            px, py = x + dx, y + dy
            if 0 <= px < SIZE and 0 <= py < SIZE:
                g[py][px] = ch

def rows(g):
    return [''.join(r) for r in g]

# --- Shapes ------------------------------------------------------------
ROCK_S  = ["Ee", "rr"]
ROCK_M  = ["EEe", "err"]
ROCK_L  = ["EEEe", "errr"]
ROOT_D  = ["rr  ", " rr ", "  rr"]      # root running down-right
ROOT_U  = ["  rr", " rr ", "rr  "]
GRIT    = ["E"]

def soil(rocks, roots, grit):
    """A dirt body: flat base, then rock and root forms where I put them."""
    g = grid('e')
    for (x, y) in roots:
        stamp(g, x, y, ROOT_D if (x + y) % 2 == 0 else ROOT_U)
    for (x, y, shape) in rocks:
        stamp(g, x, y, shape)
    for (x, y) in grit:
        stamp(g, x, y, GRIT)
    return g

def left_edge(g):
    for y in range(SIZE):
        g[y][0] = 'o'
    return g

def right_edge(g):
    for y in range(SIZE):
        g[y][SIZE - 1] = 'o'
        if g[y][SIZE - 2] in 'eE':
            g[y][SIZE - 2] = 'r'        # dark inner face before the outline
    return g

# --- Thick ground: top surface -----------------------------------------
# Grass teeth dip into the soil at chosen columns, so the boundary between
# green and brown is never a ruled line.
TEETH = [0, 3, 4, 8, 11, 12, 16]
DEEP_TEETH = [3, 11]

def grass_top():
    g = soil(
        rocks=[(2, 10, ROCK_M), (11, 8, ROCK_S), (6, 14, ROCK_L)],
        roots=[(13, 12)],
        grit=[(8, 9), (16, 13), (4, 7), (15, 16)],
    )
    for x in range(SIZE):
        g[0][x] = 'o'
        g[1][x] = 'G'
        g[2][x] = 'G'
        g[3][x] = 'g'
        g[4][x] = 'g'
        g[5][x] = 'd'
    # A couple of darker blades breaking the lit band.
    for x in (2, 7, 13, 16):
        g[2][x] = 'g'
    for x in (5, 9, 15):
        g[3][x] = 'd'
    for x in TEETH:
        g[6][x] = 'd'
    for x in DEEP_TEETH:
        g[7][x] = 'd'
    return g

T = {}
T['grass_l'] = rows(left_edge(grass_top()))
T['grass_m'] = rows(grass_top())
T['grass_r'] = rows(right_edge(grass_top()))

# --- Thick ground: body -------------------------------------------------
# Four soil tiles, each with its rocks and roots somewhere different. One
# tile repeated across a forty-tile ground is visibly one tile however well
# drawn it is; four in a hash order is enough that the eye stops finding the
# period. Only one carries a long root, so the strongest mark is the rarest.
def dirt_body(variant):
    if variant == 0:
        return soil(
            rocks=[(2, 2, ROCK_M), (12, 4, ROCK_S), (6, 9, ROCK_L), (14, 13, ROCK_M)],
            roots=[(8, 0)],
            grit=[(9, 6), (16, 2), (0, 8), (11, 11), (5, 16)],
        )
    if variant == 1:
        return soil(
            rocks=[(9, 1, ROCK_S), (3, 5, ROCK_L), (13, 9, ROCK_M), (5, 13, ROCK_S)],
            roots=[],
            grit=[(1, 3), (11, 7), (16, 10), (8, 15), (2, 9), (14, 5)],
        )
    if variant == 2:
        return soil(
            rocks=[(6, 3, ROCK_S), (14, 7, ROCK_L), (1, 11, ROCK_M)],
            roots=[(9, 12)],
            grit=[(4, 1), (12, 2), (8, 8), (2, 15), (16, 14), (10, 16)],
        )
    return soil(
        rocks=[(11, 2, ROCK_L), (4, 8, ROCK_M), (15, 12, ROCK_S), (7, 15, ROCK_S)],
        roots=[],
        grit=[(0, 5), (7, 4), (13, 6), (3, 12), (17, 9), (9, 10)],
    )

T['dirt_l'] = rows(left_edge(dirt_body(0)))
T['dirt_m'] = rows(dirt_body(0))
T['dirt_r'] = rows(right_edge(dirt_body(0)))
T['dirt_v1'] = rows(dirt_body(1))
T['dirt_v2'] = rows(dirt_body(2))
T['dirt_v3'] = rows(dirt_body(3))

# --- Thin ledge ---------------------------------------------------------
# Cap, a thin body, a dark lip, then clumps of grass hanging under it.
FRINGE = [
    (1, ["m", "m", "m"]),
    (2, ["m", "m"]),
    (6, ["m", "m", "m", "m"]),
    (7, ["m"]),
    (10, ["m", "m"]),
    (13, ["m", "m", "m"]),
    (14, ["m", "m"]),
    (16, ["m"]),
]

def ledge():
    g = grid('.')
    for x in range(SIZE):
        g[0][x] = 'o'
        g[1][x] = 'G'
        g[2][x] = 'G'
        g[3][x] = 'g'
        g[4][x] = 'd'
        g[5][x] = 'e'
        g[6][x] = 'e'
        g[7][x] = 'r'
        g[8][x] = 'o'
    for x in (3, 8, 14):
        g[2][x] = 'g'
    for x in (1, 6, 11, 16):
        g[3][x] = 'd'
    stamp(g, 4, 5, ROCK_S)
    stamp(g, 12, 5, ["Ee"])
    for x, strand in FRINGE:
        for dy, ch in enumerate(strand):
            if 9 + dy < SIZE:
                g[9 + dy][x] = ch
    return g

T['ledge_l'] = rows(left_edge(ledge()))
T['ledge_m'] = rows(ledge())
T['ledge_r'] = rows(right_edge(ledge()))

# --- Climbable trunk ----------------------------------------------------
# Vertical bark strips of uneven width, with knots. Lit on the left.
def trunk():
    g = grid('k')
    for y in range(SIZE):
        g[y][0] = 'b'
        g[y][1] = 'b'
        g[y][2] = 'k'
        g[y][SIZE - 1] = 'n'
        g[y][SIZE - 2] = 'n'
    for x in (5, 9, 14):
        for y in range(SIZE):
            g[y][x] = 'n' if (y + x) % 7 else 'k'
    for x in (4, 11):
        for y in range(SIZE):
            if (y * 3 + x) % 11 < 4:
                g[y][x] = 'b'
    stamp(g, 6, 3, ["nnn", "nkn", "nnn"])       # knot
    stamp(g, 12, 12, ["nn", "nn"])
    return g

T['trunk_l'] = rows(left_edge(trunk()))
T['trunk_m'] = rows(trunk())
T['trunk_r'] = rows(right_edge(trunk()))

if __name__ == '__main__':
    bad = False
    for name, g in T.items():
        if len(g) != SIZE:
            print(f"!! {name}: {len(g)} rows"); bad = True
        for i, row in enumerate(g):
            if len(row) != SIZE:
                print(f"!! {name} row {i}: {len(row)} chars"); bad = True
            for ch in row:
                if ch not in PALETTE:
                    print(f"!! {name} row {i}: unknown {ch!r}"); bad = True
    print("TILES OK" if not bad else "TILES BROKEN")
