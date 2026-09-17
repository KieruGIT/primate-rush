# Build notes

Practical notes for taking this repo from a clone to something running on a
phone. Written for the hackathon path in `CLAUDE_CODE_BRIEF.md`, which means
LAN multiplayer, touch controls, a Test Store purchase, and a debug APK — not
a store launch.

---

## Verification status

**This code has not been run in Godot.** It was written in an environment with
no engine binary available, so treat the first editor launch as the real first
test. What *was* checked, by `python3 tools/check_project.py`:

- every `$NodePath` and `%UniqueName` a script uses exists in the scene the
  script is attached to
- every `ext_resource` path in every `.tscn` and `.tres` resolves
- every `preload()` target exists
- every autoload in `project.godot` exists

That covers the class of typo that otherwise surfaces halfway through a
two-phone LAN test. It does not catch a GDScript type error, a physics layer
mistake, or bad tuning. Run the checker before every commit; it is fast.

## First run checklist

1. Open the project in Godot 4.7. Let it import, then check the Errors tab
   before pressing anything.
2. F5. You should land in the lobby, not the arena: the main scene is
   `scenes/Boot.tscn`, which routes between them.
3. **Play solo** on Free play, Map A. Confirm in this order, because each one
   depends on the one before it:
   - running and jumping feel right, and a tapped jump is shorter than a held one
   - walking off a ledge and jumping late still jumps (coyote time)
   - jumping just before landing still jumps (jump buffer)
   - pushing into the wall around x=2150 starts a climb, jump kicks you off it
   - jumping into a vine grabs it, A/D pumps the swing, jump releases it
   - falling below the map respawns you at the last checkpoint after ~0.7s
4. Switch to Race. Confirm the countdown freezes input, the timer runs, and
   crossing the finish gives a placement and a results screen.
5. Switch to Banana Hoard. Confirm bananas spawn, collecting scores, and
   hitting a player scatters a share of theirs.

## Testing with bots

Solo play with bots is the fastest way to exercise everything without a
second device: set bots to 3 in the lobby, pick Race, and watch whether they
reach the finish. Bots that pile up against a wall mean the level geometry
has a jump the movement cannot make, which is a level bug, not an AI bug —
they use the same input path a player does, so if a bot cannot get past it,
neither can a person who is not already good at the game.

## Tuning

Everything worth tuning is an `@export` on the player or a `.tres` in
`resources/monkeys/`. The two numbers that move game feel the most, in order:

1. `fall_gravity_mult` on Player — heavier gravity on the way down is what
   makes the arc snappy instead of floaty.
2. `run_speed` via each monkey's `speed` stat.

Do not tune the attack flavors apart. Slap, punch, and kick must stay
mechanically identical; the moment one outranges another, players start
fishing for an animation they cannot choose.

## Two-machine LAN test

1. Both machines on the same wifi, or one phone hotspotting the other.
2. Machine A: **Host**. The lobby prints the address to type.
3. Machine B: type that address, **Join**. The roster should list both.
4. Machine A picks map and mode (clients cannot; the host owns the config),
   then **Start match**.
5. What to watch for, in order of how badly it breaks the game:
   - knockback that disagrees between screens (should be impossible: hits
     resolve on the host only)
   - a client's own monkey rubber-banding (prediction error over 64px snaps)
   - bananas visible on one screen and not the other (spawns are reliable RPCs)

## Android export

1. Install the Android SDK and a JDK, and set both paths in
   Editor Settings > Export > Android.
2. `Project > Install Android Build Template`.
3. Add an Android export preset and tick **Use Gradle Build**. Min SDK 24.
4. Export a debug APK. No Play Console, no release signing, no store listing.

`export_presets.cfg` is gitignored on purpose: it holds machine-specific SDK
paths and keystore locations.

## RevenueCat

Everything store-related is guarded by
`Engine.has_singleton("GodotxRevenueCat")` and falls back to a local stub, so
desktop development never touches the store and never crashes on a missing
plugin.

1. Install the GodotX RevenueCat plugin (AssetLib or the release ZIP) and
   enable it in Project Settings > Plugins, and in the Android export preset.
2. Create a RevenueCat project. A Test Store with products is created for you.
3. Copy `secrets.cfg.example` to `secrets.cfg`, paste the **Test Store** key
   (`test_...`, never `goog_...`), and leave the file gitignored.
4. On device, the lobby's unlock button runs a real purchase against the Test
   Store and unlocks the premium monkey through the `premium_monkeys`
   entitlement.

If the plugin's signal names have moved in a newer release, `Purchases.gd`
warns per missing signal rather than crashing at startup — check the output
log before assuming the SDK is broken.

## Known gaps

- No art, no audio, no animation. Monkeys are tinted rectangles that change
  colour per state, which is deliberate for now: state has to be readable
  before it is pretty.
- Client-side prediction has no input replay. A client that diverges snaps
  rather than re-simulating. Fine on a LAN, visible on a bad connection.
- Lucky box abilities are granted by the host and expire on a local timer, so
  a client can hold an ability a few frames longer than the host thinks.
- Ranked, accounts, and cosmetics are not started. They are correctly last in
  the design doc's build order and nothing here should pretend otherwise.
