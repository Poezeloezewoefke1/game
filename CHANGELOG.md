# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-09-01

### Changed

- **The game is now first person.** The spring-arm chase camera is gone; the
  camera sits at eye height inside the body, which is hidden for its owner and
  drawn for everyone else. A viewmodel blaster is held in front of it, and its
  energy coil and vent glow with the weapon's heat, so the overheat readout is
  visible without looking at the HUD.

### Fixed

- **Every hand-built mesh in the game was inside-out, and had been from the
  first commit.** Godot treats a *clockwise* triangle as front-facing;
  `MeshFactory._add_polygon` emitted counter-clockwise, so the outward faces
  were culled and what you actually saw was the unlit inner surface of the far
  side of every wall, floor, rock, crystal and prop.

  It never looked like a geometry bug. Silhouettes, collision, navigation,
  physics and every headless test were unaffected; the only symptom was that
  levels were extremely dark and flat, which reads as a lighting problem. The
  hunt went through light attenuation, per-object light limits, tonemapping,
  material metallic values, tangents, mesh compression and face tessellation
  before an A/B against Godot's own `BoxMesh` — identical size, material and
  lamp, one lit and one black — and a shader drawing the raw normal made it
  unambiguous.

  `tests/unit/test_mesh_factory.gd` now reads the convention back off Godot's
  `BoxMesh` and `PlaneMesh` rather than asserting a remembered rule, and checks
  every generated mesh against it. The old winding check compared the stored
  normal to the shape's centre, which is true by construction in the builder and
  so could never have failed.

- A muzzle flash shorter than one frame expired before it could be drawn, so
  below roughly 18 fps the player got no feedback at all for their own shots —
  exactly when the game is struggling. It now guarantees one rendered frame.

- Hull surfaces sat at `metallic` 0.45–0.75. A metal surface has no diffuse
  response; it shows reflected environment, and a sealed room lit by a flat
  background colour has none, so those walls rendered near-black. They are
  painted panels, which are dielectric, and are now valued accordingly.

- Hub ceiling lamps delivered about 6% of their energy to the floor. Godot's
  omni falloff divides by `pow(distance, omni_attenuation)`, and 1.4 over 7.4 m
  is a rounding error.

### Added

- `scripts/utility/mesh_factory.gd` — chamfered boxes, faceted crystals,
  irregular rocks and tapered columns, built with `SurfaceTool` and shared
  through a cache. Replaces the engine's `BoxMesh`/`PrismMesh` primitives.
- `scripts/utility/prop_builder.gd`, `model_kit.gd` and `prop_scatter.gd` —
  multi-part pedestals, altars, terminals, the drop pod and the Sentinel, plus
  deterministic set dressing. The scatter is seeded and hand-bounded: level
  layout and every gameplay object remain authored, not generated.
- `scripts/player/player_body.gd` — a multi-part astronaut with a team-coloured
  accent, replacing the capsule.
- `scripts/player/view_model.gd` and `muzzle_flash.gd` — the first-person
  weapon, its bob, sway and recoil, and the flash at the barrel. The flash is
  driven by the host's tracer RPC, never by the local trigger press, so it
  cannot show a shot the host rejected.
- Head bob, a landing dip, sprint FOV, damage shake and a small firing shake.
- Ceiling light fixtures in the hub, and a warm key against the ship's cold
  cyan accents.
- `tools/screenshot.gd` and `tools/capture_screenshots.sh` — renders the real
  game to PNG under Xvfb with a software rasteriser. This is what turned the
  visual work from guesswork into a feedback loop, and what found four of the
  defects above.
- `tests/unit/test_mesh_factory.gd` (64 assertions) and first-person structural
  assertions in `tests/integration/test_app_shell.gd`.

## [0.2.1] - 2026-08-30

### Fixed

- **The player could not move, look, shoot or interact once the hub loaded.**
  The lobby set the mouse to `VISIBLE` and nothing captured it again on the
  scene change; the player treats an uncaptured mouse as "a menu is open" and
  skipped all input. Pressing Escape twice happened to fix it, which made it
  look intermittent.

  Mouse mode had four writers spread across three screens and `UIRoot`. It now
  has exactly one, re-evaluated every frame, which removes the whole class of
  "some path forgot to update it" rather than patching the one path that was
  missing.

- Tearing down during a scene transition called a method on a node the teardown
  had already freed. A freed Node in Godot 4 is not `== null`, and cannot even
  be passed to a parameter typed as `Node` - the argument check throws first.

### Added

- `tests/integration/test_app_shell.gd`, which drives the real `main.tscn`
  shell. That shell had **no** test coverage, which is exactly why the movement
  bug shipped: every other test binds its own roots and bypasses it. The gate
  was verified by reintroducing the defect and confirming the test fails on
  "entering the hub captures the mouse, so the player can actually move".

### Note for future work

The broken check short-circuits to `false` under a headless display server, so
the tests were skipping the exact line that was wrong. Anything guarded by
`DisplayServer.get_name() == "headless"` is untested by construction and should
be treated with suspicion.

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

[0.2.1]: https://github.com/Poezeloezewoefke1/game/releases/tag/v0.2.1
[0.2.0]: https://github.com/Poezeloezewoefke1/game/releases/tag/v0.2.0
[0.1.0]: https://github.com/Poezeloezewoefke1/game/releases/tag/v0.1.0
