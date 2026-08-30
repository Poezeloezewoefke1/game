# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-30

Joining without typing an IP address.

### Added

- **LAN session browser.** The host picks a session name; everyone on the same
  network sees it in a list on the main menu and clicks Join. No addresses, no
  ports, no forwarding. Built on a UDP broadcast and a dictionary with a
  timeout — there is no server anywhere.
- **Join codes.** The lobby shows a short code like `NOVA-7K3M` that *is* the
  address, packed into eight characters. The join field accepts either a code or
  a plain IP, so nothing that worked before stopped working.
  - The alphabet omits I, L, O and U, and decoding folds those back to 1, 1, 0
    and V, so a code survives being read aloud over voice chat.
  - The checksum is position-weighted, so a transposed pair is rejected rather
    than silently resolving to a different host. Both the single-typo and
    transposition cases are swept exhaustively in tests.
  - The lobby labels each code with whether it is for the local network or for
    the internet, because a code built from a private address cannot possibly
    work for a friend elsewhere and finding that out mid-session is worse than
    being told immediately.
- Session names are persisted between launches alongside the display name.

### Security

Discovery announcements are an unauthenticated broadcast, so the parser is
treated as an attack surface:

- The payload is a plain delimited string, never a serialised Variant — a
  broadcast anyone can send is the wrong place to have a deserialisation step.
- The advertised address comes from the UDP source, never the packet body, so an
  announcement cannot impersonate a different host.
- The host's display name is sent last and parsed with a split limit, so a
  player called `Bo|b` cannot shift the port and player-count fields.
- Oversized packets are discarded unread and the browser is capped at 32
  entries, so a flood cannot grow it without bound.

### Notes

`PROTOCOL_VERSION` is deliberately **not** bumped: no RPC, snapshot shape or
replicated node path changed. Discovery carries its own independent format
version, so a browser can still list — and grey out — a session running a game
build it cannot join.

Codes do not make an unreachable host reachable. A code for a public address
still needs that host to forward the port, exactly as typing the address would.
See `docs/KNOWN_LIMITATIONS.md` (LIMIT-003).

## [0.1.0] - 2026-08-30

First playable vertical slice: the complete mission *The Lost Signal*, from
lobby to victory, for one to four cooperative players.

### Added

**Mission**
- The Wayfinder Station Hub with four stasis-bed spawn points and a host-only
  Mission Terminal.
- The Nerava Landing Zone: drop pod, canyon, temple clearing, and the ruins,
  cave and grove branches, each holding one Power Crystal.
- The temple puzzle: three pedestals, each accepting exactly one crystal, and
  an altar that opens only on three distinct correct placements.
- The Star Map, with a full lifecycle — shielded, available, carried, dropped,
  recovered, extracted.
- The Sentinel: a floating guardian that hunts the Star Map carrier, fires
  slow energy bolts, and staggers for three seconds after ten validated hits.
- Victory and failure states, mission retry, and return to lobby.

**Systems**
- Host-authoritative multiplayer over ENet/UDP for up to four players, with a
  validated join handshake, protocol version check and a readable rejection for
  every refusal.
- A scene readiness barrier: the host waits for every peer to finish loading
  before spawning anyone, with a documented timeout.
- A session epoch that invalidates stale, replayed and crafted requests in one
  mechanism.
- A split authority model on the player — client-authoritative motion for
  responsiveness, host-authoritative health, downed state, revive and weapon
  heat.
- Host-side movement plausibility checking with corrective teleport.
- Per-peer, per-channel rate limiting, escalating to disconnection on sustained
  flooding.
- A heat-based blaster with host-validated cadence, heat and shot origin.
- Health, downed and three-second revive with cancellation on distance, line of
  sight, release, reviver downed, or disconnect.
- Display-name sanitisation, including stripping Unicode direction overrides
  that could be used to spoof another player's name.
- Original placeholder audio synthesised in code — no third-party assets.

**Tooling and documentation**
- A headless test runner covering compilation, scene instantiation, unit tests
  and integration tests: 533 assertions.
- A multi-process multiplayer probe running a real host, three clients and an
  over-capacity client as separate OS processes: 73 assertions.
- A navmesh-based reachability test proving every objective can actually be
  reached — this found an unwinnable level.
- `tools/check_structure.sh` for repository hygiene.
- GitHub Actions workflows for validation and Windows export, both pinned to
  Godot 4.5.1-stable with least-privilege permissions.
- Full documentation set: architecture, network rules, tech stack, traceability,
  test checklist, QA report, known limitations, build manifest, release
  checklist and repository setup.

### Fixed during development

Defects found by tests and logs rather than by hopeful reading. Listed because
they shaped the test suite; the full table is in `docs/QA_REPORT.md`.

- Interactables were wiped from the registry by the level that owned them,
  because Godot runs `_ready()` bottom-up — every interaction was rejected as
  "unknown object".
- The compile phase was blind to broken scripts: `load()` returns a non-null
  invalid `GDScript`, so a parse error passed as "0 failed".
- The Grove Crystal was physically unreachable behind the temple's back wall,
  making the mission unwinnable.
- The host could not send corrections to its own players, because a player
  node's multiplayer authority is the client and `@rpc("authority")` therefore
  excluded the host.
- The fifth player was dropped silently: the socket closed in the same frame as
  the rejection message, discarding it.
- A full lobby reported "the host has already started the mission" instead of
  naming the real cause.
- Scene transitions logged a despawn error per entity because despawns were
  announced after the next scene.
- A flooding client was kicked once per queued request, spamming ENet errors.
- The host never validated blaster cadence — only a rate limiter existed.
- The navigation readiness check passed instantly on a second visit to a level,
  so the first path query silently returned nothing.
- Two players reviving the same teammate crashed the host's revive tick,
  silently breaking revives for the rest of the mission.
- The test suite reported PASS while the engine was raising errors — GDScript
  cannot see them, so `tools/run_validation.sh` now greps the run log and fails.
  The gate was verified by reintroducing a real defect and confirming it fires.
- A downed teammate's revive bar hung on screen for the rest of the mission when
  the reviver was downed: the entry was erased directly, bypassing the only code
  that clears the bar.

### Known limitations

No host migration, no rejoin, no join in progress, no NAT traversal, no
authentication or encryption. The Windows build has never been launched, nothing
has been seen on a screen, and only loopback networking has been tested. See
`docs/KNOWN_LIMITATIONS.md` for the full list with reasoning.

[0.2.0]: https://github.com/Poezeloezewoefke1/game/releases/tag/v0.2.0
[0.1.0]: https://github.com/Poezeloezewoefke1/game/releases/tag/v0.1.0
