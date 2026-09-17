# Monkey Game - Design Document

Working title: Monkey
Engine: Godot 4.7.2
Renderer: Compatibility (OpenGL 3)
Dimension: **Full 2D, side-scrolling. Locked.**

---

## 1. Core Concept

Multiplayer party game where every player picks a monkey and competes across two modes. Movement is built on climbing, swinging, and hitting other players. Nobody dies. The only thing you can do to another monkey is knock them around or stun them, which means every interaction costs your opponent progress and time rather than removing them from the round.

That no-death rule is the design spine. It keeps rounds short, keeps everyone playing the entire round, and means the skill expression is in movement recovery rather than survival.

---

## 2. Combat Model

### Normal Attack

One button. The animation randomizes between slap, punch, and kick purely for visual variety. Mechanically they are identical: same damage-free knockback, same stun duration, same cooldown, same range.

Do not give the three animations different properties. The moment a kick has more range than a slap, players will try to fish for the kick, and they cannot control which one comes out. That turns a cosmetic system into a frustration system.

The only time attack properties change is when an ability modifies them.

### Effects of a Normal Attack

- Knockback in the direction the attacker is facing
- Brief stun, target cannot act
- Forces the target to release a vine if they are swinging
- Forces the target off a wall if they are climbing
- In Banana mode, causes the target to drop bananas

Knockback magnitude is calculated from the attacker's Power stat against the target's Weight stat. A gorilla hitting a capuchin sends them flying. A capuchin hitting a gorilla barely moves them.

### No Death, No Health

There is no health bar and no elimination. Falling off the map respawns you at the last checkpoint after a short delay. The delay is the punishment, not a life lost.

---

## 3. Monkey Roster

Each monkey is defined by stats plus one unique skill. The stats create the tradeoff, the skill creates the identity.

### Stat Axes

| Stat | What it controls |
|---|---|
| Speed | Ground movement rate |
| Weight | Resistance to incoming knockback and stun duration |
| Power | Knockback dealt by normal attacks |
| Climb | Vertical climbing speed |
| Swing | Swing momentum retention and air control |

### Roster

**Gorilla - The Bruiser**
- Speed: Low
- Weight: Very High
- Power: Very High
- Climb: Low
- Swing: Low
- Skill 1: **Grapple Dash.** Fires a short grapple forward. Connecting with terrain pulls the gorilla to it at high speed. Connecting with a player yanks that player to the gorilla and staggers them.

The gorilla is bad at the movement game and good at ruining yours. Hard to knock around, hits like a truck, but loses ground on any map built around swinging.

**Gibbon - The Swinger**
- Speed: High
- Weight: Very Low
- Power: Low
- Climb: Medium
- Swing: Very High
- Skill 1: **Air Launch.** Instantly launches in the current aim direction, usable in midair once per landing. Chains into a vine grab.

The gibbon is the skill ceiling pick. Fastest possible route through any map if played well, but one hit from a gorilla sends it across the screen.

**Orangutan - The Climber**
- Speed: Low
- Weight: High
- Power: Medium
- Climb: Very High
- Swing: Medium
- Skill 1: **Long Arm.** Extended-range grab that pulls a distant player toward you, or pulls you to a distant ledge. Slow windup.

Dominant on the vertical map, sluggish on the horizontal one. The clearest example of a monkey that is map-dependent rather than universally strong.

**Macaque - The Allrounder**
- Speed: Medium
- Weight: Medium
- Power: Medium
- Climb: Medium
- Swing: Medium
- Skill 1: **Counter Roll.** Short dodge roll with brief invulnerability to knockback. Rolling through an attack stuns the attacker instead.

No weakness and no strength. The pick for new players, and the pick that punishes people who attack carelessly.

**Capuchin - The Thief**
- Speed: Very High
- Weight: Very Low
- Power: Very Low
- Climb: High
- Swing: High
- Skill 1: **Snatch.** Dash forward. Passing through a player steals bananas from them in Hoard mode, or steals their momentum in Race mode by briefly slowing them and speeding yourself.

Built for Banana Hoard specifically. Almost useless in a straight fight, extremely annoying to play against when it is farming you.

### Roster Scope Note

Five is the target. Build **two first**, gorilla and gibbon, because they sit at opposite ends of every stat axis. If those two feel meaningfully different to play, the stat system works and the other three are just data entry. If they feel the same, the stat spread is too narrow and the whole roster is cosmetic.

---

## 4. Movement System

### Climb
Contact with a climbable surface allows vertical movement at Climb speed. Jump off to redirect. Being hit knocks you off.

### Swing
Vine anchors placed by the level designer. Grab within radius, become a pendulum, release timing sets launch angle and speed. Swing stat controls momentum retention and air control. Chaining swings without touching ground is the mastery goal.

Implementation: manual angular velocity math on a CharacterBody2D rather than PinJoint2D. More control and easier to sync over the network.

### Hit
Covered in section 2.

---

## 5. Game Modes

### Mode 1: Race

First to the finish line wins. Attacking is the interference tool.

**Map A - Horizontal Run**
Left to right. Flat ground sections reward Speed, gaps force swinging, so the optimal line is a chain of swings and the safe line is ground running. Favors gibbon and capuchin.

**Map B - Vertical Ascent**
Bottom to top. Climbable walls, vines for lateral shortcuts, ledges as rest points. Favors orangutan and gorilla. Knocking someone off costs them real progress, which is what creates comebacks.

**Parameters**
- 4 to 8 players
- Countdown start
- Checkpoints, respawn with a time penalty on falling
- Placement-based results

### Mode 2: Banana Hoard

Fixed timer, open map, most banana points wins.

- 3 minute rounds
- Bananas spawn continuously, higher and harder-to-reach spawns are worth more points
- **Hitting a player makes them drop a portion of their bananas, which anyone can then collect**

That drop rule is load-bearing. Without it players ignore each other and farm in separate corners, and the mode has no multiplayer tension at all.

**Lucky Boxes**
Random pickup granting a temporary ability. Start with four, expand later.

| Ability | Effect |
|---|---|
| Speed Boost | Increased movement speed, short duration |
| Super Hit | Next normal attack has massive knockback and doubles banana drop |
| Banana Magnet | Nearby bananas pull toward you |
| Ghost | Cannot be hit, cannot hit, pass through players |

Four tuned abilities beat seven half-tuned ones. Add Banana Bomb and Thief later if the pool feels thin.

---

## 6. Rank System

Ranked play, listed here because you asked for it, but understand what it actually requires before committing.

### What ranked needs that the base game does not

- Persistent accounts, so progress survives a restart
- A backend database, since rank cannot live on the client or players will edit it
- Enough concurrent players that matchmaking can find opponents of similar skill
- Dedicated servers or at minimum host validation, because host-authoritative play means the host can cheat

The third point is the one that kills most indie ranked systems. A rank system with twelve concurrent players is a rank system that matches a Bronze against a Diamond every single game, which is worse than no rank at all.

### Recommended design

**Tiers:** Bronze, Silver, Gold, Platinum, Diamond, Ape.

**Points:** Placement-based. In an 8 player race, first place gains the most, last place loses the most, middle placements are roughly neutral. Hoard mode scores on final banana rank, same curve.

**Placement matches:** 5 unranked games before a tier is assigned, so a bad first game does not define someone.

**Demotion protection:** A buffer at the bottom of each tier so players do not bounce between tiers every session.

**Per-mode rank:** Race rank and Hoard rank tracked separately. They test completely different skills and combining them means neither number is meaningful.

### Realistic sequencing

Build ranked **last**. Ship with casual lobbies and local stat tracking first. Add backend accounts and ranked once there is an actual playerbase to rank. Building ranked infrastructure before the game is proven fun is the single most common way indie multiplayer projects stall out.

---

## 7. Cosmetics

Secondary system. Design it now, build it late.

- Skins per monkey, recolors first since they are near-free to produce
- Hats and accessories as separate sprite layers on an attachment point
- Trail effects on swing
- Emotes

**Technical requirement to handle early:** build the monkey sprite with a modular attachment point for headwear from day one. Retrofitting attachment points onto a finished sprite rig is genuinely painful. The cosmetics themselves can wait, the hook for them cannot.

No monetization design in this document. Get the game playable first.

---

## 8. Multiplayer Architecture

### Version one
- Godot high-level multiplayer API over ENet
- Host-authoritative, one player hosts and their machine is truth
- MultiplayerSpawner for players, bananas, lucky boxes
- MultiplayerSynchronizer for position, velocity, state, selected monkey
- LAN or direct IP connect

### Not in version one
Dedicated servers, matchmaking, accounts, anti-cheat, ranked backend.

### Sync concerns specific to this game
Swinging is the risk. Independent pendulum simulation on each client drifts apart fast. Host simulates all swing physics and sends positions. Drift matters less than you think for a party game, but desynced knockback will feel broken, so knockback resolution must be host-authoritative too.

---

## 9. Build Order

Feel first, content second, infrastructure last.

**Phase 1** - One monkey, gray-box level, running and jumping. No art. Goal is movement that feels good.

**Phase 2** - Add climb and swing. Iterate until swinging is satisfying with zero opponents and zero objectives. If it is not fun alone, no mode fixes it.

**Phase 3** - Add normal attack, knockback, stun. Two players local split-input. Test whether interfering with someone is funny.

**Phase 4** - Add the stat system and the second monkey. Gorilla versus gibbon. Confirm they feel different.

**Phase 5** - Network it. Convert local to networked. Expect this to take longer than phases 1 through 4 combined.

**Phase 6** - Race mode plus Map A.

**Phase 7** - Map B vertical.

**Phase 8** - Skills, one per monkey.

**Phase 9** - Banana Hoard plus lucky boxes.

**Phase 10** - Remaining three monkeys.

**Phase 11** - Art pass, audio, menus.

**Phase 12** - Accounts, backend, ranked.

**Phase 13** - Cosmetics.

---

## 10. Base Feature Checklist

Everything required for the game to be considered functional. Anything not on this list is secondary.

- [ ] CharacterBody2D monkey with run and jump
- [ ] Climb on climbable surfaces
- [ ] Vine swing with momentum and release
- [ ] Normal attack with randomized slap/punch/kick animation
- [ ] Knockback scaled by attacker Power against target Weight
- [ ] Stun on hit
- [ ] Respawn on fall, no death, no health
- [ ] Stat block system driving all five axes
- [ ] Two playable monkeys minimum
- [ ] One skill per monkey
- [ ] Networked multiplayer, host-authoritative, 4 to 8 players
- [ ] Race mode with checkpoints and placement
- [ ] Map A horizontal
- [ ] Map B vertical
- [ ] Banana Hoard mode with timer and scoring
- [ ] Banana drop on hit
- [ ] Lucky boxes with four abilities
- [ ] Character select screen
- [ ] Lobby and results screens

---

## 11. Technical Setup Notes

- Renderer must be Compatibility, not Mobile, not Forward Plus, given the GeForce 920MX
- Main scene must be set in Project Settings under Application then Run
- CharacterBody2D for monkeys, not RigidBody2D, you want direct control
- TileMapLayer for level geometry
- Area2D for vine anchors, banana pickups, attack hitboxes
- Player in its own scene file and instanced, required for MultiplayerSpawner
- Stats as a Resource file per monkey, not hardcoded, so balancing does not require code changes
- Headwear attachment point on the sprite rig from day one
