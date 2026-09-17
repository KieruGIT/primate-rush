# Monkey - Claude Code Build Brief

Hand this file to Claude Code at the start of the session. It contains every
decision already made so you do not re-litigate scope or rediscover blockers.

---

## 0. Read This First

This is a **hackathon submission**, not a finished game. The goal is a working
Android build that demonstrates networked multiplayer and a completed RevenueCat
purchase, recorded on video. Polish, content volume, and feature completeness are
explicitly not goals.

If a task does not contribute to the demo video or the eligibility requirements,
it is out of scope. Do not suggest features from the full design doc.

**Deadline: September 30, 2026, 11:45 PM PDT.**

---

## 1. Environment

| Item | Value |
|---|---|
| Engine | Godot 4.7.2 stable |
| Project path | `D:\Game\monkey` |
| Renderer | **Compatibility (OpenGL 3)** - do not change |
| Dev GPU | NVIDIA GeForce 920MX |
| Target | Android, portrait-agnostic, landscape preferred |
| Language | GDScript only |

The dev machine's GPU does not support Direct3D 12 and fails on the Mobile and
Forward+ renderers. Compatibility is correct here and is also the widest-support
option for low-end Android devices. Do not "upgrade" the renderer.

---

## 2. Submission Category and Requirements

Entering the **RevenueCat Shipaton 2026 Next Gen Award** (student category).

What Next Gen requires:

- A working mobile app (Android)
- The RevenueCat SDK powering at least one purchase
- A demo video
- A public open-source repository with a license file
- Devpost submission before the deadline
- Verified student email

What Next Gen does **not** require:

- Google Play or App Store upload
- A paid developer account
- App review
- Any of RevenueCat's production launch checklist (tax forms, banking info,
  data safety disclosures, phased rollout). That checklist is for production
  store launches and does not apply.

---

## 3. Scope - Locked

**In scope:**

1. Core movement (run, jump, climb, swing)
2. Normal attack with knockback and stun
3. LAN multiplayer, host-authoritative, 2 to 4 players
4. Touch controls
5. RevenueCat Test Store purchase, one product, working end to end
6. Android export

**Out of scope for the hackathon:**

Rank system, cosmetics, five-monkey roster, per-monkey skills, Banana Hoard mode,
internet matchmaking, dedicated servers, ads, art pass, audio, menus beyond a
minimal lobby.

Two monkeys maximum if time allows. One is acceptable.

---

## 4. Current State

Already built and saved in the project:

```
scenes/Player.tscn      CharacterBody2D
                        |- Body (ColorRect, orange, 32x64)
                        |- Collision (CollisionPolygon2D)
                        |- Camera2D (position smoothing on)

scenes/Main.tscn        Node2D
                        |- Level (StaticBody2D)
                           |- ColGround / VisGround
                           |- ColPlat1  / VisPlat1
                           |- ColPlat2  / VisPlat2
```

Scripts written but possibly not yet attached: `scripts/Player.gd`,
`scripts/Main.gd`. Player.gd implements run, jump, coyote time, jump buffering,
and variable jump height using hardcoded key input.

**Verify before building:** that both scripts are attached to their scene roots,
and that Project Settings > Application > Run > Main Scene points at
`res://scenes/Main.tscn`.

---

## 5. RevenueCat Integration

### Plugin

Use **GodotX RevenueCat**: https://github.com/godot-x/revenuecat

- MIT licensed, targets Godot 4.7-stable, latest release 2.2.0 (June 2026)
- Ships prebuilt binaries, no compilation from source needed
- Bundles RevenueCat Android SDK 10.10.0
- Min Android SDK 24

### Install steps

1. Install via AssetLib (search "Godotx RevenueCat") or extract the release ZIP,
   which contains `addons/`, `ios/`, and `android/` folders for the project root
2. Enable the plugin in Project Settings > Plugins
3. `Project > Install Android Build Template`
4. In the Android export preset, tick **Use Gradle Build**
5. Enable GodotxRevenueCat in the export preset plugin list

### Use Test Store, not a real store

RevenueCat's **Test Store** is a built-in testing environment that works with no
platform setup. Test purchases update CustomerInfo, trigger entitlements, and
appear in the RevenueCat dashboard. No money changes hands, no Google Play
Console account is needed, no products to configure in a store.

Test Store requires `purchases-android` 9.9.0 or higher. GodotX bundles 10.10.0,
so this works.

Steps: create a RevenueCat project (a Test Store is created automatically with
products), then copy the **Test Store API key** from Project Settings > API keys,
and pass that key to `initialize()`.

Do not use a `goog_` key. Do not attempt Google Play Billing.

### API surface

The plugin exposes exactly these methods on the singleton:

`initialize`, `fetch_offerings`, `fetch_products`, `purchase`, `login`, `logout`,
`is_subscriber`, `has_entitlement`, `present_paywall`, `check_entitlement`,
`restore_purchases`

Signals: `customer_info_changed`, `purchase_result`, `offerings`, `products`,
`login_finished`, `logout_finished`, `subscriber`, `entitlement`,
`paywall_result`, `restore_finished`

### Minimal integration

```gdscript
extends Node

var rc = null

func _ready() -> void:
	if not Engine.has_singleton("GodotxRevenueCat"):
		push_warning("RevenueCat singleton missing - running in editor or plugin not enabled")
		return
	rc = Engine.get_singleton("GodotxRevenueCat")
	rc.purchase_result.connect(_on_purchase_result)
	rc.entitlement.connect(_on_entitlement)
	# Test Store API key. Never ship this key to a real store.
	rc.initialize("test_XXXXXXXXXXXX", "", true)

func buy() -> void:
	if rc:
		rc.purchase("your_test_product_id")

func _on_purchase_result(result) -> void:
	print("purchase result: ", result)

func _on_entitlement(info) -> void:
	print("entitlement: ", info)
```

### Known gotchas

**GDScript has no C-style ternary.** The plugin README uses
`OS.get_name() == "iOS" ? "appl_x" : "goog_x"`, which will not parse. Android-only
here, so just hardcode the Test Store key.

**No ads API.** The plugin wraps purchases and paywalls only. RevenueCat Ads is a
beta AdMob adapter requiring Google Mobile Ads SDK 22.0.0+ and an AdMob account
with impression-level ad revenue enabled. It is not reachable from this plugin.
Do not attempt ads. Purchases via Test Store satisfy the same requirement.

**The singleton does not exist in the editor.** Guard every call with
`Engine.has_singleton()` or the desktop build crashes during development.

---

## 6. Multiplayer

### Architecture

Godot high-level multiplayer API over ENet. Host-authoritative peer-to-peer on a
local network. 2 to 4 players.

- Host runs all physics, knockback, and collision resolution
- Clients send input only, never authoritative position
- `MultiplayerSpawner` for player instances
- `MultiplayerSynchronizer` for position, velocity, and state enum

### Connection method

**Default to manual IP entry.** A text field for the host IP plus Host and Join
buttons. Roughly 20 lines, no discovery protocol, works on any network including
a phone hotspot.

If time remains after everything else works, add UDP broadcast LAN discovery so
the join screen lists hosts automatically. This films better but is optional.

### Why LAN is sufficient

Next Gen is judged on a demo video and source code, not a live service. Two
phones on the same wifi or a hotspot is a filmable demo. Do not build matchmaking,
NAT traversal, relay servers, or dedicated hosting. That work does not fit the
deadline and is not evaluated.

### Sync risk

Swing physics simulated independently per client will drift. The host must
simulate all swing physics and all knockback resolution, sending resulting
positions to clients. Do not let clients resolve their own collisions.

---

## 7. Touch Controls

Keyboard input in `Player.gd` is a prototype placeholder. Android needs:

- Virtual joystick or left/right buttons for horizontal movement
- Jump button
- Attack button
- Climb and swing should be contextual rather than dedicated buttons, triggering
  automatically on surface or vine contact, to keep the touch layout small

Move input off hardcoded `Input.is_key_pressed` and onto the InputMap once
multiplayer needs per-device separation, or onto a small input abstraction layer
that both touch and keyboard feed into. Keyboard should keep working for desktop
testing since iterating on a phone is slow.

---

## 8. Android Export

Requirements: Android SDK, a JDK, Godot export templates, and a debug keystore.
Roughly one hour of first-time setup, then a one-click APK.

Gradle build must be enabled for the RevenueCat plugin to work. Min SDK 24.

No Play Console, no signing for release, no store listing. A debug APK plus the
demo video is the deliverable.

---

## 9. Build Order

Sequenced by risk. The riskiest unknown goes first so a failure is discovered on
day one rather than day eleven.

1. **De-risk RevenueCat.** In an empty throwaway Godot project, install the
   GodotX plugin, build an APK, install on a phone, and complete one Test Store
   purchase. Do not write game code until this works. If it fails, the whole
   submission plan changes.
2. **Android export of the current prototype.** Confirm the existing Player and
   Main scenes build and run on a device.
3. **Touch controls.** Movement must be playable on a phone before netcode, since
   testing multiplayer means two phones.
4. **LAN multiplayer.** Host and join by IP, two players moving in the same world.
5. **Attack, knockback, stun.** Host-authoritative.
6. **Climb and swing.** Host-simulated.
7. **RevenueCat wired into the real project.** One purchase, one entitlement that
   unlocks something visible, for example a second monkey or a colour.
8. **Minimal lobby UI.** Host, join, start.
9. **Record the demo video.**
10. **Clean the repo, add a LICENSE, write the README, submit on Devpost.**

Steps 1 and 2 should both be done on day one.

---

## 10. Repository

Public, open source, with a license file, since Next Gen judges source code.

Confirm `.gitignore` excludes `.godot/`, which is rebuildable cache. Commit early
and commit often. The networking phase will break things repeatedly and a working
commit to reset to is the difference between a bad afternoon and a dead project.

Do not commit the RevenueCat API key if it is ever swapped for a real one. The
Test Store key is low risk but treat it as a secret out of habit.

---

## 11. Style Notes for Generated Code

- GDScript, static typing where practical (`var x: float = 0.0`)
- Tabs for indentation, matching Godot convention
- Tuning values as `@export` variables so they can be adjusted in the inspector
  without code changes
- Comments explain why a value or approach was chosen, not what the line does
- Guard every RevenueCat call with `Engine.has_singleton()`
- Guard every multiplayer authority branch explicitly rather than assuming
