// Photoreal surface presets: tileable CC0 normal maps applied with triplanar
// projection inside the shared underwater shader (see shading.js `surface`).
// Triplanar mapping needs no UVs, so it works on the procedural geometry and
// keeps texel density constant regardless of how a mesh is scaled.

import * as THREE from 'three';

const loader = new THREE.TextureLoader();
const cache = new Map();
let maxAniso = 8;

export function setMaxAnisotropy(a) { maxAniso = a; }

/** Start loading every preset's normal maps; resolves when all have settled. */
export function preloadSurfaces() {
  for (const p of Object.values(SURFACES)) { normalTexture(p.map); normalTexture(p.side || p.map); }
  return Promise.all(pending);
}

function flatNormalImage() {
  const c = document.createElement('canvas');
  c.width = c.height = 4;
  const g = c.getContext('2d');
  g.fillStyle = 'rgb(128,128,255)'; // tangent-space "no perturbation"
  g.fillRect(0, 0, 4, 4);
  return c;
}

const pending = [];

/** Tangent-space normal map from public/textures/normals (linear data). */
export function normalTexture(id) {
  if (cache.has(id)) return cache.get(id);
  const t = new THREE.Texture(flatNormalImage()); // neutral until (or unless) the file loads
  t.needsUpdate = true;
  pending.push(new Promise((resolve) => {
    loader.load(`textures/normals/${id}.webp`, (img) => {
      t.image = img.image;
      t.needsUpdate = true;
      resolve(true);
    }, undefined, () => {
      console.warn(`[surfaces] normal map ${id} unavailable; using a flat normal`);
      resolve(false);
    });
  }));
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.NoColorSpace;
  t.anisotropy = maxAniso;
  cache.set(id, t);
  return t;
}

// map: up-facing projection, side: x/z projections, scale: tiles per metre,
// strength: normal intensity, cavity: crevice darkening, rough: roughness added in crevices,
// space: 'world' for static geometry, 'object' for things that move or animate
export const SURFACES = {
  seabed: { map: '0007', side: '0003', scale: 0.55, sideScale: 0.16, strength: 0.6, cavity: 0.22, rough: 0.1 },
  rock: { map: '0026', side: '0002', scale: 0.32, sideScale: 0.3, strength: 1.15, cavity: 0.55, rough: 0.1 },
  caveRock: { map: '0003', side: '0026', scale: 0.3, strength: 1.2, cavity: 0.6, rough: 0.05 },
  paint: { map: '0022', side: '0022', scale: 0.8, strength: 0.3, cavity: 0.15, rough: 0.2 },
  paintScratched: { map: '0022', side: '0006', scale: 0.6, sideScale: 0.35, strength: 0.4, cavity: 0.2, rough: 0.25 },
  deck: { map: '0008', side: '0022', scale: 1.4, strength: 0.8, cavity: 0.35, rough: 0.15 },
  rust: { map: '0015', side: '0015', scale: 0.55, strength: 1.0, cavity: 0.45, rough: 0.1 },
  stone: { map: '0024', side: '0024', scale: 0.22, strength: 0.9, cavity: 0.5, rough: 0.05 },
  coral: { map: '0009', side: '0009', scale: 2.2, strength: 1.0, cavity: 0.5, rough: 0.05 },
  bone: { map: '0019', side: '0019', scale: 0.7, strength: 0.7, cavity: 0.45, rough: 0.05 },
  scales: { map: '0027', side: '0027', scale: 7, strength: 0.6, cavity: 0.3, rough: 0.0, space: 'object' },
  hide: { map: '0018', side: '0018', scale: 2.5, strength: 0.7, cavity: 0.35, rough: 0.05, space: 'object' },
};

/** Resolve a preset (plus overrides) into the options patchMaterial expects. */
export function surface(name, overrides = {}) {
  const p = { ...SURFACES[name], ...overrides };
  return {
    map: normalTexture(p.map),
    side: normalTexture(p.side || p.map),
    scale: p.scale,
    sideScale: p.sideScale ?? p.scale,
    strength: p.strength ?? 1,
    cavity: p.cavity ?? 0.3,
    rough: p.rough ?? 0,
    space: p.space || 'world',
  };
}
