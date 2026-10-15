// World layout: the single source of truth for where regions and points of
// interest live, and the raw (procedural) seafloor height function.
// Coordinates: x = east, z = south (north is -z), y = up. Sea surface at y = 0.

import { Simplex, smoothstep, clamp, distToPolyline, lerp } from '../core/noise.js';

export const WORLD_HALF = 900;          // playable half-extent in metres
export const BOUNDARY = 820;            // soft boundary (strong currents)
export const SEED = 4417;

const simplex = new Simplex(SEED);
const simplexB = new Simplex(SEED * 7 + 3);

export const SITES = {
  station: { x: 0, z: 0, floor: -31 },
  monolith: { x: -120, z: -175 },
  kelp: { x: -250, z: 20 },
  caves: { path: [[-330, 70], [-365, 108], [-405, 132], [-440, 122]] },
  coral: { x: 20, z: 300 },
  echoLab: { x: 92, z: 330, floor: -96 },
  skeleton: { x: -120, z: 250 },
  canyon: { path: [[150, -70], [300, -30], [440, 25], [580, 10]] },
  wreck: { x: 395, z: 12 },
  rift: { path: [[-470, 330], [-300, 500], [-120, 640], [20, 760]] },
  ruins: { x: -290, z: 505, floor: -268 },
  abyss: { x: 380, z: 540, rIn: 140, rOut: 235, floor: -640 },
  beacon: { x: 196, z: 368 },
};

// Biome weights (0..1) used for colouring and scattering.
export function biomeWeights(x, z) {
  const kelp = 1 - smoothstep(90, 210, Math.hypot(x - SITES.kelp.x, (z - SITES.kelp.z) * 1.1));
  const coral = 1 - smoothstep(110, 250, Math.hypot((x - SITES.coral.x) * 0.85, z - SITES.coral.z));
  const canyon = 1 - smoothstep(20, 90, distToPolyline(x, z, SITES.canyon.path));
  const rift = 1 - smoothstep(40, 150, distToPolyline(x, z, SITES.rift.path));
  const da = Math.hypot(x - SITES.abyss.x, z - SITES.abyss.z);
  const abyss = 1 - smoothstep(SITES.abyss.rIn, SITES.abyss.rOut + 40, da);
  const shelf = 1 - smoothstep(120, 260, Math.hypot(x, z));
  return { kelp, coral, canyon, rift, abyss, shelf };
}

// Raw procedural height. Slow-ish; the Terrain class samples it into a grid once.
export function rawHeight(x, z) {
  const n = simplex.fbm2(x * 0.0042, z * 0.0042, 5);
  const detail = simplexB.fbm2(x * 0.035, z * 0.035, 3);
  const dS = Math.hypot(x, z);

  // Base: a gently rolling shelf around the station that slopes away into deeper plains.
  let h = -30 + n * 7 + detail * 1.4;
  h -= smoothstep(150, 560, dS) * 62;

  // Rocky ridged formations scattered across the shelf & plains.
  const ridge = simplexB.ridged2(x * 0.008 + 11, z * 0.008 - 7, 4);
  const ridgeMask = smoothstep(0.1, 0.45, simplex.noise2(x * 0.002 + 3, z * 0.002 - 9) * 0.5 + 0.5);
  h += Math.pow(ridge, 2.2) * 26 * ridgeMask;

  // Kelp basin: soft depression with mounds.
  const kelpW = 1 - smoothstep(80, 220, Math.hypot(x - SITES.kelp.x, (z - SITES.kelp.z) * 1.1));
  h = lerp(h, -46 + n * 5 + detail * 2, kelpW * 0.85);

  // Rock massif that hosts the Whisper Caves (west of the kelp forest).
  const caveD = distToPolyline(x, z, SITES.caves.path);
  const massif = 1 - smoothstep(10, 55, caveD);
  h += massif * (18 + ridge * 10);
  // carve the tunnel floor so the cave interior is navigable
  const tunnel = 1 - smoothstep(6, 12, caveD); // the slope sits behind the wall rocks
  h = lerp(h, -57 + detail, tunnel);

  // Coral terraces: stepped descent toward the south.
  const coralW = 1 - smoothstep(100, 260, Math.hypot((x - SITES.coral.x) * 0.85, z - SITES.coral.z));
  if (coralW > 0) {
    const slope = -60 - smoothstep(180, 420, z) * 75 - (n * 0.5 + 0.5) * 10;
    const step = 11;
    const raw = slope + detail * 2;
    const k = raw / step;
    const fl = Math.floor(k);
    const fr = k - fl;
    const terr = (fl + smoothstep(0.75, 1.0, fr)) * step;
    h = lerp(h, terr, coralW);
  }

  // Echo Lab foundation — flatten.
  const labD = Math.hypot(x - SITES.echoLab.x, z - SITES.echoLab.z);
  h = lerp(h, SITES.echoLab.floor + detail * 0.3, 1 - smoothstep(26, 48, labD));

  // Station foundation — flatten.
  h = lerp(h, SITES.station.floor + detail * 0.5, 1 - smoothstep(26, 60, dS));

  // Eastern canyon.
  const dc = distToPolyline(x, z, SITES.canyon.path);
  const canyonDepth = -150 - smoothstep(150, 580, x) * 26 + detail * 2;
  const canyonW = 1 - smoothstep(18, 70, dc + n * 10);
  h = Math.min(h, lerp(h, canyonDepth, canyonW));

  // Hadal Rift: a long deep trench with steep walls.
  const dr = distToPolyline(x, z, SITES.rift.path);
  const riftW = 1 - smoothstep(40, 95, dr + n * 14);
  const riftFloor = -262 - (simplex.noise2(x * 0.01, z * 0.01) * 0.5 + 0.5) * 18 + detail * 2;
  h = Math.min(h, lerp(h, riftFloor, Math.pow(riftW, 0.7)));
  // Ruins plaza — flatten inside the rift.
  const rd = Math.hypot(x - SITES.ruins.x, z - SITES.ruins.z);
  h = lerp(h, SITES.ruins.floor, 1 - smoothstep(30, 55, rd));

  // The Abyss: an impossibly circular shaft.
  const da = Math.hypot(x - SITES.abyss.x, z - SITES.abyss.z);
  const ang = Math.atan2(z - SITES.abyss.z, x - SITES.abyss.x);
  const wobble = simplex.noise2(Math.cos(ang) * 2, Math.sin(ang) * 2) * 10;
  const abyssW = 1 - smoothstep(SITES.abyss.rIn, SITES.abyss.rOut, da + wobble);
  if (abyssW > 0) {
    // terraced ledges on the walls give it a carved, artificial look
    const ledge = Math.floor((1 - abyssW) * 9) / 9;
    const wallH = lerp(SITES.abyss.floor, h, ledge * 0.6 + (1 - abyssW) * 0.4);
    h = Math.min(h, lerp(h, wallH, Math.min(1, abyssW * 1.6)));
    const floorW = 1 - smoothstep(30, SITES.abyss.rIn, da);
    h = lerp(h, SITES.abyss.floor + detail * 3 + Math.max(0, 24 - da) * 0.4, floorW);
  }
  // Rim of the abyss slightly raised.
  h += (1 - smoothstep(0, 30, Math.abs(da - SITES.abyss.rOut - 20))) * 6;

  // Distant edges fall away into deep water.
  const edge = Math.max(Math.abs(x), Math.abs(z));
  h -= smoothstep(700, 900, edge) * 120;

  return clamp(h, -700, -6);
}

// Points of interest — discovered when the player gets close.
export const POIS = [
  { id: 'station', name: 'Meridian Station', sub: 'Deepreach Expedition base', x: 0, z: 0, y: -18, radius: 40, icon: 'station' },
  { id: 'monolith', name: 'The Listening Stone', sub: 'Unknown structure', x: SITES.monolith.x, z: SITES.monolith.z, radius: 35, icon: 'ruin' },
  { id: 'kelp', name: 'Lumen Kelp Forest', sub: 'Biome', x: SITES.kelp.x, z: SITES.kelp.z, radius: 110, icon: 'biome' },
  { id: 'caves', name: 'Whisper Caves', sub: 'Cave system', x: -352, z: 96, radius: 30, icon: 'cave' },
  { id: 'coral', name: 'Coral Terraces', sub: 'Biome', x: SITES.coral.x, z: SITES.coral.z - 40, radius: 120, icon: 'biome' },
  { id: 'echoLab', name: 'Echo Lab', sub: 'Abandoned research outpost', x: SITES.echoLab.x, z: SITES.echoLab.z, radius: 45, icon: 'lab' },
  { id: 'skeleton', name: 'The Old Bones', sub: 'Remains of a colossal organism', x: SITES.skeleton.x, z: SITES.skeleton.z, radius: 50, icon: 'mystery' },
  { id: 'canyon', name: 'Eastern Canyon', sub: 'Biome', x: 300, z: -30, radius: 90, icon: 'biome' },
  { id: 'wreck', name: 'Wreck of the Corvid', sub: 'Autonomous supply barge', x: SITES.wreck.x, z: SITES.wreck.z, radius: 60, icon: 'wreck' },
  { id: 'rift', name: 'Hadal Rift', sub: 'Trench', x: -300, z: 480, radius: 130, icon: 'biome' },
  { id: 'ruins', name: 'Veyru Ruins', sub: 'Ancient structure', x: SITES.ruins.x, z: SITES.ruins.z, radius: 70, icon: 'ruin' },
  { id: 'beacon', name: 'Lindqvist’s Beacon', sub: 'Personal locator', x: SITES.beacon.x, z: SITES.beacon.z, radius: 35, icon: 'signal' },
  { id: 'abyss', name: 'The Abyss', sub: 'Unexplored', x: SITES.abyss.x, z: SITES.abyss.z, radius: 240, icon: 'abyss' },
  { id: 'gate', name: 'The Threshold', sub: 'Source of the Low Song', x: SITES.abyss.x, z: SITES.abyss.z, y: -600, radius: 90, icon: 'signal', minDepth: 450 },
];
