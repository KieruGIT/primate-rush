# Primate Rush — expanded jungle map
Design target: a 12,000 × 3,600 world-unit first-pass level. This expands playable space; it does not upscale sprites. Keep monkeys at the approved native size and use nearest filtering / integer presentation scale.

## Six connected areas
| Zone | World X range | Main feature |
|---|---|---|
| Root Village | 0–2,000 | Safe start terrace, roots, forgiving low ledges |
| Swing Grove | 2,000–4,000 | Dense world-space trees, short branch-to-branch chains |
| Waterfall Basin | 4,000–6,000 | Broad recovery islands, central contest arena, upper crossings |
| Ancient Aqueduct | 6,000–8,000 | Mossy arches, stepping columns and vertical shortcuts |
| High Canopy | 8,000–10,000 | Extended swing chains, narrow high platforms, lower bypass |
| Golden Shrine | 10,000–12,000 | High reward shrine and descending return loop |

Three broad elevation bands: lower safe trail, middle branch route, high risk/reward route. Add intermediate stepping ledges and branches between bands; don't expect a monkey to jump a whole band in one move. Target at least 35 platform surfaces and 30 clearly marked grip points, then tune counts and spacing against actual movement.

## Visual and interaction rules
- Use expanded-jungle-v2.png as the full-world concept. jungle-route-v1.png is a closer detail/style reference.
- assets/environment/approved/jungle-panorama.png is distant scenery only.
- Dense parallax foliage stays low contrast and never owns interaction anchors.
- Actual grabbable trees occupy fixed world coordinates behind the player layer. Roots attach to terrain; each grab point sits on a visible branch/trunk.
- Small jade/gold vine wraps identify grippable surfaces. No arbitrary floating anchors.
- Use the same species-colored arm for fist attacks and shoulder-to-anchor grabbing.
- Standable surfaces have bright clean moss caps and dark stone/bark undersides. Keep airborne corridors open and HUD sight lines clear.
- Low routes provide recovery platforms under difficult upper gaps. Reward higher paths with bananas and shortcuts.
- Keep all five locked monkey designs, crisp sprite imports and current user movement tuning.

## Implementation validation
The concept is not a tested collision layout. Build geometry and anchors from world data, not by using this flattened image as the level. Compute reachable spacing from the current jump, sprint and grab tuning. Confirm collision, grab acquisition, release momentum and landing routes by playtest, including left/right traversal. Keep tree placement deterministic for multiplayer. Capture full-map and normal-zoom proof.

## Short Claude handoff
Implement the expanded map in D:/Game/Monkey-Game using output/map-design/expanded-jungle-v2.png and MAP-DESIGN.md. Preserve the crisp sprite fix, approved characters and current movement changes. Make a 12,000 × 3,600 world with the six zones and three route heights. Build at least 35 real platforms and 30 reachable grab points on visible world-space trees/branches; distant parallax trees are decorative only. Use assets/environment/approved/jungle-panorama.png behind gameplay. Keep native sprite size and nearest filtering. Use Godot MCP to test navigation, punch/grab arms, collisions and all modes. Save screenshots and results to output/claude-handoff. This is a map concept to implement, not a flattened gameplay background.

Generated map concepts use built-in imagegen; prompts are saved alongside this file.

