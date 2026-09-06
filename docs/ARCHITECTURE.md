# Architecture

## Shape of the project

Everything is built from code. There are no hand-authored `.tscn` scenes beyond a one-node entry
point, and no editor-configured resources. Data lives in JSON, systems read it at load, and the scene
graph is assembled at runtime. This makes the whole game diffable, testable headlessly, and
regenerable.

```
project.godot            autoloads, rendering config
scenes/main.tscn         a single Node running scripts/core/main.gd
scripts/
  core/       event_bus, data_db, game_state, save/audio/input, main router, game_controller, wave_manager
  skin_system/ skin_data, skin_parser, mc_geometry, mc_mesh_builder, armor_builder, weapon_builder,
               mc_materials, minecraft_character, skin_library
  enemies/    damage_calc, prop_builder, enemy_manager
  towers/     tower, tower_manager, projectile_manager
  heroes/     hero, hero_summon
  bosses/     saparata_encounter, blimp_controller
  maps/       map_path, map_builder
  ui/         ui_theme, character_preview, main_menu, hero_select, map_select,
              towers_screen, codex_screen, settings_screen, game_hud
data/         heroes, towers, enemies, bosses, maps, waves, lore, characters, asset_manifest
assets/       skins, textures, audio, shaders
tests/        runners, unit suite, smoke, boss, stress, visual
tools/        gen_assets.py, gen_audio.py, gen_docs.py
```

## Autoloads

| Autoload | Responsibility |
|---|---|
| `EventBus` | Every cross-system signal. Systems never hold references to each other for notification. |
| `DataDB` | Loads and indexes all JSON at startup. Read-only afterwards. |
| `SkinLibrary` | Resolves character id → `SkinData`, caching parsed skins, materials and merged meshes. |
| `SaveSystem` | Persistent progression and settings in `user://save.json`. |
| `GameState` | Current run: hero, map, difficulty, emeralds, lives, wave, speed, stats. |
| `AudioMgr` | Music crossfade and a pooled SFX player set. Missing files degrade silently. |
| `InputSetup` | Registers the InputMap in code so no editor state is required. |

## The two representations of a character

This is the most important structural decision in the project.

**Towers, heroes and summons are nodes.** There are tens of them, they need per-part articulated
animation, click targeting and attached child nodes. `MinecraftCharacter` builds six `MeshInstance3D`
body parts around correct pivots, plus armour pieces and a held item, and animates them on the CPU.

**Enemies are rows in arrays.** There can be a thousand of them. `EnemyManager` holds ~25 parallel
`Packed*Array` pools and renders each visual variant as a single `MultiMesh`. An enemy is an integer
slot, not an object.

The two share all their geometry code. `MCMeshBuilder` can emit either one mesh per body part (for the
node path) or one merged mesh for the whole character (for the MultiMesh path), from the same
`MCGeometry` definitions.

### GPU limb animation

Merged-mesh enemies still need to walk. The merged mesh carries two custom vertex attributes:

```
CUSTOM0 = (part_id, use_vertex_color, enchant_glint, 0)
CUSTOM1 = (pivot.xyz, 0)
```

and each MultiMesh instance carries `(walk_phase, flash, ghost, swing_amplitude)` as custom data. The
vertex shader rotates each vertex around its own limb pivot by an angle derived from the part id and
the instance's phase. A thousand enemies walking costs one uniform upload per group and no CPU
animation work at all.

The same shader serves node-based characters with `anim_enabled = 0`, where the uniforms are used
instead of instance data.

## Skin pipeline

```
PNG bytes → SkinParser → SkinData → MCGeometry.part_defs() → MCMeshBuilder → ArrayMesh
                                  ↘ ImageTexture → MCMaterials → ShaderMaterial
```

`SkinParser` normalises 64×64, legacy 64×32 (expanded onto a 64×64 canvas, with left limbs mirrored
from the right) and HD multiples. Slim arms are detected by probing the four column regions that an
"Alex" skin leaves transparent, and can be forced by manifest.

`MCGeometry` holds the canonical box layout — sizes, positions, pivots and the UV origin of every part
and its second layer — as data. `face_rects()` maps a box's dimensions onto the standard skin net.
Everything downstream reads these definitions, so the layout is defined once.

Skins are loaded as **raw PNG bytes**, not through `ResourceLoader`, because the parser needs pixel
access and because it lets a player drop a file into `user://skins/` at runtime with no import step.
Block textures use the same path.

## Enemy manager internals

Parallel pools with a free list and a compacted active list:

```
alive type_idx hp max_hp dist base_speed lateral armor flags
slow_until slow_mult stun_until flash_until phase y_offset cd_a cd_b
group_idx used_once spawn_time pos_x pos_y pos_z scripted
```

Per frame: update status and movement → recompute world positions from `MapPath` → run data-driven
abilities → handle leaks → rebuild the spatial grid → upload MultiMesh transforms.

**Movement** is a scalar distance along `MapPath` plus a lateral offset, so a column spreads across
the road without any steering. `MapPath` precomputes cumulative arc lengths and binary-searches them.

**Spatial queries** use a uniform hash grid rebuilt each frame at 4-unit cells. Towers query by radius.
The grid is marked dirty on spawn and death so a query made in the same frame — a boss script, a death
explosion, a test — still sees an accurate world; this was a real bug caught by the test suite.

**Gear breaks** are a type swap in place: the slot keeps its position and identity, takes the next
definition's stats and visual group, and receives the overflow damage from the killing blow.

**Abilities** are data. `regen`, `heal_aura`, `command_aura`, `blink`, `build_wall`, `expire`,
`death_explosion`, `death_splash_slow`, `totem_revive`, `sabotage`, `projectile_block` and
`skull_volley` are declared in `enemies.json` and resolved by a `match` in the manager. Adding a
behaviour to an existing enemy is a JSON edit.

## Towers

`Tower` recomputes its entire stat block from scratch whenever anything changes — an upgrade, an aura,
a relationship, the base's health falling below half. There is no incremental stat mutation, so there
is no drift.

`TowerManager` owns placement and the aura pass. `refresh_auras()` resets all external multipliers,
then applies tower auras, the hero's aura, hero global buffs and relationship bonuses in that order,
and finally asks every tower to recompute. It runs on placement, sale, upgrade and hero ability use —
not per frame.

`ProjectileManager` is pooled and MultiMesh-rendered like the enemies. Melee "projectiles" resolve
instantly rather than spawning a row. Splash, pierce, chaining, execute thresholds, slows, stuns and
knockback are all resolved from the payload dictionary the tower supplies.

## Damage

`DamageCalc` is pure and static, which is why it is the most heavily tested part of the project:

```
effective = raw × (1 − armor_pct × (1 − armor_pen))
effective = max(effective, raw × 0.10)
```

The floor matters: without it a maxed-armour enemy becomes unkillable by chip damage, and armour
stacking has no upper bound on its value. Damage type then modifies against shields and structures,
crits multiply, and splash falls off linearly to 40% at the rim.

## Map building

`MapBuilder` reads a map definition and emits a handful of merged meshes. Terrain columns, the road,
fort walls, towers, trees, rocks, market stalls and the camp all funnel into one `_occupied`
dictionary keyed by block coordinate; a second pass emits only the faces that touch air, grouped by
block texture. A 96×96 map with structures becomes ~15 draw calls.

The road is painted by *replacing* the terrain column's surface block rather than adding a block, which
is why `_set_block` exists alongside `_add_block`.

Face winding is clockwise-as-seen-from-outside, matching Godot's front-face convention. Getting this
backwards renders the inside of the world — which is exactly what happened during development and is
why the diagnostic in `tests/visual_map_test.gd` reports per-texture face counts.

## Waves and bosses

`WaveManager` turns wave definitions into timed spawn groups and scripted events. A wave is complete
only when its spawns are exhausted, its **events have all fired**, the blimp has finished, no
non-structure enemies remain, and no boss is active. The event condition is load-bearing: the boss
wave's entire content is a single event, and without it the wave completed instantly and the run was
won before the boss appeared.

`SaparataEncounter` is a phase machine driven by the boss's health and the state of the field. It owns
its own minion budget, spawns the mini-boss and launches the blimp, and only advances when the
current phase's conditions are met.

## UI

Built in code against `UITheme`, which supplies the palette, styleboxes and control factories. Screens
are plain `Control` nodes instantiated by `main.gd`.

`CharacterPreview` renders a live 3D character into a UI rect via a `SubViewport`. Each preview sets
`own_world_3d = true` — without it every preview shares the parent viewport's world and all the
characters pile up in one place, which is a subtle bug worth knowing about.

## Testing

`tests/run_headless.gd` and `tests/run_visual.gd` load a scene script, tick it for N frames, call
`on_finish()` and quit. Scripts loaded with `-s` compile *before* autoloads are registered as globals,
so a test that touches `SkinLibrary` or `DataDB` must be loaded by a runner rather than run directly —
this is why the runners exist.

The suite covers the skin parser, UV mapping, character generation, armour, weapons, damage, path
maths, the enemy pool, enemy and tower data integrity, the Gear Rule, hero data, wave generation and
ramp, boss phases, currency, save round-tripping, relationships and lore-database integrity: 2198
assertions.
