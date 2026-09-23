# Primate Rush design style (backup)

Saved 2026-09-23. This is the approved mock style for Primate Rush (Monkey game, Shipaton 2026). Use it as the reference when building UI, sprites and levels in Godot.

Live canvas: Primate Rush Mockups. Everything in this folder can rebuild it.

## Look in one line

Night jungle, chunky 16-bit pixel art, warm torch light against cool blue night, gold as the reward color, hard 1px dark outlines on everything.

## Palette

| Use | Hex |
|---|---|
| Sky bands, top to horizon | #0b1024, #0e1530, #121b3b, #162246, #1a2a52, #1e325d |
| Panel background | #0a0e1e at 85 to 90% opacity |
| Outline, everything | #1a0f0a |
| Text main (cream) | #f4e9cf |
| Text secondary | #c9bfa6 |
| Text label (blue) | #9fb4e8 |
| Gold, banana, primary button | #ffc83a face, #d48a12 bottom edge, #ffe79a top edge |
| Banana | #f7c948, shade #d49a1f, highlight #fff3b0 |
| Golden banana | #ffe45c, shade #f0a500, glow #ffd84a |
| Grass | top #8fd14f, body #5aa33f, dark #2f6b24 |
| Dirt | #3a2616, pebbles #5c3f28 |
| Wood plank | #8a5a2e, lines #744a24, edge #5c3a1c |
| Stone platform | #5a607a, #4e5470, #666c88, mortar #262a3c |
| Jungle silhouettes | #0f2a1f, #133524, canopy #102b1f |
| Torch flame | #ff6a1c, #ff9a3c, core #ffd84a |
| Neutral button | #2a3358 face, #1c2444 edge |
| Green button | #4f9a3a face, #2f6b24 edge |
| Red (slap) button | #e0504a face, #9e2e2a edge |
| Blue (skill) button | #3a7bd5 face, #24559e edge |
| Stat bars | speed #7ed957, power #ff6b5a, climb #5ab4ff, empty #2a3358 |
| Damage text | #ff6b6b, gain text #ffd84a |

## Type

- Display and numbers: Press Start 2P (Google Fonts). Titles 20 to 24px with a two-step drop shadow (3px darker tone, then 5px #1a0f0a).
- Body and labels: Pixelify Sans 400/600/700. Labels uppercase with 1 to 2px letter spacing.

## UI rules

- No rounded corners on panels or buttons. Pixel edges only.
- Every panel: dark translucent fill, 3px #1a0f0a outer outline, 2px faint cream inner line.
- Buttons are chunky: flat face color, darker 5 to 7px bottom inset edge, lighter 3 to 4px top inset edge, 3px dark outline.
- Wood plank signs for titles and the match timer.
- HUD layout (landscape mobile): banana count top-left, timer plank top-center, leaderboard top-right with BOT tags, joystick bottom-left, Jump (largest), Slap, Skill (with cooldown number) and Lucky Box bottom-right.
- Selected state = gold inner ring (#ffd84a) plus gold label text.

## Monkeys (the approved hero-select style)

Front-facing chibi, big head, hard outline, one highlight tone and one shadow tone per color. Each type has its own body grid:

| Type | Grid | Build | Fur | Face | Skill 1 |
|---|---|---|---|---|---|
| Chimp | 16 x 16 | balanced | #8b5a2b | #e8b98a | Banana Toss |
| Kong (gorilla) | 20 x 19 | huge, grey chest, knuckle fists | #3a3440 | #b89a8a | Charge Dash |
| Lanky (spider monkey) | 14 x 21 | tall, thin, long arms, curled tail | #5f4a3a | #e0c0a0 | Tail Grapple |
| Pip (capuchin) | 12 x 13 | tiny, dark cap | #c98a4a | #f6e3c0 | Pickpocket |

Pixel grids for every type are in `generators/anim2.py` (KINDS) and `boards/Monkey.dc.html`.

Cosmetics are palette swaps (fur and face color) plus hat overlays: crown, mushroom, top hat, shades.

Palette letters used in the grids: O outline, F fur, D fur shadow (fur x 0.68), H fur highlight (30% toward white), T face, S chest (face x 0.78), E eye white, P pupil, M mouth #5a2a1a, Y gold, R red, W white, K black.

## Animation sheet

- `sprites/monkey_anim.png` + `monkey_anim.json`, 24 x 24 cells, feet on the bottom edge.
- Per type: idle x2 (3 fps), walk x4 (8 fps, waddle with arm swing and bob), jump, fall, hit, swing_hold, punch_windup, punch.
- Swing, wind-up and punch frames have no right arm. The stretch arm replaces it.

## Stretch arm (swing and punch)

- Parts per type: arm_segment (tiles along x), shoulder cap, hand_open, fist, fist_big. Arm thickness: Kong 7, Chimp 5, Lanky and Pip 4.
- Swing: arm shoots toward a branch with hand_open, switches to fist on grab, arm length becomes the rope, release at the bottom of the arc to fling.
- Punch: horizontal only, toward the facing side, short reach (about 20px, 1.5 body widths), fist_big, pixel POW flash on hit, target drops bananas and gets stun stars.
- Godot: body = AnimatedSprite2D, arm = Line2D with arm_segment texture in Tile mode from shoulder to target, hand = Sprite2D at the end rotated to the arm angle, shoulder cap drawn on top.

## Level art

- Native 480 x 270, scaled 2x. Stepped (banded) lighting: torches and the golden banana cast warm rings, everything else cool blue.
- Layers back to front: dithered sky with stars and crescent moon, far mountain with the Golden Banana Temple and light rays, two jungle ridges, ruin pillars, waterfall cliff, trees and vines, platforms (mossy stone with brick lines, rope-hung wood plank, sky shrine), ground with grass tufts and bushes, torches, bananas, characters, FX, fireflies.
- `generators/scene.py` rebuilds the full scene. Run `python scene.py` (needs numpy and pillow).

## Files

- `boards/` all canvas artboards (.dc.html) and canvas.json
- `sprites/` animation sheet and the older 3/4-view sheet, with JSON metadata
- `generators/` Python that rebuilds the sprites and scene
- `previews/` rendered PNGs of the scene, sheets and swing test
