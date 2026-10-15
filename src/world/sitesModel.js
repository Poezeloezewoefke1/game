// Detailed landmark pieces: the Old Bones (a leviathan fall), the Listening
// Stone and the Threshold gate. Visual only; Structures keeps the original
// colliders, scannables and interactables.

import * as THREE from 'three';
import { finish, limb, mergeParts, trunk, ellipse, smooth, mix } from '../creatures/anatomy.js';
import { fbm3 } from './rocks.js';
import { roundedBox, place } from './shapes.js';
import { mulberry32 } from '../core/noise.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);

// ------------------------------------------------------------------ BONE
const IVORY = new THREE.Color(0.82, 0.78, 0.68), STAIN = new THREE.Color(0.45, 0.36, 0.24), ALGAE = new THREE.Color(0.36, 0.42, 0.28);
/** Weathered bone colour: ivory with tannin stains, pits and algae on upper faces. */
export function boneColor(seed = 0, scale = 1) {
  return (x, y, z, c) => {
    const n = fbm3(x * 0.9 / scale + seed, y * 0.9 / scale, z * 0.9 / scale, 3);
    const pit = fbm3(x * 4 / scale, y * 4 / scale + seed, z * 4 / scale, 2);
    c.copy(IVORY).lerp(STAIN, smooth(-0.1, 0.45, n) * 0.75);
    if (pit < -0.25) c.multiplyScalar(0.7);
    const top = smooth(0.3, 1.2, y / scale);
    c.lerp(ALGAE, top * smooth(0.0, 0.4, fbm3(x * 0.5 + 9, y * 0.5, z * 0.5, 2)) * 0.6);
  };
}

function erode(geo, amt, freq, seed) {
  const p = geo.attributes.position, n = geo.attributes.normal;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const d = fbm3(x * freq + seed, y * freq, z * freq, 3) * amt;
    p.setXYZ(i, x + n.getX(i) * d, y + n.getY(i) * d, z + n.getZ(i) * d);
  }
  geo.computeVertexNormals();
  return geo;
}

/** One vertebra, spine axis along local z, dorsal toward +y (fits the classic sphere r1.3). */
export function vertebraGeometry(seed = 1) {
  const parts = [];
  const col = boneColor(seed, 1.4);
  // spool-shaped centrum with rims at the joint faces
  const cen = trunk({ z0: -1.05, z1: 1.05, segs: 14, radial: 22, section: (t, a) => {
    const rim = 1 + 0.06 * (smooth(0.12, 0, t) + smooth(0.88, 1, t));
    return ellipse(1.12 * (1 - 0.16 * Math.sin(Math.PI * t)) * rim, { hx: 1, hy: 0.92 })(a);
  } });
  parts.push(finish(erode(cen, 0.05, 1.6, seed), { color: col }));
  // neural arch around the spinal canal + a tall, raked neural spine
  const arch = new THREE.TorusGeometry(0.55, 0.22, 8, 16, Math.PI).translate(0, 1.15, 0);
  parts.push(finish(arch, { color: col }));
  parts.push(finish(erode(new THREE.CylinderGeometry(0.16, 0.42, 3.0, 10, 6).scale(0.45, 1, 1.05).translate(0, 2.9, 0).rotateX(-0.3), 0.04, 2, seed + 1), { color: col }));
  // transverse processes (flattened wings) and small zygapophyses
  for (const s of [-1, 1]) {
    parts.push(finish(erode(new THREE.CylinderGeometry(0.12, 0.3, 2.2, 8, 4).scale(1, 1, 0.35).rotateZ(-s * (Math.PI / 2 - 0.25)).translate(s * 1.6, -0.15, 0.1), 0.04, 2, seed + 2), { color: col }));
    parts.push(finish(new THREE.SphereGeometry(0.22, 8, 6).translate(s * 0.45, 1.45, 0.9), { color: col }));
  }
  return mergeParts(parts);
}

/** Flattened, tapering rib through `pts` (radius r0 -> r1), broken tip when `broken`. */
export function ribGeometry(pts, r0, r1, seed = 1, broken = false) {
  const use = broken ? pts.slice(0, pts.length - 1).concat([pts[pts.length - 2].clone().lerp(pts[pts.length - 1], 0.45)]) : pts;
  const g = limb(use, r0, r1, { radial: 8, segs: 20, color: boneColor(seed, 3) });
  return g;
}

/** Leviathan skull shell (rostrum toward +x) with orbits, nares and the opened crown. */
export function skullGeometry() {
  const L = 22;
  const R = (t) => {
    // rounded braincase at the back, long tapering rostrum toward the tip
    const back = Math.sin(Math.min(1, t / 0.5) * Math.PI / 2) ** 0.5;
    const front = 1 - smooth(0.3, 1, t) * 0.85;
    return 5.2 * back * front + 0.3;
  };
  // tall domed braincase, broad flat rostrum, occipital crest on top of the braincase
  const sec = (t, a) => {
    const hy = mix(0.9, 0.38, smooth(0.22, 0.55, t));
    const hx = mix(0.95, 1.15, smooth(0.3, 0.6, t));
    const [x, y] = ellipse(R(t), { hx, hy, belly: 0.7, keel: t < 0.3 ? 0.5 : 0, yo: 1.2 * (1 - smooth(0.2, 0.6, t)) })(a);
    // zygomatic flare below the orbits
    const zyg = Math.exp(-(((t - 0.4) / 0.08) ** 2)) * Math.max(0, -Math.sin(a) + 0.2) * 1.1;
    return [x + Math.sign(x) * zyg, y];
  };
  const g = trunk({ z0: -L / 2, z1: L / 2, segs: 64, radial: 48, section: sec });
  // carve openings by dropping triangles: two orbits, the nares and the broken crown
  const p = g.attributes.position;
  const idx = g.index.array;
  const keep = [];
  const hole = (x, y, z) => {
    const t = (z + L / 2) / L;
    const orbit = Math.hypot((t - 0.43) / 0.075, (y - 0.9) / 1.3) < 1 && Math.abs(x) > 1.8;
    const nares = Math.hypot((t - 0.36) / 0.035, x / 1.1) < 1 && y > 1.5;
    const crown = t < 0.3 && y > 1.6 + 1.2 * fbm3(x * 0.4, z * 0.4, 3, 3);
    return orbit || nares || crown;
  };
  for (let i = 0; i < idx.length; i += 3) {
    let cx = 0, cy = 0, cz = 0;
    for (let k = 0; k < 3; k++) { cx += p.getX(idx[i + k]); cy += p.getY(idx[i + k]); cz += p.getZ(idx[i + k]); }
    if (!hole(cx / 3, cy / 3, cz / 3)) keep.push(idx[i], idx[i + 1], idx[i + 2]);
  }
  g.setIndex(keep);
  erode(g, 0.18, 0.35, 4);
  // inner skin so the opened skull reads from inside too
  const inner = g.clone();
  const ip = inner.attributes.position, inn = inner.attributes.normal;
  for (let k = 0; k < ip.count; k++) ip.setXYZ(k, ip.getX(k) - inn.getX(k) * 0.25, ip.getY(k) - inn.getY(k) * 0.25, ip.getZ(k) - inn.getZ(k) * 0.25);
  const ix = Array.from(inner.index.array);
  for (let k = 0; k < ix.length; k += 3) { const t = ix[k + 1]; ix[k + 1] = ix[k + 2]; ix[k + 2] = t; }
  inner.setIndex(ix);
  inner.computeVertexNormals();
  const base = boneColor(7, 4);
  const col = (x, y, z, c) => {
    base(x, y, z, c);
    // sutures between the skull plates
    const sut = Math.abs(fbm3(x * 0.25 + 3, y * 0.25, z * 0.25, 2));
    if (sut < 0.025) c.multiplyScalar(0.55);
  };
  const out = mergeParts([finish(g, { color: col }), finish(inner, { color: (x, y, z, c) => { col(x, y, z, c); c.multiplyScalar(0.55); } })]);
  out.rotateY(Math.PI / 2); // rostrum z -> +x
  return out;
}

/** Mandible along the classic jaw points, with a row of conical teeth. */
export function mandibleGeometry(a, b, c, seed = 1) {
  const pts = [a, a.clone().lerp(b, 0.5).add(V(0, -0.4, 0)), b, b.clone().lerp(c, 0.5).add(V(0, 0.1, 0)), c];
  const parts = [limb(pts, 0.75, 0.35, { radial: 9, segs: 24, color: boneColor(seed, 3) })];
  const curve = new THREE.CatmullRomCurve3(pts);
  for (let i = 0; i < 14; i++) {
    const t = 0.25 + (i / 13) * 0.7;
    const q = curve.getPointAt(t);
    const len = 0.5 + 0.5 * Math.sin(t * Math.PI);
    const cone = new THREE.ConeGeometry(0.14, len, 6).translate(0, len / 2 + 0.45, 0);
    parts.push(finish(cone.translate(q.x, q.y, q.z), { color: (x, y, z, cc) => cc.setRGB(0.86, 0.82, 0.72) }));
  }
  return mergeParts(parts);
}

// ------------------------------------------------------------------ LISTENING STONE
/** Eroded tapering slab (3.2 x 15 x 1.6), glyph UVs kept from the box layout. */
export function monolithGeometry() {
  const g = new THREE.BoxGeometry(3.2, 15, 1.6, 10, 48, 6);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const t = (y + 7.5) / 15;
    x *= 1 - t * 0.25; z *= 1 - t * 0.2;
    // rounded, worn arrises
    const ex = Math.abs(x) / (1.6 * (1 - t * 0.25)), ez = Math.abs(z) / (0.8 * (1 - t * 0.2));
    const corner = smooth(0.75, 1, ex) * smooth(0.6, 1, ez);
    x *= 1 - corner * 0.08; z *= 1 - corner * 0.12;
    // broken, slanted crown
    const crown = 7.5 - 0.9 * (x + 1.6) / 3.2 - 0.6 * smooth(0, 1, fbm3(x * 1.2, z * 2, 3, 3) + 0.5);
    if (y > crown) y = crown + (y - crown) * 0.05;
    const e = fbm3(x * 1.4, y * 0.9, z * 1.4, 4) * 0.07 + fbm3(x * 5, y * 4, z * 5, 2) * 0.02;
    const nx = Math.sign(x) * smooth(0.6, 1, ex), nz = Math.sign(z) * smooth(0.6, 1, ez);
    p.setXYZ(i, x + nx * e, y, z + nz * e);
  }
  g.computeVertexNormals();
  return g;
}

// ------------------------------------------------------------------ THRESHOLD
/** Segmented ring (radius R, section half-size h) in the XY plane, glyph UVs around. */
export function gateRingGeometry(R = 30, h = 3.2, segments = 16) {
  // profile in (r, y): rounded square with a groove on each face
  const prof = [];
  const N = 40;
  for (let i = 0; i <= N; i++) {
    const a = (i / N) * Math.PI * 2;
    const c = Math.cos(a), s = Math.sin(a);
    const sq = 1 / Math.max(Math.abs(c), Math.abs(s)) ** 0.85; // rounded square
    const groove = 1 - 0.07 * Math.max(0, Math.cos(a * 4)) ** 12;
    prof.push(new THREE.Vector2(R + c * h * sq * groove * 0.82, s * h * sq * groove * 0.82));
  }
  const g = new THREE.LatheGeometry(prof, segments * 14);
  // joints between the segments
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i), y = p.getY(i);
    const ang = Math.atan2(z, x);
    const seg = ((ang / (Math.PI * 2)) * segments % 1 + 1) % 1;
    const joint = Math.min(seg, 1 - seg) < 0.012 ? 0.93 : 1;
    const r = Math.hypot(x, z);
    const off = (r - R) * joint + R;
    const e = 1 + fbm3(x * 0.3, y * 0.3, z * 0.3, 2) * 0.01;
    p.setXYZ(i, (x / r) * off * e, y * joint, (z / r) * off * e);
  }
  g.computeVertexNormals();
  g.rotateX(Math.PI / 2); // axis y -> z: ring in the XY plane
  return g;
}

/** Carved fins on the ring's outer rim and the stepped plinth rim stones. */
export function gateDetails(R = 30, h = 3.2) {
  const parts = [];
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2 + Math.PI / 8;
    const g = roundedBox(2.2, 5.5, h * 2.3, 0.4, 2);
    place(g, [Math.cos(a) * (R + h + 1.8), Math.sin(a) * (R + h + 1.8), 0], [0, 0, a - Math.PI / 2]);
    parts.push(g);
  }
  return parts;
}

export function plinthStones(radii, ys, seed = 3) {
  const rr = mulberry32(seed);
  const out = [];
  radii.forEach((r, i) => {
    const n = Math.round((Math.PI * 2 * r) / 3.2);
    for (let k = 0; k < n; k++) {
      if (rr() < 0.06) continue;
      const a = (k / n) * Math.PI * 2;
      out.push(place(roundedBox(3.0, 1.3, 1.6, 0.15, 2), [Math.cos(a) * (r - 0.7), ys[i] + (rr() < 0.1 ? -0.3 : 0), Math.sin(a) * (r - 0.7)], [0, -a + Math.PI / 2, (rr() - 0.5) * 0.05]));
    }
  });
  return out;
}
