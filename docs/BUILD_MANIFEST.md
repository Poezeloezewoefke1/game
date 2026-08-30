# Build manifest

What a build contains, how it is produced, and how to reproduce it byte-for-byte
enough to trust.

## Identity

| Field | Value |
|---|---|
| Product | Starbound Station: The Lost Signal |
| Version | `0.1.0` (`GameConfig.GAME_VERSION`, mirrored in `project.godot`) |
| Protocol version | `1` (`GameConfig.PROTOCOL_VERSION`) |
| Engine | Godot 4.5.1-stable |
| Target | Windows x86_64 desktop |
| Renderer | Forward+ |

`PROTOCOL_VERSION` must be incremented whenever the wire format changes — a new
or changed RPC signature, a change to the mission snapshot shape, or a change to
the fixed replicated node path (`SceneRoot/Stage/...`). Peers with mismatched
protocol versions are refused at the handshake with a readable message, which is
much better than a session that half-works.

## What ships

```
build/windows/
├── StarboundStation.exe      the engine plus the Windows export template
└── StarboundStation.pck      the game: scenes, scripts, resources
```

**Both files are required.** The executable will not start without the `.pck`
beside it. Distribute the folder, not the `.exe` alone. `embed_pck` is off so
the pack stays separately inspectable and patchable.

Measured from the local verification export:

| File | Size |
|---|---|
| `StarboundStation.exe` | ~93 MB |
| `StarboundStation.pck` | ~224 KB |

The pack is small because every asset is generated in code or built from engine
primitives — there are no imported textures, meshes or audio files.

## What is deliberately excluded

`export_presets.cfg` sets:

```
exclude_filter = "tests/*, tools/*, ci-logs/*, docs/*, *.md, *.sh, *.yml"
```

so no test harness, no probe, no shell tooling and no documentation reaches a
player. `.github/workflows/build-windows.yml` asserts this on every build by
searching the shipped pack for `NETCHECK` and failing if it is present.

One caveat, recorded honestly as BUILD-001 in `docs/KNOWN_LIMITATIONS.md`:
Godot's engine-generated `.godot/uid_cache.bin` and
`global_script_class_cache.cfg` are always packed and list resource paths for
everything in the project, including `tests/`. The test **code** is genuinely
absent — verified by searching the pack for test source strings, the `NETCHECK`
marker and compiled test bytecode. What remains is a handful of path strings in
an engine cache, which the export preset cannot control.

## Reproducing the build

```bash
godot --path /absolute/path/to/game --headless \
      --export-release "Windows Desktop" \
      "/absolute/path/to/game/build/windows/StarboundStation.exe"
```

Three things trip people up:

1. **Use absolute paths for both.** `--path` sets the project directory, but the
   export path is resolved against the *current working directory*. Mixing them
   is the usual reason a build lands somewhere unexpected.
2. **The preset name must match exactly**, including the space: `Windows Desktop`.
3. **The export templates must be the same version as the engine.** A mismatch
   fails with a template error rather than producing a broken build, which is
   the good outcome — but it does mean an engine upgrade requires a template
   upgrade in the same change.

Template locations:

| OS | Path |
|---|---|
| Linux | `~/.local/share/godot/export_templates/4.5.1.stable/` |
| Windows | `%APPDATA%\Godot\export_templates\4.5.1.stable\` |
| macOS | `~/Library/Application Support/Godot/export_templates/4.5.1.stable/` |

Only `windows_release_x86_64.exe`, `windows_debug_x86_64.exe`, their `_console`
variants and `version.txt` are needed for this target.

## CI production

`.github/workflows/build-windows.yml`, triggered manually or by a `v*` tag:

1. Check out the repository.
2. Restore or download Godot 4.5.1-stable and the Windows export templates.
3. `tools/check_structure.sh`.
4. Import project resources (this also registers global class names).
5. **Run the full validation suite** — an artifact is never produced from code
   that fails its own tests.
6. Export the release build.
7. Assert the output is a real `PE32+ executable` and that no harness code
   leaked into the pack.
8. Upload the whole `build/windows/` folder as the artifact
   `starbound-station-windows-x86_64`, retained 30 days.
9. Upload logs (always, not only on failure).

## What is never committed

`.gitignore` excludes, and `tools/check_structure.sh` fails the build if any of
it is tracked: `.godot/`, `build/`, `builds/`, `export/`, `exports/`,
`ci-logs/`, and every `*.exe`, `*.pck`, `*.zip`, `*.dll`, `*.so`, `*.dylib`.

Builds are distributed as workflow artifacts. The repository holds source only.

## Verification status of this manifest

| Claim | Status |
|---|---|
| The export command produces a Windows PE32+ executable | **Verified** locally, exit code 0, confirmed with `file` |
| The pack excludes harness code | **Verified** locally by string search |
| The CI workflow produces the same artifact | **Not verified** — the workflow has never been executed |
| The executable launches on Windows | **Not verified** — VERIFY-001 |
