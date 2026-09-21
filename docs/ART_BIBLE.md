# Primate Rush — Art Bible

Authoritative. When code and this document disagree, this document is right
and the code is a bug. When this document does not cover something, use a
placeholder and say so — do not invent a new visual style to fill the gap.

The reference is the key art storyboard: a deep jungle platformer, seen from
the side, in daylight under a thick canopy.

---

## 1. The one rule

**Everything is pixel art at the same pixel size.**

| | |
|---|---|
| Design resolution | 1280 × 720 |
| Art resolution | 640 × 360 |
| World pixels per art pixel (`SCALE`) | **2** |
| Tile grid | 18 × 18 art pixels (36 × 36 world) |
| Filtering | `TEXTURE_FILTER_NEAREST`, everywhere |
| Zoom factors | whole numbers only |

A fractional scale, a rotated sprite, or an unsnapped position produces
uneven pixels, and there is no fixing that downstream. Positions that come
out of maths get snapped: `(p / SCALE).round() * SCALE`.

**Never use Godot's vector draw calls for art.** `draw_circle`,
`draw_colored_polygon` and `draw_line` antialias. One antialiased curve
behind a hard-edged tile reads instantly as two different pictures. Art is
rasterised through `PixelCanvas` into an `Image` and drawn as a texture.

The exceptions, and they are the only ones: soft light (`JunglePalette.draw_glow`)
and flat colour fills that sit behind everything.

---

## 2. Light

**Light comes from up and to the left. Always.** (`PixelCanvas.LIT_SIDE`)

Every object is lit the same way or the scene stops being one place:

- lit edge on the top and the left
- dark edge on the bottom and the right
- one shared outline colour around foreground objects

Warm colour means light: a torch, a flame, an ember, a banana. Nothing that
is not a light source is warm. The jungle floor is dim, so torches read as
accents and as signposting — not as the only light in the frame.

---

## 3. Visual hierarchy

The background must never compete with the surface the player has to land
on. Contrast and saturation fall off with distance, detail falls off fastest.

| Layer | Contrast | Detail | Outline |
|---|---|---|---|
| Near frame (`near`) | flat, dark | silhouette only | no |
| Middle distance (`mid`) | low | trunks, crowns, vines | no |
| Far wall (`far`) | lowest | silhouette only | no |
| **Playable terrain** | **highest** | grain, rocks, tufts | **yes** |
| Props and characters | high | full | yes |
| Light and particles | — | — | no |

Far layers are pushed toward the haze by `JunglePalette.at_distance()`. One
function, so every distant thing fades by the same rule.

**Nothing in the background may end on a horizontal line.** A straight edge
across the screen is a seam no colour work rescues. Fills follow the
underside of whatever is above them (`PixelCanvas.fill_under_canopy`).

---

## 4. Platform anatomy

Non-negotiable, because it is how a player reads a standable surface during
a four-way race:

```
 ____________________   1 px outline
|====================|  lit grass cap, brightest on its top row
|,,,,,,,,,,,,,,,,,,,,|  grass biting down into the soil, never a ruled line
|::::.::::::.::..::::|  soil, grained — never a flat fill
|____________________|  dark underside
   \|/   \|/    \|/     moss fringe hanging off the lip
```

Tiles are baked by `JungleTiles`. A tile repeated forty times is visibly
forty copies of one tile, so every ground also gets detail at spacings
unrelated to the grid: rocks, roots, grass tufts.

---

## 5. Climbing and swinging

Gameplay vines and decorative vines must never be confusable.

| | Gameplay | Decoration |
|---|---|---|
| Thickness | thick | thin |
| Contrast | high, against everything | low |
| Anchor | visible | none |
| Layer | foreground | `mid` / `near` |

A climbable trunk is bark all the way down with a crown on top, never a
pillar of soil standing in the air.

---

## 6. Characters

Silhouette first: broad gorilla, long-armed gibbon, tailed capuchin, all
readable at gameplay scale without colour. Large head, compact torso, short
legs, long arms, big hands.

- One dominant colour per player; the silhouette never changes between them.
- Cosmetics may change the head, never obscure the hands or the feet.
- A monkey occupies roughly 13% of screen height.

---

## 7. Do not

- realistic texture or photographic reference
- gradients as a substitute for shading
- generic mobile-game UI, glassmorphism, rounded SaaS panels
- glow used as decoration rather than as a light source
- background detail that competes with a platform edge
- two pixel sizes in one frame
- a new colour that is not in `JunglePalette`

---

## 8. Where the rules live in code

| File | Owns |
|---|---|
| `scripts/world/JunglePalette.gd` | every colour, the haze rule, the glow |
| `scripts/world/PixelCanvas.gd` | the rasteriser and the jungle shapes |
| `scripts/world/JungleTiles.gd` | terrain atlas and props |
| `scripts/world/JungleBackdrop.gd` | the three parallax layers |
| `scripts/world/LevelSkin.gd` | dressing a gray-box map with all of it |
| `scripts/ui/UiTheme.gd` | the menu palette |

Add a colour to `JunglePalette` or it does not exist. Two files each owning
"jungle green" is how the jungle stops being one jungle.

---

## 9. Checking your work

The art is verified by screenshot, not by reading the diff:

```
godot --headless --fixed-fps 60 res://tools/Smoke.tscn          # nothing throws
xvfb-run godot --rendering-driver opengl3 res://tools/CaptureUi.tscn -- \
    --out=/tmp/shots/ --shots=game_a,game_b,overview_a          # look at it
```

Diagnose a screenshot against §3 and §4 specifically — readability,
hierarchy, scale, contrast — rather than asking whether it looks good.
