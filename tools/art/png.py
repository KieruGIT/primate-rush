"""Minimal PNG writer, so tiles can be authored and looked at without Godot."""
import zlib, struct

def write_png(path, rows):
    h = len(rows); w = len(rows[0])
    raw = b''.join(b'\x00' + b''.join(bytes(px) for px in row) for row in rows)
    def chunk(typ, data):
        return (struct.pack('>I', len(data)) + typ + data
                + struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(png)

def render(grids, palette, zoom=8, cols=6, gap=1, bg=(40,44,52,255)):
    """Lay out named char-grids on a sheet, nearest-neighbour zoomed."""
    names = list(grids)
    tw = max(len(g[0]) for g in grids.values())
    th = max(len(g)    for g in grids.values())
    rows_n = (len(names) + cols - 1) // cols
    W = cols * (tw + gap) * zoom
    H = rows_n * (th + gap) * zoom
    sheet = [[bg for _ in range(W)] for _ in range(H)]
    for i, name in enumerate(names):
        g = grids[name]
        ox = (i % cols) * (tw + gap) * zoom
        oy = (i // cols) * (th + gap) * zoom
        for y, line in enumerate(g):
            for x, ch in enumerate(line):
                col = palette.get(ch)
                if col is None:
                    continue
                for dy in range(zoom):
                    for dx in range(zoom):
                        sheet[oy + y*zoom + dy][ox + x*zoom + dx] = col
    return sheet
