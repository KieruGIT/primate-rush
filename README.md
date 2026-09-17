# Monkey

A 2D multiplayer party game about monkeys. Run, climb, swing, and knock each
other around. **Nobody dies.** There is no health bar and no elimination —
hitting someone costs them progress and time, never a life. That rule is the
design spine: rounds stay short, everyone plays the whole round, and the skill
is in movement recovery rather than survival.

Engine: **Godot 4.7**, Compatibility (OpenGL 3) renderer, GDScript only.

---

## Running it

1. Open the project folder in Godot 4.7.
2. Press F5. The main scene is `scenes/Boot.tscn`, which opens the lobby.
3. **Play solo** for movement testing, or **Host** on one machine and **Join**
   from another on the same network using the IP shown on the host's screen.

### Controls

| Action | Keyboard | Touch |
|---|---|---|
| Move | A / D or arrows | left-hand stick |
| Climb, rope up/down | W / S or up/down | left-hand stick |
| Jump, release vine, wall jump | Space | JUMP |
| Attack | J | HIT |
| Skill | K | SKILL |
| Leave match | Esc | — |

Climb and swing are **contextual**: touch a climbable surface while pushing
into it and you climb, pass a vine in the air and you grab it. They get no
button, which keeps the phone layout down to a stick and two buttons.

---

## What is built

| Feature | State |
|---|---|
| Run, jump, coyote time, jump buffer, variable jump height | done |
| Climb on climbable surfaces, wall jump off them | done |
| Vine swing: pendulum, pumping, rope length, timed release | done |
| Normal attack, randomized slap/punch/kick flavor | done |
| Knockback scaled by attacker Power against target Weight | done |
| Stun on hit, drops you off vines and walls | done |
| Respawn on fall with per-player checkpoints, no death, no health | done |
| Stat block system driving all five axes | done |
| Three monkeys (gorilla, gibbon, macaque) | done |
| LAN multiplayer, host authoritative, up to 4 | done |
| Touch controls | done |
| Character select, map and mode select, lobby, results | done |
| Race mode: countdown, checkpoints, placement, results | done |
| Map A horizontal run and Map B vertical ascent | done |
| One skill per monkey | done |
| RevenueCat purchase unlocking a monkey | wired, needs a key and a device |
| Banana Hoard: timer, scoring, drop on hit, lucky boxes | done |
| Art, audio, ranked, cosmetics | not yet, by design |

## Repository layout

```
scenes/      Boot, Lobby, Main (arena shell), Player, Vine, Climbable, Checkpoint,
             FinishLine, Hud, Results, TouchControls
scenes/maps/ MapA (horizontal run), MapB (vertical ascent)
scripts/
  autoload/  GameConfig (constants, roster), GameInput (devices), Net (LAN), Purchases (RevenueCat)
  player/    Player.gd (movement, climb, swing, combat), MonkeyStats, InputFrame
  world/     Main.gd (arena, respawn, snapshots), RaceDirector, HoardDirector,
             MapData, Vine, Climbable, Checkpoint, FinishLine, Pickup, BananaSpawn
  ui/        Boot router, Lobby, Hud, TouchControls
resources/monkeys/   one .tres per monkey, balancing without code changes
docs/        design document and build brief
tools/       check_project.py, static checks the engine only does at runtime
```

## Design notes worth knowing before editing

**Input is a struct, not a device.** Nothing in `Player.gd` reads a key or a
touch. It consumes an `InputFrame`, which keyboard, touch, and the network all
produce. That is what lets local and networked play share one code path
instead of two that drift apart.

**The host is truth.** The host simulates every monkey. A client simulates
only its own as prediction and snaps when the host disagrees by more than
64px. Hits and knockback resolve on the host only — knockback that disagrees
between machines is the one desync in this game that reads as broken.

**No MultiplayerSpawner or MultiplayerSynchronizer.** Both store their
configuration inside scene files, which puts netcode in a `.tscn` that cannot
be reviewed in a diff. Spawning and snapshots are explicit in `Net.gd` and
`Main.gd` instead.

**Attack flavors are cosmetic and must stay that way.** Slap, punch, and kick
share range, knockback, stun, and cooldown. The moment a kick outranges a
slap, players fish for an animation they cannot choose.

**Skills dispatch on a stat id, not a subclass.** A monkey is a `.tres` plus
one branch in `_try_skill`. Adding the capuchin is data entry and one case,
not a new script that re-implements movement.

**The banana drop is not optional.** Hitting someone knocks a share of their
bananas loose for anyone to grab. Without it players farm separate corners
and a party mode becomes a single player game with witnesses.

**Stats are data.** Balancing is editing a `.tres` in the inspector. A stat of
1.0 means "the base value in `GameConfig`", which makes the macaque the
reference monkey and every other number readable as a percentage of it.

## RevenueCat

Store code is guarded by `Engine.has_singleton("GodotxRevenueCat")` and runs in
stub mode everywhere the plugin is absent, so desktop development never touches
the store. To wire it up on device:

1. Install the GodotX RevenueCat plugin and enable it.
2. `Project > Install Android Build Template`, tick **Use Gradle Build** in the
   Android export preset, and enable the plugin there.
3. Copy `secrets.cfg.example` to `secrets.cfg` and paste your **Test Store**
   API key. `secrets.cfg` is gitignored; the key never goes in source.

Test Store, not Google Play Billing: it needs no Play Console account and still
produces real entitlements and dashboard rows.

## License

MIT. See [LICENSE](LICENSE).
