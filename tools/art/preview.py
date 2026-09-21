#!/usr/bin/env python3
"""Render the hand-drawn tiles and foliage to zoomed PNGs, to look at.

    python3 tools/art/preview.py [out_dir]

Authoring pixel art by launching the game is hopeless - the pixels are two
screen pixels wide and every round trip is a Godot import. This draws the
same grids straight to a sheet at 10x so a change can be seen immediately.
Edit tiles.py or crown.py, run this, look, repeat; wire it into the game
only once it is right.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png import write_png, render
import tiles, crown

out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
write_png(os.path.join(out, 'preview_tiles.png'),
          render(tiles.T, tiles.PALETTE, zoom=10, cols=4))
write_png(os.path.join(out, 'preview_foliage.png'),
          render(crown.SPRITES, crown.PAL, zoom=6, cols=2, bg=(58, 120, 110, 255)))
print("wrote preview_tiles.png and preview_foliage.png to", out)
