# Locked-design animation pack
Open preview.html in a browser. It works directly from disk, with no server or install.

The approved lineup is copied to approved-design.png and documented in DESIGN-LOCK.md. It remains the character design source of truth.

New sheets:
- locomotion.png: 5 characters, 4 idle + 4 walk + 4 run poses each (60 poses).
- traversal-reactions.png: 5 characters, 4 jump/landing + 3 climb + 4 hit reaction poses each (55 poses).
- Existing roll, slap and detachable arm designs are available in the preview from approved-design.png.

The generated traversal sheet supplied three climb poses rather than four; playback uses 0,1,2,1. Jump/landing and hit sequences loop only for review. Real gameplay should trigger these as one-shot sequences.

manifest.json records manually estimated source rectangles and suggested playback rates. These bounds are for preview, not a final engine atlas. Some poses vary in size or align imperfectly. Generated backgrounds remain opaque and shaded; cleanup, pivot alignment and in-between animation refinement are still needed. No game code changed.

Created using the built-in image generation tool with the user-approved image as reference. Exact prompts are saved in prompts.txt.

