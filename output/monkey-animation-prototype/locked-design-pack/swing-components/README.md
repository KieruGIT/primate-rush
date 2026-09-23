# Modular stretch-arm swing prototype
The user's mechanic reference shows a thick extensible arm connecting the shoulder directly to a map anchor. These assets follow that mechanism and retain the locked five-character palette and identity.

Rows on both sheets: common monkey, chimpanzee, gorilla, orangutan, gibbon.

- swing-bodies.png: four body pose studies per character; hanging, trailing, legs-forward and trailing variant. Arm-free torso/legs layer with shoulder attachment patches. Both arms are omitted in this modular body study.
- stretch-arms.png: three full arm states per character; open reach, closed grip, release. Shoulder end on the left, hand on the right. The arm and body are stored in separate image files.
- preview.html: view the two sheets together.

Assembly guidance: attach the rounded arm base at the visible shoulder patch; rotate toward the anchor. Stretch the shaft between shoulder and wrist while preserving hand size. Keep the grip at the map anchor as the body swings. Add a second arm layer if a free arm is desired. These are sprite components only; no swing physics or game integration was changed.

Prototype limitations: backgrounds remain opaque; crop bounds and pivots are not finalized. Some body poses need anatomy/pose refinement against the approved model before production. Four body cells include similar trailing variants, not a polished complete swing cycle. Remove backgrounds and align shoulder/hand pivots before engine import.

Created with the built-in image generation tool. Final body and arm prompts are saved in prompts.txt. Earlier rejected body drafts are not part of this pack.

