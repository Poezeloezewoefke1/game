// Detailed Veyru ruin pieces (visual only; colliders stay in buildRuins).
// Pillars keep the glyph-mapped UV layout of the classic cylinders
// (u around, v along the height) so the emissive glyph texture still reads.

import * as THREE from 'three';
import { lathe, roundedBox, place } from './shapes.js';
import { boulderGeometry, fbm3 } from './rocks.js';
import { mulberry32 } from '../core/noise.js';

/** Chamfered, fluted hexagon radius multiplier at angle a. */
function hexFlute(a, flutes = true) {
  const k = Math.PI / 3;
  const local = ((a % k) + k) % k - k / 2;
  const hex = Math.cos(Math.PI / 6) / Math.cos(local); // flat-sided hexagon
  const chamfer = Math.min(hex, 1.08 - Math.abs(local) * 0.08); // softened corners
  const flute = flutes ? 1 - 0.035 * Math.max(0, Math.cos(local * 6 * 2)) : 1;
  return chamfer * flute;
}

/**
 * Pillar along +y from 0 to h, centred (like CylinderGeometry translated by h/2).
 * r0 bottom / r1 top shaft radius. broken: jagged eroded top.
 */
export function pillarGeometry(h, r0, r1, { broken = false, seed = 1 } = {}) {
  const rnd = mulberry32(seed * 131 + 7);
  const segs = Math.max(24, Math.round(h * 4));
  const radial = 48;
  const plinthH = 1.2, capH = broken ? 0 : 1.6;
  const prof = (y) => {
    // base plinth steps, shaft with entasis + drum grooves, flared capital
    if (y < 0.45) return r0 * 1.16;
    if (y < 0.6) return r0 * 1.16 - (y - 0.45) / 0.15 * r0 * 0.08;
    if (y < plinthH) return r0 * 1.08 - (y - 0.6) / (plinthH - 0.6) * r0 * 0.08;
    const sh = (y - plinthH) / Math.max(1, h - plinthH - capH);
    let r = r0 + (r1 - r0) * sh + Math.sin(Math.min(1, sh) * Math.PI) * 0.06 * r0;
    const drum = ((y - plinthH) % 3.2 + 3.2) % 3.2;
    if (drum < 0.12) r *= 0.95; // joint between drums
    if (!broken && y > h - capH) {
      const c = (y - (h - capH)) / capH;
      r = r1 * (1 + 0.38 * Math.sin(c * Math.PI * 0.5) ** 2) * (c > 0.82 ? 1.04 : 1);
    }
    return r;
  };
  const top = broken ? (a) => h - 0.4 - 1.6 * (fbm3(Math.cos(a) * 2 + seed, Math.sin(a) * 2, seed, 3) * 0.5 + 0.5) : () => h;
  const pos = [], uv = [], idx = [];
  const cols = radial + 1;
  for (let i = 0; i <= segs; i++) {
    const t = i / segs;
    for (let k = 0; k <= radial; k++) {
      const a = (k / radial) * Math.PI * 2;
      const ht = top(a);
      const y = t * ht;
      const ero = 1 + 0.035 * fbm3(Math.cos(a) * 3 + seed, y * 0.7, Math.sin(a) * 3, 3);
      const chip = y > ht - 1.2 && broken ? 1 - 0.12 * Math.max(0, fbm3(a * 2, y * 2, seed, 2)) : 1;
      const r = prof(y) * hexFlute(a, y > plinthH && y < h - capH) * ero * chip;
      pos.push(Math.cos(a) * r, y - h / 2, Math.sin(a) * r);
      uv.push(k / radial, y / h);
    }
  }
  for (let i = 0; i < segs; i++) for (let k = 0; k < radial; k++) {
    const a = i * cols + k, b = a + 1, c = a + cols, d = c + 1;
    idx.push(a, c, d, a, d, b);
  }
  // cap (jagged when broken)
  const ci = pos.length / 3;
  let cy = 0;
  for (let k = 0; k < radial; k++) cy += pos[(segs * cols + k) * 3 + 1];
  pos.push(0, cy / radial + (broken ? 0.3 : 0), 0); uv.push(0.5, 1);
  for (let k = 0; k < radial; k++) { const a = segs * cols + k; idx.push(ci, a + 1, a); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  void rnd;
  return g;
}

/** Fallen drum section lying along x (length l, radius r), eroded ends. */
export function fallenDrumGeometry(l, r, seed = 1) {
  const g = pillarGeometry(l, r, r * 0.96, { broken: true, seed });
  g.rotateZ(Math.PI / 2);
  return g;
}

/** Arch of voussoir blocks over a half-ellipse (rx, ry), depth d, block section s. */
export function archBlocks(rx, ry, d, s, count = 17, seed = 1) {
  const rnd = mulberry32(seed);
  const out = [];
  for (let i = 0; i < count; i++) {
    const a0 = (i / count) * Math.PI, a1 = ((i + 1) / count) * Math.PI;
    const am = (a0 + a1) / 2;
    const x = Math.cos(am) * rx, y = Math.sin(am) * ry;
    // tangent of the ellipse for block orientation
    const tx = -Math.sin(am) * rx, ty = Math.cos(am) * ry;
    const ang = Math.atan2(ty, tx);
    const len = Math.hypot(Math.cos(a1) * rx - Math.cos(a0) * rx, Math.sin(a1) * ry - Math.sin(a0) * ry) - 0.18;
    const key = i === Math.floor(count / 2);
    const g = roundedBox(len, s * (key ? 1.35 : 1), d * (key ? 1.1 : 1), 0.18, 2);
    // weathering: nudge each block slightly out of line
    place(g, [x, y + (key ? 0.15 : 0), (rnd() - 0.5) * 0.15], [0, 0, ang + (rnd() - 0.5) * 0.03]);
    out.push({ geo: g, key });
  }
  return out;
}

/** Cut-stone rubble block (fractured edges). */
export function rubbleGeometry(seed) {
  return boulderGeometry(seed + 500, { detail: 4, cuts: 11, flat: 0.8, moss: 0.2, tone: [0.17, 0.19, 0.25] });
}
