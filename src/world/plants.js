// Detailed vegetation for the graphics rebuild: giant kelp with ruffled
// blades and gas bladders, and branching corals with rounded polyp tips.
// Each has a light `lod` variant for distant scatter tiles. Output matches
// geom.js (non-indexed, normal, color, aGlow).

import * as THREE from 'three';
import { mulberry32 } from '../core/noise.js';
import * as G from './geom.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

/** Single-sided sheet from pt(u, v) (plants use DoubleSide materials). */
function sheet(pt, nu, nv, color, glow) {
  const pos = [], idx = [];
  const cols = nu + 1;
  for (let j = 0; j <= nv; j++) for (let i = 0; i <= nu; i++) { const p = pt(i / nu, j / nv); pos.push(p.x, p.y, p.z); }
  for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) { const a = j * cols + i, b = a + 1, c = a + cols, d = c + 1; idx.push(a, b, d, a, d, c); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  const out = G.prep(g, 0xffffff, 0);
  const n = out.attributes.position.count;
  // recover (u, v) per vertex from the original grid order
  const src = g.index.array;
  const c = new THREE.Color();
  for (let k = 0; k < n; k++) {
    const gi = src[k];
    const u = (gi % cols) / nu, v = Math.floor(gi / cols) / nv;
    color(u, v, c);
    out.attributes.color.setXYZ(k, c.r, c.g, c.b);
    out.attributes.aGlow.setX(k, glow ? glow(u, v) : 0);
  }
  return out;
}

// ------------------------------------------------------------------ KELP
// Normalised to height 1; instances scale it to ~(1.7, 6..44, 1.7), so
// blade shapes are authored in metres and divided by the typical scale.
const KSX = 1.7, KSY = 26;
export function kelpGeometry(seed = 1, { lod = 0 } = {}) {
  const rnd = mulberry32(seed * 31 + 5);
  const parts = [];
  const hue = 0.11 + rnd() * 0.04;
  const stipeC = new THREE.Color().setHSL(hue, 0.5, 0.22);
  // stipe with a gentle S-curve
  const stem = [];
  const bend = rnd() * Math.PI * 2;
  for (let i = 0; i <= 10; i++) {
    const t = i / 10;
    stem.push(V(Math.sin(t * 3 + bend) * 0.06 * t, t, Math.cos(t * 2.4 + bend) * 0.06 * t));
  }
  const curve = new THREE.CatmullRomCurve3(stem);
  parts.push(G.tubeAlong(stem, 0.012, 0.006, lod ? 3 : 4, stipeC, null, lod ? 6 : 14));
  const blades = lod ? 14 : 22;
  for (let b = 0; b < blades; b++) {
    const t = 0.06 + (b / blades) * 0.9 + (rnd() - 0.5) * 0.02;
    const base = curve.getPointAt(Math.min(1, t));
    const a = b * 2.39996 + rnd() * 0.5; // golden-angle phyllotaxis
    const dir = V(Math.cos(a), 0, Math.sin(a));
    const side = V(-dir.z, 0, dir.x);
    const canopy = t > 0.82;
    const L = canopy ? 2.8 + rnd() * 1.4 : 1.6 + rnd() * 1.4; // metres; the surface canopy spreads out
    const W = 0.16 + rnd() * 0.12;
    const rise = canopy ? 0.15 + rnd() * 0.3 : 0.85 + rnd() * 0.35; // lower blades stream upward
    const col = new THREE.Color().setHSL(hue + (rnd() - 0.5) * 0.03, 0.6, 0.28 + rnd() * 0.1);
    const pt = (u, v) => {
      const s = v * 2 - 1;
      const along = u * L;
      const h = along * Math.cos(rise) * (1 - 0.25 * u);
      const up = along * Math.sin(rise) - u * u * 0.35 * L * 0.4; // tip droops
      const w = W * Math.sin(Math.PI * Math.min(1, u * 1.15 + 0.06)) ** 0.7 * (1 - 0.35 * u);
      const ruffle = lod ? 0 : Math.sin(u * 16 + b) * 0.035 * Math.abs(s);
      const twist = Math.sin(u * 3 + b) * 0.25;
      return V(
        base.x + (dir.x * h + side.x * s * w * Math.cos(twist)) / KSX,
        base.y + (up + s * w * Math.sin(twist) + ruffle) / KSY,
        base.z + (dir.z * h + side.z * s * w * Math.cos(twist)) / KSX,
      );
    };
    const glowBlade = b % 3 === 0;
    parts.push(sheet(pt, lod ? 3 : 6, lod ? 1 : 2,
      (u, v, c) => { const vein = Math.abs(v - 0.5) < 0.12 ? 0.8 : 1; c.copy(col).multiplyScalar(vein * (0.75 + u * 0.45)); },
      (u) => (lod && glowBlade && u < 0.12 ? 0.8 : 0)));
    if (!lod && glowBlade) {
      // glowing gas bladder at the base of every third blade (Lumen kelp)
      const bl = new THREE.SphereGeometry(1, 5, 3).scale(0.045 / KSX, 0.07 / KSY, 0.045 / KSX);
      bl.translate(base.x + dir.x * 0.05 / KSX, base.y + 0.02 / KSY, base.z + dir.z * 0.05 / KSX);
      parts.push(G.prep(bl, 0x9be7ff, 0.8));
    }
  }
  return G.merge(parts);
}

// ------------------------------------------------------------------ BRANCH CORAL
export function branchCoralGeometry(seed = 1, color = 0xd2694a, { lod = 0 } = {}) {
  const rnd = mulberry32(seed);
  const parts = [];
  const baseC = new THREE.Color(color);
  const tipC = baseC.clone().offsetHSL(0.03, 0.1, 0.22);
  const radial = lod ? 4 : 6;
  const polyp = (x, y, z, c, t) => {
    // pale polyp speckle along the branches
    const s = Math.sin(x * 61 + y * 37) * Math.sin(z * 53 - y * 29);
    c.copy(baseC).lerp(tipC, t);
    if (s > 0.55) c.offsetHSL(0, -0.05, 0.12);
  };
  function branch(start, dir, len, r, depth) {
    const pts = [start.clone()];
    const p = start.clone();
    const d = dir.clone();
    const segs = lod ? 2 : 3;
    for (let i = 0; i < segs; i++) {
      d.x += (rnd() - 0.5) * 0.45; d.z += (rnd() - 0.5) * 0.45; d.y += 0.18;
      d.normalize();
      p.addScaledVector(d, len / segs);
      pts.push(p.clone());
    }
    const g = G.tubeAlong(pts, r, r * 0.7, radial, color, null, lod ? 2 : 4);
    const t0 = depth / 4;
    G.colorize(g, (x, y, z, c) => polyp(x, y, z, c, Math.min(1, t0 + 0.15)));
    parts.push(g);
    const kids = depth < 3 ? 2 + (depth === 0 && rnd() < 0.5 ? 1 : 0) : 0;
    if (!kids && !lod) {
      // rounded, paler growing tip
      const cap = new THREE.SphereGeometry(r * 0.75, 5, 3).translate(p.x, p.y, p.z);
      parts.push(G.prep(cap, tipC, 0.3));
    }
    for (let k = 0; k < kids; k++) {
      const nd = d.clone().add(V((rnd() - 0.5) * 1.5, rnd() * 0.35, (rnd() - 0.5) * 1.5)).normalize();
      branch(p, nd, len * (0.66 + rnd() * 0.12), r * 0.64, depth + 1);
    }
  }
  // two or three trunks from an encrusting base
  const trunks = 2;
  for (let i = 0; i < trunks; i++) {
    const a = (i / trunks) * Math.PI * 2 + rnd();
    branch(V(Math.cos(a) * 0.08, -0.1, Math.sin(a) * 0.08), V(Math.cos(a) * 0.35, 1, Math.sin(a) * 0.35).normalize(), 0.55, 0.085, 0);
  }
  const foot = new THREE.SphereGeometry(0.22, lod ? 5 : 9, lod ? 3 : 5, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.4, 1).translate(0, -0.08, 0);
  parts.push(G.prep(foot, baseC.clone().multiplyScalar(0.7), 0));
  return G.merge(parts);
}
