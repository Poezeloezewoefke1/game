# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-09-02

### Added

- **A UI theme**, built by `tools/generate_ui_theme.gd` and set as the project's
  default so every Control picks it up - including screens added later without
  anyone remembering to assign it. Buttons carry a left accent bar rather than a
  full outline, inputs get an accent underline on focus, and labels have named
  variations (`TitleLabel`, `HeadingLabel`, `WarningLabel`...) so a scene says
  what a label IS instead of repeating a pile of overrides. Every label that
  sits over the game has a black outline, because white text on a sunlit dune is
  invisible without one.
- **The game's own sky behind the menus.** `scripts/ui/sky_backdrop.gd` renders
  the deep-space shader into a small offscreen viewport that drifts slowly
  behind the main menu, the lobby and both end screens, under a veil that keeps
  panel text readable when the galactic core passes behind it. The menus were
  sitting on a flat dark rectangle while the game already had a starfield and a
  ringed gas giant written and paid for.
- **`tools/render_ui.sh`**, which photographs all six screens. The in-game
  screenshot rig binds its own roots and never mounts the interface, so the
  menus, the lobby and the HUD had **never been looked at once** - which is half
  of what a player spends the mission looking at, and it turned out to be the
  weakest thing in the game by a distance.
- `hud.gd::preview_state()`, which fills every widget with representative
  mid-mission state so the HUD can be photographed without a live session. A HUD
  shot at full health with nothing carried and no objective shows the one state
  that tells you nothing about whether the HUD works.

### Changed

- **The HUD.** Health and heat are now coloured bars - green through amber to
  red, with the crossovers at the points where a player's decision actually
  changes - grouped into a panel instead of floating loose over the bottom-left
  corner. A bar you have to read the number off is a bar that failed.
- **The crosshair** is four ticks around a gap rather than a single dot. One
  pixel disappears over a bright dune and says nothing about where the weapon is
  pointing.

### Fixed

- The crosshair's ticks were positioned from the control's origin, but the
  control is a 16 px box whose top-left sits eight pixels up and left of screen
  centre - so the whole reticle was off-centre. They are anchored to the
  parent's centre now.
- Each `ProgressBar` fill is its own `StyleBoxFlat`. Tinting the shared theme
  resource would have tinted every bar in the game at once.

## [0.5.0] - 2026-09-02

### Added

- **A deep-space sky.** `shaders/deep_space_sky.gdshader` draws a four-layer
  starfield with a realistic magnitude skew and stellar colour classes, the
  galactic band with dust lanes and a brightened core, two nebulae, and the
  system's star.
- **Planets that are actually spheres.** Each body is intersected with the view
  ray per pixel, so it has a real terminator, limb darkening, an atmospheric rim
  that only lights where it is edge-on, banded cloud belts with a storm oval, an
  ocean world with coastlines and its own cloud deck, a cratered moon, and a
  ring system whose far half passes BEHIND the planet and which casts a curved
  shadow across the disc that moves with the light. A billboard cannot do any of
  that.
- **Real photographs are a drop-in.** Every planet has an `albedo` slot and a
  `use_photo` flag; assigning an equirectangular map replaces the generated
  surface and keeps the same lighting, terminator and rings. See
  `docs/ASSET_PROVENANCE.md`.
- **A generated PBR texture set**, `tools/generate_textures.gd`: seamless
  albedo, normal and roughness maps for rock, sand, hull and moss, a metallic
  map for hull, and a shared detail normal. The hull map has panel seams,
  rivets, scratches and rust creeping out of the joins.
- **`shaders/surface.gdshader`**, which every piece of level geometry now uses:
  world-space triplanar projection so texture is continuous ACROSS blocks
  rather than restarting at each one, a slope-driven second material so dust
  collects on upward faces, a detail normal faded in close to the camera, and
  macro tint variation to break up repeats.
- **Three effect shaders.** A crystal that is brighter at its edges than through
  its middle, which is a Fresnel term no emissive material reproduces; a
  hologram that is additive, depth-write-off and scanlined in world space so
  the lines stay put as the armillary turns; and a hex-cell energy field for
  the pedestal beams and the altar shield.
- **`scripts/utility/set_dressing.gd`** - seventeen kinds of hand-placed
  clutter: crate stacks, barrels, pipe runs, floodlights, antenna masts, cable
  spools, lockers, consoles, hazard barriers, wreckage, pallets, vent stacks,
  banners, broken pillars, rubble, braziers and carved stelae. **56 pieces**
  placed across the two levels.
- The hub's window now looks out at the real sky. The painted backdrop and its
  four fake stars were removed - they were what stood in front of it.

### Fixed

- **A brazier placed on the grove corridor's centre-line stopped clients ever
  reaching the Grove Crystal.** Found by the multi-process check, which walks
  the authored routes as a player does.
- Set dressing with collision was parented outside `NavigationRegion3D`, so the
  navigation mesh was baked as though the corridors were empty: pathfinding and
  the reachability test both believed a blocked route was clear. Dressing now
  lives inside the region and bakes into the mesh, so collision and navigation
  agree and the Sentinel paths around props.
- `test_level_reachability` gained a corridor-clearance check, because **"a path
  exists" and "the corridor is clear" are different claims** and only the second
  describes what a player does. The grove corridor is 12 m wide, so a navmesh
  path simply routed around the obstruction while a player walked into it. The
  new check names the offending prop when it fails.
- `_set_emission` replaced any material it was handed with a `StandardMaterial3D`,
  which would have silently undone every crystal and hologram in the level the
  first time its state refreshed. It now recognises the effect shaders and
  drives their parameters instead.
- Hull surfaces came back from the texture pass looking wet: the metallic values
  predated the textures and the roughness map's scratches dip to 0.16. Metallic
  dropped to dielectric values for painted panels, and roughness is clamped at
  0.22 - nothing in this game is a mirror.
- The detail normal at 2.4 repeats per metre aliased into glitter over every
  hull surface. Softened and pulled in closer.

## [0.4.0] - 2026-09-01

### Added

- **A studio model gallery.** `tools/render_models.sh` photographs every model
  in the game one at a time on a neutral sweep under three-point lighting, at a
  fixed three-quarter angle. In-game screenshots show whether a scene works;
  they are almost useless for judging a model, which is half-lit, half-occluded
  and thirty metres away. Every model below was rebuilt against this.
- Five new primitives in `MeshFactory`: `sphere`, `capsule`, `tube`, `wedge`
  and `torus`. Limbs need capsules with spheres at the joints, a barrel needs a
  bore you can see down, and a ring needs to be a ring. `_add_polygon` now
  takes the point a face should turn its back on, which is what makes the
  hollow shapes possible without giving up the solved-winding rule.

### Changed

- **The explorer** is now an astronaut rather than a stack of boxes: boots with
  toes and ankle cuffs, capsule limbs with sphere joints, a segmented torso, a
  neck ring, an egg-shaped helmet with a dark visor lens and lamps, a life
  support pack with open-ended tanks, and the team colour on a harness instead
  of two horizontal slabs that read as shelves.
- **The blaster** gained the four things that make a gun read as a gun: a bore,
  a trigger group inside a guard, a magazine, and a break in the silhouette
  between receiver and barrel. Its three coil rings are the heat readout and
  are now outside the shroud, where they can actually be seen.
- **The Sentinel** is a fixed armoured head inside a rotating gyro ring: a
  caged core, a hooded sensor with mandibles, thruster pods, and six armour
  plates bolted to a continuous ring. Previously loose slabs orbiting a rock.
- **The drop pod** is a landed craft - domed nose, beacon, hull banding, a
  recessed hatch with a porthole and chevrons, legs with shock absorbers and
  splayed feet, engines underneath.
- **The Star Map** is an armillary: a lit core inside three gimbal rings at
  different angles, with graduations and a polar axis. It was a `TorusMesh`,
  the last engine primitive left in the game.
- **The pedestal, altar and terminal** were rebuilt as carved masonry and a
  real console: stepped octagonal bases, fluted columns, a cradle the crystal
  sits in, a rune ring, caged crystals on the altar posts, and a keyboard with
  actual keys under a hooded screen.
- **Boulders** are chiselled and flat-bottomed rather than jittered spheres, so
  they sit on the ground instead of hovering just above it.
- **Foliage** is a three-lobed bush on a stem. It was `rock()` in green, which
  wasted one of only five kinds of set dressing on a duplicate of another.

### Fixed

- **Small shapes were silently building EMPTY meshes.** `_add_polygon` judged a
  polygon degenerate against a fixed 1e-6, which is an area in square metres: a
  2 cm x 1 cm quad is under it. Every quad in a small torus was discarded, the
  surface came out with no vertices, `generate_tangents` then failed, and the
  builder returned an ArrayMesh with no surfaces - which renders as nothing and
  reports nothing. Two parts of the blaster and several fittings on the suit
  were simply absent. The test is now relative to the polygon's own size, and
  `_commit` refuses to hand back an empty surface quietly.
- The power crystal's hover animation assigned an ABSOLUTE height, throwing
  away the rest height its scene set. The crystal dropped to the ground on the
  first frame and sat buried in its own bedrock.
- The power crystal's glow light had no colour set at all, so until the first
  snapshot refresh it was a white lamp washing out the crystal it belongs to.
  Colour is a function of `crystal_id`, which never changes, so it is now set
  once at build time.
- The mesh test's "normals point away from the origin" check assumed every
  shape is star-shaped about its centre. A tube's bore and a torus's inner
  surface legitimately face inward, and asserting otherwise would have forced
  the barrel to be built solid. That half of the check is now opt-out; the
  winding half still applies to everything.

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
