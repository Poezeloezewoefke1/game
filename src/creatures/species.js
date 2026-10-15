// Detailed creature anatomy (the graphics rebuild). Each species keeps the
// size, pivot and +z-forward contract of the classic bodies in bodies.js so
// behaviour, scan radii and swim uniforms are unchanged; `lod` builds a
// lighter version for distance.

import * as THREE from 'three';
import { V3, smooth, mix, mottle, finish, trunk, ellipse, fin, finColor, eye, teeth, limb, sphere, mergeParts } from './anatomy.js';

const clamp01 = (t) => Math.min(1, Math.max(0, t));
const col = (r, g, b) => new THREE.Color(r, g, b);
const lerpC = (c, a, b, t) => c.setRGB(mix(a.r, b.r, t), mix(a.g, b.g, t), mix(a.b, b.b, t));
const n = (v, q) => Math.max(3, Math.round(v * q));

/** Shared body colouring: countershading + mottling + optional pattern multiplier. */
function shade({ R, T, back, flank, belly, pattern, mot = 7, motAmt = 0.3 }) {
  return (x, y, z, c) => {
    const r = Math.max(R(clamp01(T(z))), 1e-3);
    const yn = y / r;
    lerpC(c, belly, flank, smooth(-0.85, -0.15, yn));
    const k = smooth(0.1, 0.75, yn);
    c.setRGB(mix(c.r, back.r, k), mix(c.g, back.g, k), mix(c.b, back.b, k));
    let m = 1 - motAmt * 0.5 + motAmt * mottle(x, y, z, mot);
    if (pattern) m *= pattern(x, y, z, yn, r);
    c.multiplyScalar(m);
  };
}

/** Hinge a list of geometries about the x axis through (y, z). */
function hinge(parts, y, z, angle) {
  for (const g of parts) { g.translate(0, -y, -z); g.rotateX(angle); g.translate(0, y, z); }
  return parts;
}

// ------------------------------------------------------------------ GLIMMERFIN
// 1 unit long, head +z. Used as the procedural fallback and as the far LOD of
// the external fish model, so its palette follows that model.
export function glimmerfin({ lod = 0 } = {}) {
  const q = lod ? 0.4 : 1;
  const z0 = -0.36, z1 = 0.5;
  const T = (z) => (z - z0) / (z1 - z0);
  const R = (t) => 0.15 * Math.pow(Math.max(0, Math.sin(Math.PI * Math.pow(t, 0.8))), 0.6) + 0.012;
  const sec = (t, a) => ellipse(R(t), { hx: 0.44, belly: 0.25 })(a);
  const P = (z, a) => sec(clamp01(T(z)), a);
  const parts = [];
  parts.push(finish(trunk({ z0, z1, segs: n(22, q), radial: lod ? 8 : 16, section: sec }), {
    color: shade({ R, T, back: col(0.16, 0.22, 0.27), flank: col(0.6, 0.66, 0.7), belly: col(0.84, 0.86, 0.86), mot: 18, motAmt: 0.18,
      pattern: (x, y, z, yn) => (z > 0.3 && z < 0.34 && Math.abs(yn) < 0.7 ? 0.65 : lod && z > 0.35 && z < 0.4 && yn > 0 && yn < 0.6 ? 0.15 : 1) }),
    glow: (x, y, z) => (lod && Math.abs(y) < 0.012 && z > -0.28 && z < 0.3 ? 0.35 : 0),
  }));
  // bioluminescent lateral line: a thin strip just proud of each flank
  if (!lod) for (const s of [-1, 1]) {
    parts.push(fin((u, v) => {
      const z = mix(0.3, -0.26, u), w = 0.007 * Math.sin(Math.PI * u) + 0.002;
      const yy = (v * 2 - 1) * w + 0.01;
      const a = Math.asin(Math.max(-1, Math.min(1, yy / Math.max(R(clamp01(T(z))), 1e-3))));
      const [x, y] = P(z, s > 0 ? a : Math.PI - a);
      return V3(x + s * 0.002, y, z);
    }, { nu: 10, nv: 1, thick: () => 0.0005, color: (u, v, c) => c.setRGB(0.8, 0.95, 1), glow: () => 0.9 }));
  }
  const fc = finColor(0x6d8496, 7, 0.35);
  // forked caudal fin
  parts.push(fin((u, v) => {
    const s = u * 2 - 1;
    const rootZ = z0 + 0.03;
    return V3(0, mix(s * 0.028, s * 0.175, v), mix(rootZ, rootZ - 0.07 - 0.12 * Math.abs(s) ** 1.3, v));
  }, { nu: n(10, q), nv: lod ? 1 : 4, thick: (u, v) => 0.006 * (1 - v), color: fc }));
  // dorsal + anal
  const top = (z) => P(z, Math.PI / 2)[1];
  const bot = (z) => P(z, -Math.PI / 2)[1];
  parts.push(fin((u, v) => { const z = mix(0.16, -0.14, u); const h = 0.11 * Math.pow(1 - u, 0.5) * smooth(0, 0.08, u); return V3(0, top(z) - 0.01 + h * v, z - 0.06 * v); },
    { nu: n(8, q), nv: lod ? 1 : 3, thick: (u, v) => 0.005 * (1 - v), color: fc }));
  if (!lod) parts.push(fin((u, v) => { const z = mix(-0.08, -0.25, u); const h = 0.06 * Math.pow(1 - u, 0.5) * smooth(0, 0.1, u); return V3(0, bot(z) + 0.01 - h * v, z - 0.04 * v); },
    { nu: n(6, q), nv: 3, thick: (u, v) => 0.004 * (1 - v), color: fc }));
  for (const s of [-1, 1]) {
    const a = s > 0 ? -0.5 : Math.PI + 0.5;
    parts.push(fin((u, v) => {
      const z = mix(0.27, 0.22, mix(u, 0.5, v * 0.7));
      const [x, y] = P(z, a);
      return V3(x * 0.96 + s * 0.09 * v, y - 0.03 * v, z - 0.07 * v);
    }, { nu: lod ? 2 : 4, nv: lod ? 1 : 3, thick: (u, v) => 0.004 * (1 - v), color: fc, fin: (u, v) => v * 0.6 }));
    if (lod) continue; // far fish: eye is painted into the body colour
    const [ex, ey] = P(0.37, s > 0 ? 0.35 : Math.PI - 0.35);
    parts.push(...eye(V3(ex * 0.9, ey, 0.37), 0.024, V3(s, 0.1, 0.25), { iris: 0xb8a060, rim: 0x2a3036, detail: 0.6 }));
  }
  return mergeParts(parts);
}

// ------------------------------------------------------------------ RAZORMAW
// 4 m ambush predator (barracuda / eel build), z -2..2, head +z.
export function razormaw({ lod = 0 } = {}) {
  const q = lod ? 0.45 : 1;
  const z0 = -1.75, z1 = 2.05;
  const T = (z) => (z - z0) / (z1 - z0);
  const R = (t) => 0.36 * Math.pow(Math.max(0, Math.sin(Math.PI * Math.pow(t, 1.3))), 0.7) + 0.022;
  const sec = (t, a) => ellipse(R(t), { hx: 0.72, belly: 0.4, keel: 0.3 })(a);
  const P = (z, a) => sec(clamp01(T(z)), a);
  const parts = [];
  const back = col(0.05, 0.075, 0.07), flank = col(0.3, 0.33, 0.3), belly = col(0.62, 0.62, 0.56);
  parts.push(finish(trunk({ z0, z1, segs: n(60, q), radial: n(22, q), section: sec }), {
    color: shade({ R, T, back, flank, belly, mot: 9,
      pattern: (x, y, z, yn) => {
        let m = 1;
        if (z < 1.25 && z > -1.5 && yn > -0.35 && Math.sin(z * 7.5 + 0.4 + yn * 0.6) > 0.35) m *= 0.45; // hunting bars
        if (z > 1.22 && z < 1.46 && Math.abs(yn) < 0.6 && ((z - 1.22) / 0.075) % 1 < 0.24) m *= 0.35; // gill slits
        return m;
      } }),
  }));
  // lower jaw: underslung, slightly open, with the mouth lining on top
  const jz0 = 1.42, jz1 = 2.17;
  const JT = (z) => (z - jz0) / (jz1 - jz0);
  const JR = (t) => 0.15 * Math.pow(Math.sin(Math.PI * (0.5 + 0.5 * t)), 0.6) + 0.006;
  const JY = (t) => -0.13 + 0.05 * t;
  const jaw = [];
  jaw.push(finish(trunk({ z0: jz0, z1: jz1, segs: n(16, q), radial: n(14, q), section: (t, a) => ellipse(JR(t), { hx: 0.95, hy: 0.5, yo: JY(t) })(a) }), {
    color: (x, y, z, c) => { const t = clamp01(JT(z)); if (y > JY(t) + 0.02) c.setRGB(0.16, 0.05, 0.05); else c.copy(belly).multiplyScalar(0.85 + 0.2 * mottle(x, y, z, 12)); },
  }));
  if (!lod) {
    for (const s of [-1, 1]) {
      jaw.push(...teeth((t) => { const z = mix(1.6, 2.1, t), tj = JT(z), r = JR(tj); return V3(s * 0.95 * r * 0.78, JY(tj) + 0.5 * r * 0.55, z); },
        8, (t) => 0.03 + 0.04 * Math.sin(t * Math.PI), 0.012, () => V3(0, 1, 0.3)));
      parts.push(...teeth((t) => { const z = mix(1.58, 2.0, t), a = -Math.PI / 2 + s * 0.8, [x, y] = P(z, a); return V3(x * 0.92, y + 0.01, z); },
        8, (t) => 0.035 + 0.035 * Math.sin(t * Math.PI), 0.012, () => V3(0, -1, 0.2)));
    }
  }
  parts.push(...hinge(jaw, -0.1, 1.5, 0.12));
  parts.push(sphere(V3(0, -0.075, 1.72), 1, { sx: 0.085, sy: 0.05, sz: 0.3, color: 0x2a0a08 }));
  // eyes (bioluminescent amber iris)
  for (const s of [-1, 1]) {
    const [ex, ey] = P(1.72, s > 0 ? 0.45 : Math.PI - 0.45);
    parts.push(...eye(V3(ex * 0.95, ey, 1.72), 0.044, V3(s, 0.25, 0.35), { iris: 0xffb040, rim: 0x141a18, glow: 0.9 }));
  }
  const fc = finColor(0x3a2418, 9, 0.3, 0.35);
  const top = (z) => P(z, Math.PI / 2)[1];
  const bot = (z) => P(z, -Math.PI / 2)[1];
  // long dorsal sail with spined, ragged edge
  parts.push(fin((u, v) => {
    const z = mix(0.95, -0.42, u);
    const h = 0.44 * Math.pow(1 - u, 0.45) * smooth(0, 0.07, u) * (0.82 + 0.18 * Math.abs(Math.cos(u * Math.PI * 8)));
    return V3(0, top(z) - 0.03 + h * v, z - 0.55 * h * v);
  }, { nu: n(22, q), nv: n(5, q), thick: (u, v) => 0.012 * (1 - v) * Math.sin(Math.PI * u) ** 0.4 + 0.0008, color: fc }));
  // second dorsal + anal finlets
  parts.push(fin((u, v) => { const z = mix(-0.7, -1.05, u); const h = 0.16 * Math.pow(1 - u, 0.5) * smooth(0, 0.1, u); return V3(0, top(z) - 0.02 + h * v, z - 0.4 * h * v); },
    { nu: n(8, q), nv: 3, thick: (u, v) => 0.008 * (1 - v), color: fc }));
  parts.push(fin((u, v) => { const z = mix(-0.5, -1.02, u); const h = 0.17 * Math.pow(1 - u, 0.5) * smooth(0, 0.1, u); return V3(0, bot(z) + 0.02 - h * v, z - 0.4 * h * v); },
    { nu: n(8, q), nv: 3, thick: (u, v) => 0.008 * (1 - v), color: fc }));
  // forked caudal fin
  parts.push(fin((u, v) => {
    const s = u * 2 - 1;
    return V3(0, mix(s * 0.06, s * 0.62, v), mix(z0 + 0.06, z0 + 0.06 - (0.2 + 0.36 * Math.abs(s) ** 1.5), v));
  }, { nu: n(14, q), nv: n(5, q), thick: (u, v) => 0.016 * (1 - v), color: finColor(0x3a2418, 12, 0.3, 0.35) }));
  // pectoral and pelvic fins (scull via aFin)
  for (const s of [-1, 1]) {
    const pa = s > 0 ? -0.45 : Math.PI + 0.45;
    parts.push(fin((u, v) => {
      const z = mix(1.3, 1.08, mix(u, 0.6, v * 0.75));
      const [x, y] = P(z, pa);
      return V3(x * 0.95 + s * 0.5 * v, y - 0.16 * v, z - 0.3 * v);
    }, { nu: n(6, q), nv: n(4, q), thick: (u, v) => 0.01 * (1 - v), color: fc, fin: (u, v) => v }));
    const va = s > 0 ? -1.2 : Math.PI + 1.2;
    parts.push(fin((u, v) => {
      const z = mix(0.32, 0.18, mix(u, 0.5, v * 0.7));
      const [x, y] = P(z, va);
      return V3(x * 0.95 + s * 0.13 * v, y - 0.13 * v, z - 0.17 * v);
    }, { nu: 4, nv: 3, thick: (u, v) => 0.007 * (1 - v), color: fc, fin: (u, v) => v * 0.6 }));
    // lateral-line photophores
    if (!lod) for (let z = 1.1; z > -1.25; z -= 0.17) {
      const [x, y] = P(z, s > 0 ? 0 : Math.PI);
      parts.push(sphere(V3(x * 0.99, y, z), 0.018, { w: 6, h: 4, color: 0xffc060, glow: 1 }));
    }
  }
  return mergeParts(parts);
}

// ------------------------------------------------------------------ HOLLOW STALKER
// 8 m deep predator: ridged eel body, armoured skull with hollow eye
// sockets, a gaping needle-toothed jaw, a throat lantern and a forehead lure.
export function stalker({ lod = 0 } = {}) {
  const q = lod ? 0.45 : 1;
  const parts = [];
  const bodyCol = col(0.075, 0.068, 0.072), bone = col(0.3, 0.27, 0.22);
  // body
  const bz0 = -3.9, bz1 = 2.3;
  const BT = (z) => (z - bz0) / (bz1 - bz0);
  const BR = (t) => 0.05 + 0.56 * Math.pow(t, 0.85);
  const bsec = (t, a) => ellipse(BR(t), { hx: 0.7, belly: 0.3, keel: 0.6 })(a);
  const BP = (z, a) => bsec(clamp01(BT(z)), a);
  parts.push(finish(trunk({ z0: bz0, z1: bz1, segs: n(60, q), radial: n(18, q), section: bsec }), {
    color: (x, y, z, c) => {
      const r = Math.max(BR(clamp01(BT(z))), 1e-3), yn = y / r;
      c.copy(bodyCol);
      const seg = ((z * 1.7) % 1 + 1) % 1;
      if (seg < 0.12) c.multiplyScalar(0.55); // armour segment seams
      else if (yn > 0.55) c.lerp(bone, 0.25 * (yn - 0.55) / 0.45);
      if (yn < -0.5) c.multiplyScalar(1.35);
      c.multiplyScalar(0.8 + 0.4 * mottle(x, y, z, 6));
    },
    glow: (x, y, z) => (z < 1.6 && z > -3 && Math.abs(y) < 0.05 && ((z * 2.2) % 1 + 1) % 1 < 0.08 ? 0.35 : 0),
  }));
  // skull
  const sz0 = 1.7, sz1 = 3.95;
  const ST = (z) => (z - sz0) / (sz1 - sz0);
  const SR = (t) => (0.6 + 0.35 * Math.sin(Math.PI * Math.min(1, t * 1.25))) * (1 - 0.45 * smooth(0.7, 1, t));
  const SY = (t) => 0.12 * t;
  const ssec = (t, a) => ellipse(SR(t), { hx: 0.85, hy: 0.9, belly: 0.65, yo: SY(t) })(a);
  const SP = (z, a) => ssec(clamp01(ST(z)), a);
  parts.push(finish(trunk({ z0: sz0, z1: sz1, segs: n(30, q), radial: n(22, q), section: ssec }), {
    color: (x, y, z, c) => {
      const t = clamp01(ST(z)), r = SR(t), yn = (y - SY(t)) / r;
      if (yn < -0.45 && z > 2.35) { c.setRGB(0.14, 0.035, 0.03); return; } // palate
      c.copy(bodyCol).lerp(bone, 0.35 + 0.35 * smooth(0, 0.8, yn));
      const plate = Math.abs(Math.sin(x * 7) * Math.sin(z * 6 + y * 3));
      if (plate < 0.12) c.multiplyScalar(0.45); // suture lines between skull plates
      c.multiplyScalar(0.75 + 0.45 * mottle(x, y, z, 5));
    },
  }));
  // gaping lower jaw
  const jz0 = 2.0, jz1 = 4.05;
  const JT = (z) => (z - jz0) / (jz1 - jz0);
  const JR = (t) => 0.55 * (1 - 0.5 * Math.pow(t, 1.5));
  const JY = (t) => -0.5 + 0.05 * t;
  const jaw = [finish(trunk({ z0: jz0, z1: jz1, segs: n(20, q), radial: n(16, q), section: (t, a) => ellipse(JR(t), { hx: 0.95, hy: 0.42, yo: JY(t) })(a) }), {
    color: (x, y, z, c) => { const t = clamp01(JT(z)); if (y > JY(t) + 0.06) c.setRGB(0.16, 0.04, 0.035); else c.copy(bodyCol).lerp(bone, 0.3).multiplyScalar(0.8 + 0.4 * mottle(x, y, z, 6)); },
  })];
  for (const s of [-1, 1]) {
    jaw.push(...teeth((t) => { const z = mix(2.5, 3.95, t), tj = JT(z), r = JR(tj); return V3(s * 0.95 * r * 0.8, JY(tj) + 0.42 * r * 0.5, z); },
      lod ? 4 : 9, (t) => 0.2 + 0.25 * t, 0.035, (t) => V3(-s * 0.15, 1, 0.25 + 0.2 * t)));
    parts.push(...teeth((t) => { const z = mix(2.45, 3.85, t), [x, y] = SP(z, -Math.PI / 2 + s * 0.85); return V3(x * 0.9, y + 0.03, z); },
      lod ? 4 : 9, (t) => 0.25 + 0.3 * t, 0.04, (t) => V3(-s * 0.12, -1, 0.3 + 0.2 * t)));
  }
  parts.push(...hinge(jaw, -0.3, 2.15, 0.36));
  // throat lantern visible through the gape
  parts.push(sphere(V3(0, -0.35, 2.75), 0.3, { color: 0xff6040, glow: 1 }));
  parts.push(sphere(V3(0, -0.3, 2.5), 1, { sx: 0.45, sy: 0.3, sz: 0.6, color: 0x1a0606 }));
  // hollow eye sockets with dim embers, under heavy brow ridges
  for (const s of [-1, 1]) {
    const [ex, ey] = SP(3.05, s > 0 ? 0.42 : Math.PI - 0.42);
    parts.push(sphere(V3(ex * 0.92, ey, 3.05), 1, { sx: 0.12, sy: 0.15, sz: 0.2, color: 0x050304 }));
    parts.push(...eye(V3(ex * 0.9, ey, 3.05), 0.1, V3(s, 0.15, 0.35), { iris: 0xff4020, rim: 0x2a2520, glow: 0.7, pupil: 0.9 }));
    parts.push(sphere(V3(ex * 0.85, ey + 0.17, 3.0), 1, { sx: 0.18, sy: 0.08, sz: 0.32, color: bone.clone().multiplyScalar(0.8) }));
    // cheek feelers with glowing tips
    parts.push(limb([[s * 0.55, 0.15, 3.3], [s * 1.25, 0.85, 3.95], [s * 1.7, 0.5, 4.9], [s * 1.6, 0.1, 5.6]], 0.045, 0.012,
      { radial: n(5, q), segs: n(16, q), color: 0x1a1816, glow: (x, y, z) => (z > 5.3 ? 1 : 0), fin: (x, y, z) => smooth(3.5, 5.6, z) * 0.5 }));
  }
  // forehead lure
  parts.push(limb([[0, 0.95, 3.1], [0, 1.75, 3.6], [0, 1.75, 4.5], [0, 1.15, 5.2]], 0.06, 0.022, { radial: n(6, q), segs: n(16, q), color: 0x24201c }));
  parts.push(sphere(V3(0, 1.05, 5.3), 0.13, { color: 0xffa070, glow: 1 }));
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2 + 0.4;
    parts.push(limb([[0, 1.0, 5.32], [Math.cos(a) * 0.12, 0.85, 5.35 + Math.sin(a) * 0.12], [Math.cos(a) * 0.2, 0.6, 5.3 + Math.sin(a) * 0.2]], 0.012, 0.004, { radial: 3, segs: 4, color: 0x2a2420, glow: (x, y) => (y < 0.7 ? 0.8 : 0) }));
  }
  // bony dorsal spines
  for (let i = 0; i < (lod ? 7 : 14); i++) {
    const z = mix(1.9, -3.2, i / 13);
    const h = mix(0.38, 0.1, i / 13);
    const top = BP(z, Math.PI / 2)[1];
    const g = new THREE.ConeGeometry(0.09, h, 5).scale(0.4, 1, 1).translate(0, h / 2, 0).rotateX(-0.5).translate(0, top - 0.03, z);
    parts.push(finish(g, { color: bone }));
  }
  const fc = finColor(0x0e0c0e, 10, 0.6, 0.3);
  // long ragged pectoral fins
  for (const s of [-1, 1]) {
    const pa = s > 0 ? -0.35 : Math.PI + 0.35;
    parts.push(fin((u, v) => {
      const z = mix(1.65, 1.2, mix(u, 0.6, v * 0.6));
      const [x, y] = BP(z, pa);
      const ragged = 1 - 0.18 * Math.abs(Math.sin(u * Math.PI * 5)) * v;
      return V3(x * 0.95 + s * 1.5 * v * ragged, y - 0.6 * v * v, z - 0.95 * v * ragged);
    }, { nu: n(10, q), nv: n(6, q), thick: (u, v) => 0.018 * (1 - v), color: fc, fin: (u, v) => v * 1.2 }));
  }
  // continuous ribbon fins along the tail (dorsal + anal) with glowing specks on the margin
  for (const side of [1, -1]) {
    parts.push(fin((u, v) => {
      const z = mix(side > 0 ? -0.8 : 0.4, -3.85, u);
      const h = 0.32 * Math.sin(Math.PI * Math.min(1, u * 1.1)) ** 0.6 * (1 - 0.6 * u);
      const yb = BP(z, side * Math.PI / 2)[1];
      return V3(0, yb + side * (-0.03 + h * v), z - 0.08 * v);
    }, { nu: n(28, q), nv: 3, thick: (u, v) => 0.01 * (1 - v), color: fc, glow: (u, v) => (v > 0.9 && Math.sin(u * 70) > 0.85 ? 0.6 : 0) }));
  }
  // tail paddle
  parts.push(fin((u, v) => { const s = u * 2 - 1; return V3(0, mix(s * 0.05, s * 0.4, v), mix(bz0 + 0.05, bz0 - 0.5, v)); },
    { nu: n(8, q), nv: 3, thick: (u, v) => 0.012 * (1 - v), color: fc, glow: (u, v) => (v > 0.85 ? 0.6 : 0) }));
  return mergeParts(parts);
}

// ------------------------------------------------------------------ CANTOR LEVIATHAN
// 100 m filter-feeding giant. Cetacean build: blunt head, ventral grooves,
// long tubercled flippers and a horizontal lunate fluke.
export function cantor() {
  const L = 100;
  const z0 = -47, z1 = 50;
  const T = (z) => (z - z0) / (z1 - z0);
  const R = (t) => (8.6 * Math.pow(Math.max(0, Math.sin(Math.PI * Math.pow(t, 0.8))), 0.5) + 0.3) * (0.22 + 0.78 * smooth(0, 0.5, t));
  const sec = (t, a) => ellipse(R(t), { hx: 0.9, hy: 0.72, belly: 0.5, keel: 0.2 })(a);
  const P = (z, a) => sec(clamp01(T(z)), a);
  const parts = [];
  const back = col(0.1, 0.14, 0.19), flank = col(0.17, 0.22, 0.28), belly = col(0.36, 0.4, 0.44);
  const mouthY = (z) => -0.1 - 0.02 * (z - 30);
  parts.push(finish(trunk({ z0, z1, segs: 96, radial: 30, section: sec }), {
    color: shade({ R, T, back, flank, belly, mot: 0.25, motAmt: 0.35,
      pattern: (x, y, z, yn, r) => {
        let m = 1;
        if (yn < -0.35 && z > 0 && Math.abs(Math.sin(x * 1.3)) > 0.75) m *= 0.62; // ventral grooves
        if (z > 28 && z < 48.5 && Math.abs(yn - mouthY(z)) < 0.05) m *= 0.3; // mouth line
        if (yn > 0.3 && mottle(x, y, z, 0.5) > 0.72) m *= 1.25; // pale scarring
        return m;
      } }),
  }));
  // eyes
  for (const s of [-1, 1]) {
    const [ex, ey] = P(34, s > 0 ? -0.05 : Math.PI + 0.05);
    parts.push(...eye(V3(ex * 0.97, ey, 34), 0.7, V3(s, 0.05, 0.3), { iris: 0x8ff4ff, rim: 0x101820, glow: 0.6 }));
  }
  // photophore rows along the flanks and a lantern crest on the head
  for (const s of [-1, 1]) {
    for (let z = -32; z < 42; z += 3.4) {
      const a = (s > 0 ? 0 : Math.PI) + s * (Math.sin(z * 0.37) * 0.12 - 0.05);
      const [x, y] = P(z, a);
      parts.push(sphere(V3(x * 0.995, y, z), 0.42, { w: 7, h: 5, color: 0x9ff4ff, glow: 1 }));
    }
  }
  for (let i = 0; i < 12; i++) {
    const z = 40 - i * 4.2;
    const [, y] = P(z, Math.PI / 2);
    if (i < 6) {
      parts.push(sphere(V3(0, y - 0.4, z), 1.1, { sx: 1, sy: 0.6, sz: 1.3, color: back }));
      parts.push(sphere(V3(0, y + 0.15, z), 0.75, { color: 0x9ff4ff, glow: 1 }));
    } else {
      // dorsal knuckles toward the tail
      const k = (i - 6) / 6;
      parts.push(sphere(V3(0, P(z - 30, Math.PI / 2)[1] - 0.3, z - 30), mix(1.2, 0.5, k), { sx: 0.8, sy: 0.7, sz: 1.6, color: back }));
    }
  }
  // flippers
  for (const s of [-1, 1]) {
    const rootZ = 27;
    const [rx, ry] = P(rootZ, s > 0 ? -0.55 : Math.PI + 0.55);
    parts.push(fin((u, v) => {
      const tub = 0.5 * Math.abs(Math.sin(u * Math.PI * 9)) * (1 - v) * smooth(0, 0.15, u);
      const chord = 7.5 * Math.pow(1 - u, 0.6) + 1.2;
      return V3(rx * 0.92 + s * 27 * u, ry - 9.5 * u * u, rootZ + 1.5 - 15 * u - (chord + tub) * v + tub);
    }, { nu: 26, nv: 6, thick: (u, v) => (1.1 * (1 - u * 0.85)) * Math.sin(Math.PI * v) ** 0.6 + 0.02,
      color: (u, v, c) => { lerpC(c, flank, belly, 0.3 + 0.4 * v); if (Math.abs(Math.sin(u * Math.PI * 9)) > 0.9 && v < 0.2) c.multiplyScalar(1.4); },
      glow: (u, v) => (u > 0.75 && v > 0.85 ? 0.35 : 0), fin: (u) => u }));
  }
  // horizontal lunate fluke with a central notch
  parts.push(fin((u, v) => {
    const x = (u * 2 - 1) * 18, a = Math.abs(x) / 18;
    const zle = -44 - 8 * Math.pow(a, 1.6);
    const zte = -49.5 - 2.5 * Math.pow(a, 0.8) + 1.4 * Math.exp(-((x / 1.6) ** 2));
    return V3(x, 0.4 * a, mix(zle, zte, v));
  }, { nu: 30, nv: 6, thick: (u, v) => 0.7 * Math.pow(1 - Math.abs(u * 2 - 1), 0.6) * Math.sin(Math.PI * v) ** 0.7 + 0.03,
    color: (u, v, c) => lerpC(c, back, flank, v * 0.6), glow: (u) => (Math.abs(u * 2 - 1) > 0.9 ? 0.5 : 0) }));
  void L;
  return mergeParts(parts);
}

// ------------------------------------------------------------------ VEIL RAY
// Translucent manta-like glider: thick central disc thinning into veined
// wings, curled cephalic lobes, a whip tail with a glowing tip.
export function veilRay() {
  const parts = [];
  const span = 1.6;
  const wingPt = (u, v) => {
    const x = (u * 2 - 1) * span, a = Math.abs(x) / span;
    const zle = 0.85 - 1.1 * Math.pow(a, 1.4) - 0.16 * Math.exp(-((x / 0.2) ** 2));
    const zte = -0.62 + 0.32 * Math.pow(a, 0.9);
    const y = 0.04 * a - 0.14 * a * a;
    return V3(x, y, mix(zle, zte, v));
  };
  const base = col(0.36, 0.52, 0.78), dark = col(0.14, 0.22, 0.38);
  parts.push(fin(wingPt, {
    nu: 40, nv: 12,
    thick: (u, v) => { const x = (u * 2 - 1) * span; return (0.15 * Math.exp(-((x / 0.38) ** 2)) + 0.01) * Math.sin(Math.PI * v) ** 0.5 + 0.002; },
    color: (u, v, c) => {
      const p = wingPt(u, v), a = Math.abs(p.x) / span;
      lerpC(c, dark, base, smooth(0.05, 0.6, a));
      c.multiplyScalar(1 + 0.25 * smooth(0.7, 1, Math.abs(Math.sin(Math.atan2(p.z + 0.1, Math.abs(p.x)) * 11))) * smooth(0.15, 0.4, a));
    },
    glow: (u, v) => {
      const p = wingPt(u, v), a = Math.abs(p.x) / span;
      const vein = Math.abs(Math.sin(Math.atan2(p.z + 0.1, Math.abs(p.x)) * 11)) > 0.96 && a > 0.2 ? 0.45 : 0;
      return Math.max(vein, a > 0.9 || v > 0.94 ? 0.4 : 0, a < 0.12 ? 0.08 : 0);
    },
  }));
  // cephalic lobes curling under the mouth
  for (const s of [-1, 1]) {
    parts.push(fin((u, v) => {
      const z = mix(0.64, 0.82, u);
      const ang = v * Math.PI * 1.4;
      const rr = 0.07 * (1 - 0.45 * v) * (1 - 0.3 * u);
      return V3(s * (0.24 + rr * Math.cos(ang)), -0.03 - rr * Math.sin(ang), z);
    }, { nu: 6, nv: 8, thick: () => 0.006, color: (u, v, c) => c.copy(dark).multiplyScalar(0.9), glow: (u) => (u > 0.9 ? 0.3 : 0) }));
    parts.push(...eye(V3(s * 0.33, 0.04, 0.6), 0.032, V3(s, 0.2, 0.3), { iris: 0x9fe8ff, rim: 0x1a2a40, glow: 0.8 }));
  }
  // whip tail
  parts.push(limb([[0, 0, -0.5], [0, 0.02, -1.3], [0, 0.04, -2.0], [0, 0.08, -2.7]], 0.035, 0.005,
    { radial: 5, segs: 14, color: 0x6a8ab0, glow: (x, y, z) => (z < -2.35 ? 0.9 : 0.15) }));
  return mergeParts(parts);
}

// ------------------------------------------------------------------ LANTERN DRIFTER
// Jellyfish: thick scalloped bell with radial canals, glowing gonads,
// frilled oral arms and fine marginal tentacles. Bell above y = 0.
export function drifter({ lod = 0 } = {}) {
  const parts = [];
  const q = lod ? 0.5 : 1;
  const bellPt = (u, v) => {
    const a = u * Math.PI * 2;
    const phi = v * Math.PI / 2;
    const scallop = 1 + 0.06 * Math.cos(a * 8) * smooth(0.78, 1, v);
    const r = Math.sin(phi) * scallop * (1 + 0.06 * smooth(0.85, 1, v));
    return V3(Math.cos(a) * r, 0.75 * Math.cos(phi) - 0.04 * smooth(0.9, 1, v), Math.sin(a) * r);
  };
  const bell = col(0.42, 0.31, 0.63);
  parts.push(fin(bellPt, {
    nu: lod ? 24 : 48, nv: lod ? 6 : 12,
    thick: (u, v) => 0.03 + 0.11 * (1 - v) * (1 - v),
    color: (u, v, c) => { c.copy(bell); if (Math.abs(Math.sin(u * Math.PI * 8)) < 0.08 && v > 0.15) c.multiplyScalar(1.5); if (v > 0.92) c.multiplyScalar(1.3); },
    glow: (u, v) => (v > 0.88 ? 0.9 : Math.abs(Math.sin(u * Math.PI * 8)) < 0.08 ? 0.5 : 0.22),
  }));
  // gonads: four glowing horseshoes under the bell apex
  if (lod) parts.push(sphere(V3(0, 0.3, 0), 0.4, { sy: 0.7, w: 8, h: 5, color: 0xa0f0ff, glow: 1 }));
  else for (let i = 0; i < 4; i++) {
    const g = new THREE.TorusGeometry(0.16, 0.05, 6, 14, Math.PI * 1.4).rotateX(Math.PI / 2).rotateY(i * Math.PI / 2 + 0.8).translate(Math.cos(i * Math.PI / 2) * 0.22, 0.42, Math.sin(i * Math.PI / 2) * 0.22);
    parts.push(finish(g, { color: 0x8fd8f0, glow: 0.7 }));
  }
  // frilled oral arms
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.4;
    const ra = V3(Math.cos(a), 0, Math.sin(a)), ta = V3(-Math.sin(a), 0, Math.cos(a));
    parts.push(fin((u, v) => {
      const len = 1.9;
      const c = V3(Math.cos(a) * 0.1 * (1 + u * 0.6) + 0.08 * Math.sin(u * 7 + a), 0.05 - u * len, Math.sin(a) * 0.1 * (1 + u * 0.6) + 0.08 * Math.cos(u * 6 + a));
      const w = 0.13 * (1 - 0.6 * u);
      const s = v * 2 - 1;
      return c.addScaledVector(ta, s * w).addScaledVector(ra, 0.05 * Math.sin(u * 38 + v * 3) * Math.abs(s));
    }, { nu: n(26, q), nv: lod ? 2 : 4, thick: () => 0.008, color: (u, v, c) => c.setRGB(0.69, 0.56, 0.88), glow: (u, v) => (Math.abs(v * 2 - 1) > 0.8 ? 0.5 : 0.2) }));
  }
  // marginal tentacles
  const nt = lod ? 10 : 16;
  for (let i = 0; i < nt; i++) {
    const a = (i / nt) * Math.PI * 2 + 0.1;
    const len = 2.2 + (i % 3) * 0.8;
    const pts = [];
    for (let k = 0; k <= 5; k++) {
      const rr = 0.95 * (1 - k * 0.07);
      pts.push(V3(Math.cos(a + k * 0.05) * rr, -0.03 - k * (len / 5), Math.sin(a + k * 0.05) * rr));
    }
    parts.push(limb(pts, 0.02, 0.004, { radial: 3, segs: lod ? 5 : 10, color: 0xd7c8ff, glow: (x, y) => (y < -len * 0.8 ? 0.7 : 0.05) }));
  }
  return mergeParts(parts);
}

// ------------------------------------------------------------------ SHELLBACK
// Armoured grazer (giant isopod build): overlapping tergite plates, a tail
// shield with uropods and seven pairs of jointed legs that walk through the
// shader (aFin = leg flex). The head is a separate mesh so it can retract.
const SHELL_LEN = 1.25;
const shellEnv = (z) => Math.sqrt(Math.max(0, 1 - (z / SHELL_LEN) ** 2));
export function shellbackBody() {
  const parts = [];
  const shell = col(0.64, 0.38, 0.18), dark = col(0.3, 0.18, 0.1), rim = col(0.72, 0.58, 0.4), algae = col(0.33, 0.4, 0.22);
  const plates = 7, step = 0.29;
  for (let k = 0; k < plates; k++) {
    const zc = 0.88 - k * step;
    const zA = zc + step * 0.62, zB = zc - step * 0.62;
    parts.push(fin((u, v) => {
      const th = mix(-0.28, Math.PI + 0.28, u);
      const z = mix(zA, zB, v);
      const e = shellEnv(z) * (0.97 + 0.07 * v); // posterior edge overlaps the next plate
      const W = 0.9 * e * (1 + 0.05 * Math.abs(Math.cos(th)) ** 8), H = 0.6 * e;
      return V3(Math.cos(th) * W, Math.sin(th) * H + 0.02, z);
    }, {
      nu: 22, nv: 4,
      thick: (u, v) => 0.028 * Math.sin(Math.PI * v) ** 0.3 * Math.sin(Math.PI * u) ** 0.2 + 0.003,
      color: (u, v, c) => {
        const th = mix(-0.28, Math.PI + 0.28, u);
        c.copy(shell).lerp(dark, 0.5 * smooth(0.5, 0, v));
        if (v > 0.82) c.lerp(rim, 0.6);
        const m = mottle(Math.cos(th) * 3 + k * 1.7, Math.sin(th) * 3, v * 2 + k, 1.5);
        if (Math.sin(th) > 0.5 && m > 0.6) c.lerp(algae, (m - 0.6) * 1.6);
        c.multiplyScalar(0.8 + 0.35 * m);
      },
    }));
    // midline knob with a glowing pore on the middle plates
    const top = 0.6 * shellEnv(zc) + 0.02;
    parts.push(sphere(V3(0, top, zc), 0.07, { sx: 1, sy: 0.6, sz: 1.4, color: dark }));
    if (k >= 1 && k <= 5) parts.push(sphere(V3(0, top + 0.035, zc), 0.045, { w: 8, h: 6, color: 0x66ffd0, glow: 1 }));
  }
  // tail shield and uropods
  parts.push(fin((u, v) => {
    const th = mix(-0.2, Math.PI + 0.2, u);
    const z = mix(-0.98, -1.32, v);
    const e = mix(0.5, 0.22, v * v);
    return V3(Math.cos(th) * 0.9 * e * 1.15, Math.sin(th) * 0.32 * e * 1.3 + 0.02, z);
  }, { nu: 16, nv: 4, thick: (u, v) => 0.025 * (1 - v * 0.8), color: (u, v, c) => c.copy(shell).lerp(rim, v * 0.5).multiplyScalar(0.85) }));
  for (const s of [-1, 1]) {
    parts.push(limb([[s * 0.22, 0.02, -1.15], [s * 0.38, 0.0, -1.45], [s * 0.44, -0.02, -1.62]], 0.05, 0.012, { color: rim.clone().multiplyScalar(0.8) }));
  }
  // underside
  parts.push(sphere(V3(0, 0.04, -0.05), 1, { sx: 0.8, sy: 0.16, sz: 1.2, w: 18, h: 8, color: 0x3a3026 }));
  // legs: hip -> knee -> foot; aFin grows toward the foot
  for (let k = 0; k < 7; k++) {
    const z = 0.78 - k * 0.27;
    for (const s of [-1, 1]) {
      const w = 0.62 * Math.max(0.6, shellEnv(z));
      parts.push(limb([[s * w * 0.8, 0.06, z], [s * (w + 0.3), 0.16, z + 0.03], [s * (w + 0.42), -0.12, z + 0.06], [s * (w + 0.38), -0.32, z + 0.04]], 0.055, 0.02,
        { radial: 5, segs: 9, color: (x, y, zz, c) => c.setRGB(0.36, 0.29, 0.21).multiplyScalar(0.85 + 0.3 * mottle(x, y, zz, 14)), fin: (x) => smooth(w * 0.85, w + 0.4, Math.abs(x)) }));
    }
  }
  return mergeParts(parts);
}

export function shellbackHead() {
  const parts = [];
  const shell = col(0.64, 0.38, 0.18);
  const g = new THREE.SphereGeometry(1, 18, 10, 0, Math.PI * 2, 0, Math.PI * 0.55).scale(0.5, 0.24, 0.3);
  parts.push(finish(g, { color: (x, y, z, c) => c.copy(shell).multiplyScalar(0.55 + 0.35 * mottle(x * 3, y * 3, z * 3, 2) + (Math.abs(x) > 0.38 ? -0.15 : 0)) }));
  parts.push(sphere(V3(0, -0.03, 0.1), 1, { sx: 0.42, sy: 0.1, sz: 0.26, color: 0x2a221a }));
  for (const s of [-1, 1]) {
    // compound eyes
    parts.push(sphere(V3(s * 0.34, 0.05, 0.1), 0.09, { sx: 0.8, sy: 0.9, sz: 1.1, color: 0x0c0d0e, glow: 0.12 }));
    // antennae and antennules
    parts.push(limb([[s * 0.14, 0.05, 0.24], [s * 0.4, 0.22, 0.62], [s * 0.75, 0.2, 1.05], [s * 1.0, 0.05, 1.2]], 0.03, 0.008, { radial: 4, segs: 14, color: 0x5a4a36 }));
    parts.push(limb([[s * 0.07, 0.02, 0.27], [s * 0.13, 0.1, 0.47], [s * 0.19, 0.08, 0.58]], 0.018, 0.006, { radial: 3, segs: 6, color: 0x5a4a36 }));
  }
  return mergeParts(parts);
}

// ------------------------------------------------------------------ EMBER SHRIMP
// Vent shrimp, 1 unit long (instances scale it to ~0.12-0.18 m), head +z.
// Translucent red-orange carapace, curled segmented abdomen, tail fan,
// long antennae and a glowing dorsal organ that marks swarms in the dark.
export function emberShrimp() {
  const parts = [];
  const shell = col(0.82, 0.32, 0.14), pale = col(0.95, 0.7, 0.5);
  // cephalothorax with a rostrum
  const cz0 = -0.02, cz1 = 0.42;
  const CR = (t) => 0.1 * Math.pow(Math.sin(Math.PI * Math.min(1, 0.2 + t * 0.85)), 0.6) + 0.006;
  parts.push(finish(trunk({ z0: cz0, z1: cz1, segs: 10, radial: 10, section: (t, a) => ellipse(CR(t), { hx: 0.8, belly: 0.3, keel: 0.4, yo: 0.01 * t })(a) }), {
    color: (x, y, z, c) => c.copy(shell).lerp(pale, smooth(0, -0.08, y) * 0.7),
    glow: (x, y, z) => (y > 0.06 && z > 0.1 && z < 0.25 ? 1 : 0),
  }));
  parts.push(limb([[0, 0.04, 0.4], [0, 0.07, 0.55], [0, 0.09, 0.62]], 0.012, 0.003, { radial: 3, segs: 4, color: shell }));
  // abdomen: six segments curling down toward the tail fan
  for (let k = 0; k < 6; k++) {
    const t = k / 6;
    const z = -0.02 - t * 0.42, y = -0.04 * t * t * 4;
    const r = 0.085 * (1 - t * 0.5);
    parts.push(sphere(V3(0, y, z - 0.035), 1, { sx: r * 0.8, sy: r, sz: 0.06, w: 8, h: 6, color: k % 2 ? shell : shell.clone().multiplyScalar(0.85), fin: t * 0.6 }));
  }
  // tail fan
  parts.push(fin((u, v) => { const s = u * 2 - 1; return V3(s * mix(0.02, 0.09, v), -0.17 - 0.02 * v, -0.48 - 0.1 * v); },
    { nu: 4, nv: 2, thick: () => 0.004, color: (u, v, c) => c.copy(pale).multiplyScalar(0.9), fin: () => 1 }));
  // eyes on stalks, antennae and walking legs
  for (const s of [-1, 1]) {
    parts.push(sphere(V3(s * 0.06, 0.06, 0.36), 0.022, { w: 6, h: 4, color: 0x050505 }));
    parts.push(limb([[s * 0.03, 0.03, 0.4], [s * 0.15, 0.12, 0.7], [s * 0.3, 0.05, 1.0], [s * 0.42, -0.08, 1.25]], 0.006, 0.002, { radial: 3, segs: 8, color: shell, fin: (x, y, z) => smooth(0.5, 1.2, z) * 0.4 }));
    for (let k = 0; k < 4; k++) {
      const z = 0.3 - k * 0.07;
      parts.push(limb([[s * 0.05, -0.05, z], [s * 0.13, -0.09, z + 0.02], [s * 0.16, -0.18, z - 0.02]], 0.007, 0.003, { radial: 3, segs: 3, color: pale, fin: 0.3 }));
    }
  }
  return mergeParts(parts);
}
