# Multiplayer: what works, and how far it can go

## Current decision (Shipaton build): no matchmaking

For the submission the game ships **without online matchmaking**. Decided
2026-09-24.

- **PLAY** goes straight to the monkey pick and fills every empty seat with
  AI. The old "SEARCHING" screen, which listened on the LAN for a few
  seconds before giving up and adding AI, was removed: nobody was ever found,
  so it was only a wait.
- **Playing with friends** is done from the **PARTY** page (host, or join by
  the hosts list or an IP), same network or over UPnP / Tailscale, as below.
  Once friends are in your room, PLAY starts for everyone.
- The search code is kept, unused: `Matchmaker.begin()` in
  `scripts/ui/Matchmaker.gd`. Bring it back only together with a real
  matchmaking backend (section 5), since a LAN-only search finds nobody.


Short answer: **yes, multiplayer works, and playing over the internet is
possible without paying for anything.** What it costs is reliability — the
free routes fail on some networks and there is no way around that without a
server. Here is the honest ladder, cheapest first.

---

## 1. Same network — works today, nothing to configure

Both devices on the same wifi, or one phone hotspotting the other. Host on
one, and the other either taps the host in the **Hosts on this network** list
(UDP broadcast discovery) or types the IP the host screen prints.

This is what the game is built around and what the demo video only needs.
Reliability: high. The one failure mode is a network with client isolation
(most guest wifi, some hotels), where devices cannot see each other at all.

## 2. Over the internet, automatic — the UPnP button

Host, then press **Open this game to the internet (UPnP)**. The game asks the
router to forward UDP 27015 and reports back the public address to share.
Whoever is joining types that address in the IP field.

No server, no cost, no accounts. It is a real option and it is already built.

It fails, by design rather than by bug, when:

- **UPnP is turned off on the router.** A common and defensible default; it
  can usually be enabled in the router admin page.
- **The host is behind carrier-grade NAT.** The host shares a public address
  with hundreds of other customers and has nothing to forward. This is most
  mobile data, and increasingly some home ISPs. Nothing on the host's side
  can fix it. Symptom: the port maps "successfully" but nobody can connect,
  or the reported address starts with `100.64.`–`100.127.`
- **Campus, office or public networks**, where forwarding is blocked
  deliberately.

The lobby prints the reason rather than failing silently.

## 3. Over the internet, manual — port forwarding

Same idea without UPnP: in the router admin page, forward **UDP 27015** to the
hosting machine's local IP, then share the public address (from any
"what is my IP" site). Works wherever UPnP would have, plus routers that have
UPnP disabled. Same CGNAT limitation.

## 4. Over the internet, guaranteed-ish — a VPN overlay

Install Tailscale or ZeroTier on both machines and join the same virtual
network. Every device then has a stable private address and behaves as if it
were on one LAN, so **the game needs no changes at all**: host, and the other
side types the Tailscale address.

This is the most reliable free option, it defeats CGNAT, and it costs zero
code. The catch is that both players have to install it, which is fine for
friends and useless for strangers.

## 5. Strangers, matchmaking, no setup — needs a server

Everything above needs someone to know someone's address. Beyond that you
need infrastructure, and there is no free version that is also reliable:

| Approach | What it takes | Ongoing cost |
|---|---|---|
| Relay server (host a headless Godot build or a small UDP relay) | A VPS, a deploy pipeline, and code to route packets | Server bill |
| Hole punching with a rendezvous server (e.g. Noray) | A small always-on coordinator, plus client code | Small server bill |
| Managed service (Nakama, Photon, Playroom) | An SDK, an account, per-player limits | Free tier, then paid |
| Steam P2P (GodotSteam) | Steam app ID, desktop only | One-off fee |

All four are out of scope for the hackathon brief, which is judged on a demo
video and source code, not a live service. They are also the right thing to
build *last*, after the game is proven fun, because matchmaking for a game
nobody is playing yet matches nobody against nobody.

---

## What the code already does for you

None of the above changes the netcode, because the netcode never assumed a
LAN. It is Godot's high-level multiplayer over ENet with the host as
authority, and an ENet connection does not care whether the address is
`192.168.1.20` or a public one.

The pieces that matter if you do go further:

- **Host authority is already absolute.** Movement, hits, knockback,
  pickups, scores and placement all resolve on the host and are replayed to
  clients. A relay or a dedicated server would slot in where the host is now
  without rewriting gameplay.
- **Input is already a struct on the wire** (`InputFrame`), not a device
  read, so a server build that has no window and no keyboard still works.
- **Latency assumptions are LAN-shaped.** Clients predict their own monkey
  and snap past 64px of error, with no input replay. That is fine at 5ms and
  visible at 80ms. Real internet play wants rollback or at least
  re-simulation, which is a real piece of work — budget it as its own
  project, not an afternoon.
- **Player count** is capped at 4 in `GameConfig.NET_MAX_PLAYERS`. The design
  doc wants 8 for Race; raising it is one constant plus a playtest, since
  nothing else is hardcoded to four.

## Recommended path

1. Ship the LAN demo. It is done, and it is what the submission needs.
2. If you want to play with friends: UPnP button, or Tailscale when that
   fails. Both are free and need no work from you.
3. Only build a relay if there is an actual playerbase asking for it.
