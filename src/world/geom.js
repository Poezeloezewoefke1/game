// Procedural geometry helpers shared by flora, structures and creatures.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Simplex, mulberry32 } from '../core/noise.js';

const simplex = new Simplex(99);

/** Normalise attributes (non-indexed, color, aGlow) so geometries can be merged. */
export function prep(geo, color = 0xffffff, glow = 0) {
  let g = geo.index ? geo.toNonIndexed() : geo;
  g.deleteAttribute('uv');
  if (g.attributes.uv1) g.deleteAttribute('uv1');
  const n = g.attributes.position.count;
  if (!g.attributes.color) {
    const c = new THREE.Color(color);
    const arr = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) { arr[i * 3] = c.r; arr[i * 3 + 1] = c.g; arr[i * 3 + 2] = c.b; }
    g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  }
  if (!g.attributes.aGlow) {
    const arr = new Float32Array(n);
    arr.fill(typeof glow === 'number' ? glow : 0);
    if (typeof glow === 'function') {
      const p = g.attributes.position;
      for (let i = 0; i < n; i++) arr[i] = glow(p.getX(i), p.getY(i), p.getZ(i));
    }
    g.setAttribute('aGlow', new THREE.BufferAttribute(arr, 1));
  }
  if (!g.attributes.normal) g.computeVertexNormals();
  return g;
}

export function merge(list) {
  const g = mergeGeometries(list, false);
  g.computeBoundingSphere();
  return g;
}

export function colorize(geo, fn) {
  const p = geo.attributes.position;
  const c = geo.attributes.color;
  const col = new THREE.Color();
  for (let i = 0; i < p.count; i++) {
    fn(p.getX(i), p.getY(i), p.getZ(i), col);
    c.setXYZ(i, col.r, col.g, col.b);
  }
  c.needsUpdate = true;
  return geo;
}

/** A bumpy boulder. */
export function rockGeometry(seed = 1, detail = 2, roughness = 0.35) {
  const g = new THREE.IcosahedronGeometry(1, detail);
  const p = g.attributes.position;
  const v = new THREE.Vector3();
  const ox = seed * 13.1, oz = seed * 7.7;
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const n = simplex.noise2(v.x * 1.3 + ox, v.y * 1.3 + v.z * 0.7 + oz) * 0.6
      + simplex.noise2(v.x * 3.1 - oz, v.z * 3.1 + v.y + ox) * 0.25;
    v.multiplyScalar(1 + n * roughness);
    v.y *= 0.72;
    p.setXYZ(i, v.x, v.y, v.z);
  }
  g.computeVertexNormals();
  return prep(g, 0x8a8f94);
}

/** Tapered tube along a list of points (for stems, tentacles, coral branches). */
export function tubeAlong(points, r0, r1, radial = 6, color = 0xffffff, glowFn = null, segCount = 0) {
  const curve = new THREE.CatmullRomCurve3(points);
  const segs = segCount || Math.max(2, points.length * 2);
  const g = new THREE.TubeGeometry(curve, segs, 1, radial, false);
  // taper: scale each ring around the curve
  const p = g.attributes.position;
  const v = new THREE.Vector3();
  const c = new THREE.Vector3();
  for (let s = 0; s <= segs; s++) {
    const t = s / segs;
    curve.getPointAt(t, c);
    const r = r0 + (r1 - r0) * t;
    for (let k = 0; k <= radial; k++) {
      const i = s * (radial + 1) + k;
      v.fromBufferAttribute(p, i).sub(c).multiplyScalar(r).add(c);
      p.setXYZ(i, v.x, v.y, v.z);
    }
  }
  g.computeVertexNormals();
  return prep(g, color, glowFn || 0);
}

export function seagrassGeometry(seed = 1) {
  const rnd = mulberry32(seed);
  const parts = [];
  const blades = 7;
  for (let b = 0; b < blades; b++) {
    const h = 0.7 + rnd() * 0.9;
    const a = rnd() * Math.PI * 2;
    const ox = Math.cos(a) * rnd() * 0.25, oz = Math.sin(a) * rnd() * 0.25;
    const lean = 0.15 + rnd() * 0.3;
    const segs = 3;
    const pos = [];
    for (let s = 0; s < segs; s++) {
      const t0 = s / segs, t1 = (s + 1) / segs;
      const w0 = 0.05 * (1 - t0) + 0.005, w1 = 0.05 * (1 - t1) + 0.005;
      const y0 = t0 * h, y1 = t1 * h;
      const l0 = lean * t0 * t0, l1 = lean * t1 * t1;
      const dx = Math.cos(a), dz = Math.sin(a);
      const px = -dz, pz = dx;
      const A = [ox + dx * l0 - px * w0, y0, oz + dz * l0 - pz * w0];
      const B = [ox + dx * l0 + px * w0, y0, oz + dz * l0 + pz * w0];
      const C = [ox + dx * l1 - px * w1, y1, oz + dz * l1 - pz * w1];
      const D = [ox + dx * l1 + px * w1, y1, oz + dz * l1 + pz * w1];
      pos.push(...A, ...B, ...D, ...A, ...D, ...C);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.computeVertexNormals();
    const tint = new THREE.Color().setHSL(0.36 + rnd() * 0.08, 0.45, 0.32 + rnd() * 0.1);
    parts.push(prep(g, tint, (x, y) => (y > h * 0.9 ? 0.3 : 0)));
  }
  return merge(parts);
}

export function kelpGeometry(seed = 1) {
  // height normalised to 1 (instance scale y = real height); x/z scale ~1.3-2.1
  const rnd = mulberry32(seed);
  const parts = [];
  const stem = [];
  for (let i = 0; i <= 8; i++) stem.push(new THREE.Vector3(Math.sin(i * 0.7 + seed) * 0.05, i / 8, Math.cos(i * 0.5) * 0.05));
  parts.push(tubeAlong(stem, 0.035, 0.012, 4, 0x4f6b2e, null, 8));
  const leaves = 22;
  for (let l = 0; l < leaves; l++) {
    const t = 0.08 + (l / leaves) * 0.9;
    const a = l * 2.4 + rnd() * 0.6;
    const len = 0.6 + rnd() * 0.5;
    const w = 0.07 + rnd() * 0.05;
    const rise = 0.035 + rnd() * 0.03;
    const dir = new THREE.Vector3(Math.cos(a), 0, Math.sin(a));
    const side = new THREE.Vector3(-dir.z, 0, dir.x);
    const segs = 5;
    const pos = [];
    const pt = (u) => dir.clone().multiplyScalar(u * len).add(new THREE.Vector3(0, t + u * rise - u * u * rise * 0.4, 0)).addScaledVector(side, Math.sin(u * 5 + l) * 0.04 * u);
    for (let s2 = 0; s2 < segs; s2++) {
      const u0 = s2 / segs, u1 = (s2 + 1) / segs;
      const wid0 = Math.sin(Math.min(1, u0 * 1.6 + 0.08) * Math.PI * 0.5) * w * (1 - u0 * 0.6) + 0.004;
      const wid1 = Math.sin(Math.min(1, u1 * 1.6 + 0.08) * Math.PI * 0.5) * w * (1 - u1 * 0.6) + 0.004;
      const p0 = pt(u0), p1 = pt(u1);
      const A = p0.clone().addScaledVector(side, -wid0), B = p0.clone().addScaledVector(side, wid0);
      const C = p1.clone().addScaledVector(side, -wid1), D = p1.clone().addScaledVector(side, wid1);
      pos.push(...A.toArray(), ...B.toArray(), ...D.toArray(), ...A.toArray(), ...D.toArray(), ...C.toArray());
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.computeVertexNormals();
    const col = new THREE.Color().setHSL(0.17 + rnd() * 0.07, 0.5, 0.26 + rnd() * 0.1);
    const leaf = prep(g, col);
    colorize(leaf, (x, y, z, c) => { const r = Math.hypot(x, z) / len; c.copy(col).multiplyScalar(0.75 + r * 0.5); });
    parts.push(leaf);
    if (l % 3 === 0) {
      const b = new THREE.OctahedronGeometry(0.03, 0);
      b.scale(1, 0.06, 1);
      b.translate(Math.cos(a) * 0.05, t, Math.sin(a) * 0.05);
      parts.push(prep(b, 0x9be7ff, 1));
    }
  }
  return merge(parts);
}

export function branchCoralGeometry(seed = 1, color = 0xd2694a) {
  const rnd = mulberry32(seed);
  const parts = [];
  const tip = new THREE.Color(color).offsetHSL(0.03, 0.1, 0.2);
  function branch(start, dir, len, r, depth) {
    const pts = [start.clone()];
    const p = start.clone();
    const d = dir.clone();
    for (let i = 0; i < 3; i++) {
      d.x += (rnd() - 0.5) * 0.5; d.z += (rnd() - 0.5) * 0.5; d.y += 0.15;
      d.normalize();
      p.addScaledVector(d, len / 3);
      pts.push(p.clone());
    }
    parts.push(tubeAlong(pts, r, r * 0.65, 4, depth > 1 ? tip : color, depth > 1 ? () => 0.25 : null, 3));
    if (depth < 3) {
      const n = 2 + (rnd() < 0.4 ? 1 : 0);
      for (let k = 0; k < n; k++) {
        const nd = d.clone().add(new THREE.Vector3((rnd() - 0.5) * 1.4, rnd() * 0.4, (rnd() - 0.5) * 1.4)).normalize();
        branch(p, nd, len * 0.72, r * 0.62, depth + 1);
      }
    }
  }
  branch(new THREE.Vector3(0, -0.1, 0), new THREE.Vector3(0, 1, 0), 0.6, 0.09, 0);
  return merge(parts);
}

export function fanCoralGeometry(seed = 1, color = 0x8e4fb0) {
  const rnd = mulberry32(seed);
  const shape = new THREE.Shape();
  shape.moveTo(0, 0);
  const n = 14;
  for (let i = 0; i <= n; i++) {
    const a = Math.PI * 0.15 + (i / n) * Math.PI * 0.7;
    const r = 0.9 + rnd() * 0.25;
    shape.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  shape.lineTo(0, 0);
  const g = new THREE.ShapeGeometry(shape, 6);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i);
    p.setZ(i, Math.sin(x * 3 + seed) * 0.08 + Math.cos(y * 4) * 0.05);
  }
  g.computeVertexNormals();
  const out = prep(g, color, (x, y) => (Math.hypot(x, y) > 0.85 ? 0.35 : 0));
  colorize(out, (x, y, z, c) => {
    const vein = Math.abs(Math.sin(Math.atan2(y, x) * 22)) > 0.85 ? 0.75 : 1;
    c.set(color).multiplyScalar(vein * (0.7 + Math.hypot(x, y) * 0.4));
  });
  return out;
}

export function brainCoralGeometry(seed = 1, color = 0xb7a26a) {
  const g = new THREE.SphereGeometry(1, 28, 16, 0, Math.PI * 2, 0, Math.PI * 0.55);
  const p = g.attributes.position;
  const v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const groove = Math.sin(v.x * 9 + Math.sin(v.z * 7 + seed) * 2) * Math.cos(v.z * 8 + v.y * 5);
    v.multiplyScalar(1 + groove * 0.05);
    v.y *= 0.7;
    p.setXYZ(i, v.x, v.y - 0.1, v.z);
  }
  g.computeVertexNormals();
  const out = prep(g, color);
  colorize(out, (x, y, z, c) => {
    const groove = Math.sin(x * 9 + Math.sin(z * 7 + seed) * 2) * Math.cos(z * 8 + y * 5);
    c.set(color).multiplyScalar(0.7 + groove * 0.25);
  });
  return out;
}

export function tubeSpongeGeometry(seed = 1, color = 0xc48b3a, glowRim = 0.8) {
  const rnd = mulberry32(seed);
  const parts = [];
  const n = 3 + Math.floor(rnd() * 4);
  for (let i = 0; i < n; i++) {
    const h = 0.6 + rnd() * 1.2;
    const r = 0.08 + rnd() * 0.08;
    const g = new THREE.CylinderGeometry(r * 1.15, r * 0.8, h, 10, 3, true);
    g.translate(0, h / 2, 0);
    const ang = rnd() * Math.PI * 2, d = rnd() * 0.3;
    g.rotateZ((rnd() - 0.5) * 0.4);
    g.translate(Math.cos(ang) * d, 0, Math.sin(ang) * d);
    parts.push(prep(g, color, (x, y) => (y > h * 0.92 ? glowRim : 0)));
    const inner = new THREE.CylinderGeometry(r * 1.05, r * 0.7, h * 0.98, 10, 1, true);
    inner.scale(-1, 1, 1);
    inner.translate(0, h / 2, 0);
    inner.translate(Math.cos(ang) * d, 0, Math.sin(ang) * d);
    parts.push(prep(inner, new THREE.Color(color).multiplyScalar(0.4)));
  }
  return merge(parts);
}

export function anemoneGeometry(seed = 1, color = 0x5a3a7a) {
  const rnd = mulberry32(seed);
  const parts = [];
  const base = new THREE.CylinderGeometry(0.16, 0.22, 0.25, 10);
  base.translate(0, 0.12, 0);
  parts.push(prep(base, color));
  const n = 18;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + rnd() * 0.3;
    const r = 0.06 + rnd() * 0.09;
    const len = 0.35 + rnd() * 0.3;
    const pts = [
      new THREE.Vector3(Math.cos(a) * r, 0.24, Math.sin(a) * r),
      new THREE.Vector3(Math.cos(a) * (r + len * 0.3), 0.24 + len * 0.5, Math.sin(a) * (r + len * 0.3)),
      new THREE.Vector3(Math.cos(a) * (r + len * 0.55), 0.24 + len * 0.85, Math.sin(a) * (r + len * 0.55)),
    ];
    parts.push(tubeAlong(pts, 0.022, 0.006, 3, 0xd0c8e0, (x, y) => (y > 0.24 + len * 0.6 ? 1 : 0), 3));
  }
  return merge(parts);
}

export function lanternPlantGeometry(seed = 1) {
  const rnd = mulberry32(seed);
  const parts = [];
  const h = 1.0 + rnd() * 0.8;
  const pts = [];
  for (let i = 0; i <= 4; i++) pts.push(new THREE.Vector3(Math.sin(i * 0.9 + seed) * 0.12 * (i / 4), (i / 4) * h, Math.cos(i * 0.7) * 0.06 * (i / 4)));
  parts.push(tubeAlong(pts, 0.035, 0.02, 4, 0x2f4a3a, null, 6));
  const top = pts[pts.length - 1];
  const bulb = new THREE.SphereGeometry(0.16, 8, 6);
  bulb.scale(1, 1.35, 1);
  bulb.translate(top.x, top.y + 0.12, top.z);
  parts.push(prep(bulb, 0x8ef0ff, 1));
  // hood petals
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * Math.PI * 2;
    const petal = new THREE.SphereGeometry(0.14, 3, 2, 0, Math.PI * 0.6, 0, Math.PI * 0.5);
    petal.rotateY(a);
    petal.scale(1.1, 1.0, 1.1);
    petal.translate(top.x, top.y + 0.2, top.z);
    parts.push(prep(petal, 0x3b5f4a));
  }
  // small leaves
  for (let k = 0; k < 3; k++) {
    const leaf = new THREE.SphereGeometry(0.12, 5, 3);
    leaf.scale(1.6, 0.15, 0.6);
    leaf.rotateY(k * 2.1);
    leaf.translate(0, 0.15 + k * 0.12, 0);
    parts.push(prep(leaf, 0x3d6b45));
  }
  return merge(parts);
}

export function crystalClusterGeometry(seed = 1, color = 0x7a5cff) {
  const rnd = mulberry32(seed);
  const parts = [];
  const n = 5 + Math.floor(rnd() * 6);
  for (let i = 0; i < n; i++) {
    const h = 0.5 + rnd() * 1.6;
    const r = 0.08 + rnd() * 0.12;
    const g = new THREE.CylinderGeometry(0, r, h * 0.25, 6, 1);
    g.translate(0, h * 0.875, 0);
    const body = new THREE.CylinderGeometry(r, r * 1.05, h * 0.75, 6, 1);
    body.translate(0, h * 0.375, 0);
    const m = merge([prep(body, color, (x, y) => 0.25 + (y / h) * 0.6), prep(g, color, 1)]);
    m.rotateZ((rnd() - 0.5) * 1.1);
    m.rotateX((rnd() - 0.5) * 1.1);
    m.translate((rnd() - 0.5) * 0.4, 0, (rnd() - 0.5) * 0.4);
    parts.push(m);
  }
  return merge(parts);
}

export function tubeWormGeometry(seed = 1) {
  const rnd = mulberry32(seed);
  const parts = [];
  const n = 8 + Math.floor(rnd() * 8);
  for (let i = 0; i < n; i++) {
    const h = 0.6 + rnd() * 1.4;
    const a = rnd() * Math.PI * 2, d = rnd() * 0.45;
    const g = new THREE.CylinderGeometry(0.045, 0.06, h, 6, 1, true);
    g.translate(Math.cos(a) * d, h / 2, Math.sin(a) * d);
    parts.push(prep(g, 0xd8d0c0));
    const plume = new THREE.SphereGeometry(0.07, 6, 5);
    plume.scale(1, 1.6, 1);
    plume.translate(Math.cos(a) * d, h + 0.08, Math.sin(a) * d);
    parts.push(prep(plume, 0xc02a2a, 0.6));
  }
  return merge(parts);
}
