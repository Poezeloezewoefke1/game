# Network rules and threat model

## Transport

| Item | Value |
|---|---|
| Library | Godot high-level multiplayer over `ENetMultiplayerPeer` |
| Protocol | ENet over **UDP** |
| Default port | **7000** (configurable in the main menu) |
| Topology | Listen server: the host plays and is also the authority |
| Maximum players | **4**, host included |
| Supported use | LAN and direct IP |

`ENetMultiplayerPeer.create_server()` is deliberately opened with **two sockets
above** the player cap. ENet would otherwise refuse the fifth connection at the
transport layer, and the player would see nothing but "connection failed". With
the extra room the host accepts the socket, answers with *"The session is full
(4/4 players)."*, and only then closes it.

That message is also why disconnects are **delayed** by
`NetworkManager.KICK_FLUSH_DELAY`. RPCs are written to the transport when the
multiplayer layer flushes at the end of a frame; closing the socket in the same
frame as the rejection throws the message away. The delay is the difference
between a player knowing the lobby is full and a player staring at a silent
failure.

## LAN discovery

The host broadcasts a small announcement on **UDP 7001** once a second so that
players on the same network can pick the session out of a list. Discovery is
deliberately on its own port: it is an unauthenticated broadcast and has no
business sharing a socket with the session itself.

The payload is a plain delimited string, not a serialised Variant. That is a
security decision - a broadcast anyone can send is the wrong place to have a
deserialisation step. Every field is validated individually, oversized packets
are discarded unread, and the browser is capped at 32 entries so a flood cannot
grow it without bound.

**The host's address is taken from the UDP source address, never from the packet
body.** An announcement therefore cannot claim to come from somewhere it did
not, which removes the obvious way to lure players onto a machine of the
sender's choosing.

The host's display name is sent as the LAST field and parsed with a split limit,
so a player called `Bo|b` cannot shift the port and player-count fields.

### What discovery does not do

Broadcasts do not cross routers. Discovery finds sessions on the local network
and nothing else; it is not a server browser and there is no central list.

### Known discovery limitations

* **Announcements are unauthenticated.** Anyone on the network can advertise a
  session, including one pointing at their own machine with an appealing name.
  On a home LAN this is not meaningfully different from someone telling you the
  wrong IP address. On an untrusted network, join by code instead.
* **One listener per machine.** The browser binds a fixed port, so a second copy
  of the game on the same computer cannot browse. It says so and falls back to
  joining by code or address, rather than showing an empty list.
* **The count and status can be a second stale**, since they are only as fresh
  as the last announcement.

## Join codes

A code like `NOVA-7K3M` **is** the address, packed into eight characters -
32 bits of IPv4, or 48 bits with a non-default port, in Crockford base32 plus a
position-weighted checksum character.

There is no lookup and no server. That is what makes it free: nothing to host,
nothing to keep alive, no account.

It follows that **a code cannot make an unreachable host reachable**. A code for
a public address still needs that host to forward the game's UDP port, exactly
as typing the address would. Codes remove typing mistakes, not NAT. The lobby
labels each generated code with which of the two situations it is for.

The alphabet excludes I, L, O and U, and decoding folds those back to 1, 1, 0
and V, so a code read aloud over voice survives being misheard. The checksum is
position-weighted so a transposed pair is rejected rather than silently
resolving to a different host.

## What is explicitly NOT supported

Stated plainly so nobody plans around a feature that does not exist:

* No NAT traversal, no relay servers, no matchmaking, and no global server
  browser. LAN discovery finds sessions on your own network only.
* Join codes are an encoding of an address, not a name registered anywhere. They
  do not make a host reachable that was not already reachable.
* No dedicated server. The host plays.
* No host migration. If the host leaves, the session ends for everyone.
* No reconnection or rejoin. A dropped player cannot return to a mission in
  progress; joins are refused once the session has started.
* No encryption or authentication of the game protocol. Anyone who can reach
  the port can attempt to join. Do not expose it to the open internet.

## Authority

The host is authoritative over connection acceptance, name validation, lobby
membership and readiness, permission to start, scene transitions and the
readiness barrier, mission state, objective state, crystal existence, ownership
and placement, pedestal and altar activation, Star Map pickup/ownership/drop,
Sentinel spawning, targeting, AI, projectiles, hits and stagger, player health,
the downed state, revive progress and completion, extraction, victory, failure,
cleanup, disconnect resolution and session reset.

Clients are **never** trusted to report health, damage, hit results, inventory,
crystal ownership, pedestal activation, Star Map ownership, position for a
critical interaction, blaster cooldown or heat, Sentinel stagger, revive
completion, extraction, victory, failure, or scene-transition completion.

Clients *are* trusted with their own presentation: their camera, their
interpolation, and their own movement input, bounded by the plausibility check
below.

## RPC categories

| Category | Declaration | Enforcement |
|---|---|---|
| Client request | `@rpc("any_peer", "call_remote", "reliable")` | First line proves the receiver is the host; then sender identity, rate limit, epoch, and the rules |
| Host broadcast on a host-authority node | `@rpc("authority", ...)` | Enforced by Godot |
| Host message on a **client-authority** node (the player) | `@rpc("any_peer", ...)` | Explicit `_from_host()` sender check |
| Cosmetic | `unreliable` | Carries no gameplay meaning; a dropped packet costs a visual |

`server_relay` is left enabled because the client-authority `MotionSync` needs
the server to forward player transforms between clients. The consequence is that
a malicious client *can* send a packet addressed to another client. It gains
nothing: every request handler begins by proving it is running on the host, and
every host-originated message on a client-authority node verifies the sender is
peer 1. `get_remote_sender_id()` is set by the receiving peer's multiplayer
layer from the real transport peer and cannot be forged by the sender.

## What the host validates on every critical request

1. The requesting peer exists and is connected.
2. The peer is not already being disconnected (`is_peer_leaving`).
3. The peer owns the player it claims to act as.
4. The request carries the **current session epoch**.
5. The player is in a gameplay scene.
6. The player is alive and not downed.
7. The named object id exists in the host's own registry.
8. The object is in the current scene and session.
9. The object is in a valid state for the action.
10. The player is within `INTERACT_VALIDATE_DISTANCE` horizontally and
    `INTERACT_VALIDATE_HEIGHT` vertically, measured from the raw replicated
    position, not the smoothed one.
11. Line of sight is clear against world geometry, unless the object opts out.
12. Mission state permits the action (`MissionRules`).
13. Inventory permits the action.
14. Cooldown and rate limit permit the action.
15. The request is not a duplicate, stale, replayed or malformed one.

The range the host validates against is deliberately larger than the range the
client's prompt uses (`5.0 m` vs `3.2 m`). That gap absorbs the latency between
a player seeing a valid prompt and the host processing the request. It is small
enough not to be worth exploiting: reaching a crystal from five metres is not a
meaningful advantage over reaching it from three.

## Rate limiting

Per **peer** and per **channel**, so one player spamming interact cannot starve
their own weapon and one hostile client cannot starve anybody else.

| Channel | Requests/second | Abuse threshold |
|---|---|---|
| Interact | 8 | 6x for 3 s |
| Fire | 12 | 6x for 3 s |
| Revive | 10 | 6x for 3 s |
| Lobby | 4 | 6x for 3 s |
| Scene ack | 4 | 6x for 3 s |

Requests over the limit are dropped silently. A peer that floods far past it for
a sustained window is disconnected - verified end to end by the multi-process
check, which floods the host and asserts that exactly the flooding peer is
removed while the mission continues for everyone else.

Kicking is idempotent. Without that, every queued request from a flooding client
triggered another kick and another rejection RPC to a socket that was already
closing, producing `Unable to send packet on channel 0` for each one.

## Movement plausibility

Movement is client-driven, so the host samples each client's position every
`MOVEMENT_SAMPLE_INTERVAL` (0.5 s) and compares the distance travelled against
`GameConfig.max_plausible_travel(dt)` - sprint speed times a tolerance, plus a
fixed jitter allowance. Three consecutive violations teleport the player back to
the last accepted position.

The sampling window is long *on purpose*. A short window would let the fixed
jitter allowance dominate and permit repeated micro-teleports. The tolerance is
roughly twice sprint speed, which absorbs latency and slope-assisted descent
while remaining nowhere near enough to cross the map.

`host_full_reset()` re-baselines the validator, or a legitimate respawn teleport
would be read as cheating and the player would be snapped back to where they
died.

## Session epoch

Every fresh lobby, hub entry, descent, retry and return to lobby increments
`GameManager.session_epoch`. Every critical request carries the epoch it was
made under; anything else is rejected. This is what makes stale, replayed and
crafted requests a single solved problem rather than a per-feature concern.

## Display names

A display name is presentation only. Identity is always the peer id. Names are
sanitised on the host and again on receipt: control characters, DEL, zero-width
characters and Unicode direction overrides are stripped (the last of these can
be used to visually spoof another player's name), whitespace is collapsed,
length is clamped, and anything unusable becomes a deterministic
`Explorer-<n>` fallback. Names are rendered in plain `Label` nodes; where rich
text is ever used, `NameSanitizer.escape_markup()` must be applied.

Duplicate names are allowed. Nothing in the authority model may depend on names
being unique.

## Known security limitations

These are real and are not going to be fixed at this scope. They are listed so
nobody assumes otherwise:

* **No authentication.** Anyone who can reach the port can attempt to join. The
  protocol version check is a compatibility check, not a security control.
* **No encryption.** Traffic is readable and modifiable by anyone on the path.
  ENet DTLS exists and is not configured here.
* **The host is fully trusted.** A modified host can do anything. Play with
  people you trust.
* **Cosmetic state is not protected.** A modified client can hide the fog, see
  through walls, or misreport its own animation. None of it changes an outcome.
* **A modified client can still move oddly** within the plausibility envelope -
  no lag compensation model is perfect. It cannot teleport, and it cannot
  interact with anything the host does not agree it is standing next to.
* **Denial of service is only partly mitigated.** Rate limiting and kicking
  handle a flooding *game* client. They do nothing about raw socket-level flood
  from off-protocol traffic.
