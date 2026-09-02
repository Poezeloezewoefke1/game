# Technology stack

Every version here is pinned. Nothing in this project is allowed to depend on
"latest": an engine upgrade that arrives silently is an engine upgrade nobody
tested.

## Engine

| Item | Value |
|---|---|
| Engine | Godot Engine |
| Version | **4.5.1-stable** (`4.5.1.stable.official.f62fdbde1`) |
| Renderer | Forward+ |
| Language | GDScript only |
| Export templates | **4.5.1-stable** - must match the editor exactly |

### Why 4.5.1-stable

* It is a patch release of a matured 4.5 line rather than the first release of
  a new minor line, so the multiplayer, navigation and export code paths this
  project leans on have had a full cycle of fixes.
* Every API this project depends on was verified against this exact binary
  before any of it was written, not assumed from documentation:
  `SceneReplicationConfig.add_property` / `property_set_spawn` /
  `property_set_replication_mode`, `MultiplayerSpawner.spawn_function`,
  `MultiplayerSynchronizer.replication_interval` / `delta_interval`,
  `ENetMultiplayerPeer.create_server` / `create_client` / `disconnect_peer`,
  `NavigationRegion3D.bake_navigation_mesh` and its `bake_finished` signal, and
  `NavigationServer3D.map_get_path` / `map_get_regions`.
* Windows x86_64 export templates are published for it.

### Upgrading the engine

The version appears in exactly three places, and `tools/check_structure.sh`
fails the build if the two workflow pins disagree:

1. `.github/workflows/validate.yml` -> `env.GODOT_VERSION`
2. `.github/workflows/build-windows.yml` -> `env.GODOT_VERSION`
3. `project.godot` -> `config/features` (the `"4.5"` feature tag)

An upgrade is not complete until the full validation run and the multi-process
multiplayer check both pass on the new version, and `docs/QA_REPORT.md` records
which engine build produced that evidence.

## Continuous integration

| Item | Value | Why |
|---|---|---|
| Runner | `ubuntu-24.04` | Pinned rather than `ubuntu-latest`, so a runner image rollover cannot change results underneath us. |
| Godot install | Direct download of the official `Godot_v4.5.1-stable_linux.x86_64.zip` release asset from `github.com/godotengine/godot`, cached by `actions/cache` | No third-party setup action, so there is no extra supply-chain dependency to audit. |
| Export templates | Official `Godot_v4.5.1-stable_export_templates.tpz`, Windows entries only | Extracting all platforms costs about a gigabyte of runner disk for no benefit. |

### GitHub Actions used

All three are first-party GitHub actions, pinned to a major version tag:

| Action | Version | Purpose | Risk note |
|---|---|---|---|
| `actions/checkout` | `v4` | Fetch the repository | First-party. |
| `actions/cache` | `v4` | Cache the engine binary and templates | First-party. A poisoned cache could substitute a binary; the cache key includes the exact engine version, and the workflow prints `--version` on every run so a substitution is visible in the log. |
| `actions/upload-artifact` | `v4` | Publish the Windows build and logs | First-party. |

No third-party actions are used. If one is ever added, this table must record
its source, version or digest, purpose, risk, and why no safer alternative
exists.

### Workflow permissions

Both workflows declare `permissions: contents: read`. Neither needs write
access: builds are published as workflow artifacts, never committed.

## Local development requirements

* Godot 4.5.1-stable (standard editor build; the headless flag is part of it).
* For a Windows export: the matching 4.5.1-stable export templates, installed
  via *Editor -> Manage Export Templates* or by unpacking the `.tpz` into
  `~/.local/share/godot/export_templates/4.5.1.stable/` (Linux/macOS) or
  `%APPDATA%\Godot\export_templates\4.5.1.stable\` (Windows).
* For `tools/run_multiplayer_check.sh`: bash, and enough memory for four to
  five concurrent headless Godot processes (roughly 1.5 GB total).
* For `tools/capture_screenshots.sh` and `tools/render_models.sh`:
  `xvfb-run` and a working OpenGL 3.3
  driver. On a machine with no GPU, Mesa's `llvmpipe` software rasteriser is
  enough - that is what this project's captures were taken with. The script
  forces `--rendering-driver opengl3 --rendering-method gl_compatibility` for
  exactly that reason; it does not change what the shipped game uses, which is
  Forward+.

### Shaders

Five, all original:

| Shader | Does |
| --- | --- |
| `deep_space_sky` | Starfield, galactic band, nebulae, and planets intersected as real spheres with terminators, atmospheres and rings |
| `surface` | World-space triplanar level geometry with slope blending, detail normals and macro variation |
| `crystal` | Fresnel-driven edge glow with internal flow |
| `hologram` | Additive, depth-write-off, world-space scanlines |
| `energy_field` | Hex-cell containment field |

### Assets

No paid assets, paid plugins, downloaded model packs, or external services are
used - and this was tested rather than assumed. `docs/ASSET_PROVENANCE.md`
records which hosts are reachable from the build environment, which are blocked,
and why the planet textures that ARE reachable were rejected on licence grounds.

Every texture is produced by `tools/generate_textures.gd`, and every model is
generated at runtime by
`scripts/utility/mesh_factory.gd` and its builders. The primitives are chamfered
boxes, faceted spheres, capsules, tubes with a real bore, wedges, tori, faceted
crystals, irregular rocks and tapered columns; those are assembled by
`prop_builder.gd`, `player_body.gd` and `view_model.gd` into the characters, the
weapon and every prop. Nothing is downloaded, nothing is licensed from a third party,
and there is not a single binary model file to keep in sync.

Two consequences are worth writing down, because each cost a long debugging
session.

**Degeneracy has to be judged relative to a polygon's own size.** An absolute
area epsilon silently discards every face of a small shape, and the builder then
returns a mesh with no surfaces at all - which renders as nothing and reports
nothing.

**Godot treats a clockwise triangle as front-facing**, which is the opposite of
the OpenGL convention Newell's method naturally produces. Any new geometry
builder must match it, and `tests/unit/test_mesh_factory.gd` reads that
convention back off Godot's own `BoxMesh` and `PlaneMesh` rather than trusting a
remembered rule.

## Compatibility assumptions

* ENet over UDP on a single port (default 7000) reachable between all peers.
* All peers run the same build. `GameConfig.PROTOCOL_VERSION` is checked during
  the join handshake and mismatched clients are refused with a readable message.
* Peers agree on scene structure because they run identical builds; replicated
  node paths are fixed (`/root/Main/SceneRoot/Stage/...`).

## Known risks

* **Runtime navigation baking.** Nerava bakes its navigation mesh on the host at
  level load rather than shipping a pre-baked mesh. This keeps the mesh from
  ever going stale relative to the geometry, at the cost of roughly a second of
  load time. If load time ever matters more, pre-bake and commit the mesh - and
  add a test that the committed mesh still matches the geometry.
* **Single-port UDP.** Playing over the internet requires the host to forward
  the port. There is no NAT traversal and none is planned.
