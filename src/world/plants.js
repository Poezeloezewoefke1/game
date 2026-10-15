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

// ------------------------------------------------------------------ SEA FAN
// Gorgonian: a dichotomously branching planar skeleton over a thin
// polyp-mesh sheet whose colour carries the lattice. Faces +z, base at 0.
export function fanCoralGeometry(seed = 1, color = 0x8e4fb0, { lod = 0 } = {}) {
  const rnd = mulberry32(seed * 13 + 1);
  const parts = [];
  const base = new THREE.Color(color);
  const dark = base.clone().multiplyScalar(0.55);
  const curl = (x, y) => Math.sin(x * 2.6 + seed) * 0.07 + Math.cos(y * 3.1) * 0.05;
  const tips = [];
  function branch(p, ang, len, r, depth) {
    const pts = [p.clone()];
    let a = ang;
    const q = p.clone();
    const segs = lod ? 1 : 3;
    for (let i = 0; i < segs; i++) {
      a += (rnd() - 0.5) * 0.35;
      q.x += Math.cos(a) * len / segs; q.y += Math.sin(a) * len / segs;
      q.z = curl(q.x, q.y);
      pts.push(q.clone());
    }
    if (!lod || depth < 3) parts.push(G.tubeAlong(pts, r, r * 0.75, lod ? 3 : 4, dark, null, lod ? 1 : 3));
    if (depth < 4) {
      const spread = 0.35 + rnd() * 0.25;
      branch(q, a - spread, len * 0.78, r * 0.72, depth + 1);
      branch(q, a + spread, len * 0.78, r * 0.72, depth + 1);
    } else tips.push(q.clone());
  }
  branch(V(0, -0.05, 0), Math.PI / 2, 0.36, 0.035, 0);
  // membrane through the tips: a fan-shaped sheet with a lattice colour pattern
  const nu = lod ? 8 : 18, nv = lod ? 3 : 6;
  const outline = (u) => {
    const a = Math.PI * (0.12 + 0.76 * u);
    const rr = 0.95 + 0.12 * Math.sin(u * 17 + seed) + 0.06 * Math.sin(u * 41);
    return [Math.cos(a) * rr, Math.sin(a) * rr * 1.05];
  };
  parts.push(sheet((u, v) => {
    const [ox, oy] = outline(u);
    const x = ox * v, y = 0.04 + oy * v;
    return V(x, y, curl(x, y) - 0.005);
  }, nu, nv, (u, v, c) => {
    const [ox, oy] = outline(u);
    const x = ox * v * 9, y = oy * v * 9;
    const cell = Math.abs(Math.sin(x * 2.1 + Math.sin(y * 1.7)) * Math.sin(y * 2.3 + Math.cos(x * 1.3)));
    c.copy(base).multiplyScalar(cell < 0.25 ? 0.6 : 0.95 + v * 0.25);
  }, (u, v) => (v > 0.9 ? 0.35 : 0)));
  void tips;
  return G.merge(parts);
}

// ------------------------------------------------------------------ TUBE / BARREL SPONGE
export function tubeSpongeGeometry(seed = 1, color = 0xc48b3a, { lod = 0 } = {}) {
  const rnd = mulberry32(seed * 7 + 3);
  const parts = [];
  const base = new THREE.Color(color);
  const n = 3 + Math.floor(rnd() * 3);
  const radial = lod ? 6 : 12, rows = lod ? 3 : 9;
  for (let i = 0; i < n; i++) {
    const h = 0.6 + rnd() * 1.2, r = 0.09 + rnd() * 0.09;
    const ang = rnd() * Math.PI * 2, d = i ? 0.12 + rnd() * 0.2 : 0;
    const ox = Math.cos(ang) * d, oz = Math.sin(ang) * d, lean = (rnd() - 0.5) * 0.35;
    const prof = (t) => r * (0.8 + 0.35 * t + 0.12 * Math.sin(t * Math.PI)) * (t > 0.94 ? 1.08 : 1);
    const outer = [], inner = [];
    for (let j = 0; j <= rows; j++) {
      const t = j / rows;
      outer.push(new THREE.Vector2(prof(t) * (lod ? 1 : 1 + 0.04 * Math.sin(j * 2.2)), t * h));
    }
    for (let j = rows; j >= 0; j--) inner.push(new THREE.Vector2(prof(j / rows) * 0.78, (j / rows) * h * 0.98));
    const g = new THREE.LatheGeometry(outer.concat(inner), radial);
    g.rotateZ(lean);
    g.translate(ox, 0, oz);
    const out = G.prep(g, base);
    const p = out.attributes.position, c = out.attributes.color, glow = out.attributes.aGlow;
    for (let k = 0; k < p.count; k++) {
      const x = p.getX(k) - ox, y = p.getY(k), z = p.getZ(k) - oz;
      const rr = Math.hypot(x, z);
      const isInner = rr < prof(Math.min(1, Math.max(0, y / h))) * 0.85;
      const pore = Math.sin(Math.atan2(z, x) * 9) * Math.sin(y * 28) > 0.6 ? 0.8 : 1;
      const k2 = isInner ? 0.35 : pore * (0.8 + 0.3 * (y / h));
      c.setXYZ(k, base.r * k2, base.g * k2, base.b * k2);
      glow.setX(k, !isInner && y > h * 0.965 ? 0.45 : 0);
    }
    parts.push(out);
  }
  return G.merge(parts);
}

// ------------------------------------------------------------------ ANEMONE
export function anemoneGeometry(seed = 1, color = 0x5a3a7a, { lod = 0 } = {}) {
  const rnd = mulberry32(seed * 3 + 11);
  const parts = [];
  const col = new THREE.Color(color);
  const column = new THREE.LatheGeometry([
    new THREE.Vector2(0.0, 0), new THREE.Vector2(0.24, 0), new THREE.Vector2(0.2, 0.08), new THREE.Vector2(0.16, 0.18),
    new THREE.Vector2(0.18, 0.25), new THREE.Vector2(0.22, 0.27), new THREE.Vector2(0.06, 0.26), new THREE.Vector2(0, 0.24),
  ], lod ? 6 : 14);
  parts.push(G.prep(column, col));
  const n = lod ? 12 : 30;
  const tipC = new THREE.Color(0xe8d8ff);
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + rnd() * 0.2;
    const ring = i % 2 ? 0.17 : 0.12;
    const len = 0.32 + rnd() * 0.3;
    const pts = [];
    const segs = lod ? 2 : 5;
    for (let k = 0; k <= segs; k++) {
      const t = k / segs;
      const out = ring + len * 0.55 * t, up = 0.25 + len * (0.9 * t - 0.25 * t * t);
      const sway = Math.sin(t * 3 + i) * 0.04 * t;
      pts.push(V(Math.cos(a + sway) * out, up, Math.sin(a + sway) * out));
    }
    const g = G.tubeAlong(pts, 0.024, 0.007, 3, tipC, (x, y) => (y > 0.25 + len * 0.55 ? 1 : 0.1), lod ? 2 : 5);
    G.colorize(g, (x, y, z, c) => c.copy(col).lerp(tipC, Math.min(1, (y - 0.25) / len)));
    parts.push(g);
  }
  return G.merge(parts);
}

// ------------------------------------------------------------------ GIANT TUBE WORMS
export function tubeWormGeometry(seed = 1, { lod = 0 } = {}) {
  const rnd = mulberry32(seed * 5 + 2);
  const parts = [];
  const n = 9 + Math.floor(rnd() * 8);
  for (let i = 0; i < n; i++) {
    const h = 0.6 + rnd() * 1.5;
    const a = rnd() * Math.PI * 2, d = rnd() * 0.45;
    const bx = Math.cos(a) * d, bz = Math.sin(a) * d, lean = (rnd() - 0.5) * 0.3;
    const pts = [V(bx, 0, bz), V(bx + lean * 0.3, h * 0.5, bz), V(bx + lean, h, bz + lean * 0.2)];
    const tube = G.tubeAlong(pts, 0.065, 0.05, lod ? 4 : 7, 0xd8d0c0, null, lod ? 2 : 6);
    // growth rings on the chitin tube
    G.colorize(tube, (x, y, z, c) => c.setRGB(0.85, 0.82, 0.74).multiplyScalar(Math.sin(y * 40) > 0.6 ? 0.78 : 1));
    parts.push(tube);
    const top = pts[2];
    if (lod) {
      parts.push(G.prep(new THREE.SphereGeometry(0.08, 5, 4).scale(1, 1.6, 1).translate(top.x, top.y + 0.08, top.z), 0xc02a2a, 0.6));
      continue;
    }
    // feathery red plume: a ring of blade-like lamellae
    for (let k = 0; k < 8; k++) {
      const pa = (k / 8) * Math.PI * 2;
      const dir = V(Math.cos(pa), 0, Math.sin(pa));
      parts.push(sheet((u, v) => V(
        top.x + dir.x * (0.02 + 0.06 * u) + (v - 0.5) * 0.05 * -dir.z,
        top.y + 0.02 + u * 0.2,
        top.z + dir.z * (0.02 + 0.06 * u) + (v - 0.5) * 0.05 * dir.x,
      ), 3, 1, (u, v, c) => c.setRGB(0.75, 0.12, 0.12).multiplyScalar(0.8 + u * 0.4), () => 0.6));
    }
  }
  return G.merge(parts);
}
