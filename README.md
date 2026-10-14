# ABYSSAL — The Lost Ocean

A first-person science-fiction exploration game set on **Maren**, an alien world that is entirely ocean. You are the recovery diver sent to find out why the Deepreach Expedition went silent 214 days ago. Their story, and the story of the vanished Veyru civilisation, are spread across a dark, glowing ocean full of life.

Built with **three.js** and **Vite**. Every model, texture, creature, sound effect and piece of music is generated procedurally at runtime. The game uses no external art or audio files.

## Running

```bash
npm install
npm run dev        # http://localhost:5173 — development server
npm run build      # production build in dist/
npm run preview    # serve dist/ at http://localhost:4173
```

You need a current desktop browser with WebGL 2 and hardware acceleration. Headphones are recommended. Click the game to capture the mouse.

## Controls

| Input | Action |
| --- | --- |
| `W A S D` / mouse | Swim and look (or steer the Kestrel) |
| `Space` / `C` | Rise / descend |
| `Shift` | Sprint (uses more O₂) / Kestrel boost |
| Hold `Right Mouse` or `F` | Scan |
| `E` or `Left Click` | Collect, interact, board or exit the Kestrel |
| `Q` | Sonar ping (shows terrain beyond visibility, marks deposits, startles predators) |
| `L` | Headlamp / Kestrel lights |
| `Tab` | Wrist PDA: objectives, map, databank, logs, inventory, equipment |
| `M` | Map |
| `H` | Use a field medkit |
| `Esc` / `P` | Pause |

A short contextual tutorial teaches these controls as you play. You can turn it off in Settings.

## The loop

1. **Explore** a 1.8 km × 1.8 km ocean region. Areas include the sunlit station shelf, the Lumen Kelp Forest, the Whisper Caves, the stepped Coral Terraces, the Eastern Canyon, the Hadal Rift trench, and a perfectly circular **Abyss** more than 600 m deep.
2. **Scan** creatures, plants, geology, wrecks and ruins. There are 31 databank entries. Some scans unlock blueprints.
3. **Collect** seven resource types (ferrite, lumen crystal, kelp fibre, coral silica, titanite, void glass, Veyru alloy).
4. **Return** to Meridian Station or the Kestrel to breathe, recharge, store materials and fabricate.
5. **Craft** upgrades: O₂ tanks, Pressure Suit Mk I/II, hydro-fins, sonar booster, a battery pack, and Kestrel hull reinforcements. Each one opens up deeper water.
6. **Recover** 15 audio logs and records. Follow the trail from the station to Echo Lab, the Corvid wreck, the Veyru ruins, Commander Lindqvist's beacon and, finally, the Threshold.

Depth gating: the suit is rated to 60 m at first, then 180 m and 340 m. The Kestrel is rated to 200 m, then 450 m and 900 m. Going past your rating causes pressure damage, visor cracks and hull stress.

## Systems

- **Swimming:** inertia and drag, neutral buoyancy, floating at the surface, collision against terrain, rocks, structures and cave walls, and soft world-boundary currents.
- **Survival:** oxygen, which refills at the surface, in the station moonpool and in the Kestrel. Also vitals with regeneration, a suit battery for the headlamp, scanner and sonar, and pressure damage. Death returns you to the station and costs a share of your carried materials.
- **Kestrel submersible:** first-person cockpit, power and hull integrity, crush depth, docking that recharges and repairs, a manipulator arm for collecting from inside, a field fabricator, and autopilot recall from the station terminal.
- **Ecosystem:**
  - Schooling glimmerfin (boids) that flee you and predators, and at night turn as one toward the Abyss.
  - Pulsing lantern drifters and grazing shellbacks.
  - Razormaws that hunt the fish and drive off divers who stray into their territory.
  - 100 m Cantor leviathans circling in the distance, singing.
  - The rare veil ray, found in a hidden grotto and in the kelp at night.
  - Hollow stalkers in the deep. They are drawn to light and engine noise, and sonar startles them.
- **Atmosphere:**
  - Per-fragment light absorption with depth (reds fade first), animated caustics, depth-tinted fog, light shafts, marine snow lit by your lamp, bioluminescent plankton and bloom.
  - A day/night cycle, an alien sky with a ringed gas giant when you surface, and a sonar pulse that sweeps across all geometry.
- **Audio:** a Web Audio synthesis engine. It includes an underwater bed, a depth drone, the "Low Song" signal, cantor calls, sonar, scanner, breathing and bubbles, a sub hum and thrusters, creaks under pressure, generative ambient music, and muffling that changes between air and water.
- **UI:** title screen with a live world behind it, an intro, a HUD (compass, objective, vitals, depth gauge and zone, scan ring, prompts, waypoints), a wrist PDA, pause, settings (sensitivity, invert Y, FOV, volumes, quality, subtitles, hints, head bob), controls, credits, a death screen, and the chapter ending.
- **Saving:** manual saves from the pause menu or the station terminal, plus autosaves when power is restored, when you fabricate at the station, and at the ending. Saves go to `localStorage`, and Continue loads them from the title screen.

## Graphics and external assets

- **Surface detail:** tileable CC0 normal maps (`public/textures/normals/`) are applied with triplanar projection in the shared underwater shader (`src/world/shading.js`, presets in `src/world/surfaces.js`). It needs no UVs and keeps texel density constant on procedural geometry.
- **Reflections:** image-based specular reflections from a procedural ocean light field, plus a CC0 HDRI inside the station (`src/world/envmaps.js`). They fade with depth like sunlight; image-based diffuse is disabled because the game's own ambient model provides it.
- **External models:** optional glTF models listed in `MODEL_MANIFEST` (`src/world/assets.js`) are preloaded and normalised to the size, pivot and facing the game expects. Every one has a procedural fallback, so a missing or broken file never breaks the game. To swap in your own model, put a `.glb` in `public/models/` and point the manifest entry at it.
- **Environment:** fractured boulders (`src/world/rocks.js`) for scattered rocks and the cave walls, giant kelp and branch coral (`src/world/plants.js`), the Corvid wreck (`src/world/wreckModel.js`) and the Veyru ruins (`src/world/ruinsModel.js`). Scatter tiles and cave chunks switch to light versions at distance.
- **Hero models:** the Kestrel (`src/player/kestrelModel.js`), Meridian Station (`src/world/stationModel.js`) and all seven creature species (`src/creatures/species.js`, built with `src/creatures/anatomy.js`) are detailed procedural models. Parts are merged per material, so each creature is one draw call. Fins are real membranes that bend with the swim shader, paired fins and legs animate through a per-vertex flex weight, and tail beat follows swimming speed. Fish, drifters, razormaws and stalkers switch to lighter models at distance.
- **Quality:** surface detail is disabled on Low and reduced on Medium (Settings → Graphics quality).
- **Rollback/compare:** open the game with `?classic` to turn off all graphics upgrades.
- **Credits:** third-party assets and their licenses are listed in `public/CREDITS.md` and on the in-game Credits screen.

## Project layout

```
index.html              UI markup (HUD, PDA, menus)
src/main.js             entry point, fonts, WebGL check
src/game.js             game loop, modes, life support, scanning, interaction, story events, save/load
src/core/               input, synthesized audio, post-processing, storage, events, noise
src/world/layout.js     world map: regions, sites, points of interest, procedural height function
src/world/terrain.js    sampled heightfield, chunked meshes, fast height/normal queries
src/world/shading.js    shared underwater shader patch (absorption, caustics, fog, sonar, animation)
src/world/environment.js surface, sky, light shafts, particles, bubbles, day/night
src/world/flora.js      instanced vegetation, coral, crystals and rocks (tile-culled)
src/world/structures.js Meridian Station, Echo Lab, Corvid wreck, caves, ruins, beacon, Threshold
src/world/resources.js  collectable deposits (stable ids for saves, slow respawn)
src/creatures/          procedural bodies and behaviours for seven species
src/player/             diver physics, Kestrel submersible, first-person equipment
src/systems/story.js    objectives and tutorial hints
src/data/               items, recipes, upgrades, databank entries, expedition logs
src/ui/                 HUD, PDA, menus, map renderer, icons
tests/e2e.mjs           automated gameplay tests (Playwright)
```

New biomes can be added by extending `layout.js` (height function and sites), `flora.js` (scatter rules), `creatures.js` (homes) and `story.js` (objectives).

## Tests

```bash
npm run build
npm run preview &     # serve the build on :4173
npm test              # Playwright + Chromium (software WebGL works)
npm run test:fallback # blocks every external asset and checks the procedural fallbacks
```

The suite boots the game and starts a new expedition. It then steps the simulation and checks swimming, moonpool and terrain collision, oxygen drain, refill and drowning, pressure damage, scanning, resource collection, fabrication, restoring station power, upgrades, piloting the Kestrel, the save/load round trip, death and respawn, and the full story conclusion. It also fails on any runtime error. Set `ABYSSAL_URL` or `CHROMIUM_PATH` to override the defaults.

## Notes and limitations

- The seafloor is a heightfield. Overhangs and caves (the Whisper Caves, the station interior, the wreck and lab interiors) are built from colliding rock and structure geometry on top of it.
- The expedition's "audio logs" appear as transcripts that type out over synthesized radio static. There is no recorded voice acting.
- Chapter I ends at the Threshold. You can keep exploring afterwards, and the Chapter II signal is waiting beyond the northern survey line.
