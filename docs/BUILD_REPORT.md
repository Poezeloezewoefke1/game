# Build Report

## The deliverable

| | |
|---|---|
| **File** | `build/windows/UNSTABLE_LAST_STAND.exe` |
| **Size** | 81,074,592 bytes (77.3 MB) |
| **Format** | PE32+ executable (GUI), x86-64, 13 sections |
| **Machine** | `0x8664` |
| **PCK** | Embedded (`GDPC` marker present) — single-file distribution, no external data |
| **Built** | 6 September 2026 |

## Toolchain

| | |
|---|---|
| Engine | Godot **4.4.1-stable** (commit `49a5bc7b6`) |
| Editor binary | Ubuntu `questing` `godot` package, run under its own glibc loader |
| Export template | **Built from source** in this environment |
| Target | Windows Desktop, `x86_64`, release |
| Renderer | Forward+, with `fallback_to_opengl3 = true` |

### Why the template was built from source

Godot's official export templates are distributed from `downloads.tuxfamily.org` and GitHub release
assets. Both were unreachable from this build environment — the egress proxy denied them, and
`api.github.com` returns 403 for repositories outside this session's scope. Docker Hub was blocked
too, so the usual `barichello/godot-ci` image was not an option either.

So the template was compiled from the engine source:

```bash
git clone --depth 1 --branch 4.4.1-stable https://github.com/godotengine/godot
apt-get install -y build-essential scons mingw-w64
update-alternatives --set x86_64-w64-mingw32-gcc  /usr/bin/x86_64-w64-mingw32-gcc-posix
update-alternatives --set x86_64-w64-mingw32-g++  /usr/bin/x86_64-w64-mingw32-g++-posix

scons platform=windows target=template_release arch=x86_64 use_mingw=yes \
      d3d12=no module_openxr_enabled=no module_mobile_vr_enabled=no \
      module_webxr_enabled=no module_raycast_enabled=no -j4
```

Cross-compile time: **28 minutes 39 seconds**. Output:

```
godot.windows.template_release.x86_64.exe          77,432,320 bytes
godot.windows.template_release.x86_64.console.exe     185,344 bytes
```

Installed to `~/.local/share/godot/export_templates/4.4.1.stable/` as
`windows_release_x86_64.exe` and `windows_release_x86_64_console.exe`.

The POSIX-threads mingw variant is required; the default win32-threads variant does not build Godot.

Modules disabled (`d3d12`, OpenXR, mobile VR, WebXR, raycast) are all unused by this project and cut
build time; the game runs on Vulkan or OpenGL 3.

## Export preset

`export_presets.cfg`, preset "Windows Desktop":

```
platform                   = Windows Desktop
binary_format/architecture = x86_64
binary_format/embed_pck    = true
export_filter              = all_resources
include_filter             = *.json, *.png, *.gdshader, *.gdshaderinc, *.wav
exclude_filter             = tests/*, tools/*, docs/*, build/*
script_export_mode         = 2        (compiled bytecode)
application/modify_resources = false
```

A Linux preset is included and uses the same filters.

`include_filter` is load-bearing: skins and block textures are imported with Godot's `keep` importer
(the game reads their raw bytes so a player can drop a skin in at runtime), and `keep`-imported files
are only packed if the filter names them.

`modify_resources` is off because it requires `rcedit`, a Windows tool not available here. The
consequence is that the exe carries the default Godot icon and no embedded version metadata — see
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

## Build command

```bash
godot --headless --path . --export-release "Windows Desktop" \
      build/windows/UNSTABLE_LAST_STAND.exe
```

Completes with **0 warnings and 0 errors**.

## Verification performed

**Binary structure** — confirmed by parsing the PE header directly:

```
MZ header      : b'MZ'
PE signature   : b'PE\0\0'
Machine        : 0x8664  (x86-64)
Subsystem      : GUI
Sections       : 13
GDPC marker    : found (PCK is embedded)
```

**Execution** — the exe was run under Wine 9.0 in this environment:

```
$ wine UNSTABLE_LAST_STAND.exe --headless --quit-after 300
Godot Engine v4.4.1.stable.custom_build.49a5bc7b6 - https://godotengine.org
[DataDB] loaded: 4 heroes, 14 towers, 30 enemies, 2 bosses, 2 maps, 49 lore characters
exit 0
```

The packaged game boots, mounts the embedded PCK, runs its autoloads, loads every JSON data file and
starts the main scene. A windowed run under Wine reaches display-server creation and then fails:

```
WARNING: Your video card drivers seem not to support the required OpenGL 3.3 version, switching to ANGLE.
ERROR: Can't load EGL dynamic library.
```

That is Wine's software GL in a GPU-less VM, not a fault in the build. On real Windows hardware the
Forward+ (Vulkan) renderer is used, with OpenGL 3 as the configured fallback.

## What is inside the package

| | |
|---|---|
| GDScript files | 39 (7,834 lines) |
| JSON data files | 19 |
| Skin PNGs | 38 |
| Block/pattern textures | 35 |
| Audio files | 34 (11 music, 23 SFX) |
| Shaders | 3 |

## Performance results

Measured in this environment; see [TEST_REPORT.md](TEST_REPORT.md) for the full tables.

- **Game logic:** 50 → 1000 concurrent enemies costs **+0.5 ms** frame time, **+6 nodes**, **+0.7 MB**.
- **Rendering:** frame time and draw calls are **flat** from 50 to 1000 enemies (133.3 ms, ~580 calls)
  under a software rasteriser — enemy count adds no draw calls.
- **No GPU frame rate is claimed.** This VM has no GPU.

## Reproducing this build

```bash
# 1. Export templates (only if you do not already have official 4.4.1 templates)
git clone --depth 1 --branch 4.4.1-stable https://github.com/godotengine/godot
cd godot && scons platform=windows target=template_release arch=x86_64 use_mingw=yes -j$(nproc)
mkdir -p ~/.local/share/godot/export_templates/4.4.1.stable
cp bin/godot.windows.template_release.x86_64.exe \
   ~/.local/share/godot/export_templates/4.4.1.stable/windows_release_x86_64.exe

# 2. Assets (only if regenerating placeholders)
python3 tools/gen_assets.py
python3 tools/gen_audio.py

# 3. Import, test, export
godot --headless --path . --import
godot --headless --path . -s tests/run_headless.gd -- res://tests/test_suite.gd 4
godot --headless --path . --export-release "Windows Desktop" build/windows/UNSTABLE_LAST_STAND.exe
```
